import Foundation
import HealthKit
import CoreLocation

/// Apple 건강의 사이클링 워크아웃을 읽어 RideRecord 로 변환한다.
/// (Cyclemeter 등이 이미 건강에 저장해 둔 라이딩을 앱 Routes 로 가져올 때 사용.)
/// - 요약(거리·시간·평균/최대 심박·최대 케이던스)은 워크아웃 통계에서 즉시 읽고,
/// - 경로(HKWorkoutRoute)는 비동기로 받아 트랙(고도·시각·속도)을 채운다.
final class HealthWorkoutImporter {
    private let healthStore = HKHealthStore()

    func importCyclingWorkouts(completion: @escaping ([RideRecord]) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion([]); return }
        let predicate = HKQuery.predicateForWorkouts(with: .cycling)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let self, let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                completion([]); return
            }
            self.buildRecords(workouts, completion: completion)
        }
        healthStore.execute(query)
    }

    private func buildRecords(_ workouts: [HKWorkout], completion: @escaping ([RideRecord]) -> Void) {
        let group = DispatchGroup()
        var results = [RideRecord?](repeating: nil, count: workouts.count)
        for (i, workout) in workouts.enumerated() {
            group.enter()
            buildRecord(workout) { record in
                results[i] = record
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(results.compactMap { $0 }) }
    }

    private func buildRecord(_ w: HKWorkout, completion: @escaping (RideRecord?) -> Void) {
        let total = w.endDate.timeIntervalSince(w.startDate)
        let duration = w.duration

        // 요약 통계(동기) — 워크아웃에 저장된 값.
        let distType = HKQuantityType.quantityType(forIdentifier: .distanceCycling)
        var distance = distType.flatMap { w.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) } ?? 0

        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let hrStats = hrType.flatMap { w.statistics(for: $0) }
        let avgHR = hrStats?.averageQuantity().map { Int($0.doubleValue(for: hrUnit).rounded()) }
        let maxHR = hrStats?.maximumQuantity().map { Int($0.doubleValue(for: hrUnit).rounded()) }

        let cadType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence)
        let maxCad = cadType.flatMap { w.statistics(for: $0)?.maximumQuantity() }
            .map { Int($0.doubleValue(for: hrUnit).rounded()) }

        let name = (w.metadata?[HKMetadataKeyWorkoutBrandName] as? String) ?? w.sourceRevision.source.name

        // 경로(비동기).
        fetchRoute(w) { locations in
            let points = locations.map { loc in
                RideRecord.Coordinate(
                    lat: loc.coordinate.latitude,
                    lon: loc.coordinate.longitude,
                    ele: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
                    time: loc.timestamp,
                    speed: loc.speed >= 0 ? loc.speed : nil,
                    hr: nil)
            }
            // 거리/최고속도 보강(통계에 거리가 없으면 경로로 계산).
            if distance <= 0, locations.count > 1 {
                for i in 1..<locations.count {
                    let d = locations[i].distance(from: locations[i - 1])
                    if d < 200 { distance += d }
                }
            }
            let maxSpeed = locations.compactMap { $0.speed >= 0 ? $0.speed : nil }.max()
                ?? (duration > 0 ? distance / duration : 0)
            let avgSpeed = duration > 0 ? distance / duration : 0

            let record = RideRecord(
                name: name,
                startedAt: w.startDate,
                duration: duration,
                totalElapsed: total,
                distanceMeters: distance,
                averageSpeedMps: avgSpeed,
                maxSpeedMps: maxSpeed,
                maxHeartRate: maxHR,
                avgHeartRate: avgHR,
                maxCadence: maxCad,
                track: points)
            completion(record)
        }
    }

    /// 워크아웃에 연결된 경로 좌표들을 모두 받아 반환(없으면 빈 배열).
    private func fetchRoute(_ workout: HKWorkout, completion: @escaping ([CLLocation]) -> Void) {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeQuery = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(), predicate: predicate,
                                               anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            guard let self, let routes = samples as? [HKWorkoutRoute], let route = routes.first else {
                completion([]); return
            }
            self.readLocations(route, completion: completion)
        }
        healthStore.execute(routeQuery)
    }

    private func readLocations(_ route: HKWorkoutRoute, completion: @escaping ([CLLocation]) -> Void) {
        var all: [CLLocation] = []
        let q = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
            if let locations { all.append(contentsOf: locations) }
            if done { completion(all) }
        }
        healthStore.execute(q)
    }
}
