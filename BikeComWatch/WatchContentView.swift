import SwiftUI

/// 워치 주행화면 — 실시간 심박수 + 시작/정지 + 휴식 중 SpO2 측정 버튼.
/// 아이폰 Start 로 자동 실행되지만 워치에서 직접 시작할 수도 있다.
struct WatchContentView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.title3)
                    .symbolEffect(.pulse, isActive: workout.isRunning)

                Text(workout.heartRate > 0 ? "\(workout.heartRate)" : "--")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
                    .contentTransition(.numericText())

                Text("bpm")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    workout.isRunning ? workout.stopWorkout() : workout.startWorkout()
                } label: {
                    Text(workout.isRunning ? "정지" : "시작")
                        .frame(maxWidth: .infinity)
                }
                .tint(workout.isRunning ? .red : .green)
                .padding(.top, 4)

                Divider().padding(.vertical, 2)

                spo2Section
            }
            .padding()
        }
        .onAppear { workout.requestAuthorization() }
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
