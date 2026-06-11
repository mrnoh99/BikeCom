import Foundation
import HealthKit
import CoreLocation

/// 폰 측 Apple Health 연동.
/// - 누적 거리(이번달/올해/총)를 건강 앱의 **모든 사이클링 거리(`distanceCycling`)** 합에서 읽는다.
///   → 앱 설치 전·다른 기기(워치 등)로 탄 기록까지 포함되고, 재설치해도 유지된다.
/// - 워치 없이 폰 단독으로 탄 라이딩은 폰이 직접 HKWorkout 으로 저장한다.
///   (워치 사용 시에는 워치가 워크아웃을 저장하므로 폰은 저장하지 않아 이중 계산을 막는다.)
///
/// HealthKit 권한은 `WatchSensorManager.requestAuthorization()` 에서 함께 요청한다
/// (workout·distanceCycling 공유/읽기). 별도 프롬프트를 띄우지 않는다.
final class HealthStore: ObservableObject {
    @Published private(set) var thisMonthMeters: Double = 0
    @Published private(set) var thisYearMeters: Double = 0
    @Published private(set) var totalMeters: Double = 0

    /// 건강 권한이 허용되어 누적값을 읽어온 적이 있는지(폴백 판정용).
    @Published private(set) var hasHealthData = false

    /// 가장 최근 산소포화도(0~1 비율)와 그 측정 시각.
    /// watchOS 가 백그라운드로 기록한 값 — 실시간 연속 측정은 불가(운동 중 모션으로 측정도 드묾).
    @Published private(set) var latestSpO2: Double?
    @Published private(set) var latestSpO2Date: Date?
    /// 24시간 이내 최저/최고 산소포화도와 그 측정 시각.
    @Published private(set) var minSpO2: Double?
    @Published private(set) var minSpO2Date: Date?
    @Published private(set) var maxSpO2: Double?
    @Published private(set) var maxSpO2Date: Date?

