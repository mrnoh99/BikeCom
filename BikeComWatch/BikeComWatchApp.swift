import SwiftUI
import HealthKit
import WatchKit

/// 워치 앱 진입점. 아이폰이 `startWatchApp(toHandle:)` 으로 띄우면
/// `WatchAppDelegate.handle(_:)` 가 워크아웃을 시작한다.
@main
struct BikeComWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(WorkoutManager.shared)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WorkoutManager.shared.requestAuthorization()
        WorkoutManager.shared.consumePendingWorkoutCommandIfNeeded()
    }

    /// 아이폰 `startWatchApp` 으로 앱을 깨울 때 호출된다. 여기서 세션을 직접 시작하지 않고
    /// 폰의 `workoutActive` 방송(reconcile)만 따른다 — 이중 HKWorkoutSession 생성·크래시 방지.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WorkoutManager.shared.adoptWorkoutConfiguration(workoutConfiguration)
    }
}
