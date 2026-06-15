import SwiftUI

// MARK: - Apple Workout 앱과 동일한 타이포·간격

enum WorkoutScreenStyle {
    static let timerFont = Font.system(size: 36, weight: .bold, design: .monospaced)
    static let metricFont = Font.system(size: 32, weight: .bold, design: .rounded)
    static let unitFont = Font.system(size: 11, weight: .semibold)
    static let labelFont = Font.system(size: 11, weight: .regular)
    static let heartIconSize: CGFloat = 22
    static let connectionLightSize: CGFloat = 22   // 연결등을 하트와 같은 크기로
    static let sectionSpacing: CGFloat = 0
    static let leadingInset: CGFloat = 2
}

/// 워치 운동 화면·컴플리케이션 공통 — 상단 녹색 자전거 아이콘(Apple Workout 스타일).
struct WorkoutBikeIcon: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: size, height: size)
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundColor(.white)
        }
        .accessibilityLabel("BikeCom")
    }
}

/// 센서 연결 상태 표시등 — 연결 시 파랑(폰의 워치 연결 표기와 동일), 미연결 시 회색.
struct ConnectionLight: View {
    let connected: Bool
    var diameter: CGFloat = 6

    var body: some View {
        Circle()
            .fill(connected ? Color.blue : Color.gray.opacity(0.45))
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(connected ? "연결됨" : "미연결")
    }
}

/// 큰 숫자 · 작은 단위 · (연결등) · 오른쪽 라벨.
struct WorkoutMetricRow: View {
    let value: String
    let unit: String
    let labelTop: String
    let labelBottom: String?
    var connected: Bool? = nil
    /// nil = 하트 없음, true = 맥동(연결됨), false = 정지 하트.
    var heartPounding: Bool? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            Text(value)
                .font(WorkoutScreenStyle.metricFont)
                .foregroundColor(.white)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            if let heartPounding {
                Image(systemName: "heart.fill")
                    .font(.system(size: WorkoutScreenStyle.heartIconSize))
                    .foregroundColor(.red)
                    .symbolEffect(.pulse, options: .repeating, isActive: heartPounding)
                    .padding(.leading, 1)
            }

            Text(unit)
                .font(WorkoutScreenStyle.unitFont)
                .foregroundColor(.white.opacity(0.85))

            if let connected {
                ConnectionLight(connected: connected, diameter: WorkoutScreenStyle.connectionLightSize)
                    .padding(.leading, 2)
            }

            Spacer(minLength: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(labelTop)
                    .font(WorkoutScreenStyle.labelFont)
                    .foregroundColor(.white.opacity(0.85))
                if let labelBottom {
                    Text(labelBottom)
                        .font(WorkoutScreenStyle.labelFont)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }
}

/// 경과 시간 — Workout 타이머 형식 `00:30.97`
func formatWorkoutElapsed(_ seconds: TimeInterval) -> String {
    let clamped = max(0, seconds)
    let whole = Int(clamped)
    let centis = Int((clamped - Double(whole)) * 100)
    return String(format: "%02d:%02d.%02d", whole / 60, whole % 60, centis)
}

/// 거리 — Workout 타이머와 같은 크기·위치용 `12.34 km`
func formatWorkoutDistance(km: Double) -> String {
    String(format: "%.2f km", km)
}
