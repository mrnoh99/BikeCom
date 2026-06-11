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
    @Published private(set) var statusMessage = "대기"
    @Published private(set) var lastError: String?

    @Published private(set) var spo2: Double?
    @Published private(set) var spo2Date: Date?

    private(set) var didReceiveWatchDataThisRide = false

    private let healthStore = HKHealthStore()
    private let sensorFreshness: TimeInterval = 5
    private var lastSpeedSensorAt: Date?
    private var lastCadenceSensorAt: Date?
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
        lastAnyDataAt = nil
        speedSensorConnected = false
        cadenceSensorConnected = false
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
        launchWatchApp(config: config, attempt: 1)
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
                    self.send(["command": "start"])
                    return
                }
                self.lastError = """
                Watch 앱이 설치되지 않았습니다.
                iPhone Watch 앱 → 일반 → BikeComputer → "Apple Watch에 설치"를 켜세요.
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
        send(["command": "stop"])
        heartRateBPM = nil
        watchSpeedMps = nil
        watchCadenceRPM = nil
        lastSpeedSensorAt = nil
        lastCadenceSensorAt = nil
        lastAnyDataAt = nil
        speedSensorConnected = false
        cadenceSensorConnected = false
        statusMessage = "대기"
    }

    private func refreshSensorConnectionFlags() {
        let now = Date()
        speedSensorConnected = isFresh(lastSpeedSensorAt, now: now)
        cadenceSensorConnected = isFresh(lastCadenceSensorAt, now: now)
        if let lastAnyDataAt, now.timeIntervalSince(lastAnyDataAt) <= sensorFreshness {
            statusMessage = watchReachable ? "워치 데이터 수신 중" : "워치 데이터 수신(백그라운드)"
        }
    }

    private func isFresh(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) <= sensorFreshness
    }

    private func send(_ payload: [String: Any]) {
        let s = WCSession.default
        guard s.activationState == .activated else {
            lastError = "WatchConnectivity 미활성"
            return
        }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil) { [weak self] error in
                DispatchQueue.main.async { self?.lastError = error.localizedDescription }
            }
        } else {
            do {
                try s.updateApplicationContext(payload)
            } catch {
                DispatchQueue.main.async { self.lastError = error.localizedDescription }
            }
        }
    }

    private func handle(_ message: [String: Any]) {
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
                self.heartRateBPM = hr
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
