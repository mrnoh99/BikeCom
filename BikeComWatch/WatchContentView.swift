import SwiftUI

/// 워치 주행화면 — Apple Workout 앱과 동일한 크기·위치·폰트.
struct WatchContentView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        TabView {
            workoutPage
            spo2Page
        }
        .tabViewStyle(.verticalPage)
        .onAppear {
            workout.requestAuthorization()
            workout.consumePendingWorkoutCommandIfNeeded()
        }
    }

    // MARK: - Page 1 (Apple 피트니스 '실외 자전거' 스타일)
    // 1) 현재 시각  2) 심박수  3) 속도+연결등  4) 케이던스+연결등  5) 시작/정지

    private var workoutPage: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 1) 현재 시각 (좌상단 자전거 + 큰 시계, 1초마다 갱신)
            HStack(spacing: 4) {
                WorkoutBikeIcon(size: 20)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.clock.string(from: ctx.date))
                        .font(WorkoutScreenStyle.timerFont)
                        .foregroundColor(.yellow)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            // 2) 심박수 (현재)
            WorkoutMetricRow(
                value: workout.heartRate > 0 ? "\(workout.heartRate)" : "--",
                unit: "BPM", labelTop: "심박수", labelBottom: nil
            )

            // 3) 속도 (현재) + 연결등
            WorkoutMetricRow(
                value: workout.speedMps > 0 ? String(format: "%.1f", workout.speedMps * 3.6) : "--",
                unit: "KM/H", labelTop: "속도", labelBottom: nil,
                connected: workout.speedSensorConnected
            )

            // 4) 케이던스 (현재) + 연결등
            WorkoutMetricRow(
                value: workout.cadenceRPM > 0 ? "\(workout.cadenceRPM)" : "--",
                unit: "RPM", labelTop: "케이던스", labelBottom: nil,
                connected: workout.cadenceSensorConnected
            )

            Spacer(minLength: 2)

            // 5) 시작 / 정지
            HStack {
                Spacer(minLength: 0)
                Button {
                    workout.isRunning ? workout.stopWorkout() : workout.startWorkout()
                } label: {
                    Text(workout.isRunning ? "DISCONNECT" : "CONNECT")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(minWidth: 88)
                }
                .tint(workout.isRunning ? .red : .green)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, WorkoutScreenStyle.leadingInset)
        .padding(.trailing, 4)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    // MARK: - Page 2 (SpO2)

    private var spo2Page: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "lungs.fill").foregroundColor(.cyan)
                Text(workout.spo2 > 0 ? "SpO₂ \(workout.spo2)%" : "SpO₂ --")
                    .font(WorkoutScreenStyle.metricFont)
                    .foregroundColor(.cyan)
            }
            Button { workout.measureSpO2() } label: {
                Label(workout.measuringSpO2 ? "측정 대기…" : "SpO₂ 측정",
                      systemImage: "lungs.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.cyan)
            .disabled(workout.measuringSpO2)
            Spacer(minLength: 0)
        }
        .padding()
    }
}
