import AppIntents
import Foundation

/// 컴플리케이션에서 주행 시작 — App Group 명령 후 워치 앱을 연다.
struct StartRideIntent: AppIntent {
    static var title: LocalizedStringResource = "시작"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        RideMetricsStore.setPendingCommand("start")
        return .result()
    }
}

/// 컴플리케이션에서 주행 정지.
struct StopRideIntent: AppIntent {
    static var title: LocalizedStringResource = "정지"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        RideMetricsStore.setPendingCommand("stop")
        return .result()
    }
}
