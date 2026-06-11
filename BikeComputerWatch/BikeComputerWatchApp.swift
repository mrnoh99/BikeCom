import SwiftUI
import HealthKit
import WatchKit

/// 워치 앱 진입점. 아이폰이 `startWatchApp(toHandle:)` 으로 띄우면
/// `WatchAppDelegate.handle(_:)` 가 워크아웃을 시작한다.
@main
struct BikeComputerWatchApp: App {
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
    }

    /// 아이폰에서 라이딩을 시작하면 이 콜백으로 워크아웃 설정이 전달된다.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WorkoutManager.shared.startWorkout(configuration: workoutConfiguration)
    }
}
