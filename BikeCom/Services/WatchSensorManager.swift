import Foundation
import Combine
import HealthKit
import WatchConnectivity

/// 애플워치에서 측정한 실시간 센서값(심박수·속도·케이던스)을 받는다.
final class WatchSensorManager: NSObject, ObservableObject {
    @Published private(set) var heartRateBPM: Int?
    @Published private(set) var watchSpeedMps: Double?
    @Published private(set) var watchCadenceRPM: Int?
    @Published private(set) var watchReachable = false
    @Published private(set) var sessionActivated = false
    @Published private(set) var authorized = false
    @Published private(set) var speedSensorConnected = false
    @Published private(set) var cadenceSensorConnected = false
    @Published private(set) var heartRateConnected = false
    @Published private(set) var statusMessage = "대기"
    @Published private(set) var lastError: String?

    @Published private(set) var spo2: Double?
    @Published private(set) var spo2Date: Date?

    private(set) var didReceiveWatchDataThisRide = false

    // MARK: 워크아웃 동기화 (폰이 단일 권위; 워치는 이 레벨을 따라감)
    /// 워치 버튼(CONNECT/DISCONNECT)이 보낸 요청을 RideSession 으로 전달한다.
    /// true = 시작 요청, false = 정지 요청.
    var onWatchRequest: ((Bool) -> Void)?
    /// 현재 폰 ride 가 진행 중인지(활성화 시 권위 상태 재방송용).
    var isRideActive: () -> Bool = { false }
    /// 권위 상태 토큰(타임스탬프). 워치는 더 새 토큰만 채택한다(재시작·재생 안전).
    private var workoutToken: Double = 0

    private let healthStore = HKHealthStore()
    private let sensorFreshness: TimeInterval = 5
    private var lastSpeedSensorAt: Date?
    private var lastCadenceSensorAt: Date?
    private var lastHeartRateAt: Date?
    private var lastAnyDataAt: Date?
    private var freshnessTimer: AnyCancellable?

