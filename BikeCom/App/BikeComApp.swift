import SwiftUI

/// 앱 진입점. 라이딩 세션(센서·GPS·통계)을 전역 상태로 주입한다.
@main
struct BikeComApp: App {
    // CloudKit silent push(백그라운드 즉시 동기화) 수신 등록용. 자세한 건 AppDelegate.swift 참고.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = RideSession()

    init() {
        // 설정(⚙️ → 지도 → 지도 API 키)에서 입력한 키가 있으면 그쪽이 우선이고,
        // 없으면 Info.plist 의 빌드 고정 키로 폴백(GMapsConfig/NaverConfig 참고).
        GMapsConfig.applyIfNeeded(GMapsConfig.apiKey)
        NaverConfig.applyIfNeeded(NaverConfig.clientId)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}
