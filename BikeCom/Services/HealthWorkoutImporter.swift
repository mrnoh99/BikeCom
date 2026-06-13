import Foundation
import HealthKit
import CoreLocation

/// Apple 건강의 사이클링 워크아웃을 읽어 RideRecord 로 변환한다.
/// (Cyclemeter 등이 이미 건강에 저장해 둔 라이딩을 앱 Routes 로 가져올 때 사용.)
///
/// 성능/안정성 설계 — 건강에 워크아웃이 수천 개일 수 있으므로:
///  1) **요약(거리·시간·심박·케이던스)** 은 워크아웃 통계에서 동기로 즉시 읽는다(경로 미포함, 매우 빠름).
///  2) `skipIfDuplicate` 로 **기존 기록과 겹치는 워크아웃을 먼저 제외**한다.
///     → 버려질 기록의 GPS 경로를 조회하지 않으므로 시간이 수십 분 → 수 초로 줄어든다.
///  3) 남은 새 라이딩에 대해서만 경로(HKWorkoutRoute)를 **동시 실행 제한 + 타임아웃**으로 받아 트랙을 채운다.
final class HealthWorkoutImporter {
    private let healthStore = HKHealthStore()

    /// 동시에 처리할 경로 조회 수(HealthKit 폭주 방지).
    private let maxConcurrent = 4
    /// 워크아웃 1건의 경로 읽기 제한 시간. 초과 시 경로 없이 요약만 사용(무한 대기 방지).
    private let routeTimeout: TimeInterval = 15

