import AppIntents
import Foundation

/// 컴플리케이션 CONNECT — 워치 데이터(심박·속도·케이던스)를 폰으로 보내기 시작.
struct StartRideIntent: AppIntent {
    static var title: LocalizedStringResource = "CONNECT"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        RideMetricsStore.setPendingCommand("start")
        return .result()
    }
}

/// 컴플리케이션 DISCONNECT — 워치 데이터 송신 중지.
struct StopRideIntent: AppIntent {
    static var title: LocalizedStringResource = "DISCONNECT"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        RideMetricsStore.setPendingCommand("stop")
        return .result()
    }
}
