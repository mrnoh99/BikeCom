import Foundation
import HealthKit
import WatchConnectivity

/// 워치에서 사이클링 워크아웃 세션을 돌려 실시간 심박수·속도·케이던스를 수집하고
/// `WCSession` 으로 아이폰에 전송한다.
/// 주행 종료 직후 워치에 잠깐 보여주는 요약(거리·시간·평균 속도·평균 심박·평균 케이던스).
struct WorkoutSummary: Identifiable {
    let id = UUID()
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval
    let avgSpeedMps: Double
    let avgHeartRate: Int
    let avgCadenceRPM: Int
}

final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    @Published var heartRate: Int = 0
    @Published var isRunning = false
    /// 주행 종료 시 채워지는 요약(요약 시트 표시용). 닫으면 nil.
    @Published var summary: WorkoutSummary?

    @Published var spo2: Int = 0
    @Published var measuringSpO2 = false

    // 주행 지표(워치 화면·컴플리케이션 표시용)
    @Published var avgHeartRate: Int = 0
    @Published var speedMps: Double = 0
    @Published var avgSpeedMps: Double = 0
    @Published var cadenceRPM: Int = 0
    @Published var avgCadenceRPM: Int = 0
    @Published var distanceMeters: Double = 0
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var speedSensorConnected = false
    @Published var cadenceSensorConnected = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// `startWatchApp(toHandle:)` 로 전달된 설정. 세션 시작 시 우선 사용한다.
    private var pendingConfiguration: HKWorkoutConfiguration?
    /// `updateApplicationContext` 는 최신 스냅샷용 — 고빈도 호출 시 watchOS 부하·크래시 유발.
    private var lastContextUpdateAt: Date = .distantPast
    private let minContextInterval: TimeInterval = 1.0
    /// 시작이 진행 중인지(begin​Collection 콜백 전까지 isRunning 이 아직 false 인 구간).
    /// 이 구간의 재진입을 막아 두 번째 세션이 생기는 것을 차단한다(Ended 전이 오류 방지).
    private var isStarting = false
    /// 폰이 방송한 권위 워크아웃 레벨의 토큰(타임스탬프). 더 새 것만 채택한다.
    private var workoutToken: Double = 0
    /// 폰 속도·케이던스 중계 허용(⌚ 모드). false 이면 주행 중이 아닐 때 세션 종료.
    private var speedCadenceRelayEnabled = true
    private var relayToken: Double = 0
    private var spo2Query: HKQuery?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var relayTimer: Timer?

    // 센서 신선도(최근 샘플 수신 시각) — 연결 상태 판정용
    private let sensorFreshness: TimeInterval = 5
    private var lastSpeedSampleAt: Date?
    private var lastCadenceSampleAt: Date?

    private var latestSpeedMps: Double?
    private var latestCadenceRPM: Int?
    /// updateApplicationContext 는 마지막 페이로드만 유지하므로 누적한다.
    private var outboundContext: [String: Any] = [:]

    override init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    func requestAuthorization() {
        consumePendingWorkoutCommandIfNeeded()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        var share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let ids: [HKQuantityTypeIdentifier] = [.heartRate, .activeEnergyBurned, .distanceCycling,
                                               .cyclingSpeed, .cyclingCadence]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                read.insert(t); share.insert(t)
            }
        }
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            read.insert(spo2)
        }
        healthStore.requestAuthorization(toShare: share, read: read) { _, _ in }
    }

    /// 컴플리케이션 CONNECT/DISCONNECT → 워치 센서 세션만 켜고/끔(폰 라이딩과 분리).
    func consumePendingWorkoutCommandIfNeeded() {
        guard let cmd = RideMetricsStore.consumePendingCommand() else { return }
        switch cmd {
        case "start": requestWorkout(true)
        case "stop": requestWorkout(false)
        default: break
        }
    }

    func measureSpO2() {
        guard !measuringSpO2,
              let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        DispatchQueue.main.async { self.measuringSpO2 = true }

        fetchLatestSpO2()

        let tap = Date()
        let pred = HKQuery.predicateForSamples(withStart: tap, end: nil, options: .strictStartDate)
        let q = HKAnchoredObjectQuery(type: type, predicate: pred, anchor: nil,
                                      limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.handleSpO2(samples, finishMeasuring: true)
        }
        q.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.handleSpO2(samples, finishMeasuring: true)
        }
        healthStore.execute(q)
        spo2Query = q

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.stopMeasuringSpO2()
        }
    }

    private func fetchLatestSpO2() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            self?.handleSpO2(samples, finishMeasuring: false)
        }
        healthStore.execute(q)
    }

    private func handleSpO2(_ samples: [HKSample]?, finishMeasuring: Bool) {
        guard let s = samples?.compactMap({ $0 as? HKQuantitySample })
            .max(by: { $0.endDate < $1.endDate }) else { return }
        let pct = s.quantity.doubleValue(for: .percent())
        DispatchQueue.main.async {
            self.spo2 = Int((pct * 100).rounded())
            if finishMeasuring { self.measuringSpO2 = false }
        }
        sendEphemeral(["spo2": pct, "spo2Date": s.endDate.timeIntervalSince1970])
        if finishMeasuring { stopMeasuringSpO2() }
    }

    private func stopMeasuringSpO2() {
        if let q = spo2Query { healthStore.stop(q); spo2Query = nil }
        DispatchQueue.main.async { self.measuringSpO2 = false }
    }

    /// `WatchAppDelegate.handle` — 앱만 깨우고, 실제 시작은 폰 `workoutActive` 방송(reconcile)이 담당.
    func adoptWorkoutConfiguration(_ configuration: HKWorkoutConfiguration) {
        pendingConfiguration = configuration
        let ctx = WCSession.default.receivedApplicationContext
        let active = (ctx["workoutActive"] as? Bool) ?? (ctx["workoutActive"] as? NSNumber)?.boolValue
        if active == true {
            reconcile(active: true)
        }
    }

    func startWorkout(configuration: HKWorkoutConfiguration? = nil) {
        guard !isRunning, !isStarting, HKHealthStore.isHealthDataAvailable() else { return }
        isStarting = true   // 콜백 전까지 재진입(중복 세션 생성) 차단
        let config: HKWorkoutConfiguration = configuration ?? pendingConfiguration ?? {
            let c = HKWorkoutConfiguration()
            c.activityType = .cycling
            c.locationType = .outdoor
            return c
        }()
        pendingConfiguration = nil

        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            for id in [HKQuantityTypeIdentifier.heartRate, .cyclingSpeed, .cyclingCadence, .distanceCycling] {
                if let t = HKQuantityType.quantityType(forIdentifier: id) {
                    dataSource.enableCollection(for: t, predicate: nil)
                }
            }
            b.dataSource = dataSource
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            latestSpeedMps = nil
            latestCadenceRPM = nil
            resetRideMetrics()

            let startDate = Date()
            s.prepare()   // 세션을 미리 활성화해 워크아웃 중 watchOS 가 앱을 종료하지 않도록.
            s.startActivity(with: startDate)
            b.beginCollection(withStart: startDate) { [weak self] success, error in
                guard let self else { return }
                self.isStarting = false
                if let error {
                    // 시작 실패 시 세션을 정리해 다음 CONNECT 가 깨끗한 세션으로 시작되게 한다.
                    s.end()
                    self.session = nil
                    self.builder = nil
                    self.sendEphemeral(["workoutError": error.localizedDescription])
                    return
                }
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.startRelayTimer()
                    self.persistSnapshot(forceReload: true)
                }
                self.startHeartRateQuery(from: startDate)
                self.sendEphemeral(["workoutStarted": success])
                self.sendMetricsToPhone()
            }
        } catch {
            isStarting = false
            session = nil
            builder = nil
            sendEphemeral(["workoutError": error.localizedDescription])
        }
    }

    func stopWorkout() {
        stopRelayTimer()
        stopHeartRateQuery()
        isStarting = false
        guard let activeSession = session else { return }
        let activeBuilder = builder
        session = nil
        builder = nil
        latestSpeedMps = nil
        latestCadenceRPM = nil
        activeSession.end()
        activeBuilder?.endCollection(withEnd: Date()) { _, _ in }
        outboundContext.removeValue(forKey: "hr")
        outboundContext.removeValue(forKey: "speedMps")
        outboundContext.removeValue(forKey: "cadence")
        DispatchQueue.main.async {
            // 지표 초기화 전에 요약 캡처(의미 있는 주행일 때만 표시).
            if self.distanceMeters > 0 || self.elapsedSeconds >= 5 {
                self.summary = WorkoutSummary(
                    distanceMeters: self.distanceMeters,
                    elapsedSeconds: self.elapsedSeconds,
                    avgSpeedMps: self.avgSpeedMps,
                    avgHeartRate: self.avgHeartRate,
                    avgCadenceRPM: self.avgCadenceRPM)
            }
            self.isRunning = false
            self.heartRate = 0
            self.speedMps = 0
            self.cadenceRPM = 0
            self.speedSensorConnected = false
            self.cadenceSensorConnected = false
            self.elapsedSeconds = 0
        }
        // 종료 스냅샷(주행 종료 표시) 즉시 반영 → 컴플리케이션 갱신.
        var snap = RideMetricsStore.load()
        snap.isRunning = false
        snap.updatedAt = Date()
        RideMetricsStore.save(snap, forceReload: true)
    }

    private func startHeartRateQuery(from startDate: Date) {
        stopHeartRateQuery()
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let pred = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let query = HKAnchoredObjectQuery(type: hrType, predicate: pred, anchor: nil,
                                          limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.ingestHeartRateSamples(samples)
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.ingestHeartRateSamples(samples)
        }
        healthStore.execute(query)
        heartRateQuery = query
    }

    private func stopHeartRateQuery() {
        if let q = heartRateQuery {
            healthStore.stop(q)
            heartRateQuery = nil
        }
    }

    private func ingestHeartRateSamples(_ samples: [HKSample]?) {
        guard let sample = samples?.compactMap({ $0 as? HKQuantitySample })
            .max(by: { $0.endDate < $1.endDate }) else { return }
        let bpm = Int(sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        guard bpm > 0 else { return }
        DispatchQueue.main.async { self.heartRate = bpm }
        sendMetricsToPhone()
    }

    private func startRelayTimer() {
        stopRelayTimer()
        relayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let elapsed = self.builder?.elapsedTime {
                DispatchQueue.main.async { self.elapsedSeconds = elapsed }
            }
            self.refreshSensorFlagsAndPersist()
            self.sendMetricsToPhone()
        }
    }

    /// 최근 샘플 수신 여부로 속도·케이던스 센서 연결 상태를 갱신하고
    /// 공유 저장소(App Group)에 최신 지표를 기록한다(컴플리케이션 표시용).
    private func refreshSensorFlagsAndPersist() {
        let now = Date()
        let speedOn = lastSpeedSampleAt.map { now.timeIntervalSince($0) <= sensorFreshness } ?? false
        let cadOn = lastCadenceSampleAt.map { now.timeIntervalSince($0) <= sensorFreshness } ?? false
        DispatchQueue.main.async {
            self.speedSensorConnected = speedOn
            self.cadenceSensorConnected = cadOn
        }
        persistSnapshot()
    }

    private func persistSnapshot(forceReload: Bool = false) {
        let now = Date()
        let speedOn = lastSpeedSampleAt.map { now.timeIntervalSince($0) <= sensorFreshness } ?? false
        let cadOn = lastCadenceSampleAt.map { now.timeIntervalSince($0) <= sensorFreshness } ?? false
        let snap = RideMetricsStore.Snapshot(
            isRunning: isRunning,
            heartRate: heartRate,
            avgHeartRate: avgHeartRate,
            speedMps: speedMps,
            avgSpeedMps: avgSpeedMps,
            avgCadenceRPM: avgCadenceRPM,
            distanceMeters: distanceMeters,
            speedSensorConnected: speedOn,
            cadenceSensorConnected: cadOn,
            updatedAt: now
        )
        RideMetricsStore.save(snap, forceReload: forceReload)
    }

    private func resetRideMetrics() {
        lastSpeedSampleAt = nil
        lastCadenceSampleAt = nil
        DispatchQueue.main.async {
            self.avgHeartRate = 0
            self.speedMps = 0
            self.avgSpeedMps = 0
            self.cadenceRPM = 0
            self.avgCadenceRPM = 0
            self.distanceMeters = 0
            self.elapsedSeconds = 0
            self.speedSensorConnected = false
            self.cadenceSensorConnected = false
        }
    }

    private func stopRelayTimer() {
        relayTimer?.invalidate()
        relayTimer = nil
    }

    private func sendMetricsToPhone() {
        guard isRunning else { return }
        let hr = heartRate > 0 ? heartRate : nil
        let payload = metricsPayload(hr: hr, speedMps: latestSpeedMps, cadence: latestCadenceRPM)
        guard hr != nil || latestSpeedMps != nil || latestCadenceRPM != nil else { return }
        send(payload)
    }

    private func metricsPayload(hr: Int?, speedMps: Double?, cadence: Int?) -> [String: Any] {
        var payload: [String: Any] = ["ts": Date().timeIntervalSince1970]
        if let hr, hr > 0 { payload["hr"] = hr }
        if let speedMps, speedMps >= 0 { payload["speedMps"] = speedMps }
        if let cadence, cadence >= 0 { payload["cadence"] = cadence }
        return payload
    }

    /// 센서 스냅샷 — applicationContext 에 누적(최신값만). 고빈도 전송은 throttling.
    private func send(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }

        for key in ["hr", "speedMps", "cadence"] where payload[key] == nil {
            outboundContext.removeValue(forKey: key)
        }
        for (key, value) in payload {
            outboundContext[key] = value
        }

        let now = Date()
        let shouldSyncContext = now.timeIntervalSince(lastContextUpdateAt) >= minContextInterval
        if shouldSyncContext {
            try? s.updateApplicationContext(outboundContext)
            lastContextUpdateAt = now
        }

        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else if shouldSyncContext {
            s.transferUserInfo(outboundContext)
        }
    }

    /// 1회성 이벤트(workoutStarted·오류·SpO₂) — context 에 넣지 않는다(상태 깜빡임·재처리 방지).
    private func sendEphemeral(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            s.transferUserInfo(payload)
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended {
            stopHeartRateQuery()
            isStarting = false
            DispatchQueue.main.async {
                self.isRunning = false
                self.stopRelayTimer()
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        isStarting = false
        // 실패한 세션은 종료·해제해 다음 시작이 새 세션으로 진행되게 한다.
        session?.end()
        session = nil
        builder = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.stopRelayTimer()
        }
        sendEphemeral(["workoutError": error.localizedDescription])
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let mps = HKUnit.meter().unitDivided(by: .second())
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(hrType) {
            let stats = workoutBuilder.statistics(for: hrType)
            if let q = stats?.mostRecentQuantity() {
                let bpm = Int(q.doubleValue(for: bpmUnit).rounded())
                if bpm > 0 { DispatchQueue.main.async { self.heartRate = bpm } }
            }
            if let avg = stats?.averageQuantity() {
                let avgBpm = Int(avg.doubleValue(for: bpmUnit).rounded())
                DispatchQueue.main.async { self.avgHeartRate = avgBpm }
            }
        }

        if let spType = HKQuantityType.quantityType(forIdentifier: .cyclingSpeed),
           collectedTypes.contains(spType) {
            let stats = workoutBuilder.statistics(for: spType)
            if let q = stats?.mostRecentQuantity() {
                latestSpeedMps = q.doubleValue(for: mps)
                lastSpeedSampleAt = Date()
                let cur = latestSpeedMps ?? 0
                DispatchQueue.main.async { self.speedMps = cur }
            }
            if let avg = stats?.averageQuantity() {
                let v = avg.doubleValue(for: mps)
                DispatchQueue.main.async { self.avgSpeedMps = v }
            }
        }
        if let cadType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence),
           collectedTypes.contains(cadType) {
            let stats = workoutBuilder.statistics(for: cadType)
            if let q = stats?.mostRecentQuantity() {
                let rpm = Int(q.doubleValue(for: bpmUnit).rounded())
                latestCadenceRPM = rpm
                lastCadenceSampleAt = Date()
                DispatchQueue.main.async { self.cadenceRPM = rpm }
            }
            if let avg = stats?.averageQuantity() {
                let rpm = Int(avg.doubleValue(for: bpmUnit).rounded())
                DispatchQueue.main.async { self.avgCadenceRPM = rpm }
            }
        }
        var totalMeters: Double?
        if let dType = HKQuantityType.quantityType(forIdentifier: .distanceCycling),
           collectedTypes.contains(dType),
           let q = workoutBuilder.statistics(for: dType)?.sumQuantity() {
            let meters = q.doubleValue(for: .meter())
            totalMeters = meters
            DispatchQueue.main.async { self.distanceMeters = meters }
        }

        // 평균 속도 보강: 속도 센서가 없어도 거리/경과시간으로 평균을 추정.
        let elapsed = workoutBuilder.elapsedTime
        if elapsed > 1, let dm = totalMeters {
            let derived = dm / elapsed
            DispatchQueue.main.async { if self.avgSpeedMps == 0 { self.avgSpeedMps = derived } }
        }

        refreshSensorFlagsAndPersist()
        sendMetricsToPhone()
    }
}

