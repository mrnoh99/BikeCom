import SwiftUI

/// 대시보드 색상·라벨 등 디자인 토큰. 스크린샷의 색 코딩을 그대로 따른다.
enum Theme {
    // 배경
    static let background = Color.black
    static let cardBorder = Color(white: 0.16)
    static let label = Color(white: 0.62)

    // 지표별 강조색
    static let value = Color.white          // 시계·평균속도·총시간
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.10)   // 거리·라이딩시간
    static let blue = Color(red: 0.16, green: 0.55, blue: 1.0)   // 현재 속도
    static let red = Color(red: 1.0, green: 0.30, blue: 0.27)    // 심박수
    static let purple = Color(red: 0.75, green: 0.40, blue: 0.95) // 누적 거리(달/년/총)
    static let cyan = Color(red: 0.25, green: 0.80, blue: 0.85)  // 산소포화도(SpO2)
    static let green = Color(red: 0.30, green: 0.78, blue: 0.40) // Start 버튼
    static let gray = Color(white: 0.30)                         // Done 버튼

    /// 큰 숫자 폰트 (대시보드 메트릭 값)
    static func metricFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}
