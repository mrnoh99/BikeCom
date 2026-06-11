import SwiftUI
#if canImport(GoogleMaps)
import GoogleMaps
#endif

/// 앱 진입점. 라이딩 세션(센서·GPS·통계)을 전역 상태로 주입한다.
@main
struct BikeComputerApp: App {
    @StateObject private var session = RideSession()

    init() {
        #if canImport(GoogleMaps)
        // Info.plist 의 GMSApiKey 가 있으면 Google 지도 초기화(과거 코스 오버레이용).
        if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !key.isEmpty {
            GMSServices.provideAPIKey(key)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}