    override init() {
        super.init()
        activateSession()
        freshnessTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshSensorConnectionFlags() }
    }

    private func activateSession() {
        guard WCSession.isSupported() else {
            statusMessage = "WatchConnectivity 미지원"
            return
        }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "HealthKit 사용 불가"
            return
        }
        let workout = HKObjectType.workoutType()
        var read: Set<HKObjectType> = [workout]
        var share: Set<HKSampleType> = [workout, HKSeriesType.workoutRoute()]
        for id in [HKQuantityTypeIdentifier.heartRate, .distanceCycling] {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                read.insert(t); share.insert(t)
            }
        }
        for id in [HKQuantityTypeIdentifier.oxygenSaturation, .cyclingCadence] {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { read.insert(t) }
        }
        read.insert(HKSeriesType.workoutRoute())
        healthStore.requestAuthorization(toShare: share, read: read) { [weak self] ok, error in
            DispatchQueue.main.async {
                self?.authorized = ok
                if let error { self?.lastError = error.localizedDescription }
            }
        }
    }

    func startWatchWorkout() {
        didReceiveWatchDataThisRide = false
        heartRateBPM = nil
        watchSpeedMps = nil
        watchCadenceRPM = nil
        lastSpeedSensorAt = nil
        lastCadenceSensorAt = nil
        lastHeartRateAt = nil
        lastAnyDataAt = nil
        speedSensorConnected = false
        cadenceSensorConnected = false
        heartRateConnected = false
        lastError = nil

        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "HealthKit 없음"
            lastError = "이 기기에서 HealthKit을 사용할 수 없습니다."
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        statusMessage = "워치 앱 실행 중…"
        broadcastWorkoutActive(true)        // 권위 상태 = 활성 (워치가 따라 세션 시작)
        launchWatchApp(config: config, attempt: 1)   // 워치 앱을 깨워 방송을 받게 함
    }

    /// 폰의 권위 워크아웃 상태를 워치로 방송한다.
    /// applicationContext(영구)로 항상 저장하고, reachable 이면 sendMessage 로 즉시도 보낸다.
    /// 워치는 더 새 토큰만 채택해 정합하므로 재생·중복에 안전하다.
    private func broadcastWorkoutActive(_ active: Bool) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        workoutToken = Date().timeIntervalSince1970
        let payload: [String: Any] = ["workoutActive": active, "wToken": workoutToken]
        try? s.updateApplicationContext(payload)
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func launchWatchApp(config: HKWorkoutConfiguration, attempt: Int) {
        healthStore.startWatchApp(with: config) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    self.statusMessage = "워치 실행 실패"
                    self.retryWatchLaunch(config: config, attempt: attempt)
                    return
                }
                if success {
                    self.lastError = nil
                    self.statusMessage = "워치 워크아웃 대기"
                    // 시작은 broadcastWorkoutActive(true) 가 담당(레벨 기반). 여기선 깨우기만.
                    return
                }
                self.lastError = """
                Watch 앱이 설치되지 않았습니다.
                iPhone Watch 앱 → 일반 → BikeCom → "Apple Watch에 설치"를 켜세요.
                """
                self.statusMessage = "워치 앱 미설치"
                self.retryWatchLaunch(config: config, attempt: attempt)
            }
        }
    }

    private func retryWatchLaunch(config: HKWorkoutConfiguration, attempt: Int) {
        guard attempt < 6 else { return }
        statusMessage = "워치 앱 설치 대기… (\(attempt)/5)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.launchWatchApp(config: config, attempt: attempt + 1)
        }
    }

    func stopWatchWorkout() {
        broadcastWorkoutActive(false)       // 권위 상태 = 비활성 (워치가 따라 세션 종료)
        heartRateBPM = nil
        watchSpeedMps = nil
        watchCadenceRPM = nil
        lastSpeedSensorAt = nil
        lastCadenceSensorAt = nil
        lastHeartRateAt = nil
        lastAnyDataAt = nil
        speedSensorConnected = false
        cadenceSensorConnected = false
        heartRateConnected = false
        statusMessage = "대기"
    }

    private func refreshSensorConnectionFlags() {
        let now = Date()
        // 값이 실제로 바뀔 때만 대입한다. (@Published 는 같은 값이어도 대입하면 objectWillChange 를
        // 발행하므로, 0.5초마다 무조건 대입하면 상위 session 이 계속 갱신돼 화면이 깜빡인다.)
        let speed = isFresh(lastSpeedSensorAt, now: now)
        if speed != speedSensorConnected { speedSensorConnected = speed }
        let cadence = isFresh(lastCadenceSensorAt, now: now)
        if cadence != cadenceSensorConnected { cadenceSensorConnected = cadence }
        let hr = isFresh(lastHeartRateAt, now: now)
        if hr != heartRateConnected { heartRateConnected = hr }
        if !hr, heartRateBPM != nil { heartRateBPM = nil }
        let receiving = lastAnyDataAt.map { now.timeIntervalSince($0) <= sensorFreshness } ?? false
        if receiving {
            let msg = watchReachable ? "워치 데이터 수신 중" : "워치 데이터 수신(백그라운드)"
            if msg != statusMessage { statusMessage = msg }
        } else if lastError == nil, statusMessage.hasPrefix("워치 데이터 수신") {
            // 워치가 DISCONNECT 되어 데이터가 끊기면 '수신 중' 표시를 해제한다(멈춤 방지).
            statusMessage = "대기"
        }
    }

    private func isFresh(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) <= sensorFreshness
    }

    private func handle(_ message: [String: Any]) {
        // 워치 버튼(CONNECT/DISCONNECT) 요청 → RideSession 으로 전달(폰이 ride 를 시작/종료).
        if let req = message["workoutRequest"] as? Bool {
            DispatchQueue.main.async { self.onWatchRequest?(req) }
        }
        if let err = message["workoutError"] as? String {
            DispatchQueue.main.async {
                self.lastError = err
                self.statusMessage = "워치 워크아웃 오류"
            }
        }
        if WCPayload.bool(message, "workoutStarted") == true {
            DispatchQueue.main.async { self.statusMessage = "워치 워크아웃 시작됨" }
        }
        if let v = WCPayload.double(message, "spo2") {
            DispatchQueue.main.async {
                self.spo2 = v
                if let t = WCPayload.double(message, "spo2Date") {
                    self.spo2Date = Date(timeIntervalSince1970: t)
                } else {
                    self.spo2Date = Date()
                }
            }
        }
        guard WCPayload.hasSensorData(message) else { return }

        DispatchQueue.main.async {
            self.didReceiveWatchDataThisRide = true
            self.lastError = nil
            self.lastAnyDataAt = Date()

            if let hr = WCPayload.int(message, "hr"), hr > 0 {
                self.lastHeartRateAt = Date()
                self.heartRateBPM = hr
                self.heartRateConnected = true
            }
            if message["speedMps"] != nil {
                self.lastSpeedSensorAt = Date()
                if let v = WCPayload.double(message, "speedMps"), v >= 0 {
                    self.watchSpeedMps = v
                }
                self.speedSensorConnected = true
            }
            if message["cadence"] != nil {
                self.lastCadenceSensorAt = Date()
                if let rpm = WCPayload.int(message, "cadence"), rpm >= 0 {
                    self.watchCadenceRPM = rpm
                }
                self.cadenceSensorConnected = true
            }
        }
    }
}

extension WatchSensorManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.sessionActivated = state == .activated
            self.watchReachable = session.isReachable
            if let error {
                self.lastError = error.localizedDescription
                self.statusMessage = "Watch 연결 오류"
            } else if state == .activated {
                self.statusMessage = session.isPaired ? "Watch 연결됨" : "Watch 미페어링"
                let ctx = session.receivedApplicationContext
                if !ctx.isEmpty { self.handle(ctx) }
                // 새로 활성화된 워치가 현재 권위 상태를 따라오도록 재방송.
                self.broadcastWorkoutActive(self.isRideActive())
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.watchReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }
}
