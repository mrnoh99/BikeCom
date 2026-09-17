import SwiftUI
#if canImport(GoogleMaps)
import GoogleMaps
#endif
#if canImport(NMapsMap)
import NMapsMap
#endif

/// 앱 진입점. 라이딩 세션(센서·GPS·통계)을 전역 상태로 주입한다.
@main
struct BikeComApp: App {
    @StateObject private var session = RideSession()

    init() {
        // 설정(⚙️ → 지도 → 지도 API 키)에서 입력한 키가 있으면 그쪽이 우선이고,
        // 없으면 Info.plist 의 빌드 고정 키로 폴백(GMapsConfig/NaverConfig 참고).
        #if canImport(GoogleMaps)
        if GMapsConfig.hasKey { GMSServices.provideAPIKey(GMapsConfig.apiKey) }
        #endif
        #if canImport(NMapsMap)
        if NaverConfig.hasKey { NMFAuthManager.shared().ncpKeyId = NaverConfig.clientId }
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