extension WorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty { handleCommand(ctx) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleCommand(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleCommand(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleCommand(userInfo)
    }

    /// 폰이 방송한 권위 워크아웃 레벨·속도/케이던스 중계 정책에 세션을 정합한다.
    private func handleCommand(_ message: [String: Any]) {
        DispatchQueue.main.async {
            if let active = message["workoutActive"] as? Bool {
                let token = (message["wToken"] as? Double) ?? 0
                if token > self.workoutToken {
                    self.workoutToken = token
                    self.reconcile(active: active)
                }
            }
            if let relay = message["speedCadenceRelay"] as? Bool {
                let rToken = (message["relayToken"] as? Double) ?? 0
                if rToken > self.relayToken {
                    self.relayToken = rToken
                    self.speedCadenceRelayEnabled = relay
                    self.applyRelayPolicy()
                }
            }
            if message["releaseSensors"] as? Bool == true {
                self.speedCadenceRelayEnabled = false
                self.applyRelayPolicy()
            }
        }
    }

    /// 폰 BLE 모드: 주행 중이 아니면 워치 센서 세션 종료.
    private func applyRelayPolicy() {
        let ctx = WCSession.default.receivedApplicationContext
        let phoneRideActive = (ctx["workoutActive"] as? Bool)
            ?? (ctx["workoutActive"] as? NSNumber)?.boolValue
            ?? false
        if !speedCadenceRelayEnabled, !phoneRideActive, isRunning || isStarting {
            stopWorkout()
        }
    }

    /// 권위 레벨에 맞춰 세션을 켜거나 끈다(현재 상태와 같으면 아무것도 하지 않음).
    private func reconcile(active: Bool) {
        if active {
            if !isRunning && !isStarting { startWorkout() }
        } else {
            if isRunning || isStarting { stopWorkout() }
        }
    }

    /// 워치 CONNECT/DISCONNECT — 폰 라이딩 시작/종료와 분리.
    /// CONNECT: 워치에서만 HKWorkoutSession(심박·센서) 시작. DISCONNECT: 폰 주행 중이면 종료 요청, 아니면 워치 세션만 종료.
    func requestWorkout(_ start: Bool) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }

        if start {
            if !isRunning, !isStarting { startWorkout() }
            return
        }

        let ctx = s.receivedApplicationContext
        let phoneRideActive = (ctx["workoutActive"] as? Bool)
            ?? (ctx["workoutActive"] as? NSNumber)?.boolValue
            ?? false
        if phoneRideActive {
            let payload: [String: Any] = ["workoutRequest": false]
            if s.isReachable {
                s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            } else {
                s.transferUserInfo(payload)
            }
        } else if isRunning || isStarting {
            stopWorkout()
        }
    }
}
