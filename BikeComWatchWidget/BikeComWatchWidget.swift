import AppIntents
import WidgetKit
import SwiftUI

/// 워치 컴플리케이션(WidgetKit accessory) — 주행 지표 + 시작 버튼.
/// 데이터는 App Group 공유 저장소에서 읽는다.
struct RideEntry: TimelineEntry {
    let date: Date
    let snapshot: RideMetricsStore.Snapshot
}

struct RideProvider: TimelineProvider {
    func placeholder(in context: Context) -> RideEntry {
        RideEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RideEntry) -> Void) {
        let snap = context.isPreview ? .placeholder : RideMetricsStore.load()
        completion(RideEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RideEntry>) -> Void) {
        let snap = RideMetricsStore.load()
        let entry = RideEntry(date: Date(), snapshot: snap)
        let next = Date().addingTimeInterval(snap.isRunning ? 60 : 600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct BikeComComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RideEntry

    private var snap: RideMetricsStore.Snapshot { entry.snapshot }
    private var hrText: String { snap.heartRate > 0 ? "\(snap.heartRate)" : "--" }
    private var avgHrText: String { snap.avgHeartRate > 0 ? "\(snap.avgHeartRate)" : "--" }
    private var distText: String { String(format: "%.1f", snap.distanceKm) }
    private var avgSpeedText: String { snap.avgSpeedKmh > 0 ? String(format: "%.0f", snap.avgSpeedKmh) : "--" }
    private var avgCadenceText: String { snap.avgCadenceRPM > 0 ? "\(snap.avgCadenceRPM)" : "--" }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularLayout
        case .accessoryCircular:
            circularLayout
        case .accessoryInline:
            inlineLayout
        case .accessoryCorner:
            cornerLayout
        default:
            Text(hrText)
        }
    }

    // MARK: - Rectangular (메인 — 5단 레이아웃)

    private var rectangularLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer(minLength: 0)
                WorkoutBikeIcon(size: 16)
            }

            Text("\(distText) km")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)

            HStack(spacing: 3) {
                Text(hrText).font(.system(size: 13, weight: .bold, design: .rounded))
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                Text("⌀\(avgHrText)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("⌀\(avgSpeedText)")
                        .font(.system(size: 11, weight: .medium))
                    ConnectionLight(connected: snap.speedSensorConnected, diameter: 5)
                }
                HStack(spacing: 2) {
                    Text("⌀\(avgCadenceText)")
                        .font(.system(size: 11, weight: .medium))
                    ConnectionLight(connected: snap.cadenceSensorConnected, diameter: 5)
                }
            }

            startButton
        }
    }

    @ViewBuilder
    private var startButton: some View {
        if snap.isRunning {
            Button(intent: StopRideIntent()) {
                Text("정지")
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        } else {
            Button(intent: StartRideIntent()) {
                Text("시작")
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
        }
    }

    // MARK: - Compact families

    private var circularLayout: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                WorkoutBikeIcon(size: 14)
                Text(hrText).font(.system(size: 15, weight: .bold, design: .rounded))
            }
        }
    }

    private var inlineLayout: some View {
        HStack(spacing: 4) {
            WorkoutBikeIcon(size: 12)
            Text("\(distText) km · \(hrText)♥ · ⌀\(avgSpeedText)")
        }
    }

    private var cornerLayout: some View {
        Text(hrText)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .widgetLabel {
                HStack(spacing: 3) {
                    WorkoutBikeIcon(size: 10)
                    Text("\(distText) km")
                }
            }
    }
}

struct BikeComComplication: Widget {
    let kind = "BikeComComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RideProvider()) { entry in
            BikeComComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("BikeCom")
        .description("거리·심박·평균속도·케이던스와 시작 버튼.")
        .supportedFamilies([.accessoryCircular, .accessoryInline,
                            .accessoryCorner, .accessoryRectangular])
    }
}

@main
struct BikeComWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        BikeComComplication()
    }
}
