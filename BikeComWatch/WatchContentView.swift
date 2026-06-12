import SwiftUI

/// 워치 주행화면 — 실시간 심박 + 센서 연결 상태 + 평균 지표 + 시작/정지 + SpO2.
/// 아이폰 Start 로 자동 실행되지만 워치에서 직접 시작할 수도 있다.
struct WatchContentView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                heartRate

                // 1·2·3. 속도/케이던스 센서 연결 상태
                HStack(spacing: 10) {
                    SensorBadge(title: "속도", on: workout.speedSensorConnected)
                    SensorBadge(title: "케이던스", on: workout.cadenceSensorConnected)
                }

                // 4. 평균 속도 · 평균 심박 · 주행거리
                HStack(spacing: 6) {
                    MetricBox(title: "평균속도",
                              value: String(format: "%.1f", workout.avgSpeedMps * 3.6),
                              unit: "km/h", tint: .green)
                    MetricBox(title: "평균심박",
                              value: workout.avgHeartRate > 0 ? "\(workout.avgHeartRate)" : "--",
                              unit: "bpm", tint: .red)
                }
                MetricBox(title: "주행거리",
                          value: String(format: "%.2f", workout.distanceMeters / 1000),
                          unit: "km", tint: .orange, wide: true)

                Button {
                    workout.isRunning ? workout.stopWorkout() : workout.startWorkout()
                } label: {
                    Text(workout.isRunning ? "정지" : "시작")
                        .frame(maxWidth: .infinity)
                }
                .tint(workout.isRunning ? .red : .green)
                .padding(.top, 2)

                Divider().padding(.vertical, 2)

                spo2Section
            }
            .padding()
        }
        .onAppear { workout.requestAuthorization() }
    }

    private var heartRate: some View {
        VStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
                .font(.title3)
                .symbolEffect(.pulse, isActive: workout.isRunning)
            Text(workout.heartRate > 0 ? "\(workout.heartRate)" : "--")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.red)
                .contentTransition(.numericText())
            Text("bpm")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // 휴식 중 SpO2 측정 (센서를 직접 켤 수 없어, 들어오는 측정값을 포착해 폰으로 전송)
    private var spo2Section: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "lungs.fill").foregroundColor(.cyan).font(.footnote)
                Text(workout.spo2 > 0 ? "SpO₂ \(workout.spo2)%" : "SpO₂ --")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.cyan)
                    .contentTransition(.numericText())
            }

            Button { workout.measureSpO2() } label: {
                Label(workout.measuringSpO2 ? "측정 대기…" : "SpO₂ 측정",
                      systemImage: "lungs.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.cyan)
            .disabled(workout.measuringSpO2)

            if workout.measuringSpO2 {
                Text("팔을 가만히 두고 '혈중 산소' 앱에서 측정하세요. 측정값이 들어오면 자동으로 폰에 전송됩니다.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// 센서 연결 상태 배지 — 연결 시 초록, 미연결 시 회색.
private struct SensorBadge: View {
    let title: String
    let on: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(on ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption2)
                .foregroundColor(on ? .primary : .secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(on ? 0.12 : 0.04), in: Capsule())
    }
}

/// 지표 박스 — 제목/값/단위.
private struct MetricBox: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color
    var wide: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
