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
        // 주행 종료(Done/DISCONNECT) 직후 요약을 잠깐 보여준다.
        .sheet(item: $workout.summary) { summary in
            summaryView(summary)
        }
    }

    // MARK: - 주행 요약 (종료 직후)

    private func summaryView(_ s: WorkoutSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    WorkoutBikeIcon(size: 18)
                    Text("라이딩 요약")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.yellow)
                }
                .padding(.bottom, 2)

                summaryRow("거리", String(format: "%.2f", s.distanceMeters / 1000), "KM")
                summaryRow("시간", Self.duration(s.elapsedSeconds), "")
                summaryRow("평균 속도", String(format: "%.1f", s.avgSpeedMps * 3.6), "KM/H")
                summaryRow("평균 심박", s.avgHeartRate > 0 ? "\(s.avgHeartRate)" : "--", "BPM")
                summaryRow("평균 케이던스", s.avgCadenceRPM > 0 ? "\(s.avgCadenceRPM)" : "--", "RPM")

                Button("완료") { workout.summary = nil }
                    .frame(maxWidth: .infinity)
                    .tint(.green)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryRow(_ label: String, _ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// 경과 초 → H:MM:SS 또는 M:SS.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
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

            // 2) 심박수 (현재) — 연결되면 맥동 하트
            WorkoutMetricRow(
                value: workout.heartRate > 0 ? "\(workout.heartRate)" : "--",
                unit: "BPM", labelTop: "심박수", labelBottom: nil,
                heartPounding: workout.isRunning && workout.heartRate > 0
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
                    // CONNECT: 워치 센서(심박 등)만 켬. 폰 Start 와 별개.
                    // DISCONNECT: 폰 주행 중이면 종료 요청, 아니면 워치 세션만 종료.
                    workout.requestWorkout(!workout.isRunning)
                } label: {
                    Text(workout.isRunning ? "DISCONNECT" : "CONNECT")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(minWidth: 88)
                }
                .tint(workout.isRunning ? .red : .green)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Text("Developed by JaiSung NOH MD 2026")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
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
