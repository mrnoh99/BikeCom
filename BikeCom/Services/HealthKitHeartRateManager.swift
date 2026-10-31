import Foundation
import HealthKit
import Combine
import UIKit

/// 폰 단독 `HKWorkoutSession`(iOS 26+)으로 심박 측정 이어버즈(Powerbeats Pro 2 등)의 심박을
/// **HealthKit 경유**로 실시간 수신한다.
///
/// `BLEHeartRateManager`로 이어버즈를 직접 스캔·연결하려면 이어버드 b버튼을 더블프레스·홀드해
/// "운동 기구 연결" 모드로 들어가야 하는데, 이 모드는 **iPhone과의 오디오 연결을 끊는다**(Apple
/// 공식 문서). 반면 이 경로는 이어버즈를 평소처럼 음악 재생용으로 페어링해둔 채, 폰이 자체
/// 워크아웃 세션을 띄우기만 하면 Beats 펌웨어가 알아서 HealthKit으로 심박을 흘려보낸다 — 즉
/// **음악을 들으면서 동시에 심박을 받을 수 있다.** (Beats 앱의 "심박 모니터링" 토글은 켜져 있어야
/// 한다.) `HKWorkoutSession(healthStore:configuration:)`를 폰에서 직접 시작하는 API는
/// iOS 26부터 제공된다.
///
/// `finishWorkout()`을 호출하지 않으므로(= `session.end()`만), Health 앱에 별도 운동 기록이
/// 남지 않는다 — 순수하게 실시간 심박 파이프로만 쓴다(워치 쪽 `WorkoutManager`와 동일한 패턴).
final class HealthKitHeartRateManager: NSObject, ObservableObject {
    @Published private(set) var bpm: Int = 0
    @Published private(set) var active = false
    @Published private(set) var lastError: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isStarting = false
    private var lastSampleAt = Date.distantPast
    private var staleTimer: AnyCancellable?

    override init() {
        super.init()
        staleTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.decayIfStale() }
    }

    func start() {
        guard !active, !isStarting, HKHealthStore.isHealthDataAvailable() else { return }
        isStarting = true
        lastError = nil

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                dataSource.enableCollection(for: hrType, predicate: nil)
            }
            b.dataSource = dataSource
            s.delegate = self
            b.delegate = self
            session = s
            builder = b

            let startDate = Date()
            s.startActivity(with: startDate)
            b.beginCollection(withStart: startDate) { [weak self] success, error in
                guard let self else { return }
                self.isStarting = false
                if let error {
                    s.end()
                    self.session = nil
                    self.builder = nil
                    DispatchQueue.main.async { self.lastError = error.localizedDescription }
                    return
                }
                DispatchQueue.main.async { self.active = success }
            }
        } catch {
            isStarting = false
            session = nil
            builder = nil
            lastError = error.localizedDescription
        }
    }

    /// `session.end()`/`builder.endCollection(withEnd:completion:)`는 모두 비동기다 — 앱이
    /// 백그라운드로 내려간 직후 곧바로 완전히 서스펜드·종료되면 이 처리가 끝나기 전에 끊겨서,
    /// 시스템이 "운동 세션이 아직 살아있다"고 보고 상태 표시줄 표시(+배터리 소모)가 한동안
    /// 안 없어지는 문제가 실제로 있었다. `beginBackgroundTask`로 종료 처리가 끝날 때까지
    /// 몇 초 더 실행 시간을 확보해 이 레이스를 줄인다(사용자가 앱 스위처에서 바로 강제
    /// 종료하는 경우까지는 어떤 방법으로도 막을 수 없다 — 그 경우 OS가 즉시 프로세스를 죽인다).
    func stop() {
        isStarting = false
        guard let activeSession = session else { return }
        let activeBuilder = builder
        session = nil
        builder = nil

        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "HealthKitHeartRateStop") {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }

        activeSession.end()
        if let activeBuilder {
            activeBuilder.endCollection(withEnd: Date()) { _, _ in
                guard taskID != .invalid else { return }
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        } else if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }

        DispatchQueue.main.async {
            self.active = false
            self.bpm = 0
        }
    }

    private func decayIfStale() {
        guard Date().timeIntervalSince(lastSampleAt) > 10, bpm != 0 else { return }
        bpm = 0
    }
}

extension HealthKitHeartRateManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        DispatchQueue.main.async {
            self.active = false
            self.bpm = 0
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        isStarting = false
        session?.end()
        session = nil
        builder = nil
        DispatchQueue.main.async {
            self.active = false
            self.lastError = error.localizedDescription
        }
    }
}

extension HealthKitHeartRateManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType),
              let q = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity() else { return }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let value = Int(q.doubleValue(for: bpmUnit).rounded())
        guard value > 0 else { return }
        lastSampleAt = Date()
        DispatchQueue.main.async { self.bpm = value }
    }
}
