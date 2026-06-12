import SwiftUI

/// 워치 운동 화면·컴플리케이션 공통 — 상단 녹색 자전거 아이콘(Apple Workout 스타일).
struct WorkoutBikeIcon: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: size, height: size)
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundColor(.white)
        }
        .accessibilityLabel("BikeCom")
    }
}

/// 센서 연결 상태 표시등 — 연결 시 초록, 미연결 시 회색.
struct ConnectionLight: View {
    let connected: Bool
    var diameter: CGFloat = 7

    var body: some View {
        Circle()
            .fill(connected ? Color.green : Color.gray.opacity(0.45))
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(connected ? "연결됨" : "미연결")
    }
}

/// 평균 지표 + 연결 표시등 한 줄.
struct MeanMetricRow: View {
    let title: String
    let value: String
    let unit: String
    let connected: Bool

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            ConnectionLight(connected: connected)
        }
    }
}
