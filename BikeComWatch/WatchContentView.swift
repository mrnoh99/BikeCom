import SwiftUI

/// 워치 주행화면 — 운동 앱 스타일 레이아웃.
/// 1) 녹색 자전거 아이콘  2) 거리  3) 심박+평균심박  4) 평균속도·케이던스+연결등  5) 시작/정지
struct WatchContentView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 1. 상단 자전거 아이콘 (Workout 앱과 동일)
                HStack {
                    Spacer(minLength: 0)
                    WorkoutBikeIcon(size: 28)
                }

                // 2. 주행 거리
                distanceSection

                // 3. 현재 심박 + 하트 · 평균 심박
                heartRateSection

                // 4. 평균 속도 · 평균 케이던스 (각 연결 표시등)
                HStack(alignment: .top, spacing: 8) {
                    MeanMetricRow(
                        title: "평균 KM/H",
                        value: workout.avgSpeedMps > 0 ? String(format: "%.0f", workout.avgSpeedMps * 3.6) : "--",
                        unit: "KM/H",
                        connected: workout.speedSensorConnected
                    )
                    Spacer(minLength: 0)
                    MeanMetricRow(
                        title: "케이던스",
                        value: workout.avgCadenceRPM > 0 ? "\(workout.avgCadenceRPM)" : "--",
                        unit: "RPM",
                        connected: workout.cadenceSensorConnected
                    )
                }

                // 5. 시작 / 정지
                Button {
                    workout.isRunning ? workout.stopWorkout() : workout.startWorkout()
                } label: {
                    Text(workout.isRunning ? "정지" : "시작")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .tint(workout.isRunning ? .red : .green)
                .padding(.top, 2)

                Divider().padding(.vertical, 2)
                spo2Section
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .onAppear {
            workout.requestAuthorization()
            workout.consumePendingWorkoutCommandIfNeeded()
        }
    }

    private var distanceSection: some View {
        VStack(spacing: 0) {
            Text(String(format: "%.2f", workout.distanceMeters / 1000))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("km")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heartRateSection: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(workout.heartRate > 0 ? "\(workout.heartRate)" : "--")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.title3)
                    .symbolEffect(.pulse, isActive: workout.isRunning && workout.heartRate > 0)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text("평균 심박수")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(workout.avgHeartRate > 0 ? "\(workout.avgHeartRate) BPM" : "-- BPM")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        }
    }

    private var spo2Section: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "lungs.fill").foregroundColor(.cyan).font(.footnote)
                Text(workout.spo2 > 0 ? "SpO₂ \(workout.spo2)%" : "SpO₂ --")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.cyan)
            }
            Button { workout.measureSpO2() } label: {
                Label(workout.measuringSpO2 ? "측정 대기…" : "SpO₂ 측정",
                      systemImage: "lungs.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.cyan)
            .disabled(workout.measuringSpO2)
        }
    }
}
