import SwiftUI

/// 앱의 루트 뷰. 대시보드 단일 화면 — 지도·기록·장치·설정은 ⚙️ 버튼(정리된 리스트)으로 접근.
struct ContentView: View {
    @EnvironmentObject var session: RideSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            NavigationStack {
                DashboardView()
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { session.refreshScreenAwake() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refreshScreenAwake() }
        }
    }
}

#if DEBUG
// 캔버스(Resume)에서 더미 데이터가 채워진 전체 앱 목업을 볼 수 있다.
#Preview("iPhone 12 mini (목업)") {
    ContentView()
        .environmentObject(RideSession.preview)
        .preferredColorScheme(.dark)
        .previewDevice(PreviewDevice(rawValue: "iPhone 12 mini"))
}

#Preview("앱 전체 (빈 상태)") {
    ContentView()
        .environmentObject(RideSession())
        .preferredColorScheme(.dark)
}
#endif