    /// - skipIfDuplicate: 요약(경로 없음)만으로 기존 기록과 중복인지 판단. true 면 결과에서 제외.
    /// - includeRoutes: GPS 경로까지 받을지. 기본 `false`(요약만, 즉시 완료·안정적).
    ///   대량 가져오기에서 경로를 받으면 수백 건의 HealthKit 경로 쿼리로 매우 느려질 수 있다.
    /// - progress: (완료 수, 새 라이딩 전체 수) 를 메인 큐로 알린다.
    /// - completion: 변환된 새 기록을 메인 큐로 돌려준다.
    func importCyclingWorkouts(skipIfDuplicate: @escaping (RideRecord) -> Bool = { _ in false },
                               includeRoutes: Bool = false,
                               progress: ((Int, Int) -> Void)? = nil,
                               completion: @escaping ([RideRecord]) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { completion([]) }; return
        }
        let predicate = HKQuery.predicateForWorkouts(with: .cycling)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let self, let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                DispatchQueue.main.async { completion([]) }; return
            }
            // 1·2단계: 요약 생성 후 중복 제외 → 새 라이딩만 남긴다(빠름).
            let candidates: [(HKWorkout, RideRecord)] = workouts.compactMap { w in
                let summary = self.summaryRecord(w)
                return skipIfDuplicate(summary) ? nil : (w, summary)
            }
            guard !candidates.isEmpty else {
                DispatchQueue.main.async { completion([]) }; return
            }
            // 요약만 필요하면 즉시 완료(경로 조회 생략 → 멈춤·지연 없음).
            guard includeRoutes else {
                let recs = candidates.map { $0.1 }
                DispatchQueue.main.async { progress?(recs.count, recs.count); completion(recs) }
                return
            }
            // 3단계: 새 라이딩의 경로만 조회.
            self.attachRoutes(candidates, progress: progress, completion: completion)
        }
        healthStore.execute(query)
    }

    // MARK: - 1단계: 요약(경로 없음)

    /// 워크아웃 통계에서 거리·시간·심박·케이던스를 읽어 트랙이 빈 RideRecord 를 만든다(동기, 빠름).
    private func summaryRecord(_ w: HKWorkout) -> RideRecord {
        let total = w.endDate.timeIntervalSince(w.startDate)
        let duration = w.duration

        let distType = HKQuantityType.quantityType(forIdentifier: .distanceCycling)
        let distance = distType.flatMap { w.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) } ?? 0

        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let hrStats = hrType.flatMap { w.statistics(for: $0) }
        let avgHR = hrStats?.averageQuantity().map { Int($0.doubleValue(for: hrUnit).rounded()) }
        let maxHR = hrStats?.maximumQuantity().map { Int($0.doubleValue(for: hrUnit).rounded()) }

        let cadType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence)
        let maxCad = cadType.flatMap { w.statistics(for: $0)?.maximumQuantity() }
            .map { Int($0.doubleValue(for: hrUnit).rounded()) }

        let name = (w.metadata?[HKMetadataKeyWorkoutBrandName] as? String) ?? w.sourceRevision.source.name
        let avgSpeed = duration > 0 ? distance / duration : 0

        return RideRecord(
            name: name,
            source: .health,
            startedAt: w.startDate,
            duration: duration,
            totalElapsed: total,
            distanceMeters: distance,
            averageSpeedMps: avgSpeed,
            maxSpeedMps: avgSpeed,   // 경로 붙이면 갱신
            maxHeartRate: maxHR,
            avgHeartRate: avgHR,
            maxCadence: maxCad,
            track: [])
    }

    // MARK: - 3단계: 경로 부착(동시 실행 제한 + 타임아웃)

    private func attachRoutes(_ candidates: [(HKWorkout, RideRecord)],
                              progress: ((Int, Int) -> Void)?,
                              completion: @escaping ([RideRecord]) -> Void) {
        let total = candidates.count
        var results = [RideRecord?](repeating: nil, count: total)
        let lock = NSLock()
        var doneCount = 0
        let group = DispatchGroup()
        let gate = DispatchSemaphore(value: maxConcurrent)

        DispatchQueue.global(qos: .userInitiated).async {
            for (i, pair) in candidates.enumerated() {
                gate.wait()
                group.enter()
                self.fetchRoute(pair.0) { locations in
                    let record = Self.record(pair.1, withRoute: locations)
                    lock.lock()
                    results[i] = record
                    doneCount += 1
                    let d = doneCount
                    lock.unlock()
                    progress?(d, total)
                    gate.signal()
                    group.leave()
                }
            }
            group.notify(queue: .main) { completion(results.compactMap { $0 }) }
        }
    }

    /// 요약 기록에 경로 좌표를 입혀 최종 기록을 만든다. 경로가 비면 요약 그대로 반환.
    private static func record(_ summary: RideRecord, withRoute locations: [CLLocation]) -> RideRecord {
        guard !locations.isEmpty else { return summary }
        var r = summary
        r.track = locations.map { loc in
            RideRecord.Coordinate(
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                ele: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
                time: loc.timestamp,
                speed: loc.speed >= 0 ? loc.speed : nil,
                hr: nil)
        }
        // 통계에 거리가 없으면 경로로 보강.
        if r.distanceMeters <= 0, locations.count > 1 {
            var d = 0.0
            for i in 1..<locations.count {
                let seg = locations[i].distance(from: locations[i - 1])
                if seg < 200 { d += seg }
            }
            r.distanceMeters = d
            r.averageSpeedMps = r.duration > 0 ? d / r.duration : 0
        }
        if let maxSpeed = locations.compactMap({ $0.speed >= 0 ? $0.speed : nil }).max() {
            r.maxSpeedMps = maxSpeed
        }
        return r
    }

    /// 워크아웃 경로 좌표를 받아 반환(없거나 시간초과 시 빈 배열).
    /// completion 은 **정확히 한 번만** 호출되며, 끝나면 관련 쿼리를 모두 stop 한다
    /// (HKWorkoutRouteQuery 는 장시간 유지되는 쿼리라 stop 하지 않으면 쌓여서 HealthKit 이 막힌다).
    private func fetchRoute(_ workout: HKWorkout, completion: @escaping ([CLLocation]) -> Void) {
        let lock = NSLock()
        var finished = false
        var activeQueries: [HKQuery] = []
        let finishOnce: ([CLLocation]) -> Void = { [weak self] locs in
            lock.lock()
            let already = finished
            finished = true
            let toStop = activeQueries
            activeQueries = []
            lock.unlock()
            guard !already else { return }
            for q in toStop { self?.healthStore.stop(q) }
            completion(locs)
        }

        // 경로 쿼리가 응답하지 않아도 전체가 멈추지 않도록 시간 제한.
        DispatchQueue.global().asyncAfter(deadline: .now() + routeTimeout) {
            finishOnce([])
        }

        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeQuery = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(), predicate: predicate,
                                               anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, error in
            guard let self, error == nil,
                  let routes = samples as? [HKWorkoutRoute], let route = routes.first else {
                finishOnce([]); return
            }
            self.readLocations(route, register: { lock.lock(); activeQueries.append($0); lock.unlock() },
                               completion: finishOnce)
        }
        lock.lock(); activeQueries.append(routeQuery); lock.unlock()
        healthStore.execute(routeQuery)
    }

    private func readLocations(_ route: HKWorkoutRoute,
                               register: (HKQuery) -> Void,
                               completion: @escaping ([CLLocation]) -> Void) {
        var all: [CLLocation] = []
        let q = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
            if let locations { all.append(contentsOf: locations) }
            // 오류 시 지금까지 모은 좌표로 마무리(무한 대기 방지).
            if error != nil { completion(all); return }
            if done { completion(all) }
        }
        register(q)
        healthStore.execute(q)
    }
}