    private let healthStore = HKHealthStore()
    private var distanceType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .distanceCycling)
    }
    private var spo2Type: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)
    }
    private var observer: HKObserverQuery?
    private var spo2Observer: HKObserverQuery?

    /// 관찰 시작 + 첫 집계. 새 운동(워치 포함)이 저장되면 자동 재집계한다.
    func start() {
        refreshTotals()
        refreshSpO2()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if observer == nil, let type = distanceType {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                self?.refreshTotals()
                completion()
            }
            observer = q
            healthStore.execute(q)
        }
        // 새 SpO2 측정이 들어오면 자동 갱신.
        if spo2Observer == nil, let type = spo2Type {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                self?.refreshSpO2()
                completion()
            }
            spo2Observer = q
            healthStore.execute(q)
        }
    }

    /// 최근 산소포화도 1건 + 24시간 이내 최저/최고를 읽어 발행한다.
    func refreshSpO2() {
        guard HKHealthStore.isHealthDataAvailable(), let type = spo2Type else { return }

        // 최근 1건(시간 제한 없음).
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let qLatest = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let s = samples?.first as? HKQuantitySample else { return }
            DispatchQueue.main.async {
                self?.latestSpO2 = s.quantity.doubleValue(for: .percent())
                self?.latestSpO2Date = s.endDate
            }
        }
        healthStore.execute(qLatest)

        // 24시간 이내 최저/최고(값과 그 측정 시각).
        let dayAgo = Date().addingTimeInterval(-86_400)
        let pred = HKQuery.predicateForSamples(withStart: dayAgo, end: nil, options: .strictStartDate)
        let q24 = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, _ in
            let qs = (samples as? [HKQuantitySample]) ?? []
            func val(_ s: HKQuantitySample) -> Double { s.quantity.doubleValue(for: .percent()) }
            let mn = qs.min { val($0) < val($1) }
            let mx = qs.max { val($0) < val($1) }
            DispatchQueue.main.async {
                self?.minSpO2 = mn.map(val); self?.minSpO2Date = mn?.endDate
                self?.maxSpO2 = mx.map(val); self?.maxSpO2Date = mx?.endDate
            }
        }
        healthStore.execute(q24)
    }

    /// 이번달/올해/총 사이클링 거리(미터)를 다시 집계한다.
    func refreshTotals() {
        guard HKHealthStore.isHealthDataAvailable(), distanceType != nil else { return }
        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        let yearStart = cal.dateInterval(of: .year, for: now)?.start ?? now

        sum(from: monthStart, to: now) { [weak self] m in self?.set(\.thisMonthMeters, m) }
        sum(from: yearStart, to: now) { [weak self] m in self?.set(\.thisYearMeters, m) }
        sum(from: nil, to: now) { [weak self] m in self?.set(\.totalMeters, m) }
    }

    private func set(_ key: ReferenceWritableKeyPath<HealthStore, Double>, _ value: Double) {
        DispatchQueue.main.async {
            self[keyPath: key] = value
            self.hasHealthData = true
        }
    }

    private func sum(from start: Date?, to end: Date, completion: @escaping (Double) -> Void) {
        guard let type = distanceType else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                  options: .cumulativeSum) { _, stats, _ in
            let meters = stats?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            completion(meters)
        }
        healthStore.execute(q)
    }

    /// 라이딩을 건강 앱에 사이클링 워크아웃으로 저장한다(거리 + GPS 경로).
    /// 심박은 워치 워크아웃 세션 동안 시스템이 HealthKit 에 기록하므로 별도 추가하지 않는다.
    func saveRide(_ record: RideRecord, completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else { completion?(false); return }
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        let start = record.startedAt
        let end = start.addingTimeInterval(record.totalElapsed)

        builder.beginCollection(withStart: start) { [weak self] ok, _ in
            guard ok else { completion?(false); return }
            let finish = {
                builder.endCollection(withEnd: end) { _, _ in
                    builder.finishWorkout { workout, _ in
                        if let workout { self?.saveRoute(record, to: workout) }
                        DispatchQueue.main.async { self?.refreshTotals(); completion?(workout != nil) }
                    }
                }
            }
            if record.distanceMeters > 0,
               let type = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
                let quantity = HKQuantity(unit: .meter(), doubleValue: record.distanceMeters)
                let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end)
                builder.add([sample]) { _, _ in finish() }
            } else {
                finish()
            }
        }
    }

    /// GPS 트랙을 HKWorkoutRoute 로 워크아웃에 첨부한다(건강 앱 지도 표시).
    private func saveRoute(_ record: RideRecord, to workout: HKWorkout) {
        guard !record.track.isEmpty else { return }
        let n = record.track.count
        let locations: [CLLocation] = record.track.enumerated().map { i, c in
            let t = c.time ?? record.startedAt.addingTimeInterval(record.totalElapsed * Double(i) / Double(max(1, n - 1)))
            return CLLocation(coordinate: c.clCoordinate,
                              altitude: c.ele ?? 0,
                              horizontalAccuracy: 5,
                              verticalAccuracy: c.ele != nil ? 5 : -1,
                              course: -1,
                              speed: c.speed ?? -1,
                              timestamp: t)
        }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        routeBuilder.insertRouteData(locations) { ok, _ in
            guard ok else { return }
            routeBuilder.finishRoute(with: workout, metadata: nil) { _, _ in }
        }
    }

    #if DEBUG
    /// SwiftUI 프리뷰용 — 최근/24h 최저/최고 SpO2 값 주입.
    func seedPreviewSpO2(latest: Double, latestAt: Date,
                         min: Double, minAt: Date, max: Double, maxAt: Date) {
        latestSpO2 = latest / 100; latestSpO2Date = latestAt
        minSpO2 = min / 100; minSpO2Date = minAt
        maxSpO2 = max / 100; maxSpO2Date = maxAt
    }
    #endif
}
