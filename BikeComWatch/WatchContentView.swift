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

    // MARK: - Page 1 (Workout 레이아웃)

    private var workoutPage: some View {
        VStack(alignment: .leading, spacing: WorkoutScreenStyle.sectionSpacing) {
            // 1. 좌상단 자전거
            WorkoutBikeIcon(size: 22)

            // 거리 (노란색·큰 글씨)
            Text(formatWorkoutDistance(km: workout.distanceMeters / 1000))
                .font(WorkoutScreenStyle.timerFont)
                .foregroundColor(.yellow)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            // 2. 현재 심박수 (평균 아님)
            heartRateRow

            // 평균 속도
            WorkoutMetricRow(
                value: workout.avgSpeedMps > 0
                    ? String(format: "%.0f", workout.avgSpeedMps * 3.6)
                    : "--",
                unit: "KM/H",
                labelTop: "평균 속도",
                labelBottom: nil,
                connected: workout.speedSensorConnected
            )

            // 평균 케이던스
            WorkoutMetricRow(
                value: workout.avgCadenceRPM > 0 ? "\(workout.avgCadenceRPM)" : "--",
                unit: "RPM",
                labelTop: "평균케이던스",
                labelBottom: nil,
                connected: workout.cadenceSensorConnected
            )

            Spacer(minLength: 2)

            HStack {
                Spacer(minLength: 0)
                Button {
                    workout.isRunning ? workout.stopWorkout() : workout.startWorkout()
                } label: {
                    Text(workout.isRunning ? "정지" : "시작")
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

    private var heartRateRow: some View {
        HStack(alignment: .center, spacing: 3) {
            HStack(alignment: .center, spacing: 3) {
                Text(workout.heartRate > 0 ? "\(workout.heartRate)" : "--")
                    .font(WorkoutScreenStyle.metricFont)
                    .foregroundColor(.white)
                    .contentTransition(.numericText())

                Image(systemName: "heart.fill")
                    .font(.system(size: WorkoutScreenStyle.heartIconSize, weight: .bold))
                    .foregroundColor(.red)
                    .symbolEffect(.pulse, isActive: workout.isRunning && workout.heartRate > 0)

                Text("BPM")
                    .font(WorkoutScreenStyle.unitFont)
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer(minLength: 2)

            VStack(spacing: 0) {
                Text(workout.avgHeartRate > 0 ? "\(workout.avgHeartRate)" : "--")
                    .font(WorkoutScreenStyle.metricFont)
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("평균 심박수")
                    .font(WorkoutScreenStyle.labelFont)
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 2)

            Text("심박수")
                .font(WorkoutScreenStyle.labelFont)
                .foregroundColor(.white.opacity(0.85))
        }
    }

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
