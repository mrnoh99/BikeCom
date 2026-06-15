import SwiftUI

/// 앱의 루트 뷰. 하단 탭으로 Ride(대시보드)·Map·Routes·More 를 오간다.
struct ContentView: View {
    @EnvironmentObject var session: RideSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                DashboardView()
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .tag(0)
            .tabItem { Label("Ride", systemImage: "stopwatch.fill") }

            NavigationStack { MapTabView() }
                .tag(1)
                .tabItem { Label("Map", systemImage: "map.fill") }

            NavigationStack { RoutesView() }
                .tag(2)
                .tabItem { Label("Routes", systemImage: "list.bullet") }

            NavigationStack { MoreView() }
                .tag(3)
                .tabItem { Label("More", systemImage: "gearshape.fill") }
        }
        .tint(Theme.gold)
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
