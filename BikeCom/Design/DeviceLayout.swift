import SwiftUI

/// iPhone 12 mini(375×812pt) 기준 대시보드 레이아웃.
/// 더 큰 기기는 비율만 소폭 키우고, mini 에서 한 화면·가독성을 최우선으로 맞춘다.
enum DeviceLayout {
    static let miniWidth: CGFloat = 375
    /// 노치·홈 인디케이터 제외 후 대시보드가 쓰는 실제 높이(≈812−47−34).
    static let miniContentHeight: CGFloat = 731

    struct Dashboard: Equatable {
        let scale: CGFloat

        let labelFont: CGFloat
        let unitFont: CGFloat
        let chipFont: CGFloat
        let chipHPadding: CGFloat
        let chipVPadding: CGFloat
        let headerHPadding: CGFloat
        let headerTopPadding: CGFloat
        let headerBottomPadding: CGFloat
        let controlHeight: CGFloat
        let controlFont: CGFloat
        let controlVPadding: CGFloat
        let gearIcon: CGFloat
        let footerFont: CGFloat
        let gridHPadding: CGFloat

        /// 375×731(세이프 영역) 기준 튜닝값. scale 로 다른 기기에 소폭 대응.
        static func make(for size: CGSize) -> Dashboard {
            let h = size.height / miniContentHeight
            let w = size.width / miniWidth
            // mini 보다 큰 폰은 최대 8%만 키움. 작으면 92%까지 축소.
            let scale = min(1.08, max(0.92, min(h, w)))
            return Dashboard(
                scale: scale,
                labelFont: 10 * scale,
                unitFont: 9 * scale,
                chipFont: 15 * scale,
                chipHPadding: 11 * scale,
                chipVPadding: 6 * scale,
                headerHPadding: 12 * scale,
                headerTopPadding: 4 * scale,
                headerBottomPadding: 10 * scale,
                controlHeight: 42 * scale,
                controlFont: 17 * scale,
                controlVPadding: 6 * scale,
                gearIcon: 20 * scale,
                footerFont: 8 * scale,
                gridHPadding: 6 * scale
            )
        }

        static let standard = make(for: CGSize(width: miniWidth, height: miniContentHeight))
    }
}

struct DashboardLayoutKey: EnvironmentKey {
    static let defaultValue = DeviceLayout.Dashboard.standard
}

extension EnvironmentValues {
    var dashboardLayout: DeviceLayout.Dashboard {
        get { self[DashboardLayoutKey.self] }
        set { self[DashboardLayoutKey.self] = newValue }
    }
}
