import WidgetKit
import SwiftUI

/// 워치 컴플리케이션(WidgetKit accessory) — 최근 심박·평균속도·주행거리를 표시하고
/// 탭하면 BikeCom 워치 앱을 연다. 데이터는 App Group 공유 저장소에서 읽는다.
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
        // 주행 중이면 자주, 아니면 느리게 갱신(워치 위젯 예산 보호).
        let next = Date().addingTimeInterval(snap.isRunning ? 60 : 600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct BikeComComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RideEntry

    private var hrText: String { entry.snapshot.heartRate > 0 ? "\(entry.snapshot.heartRate)" : "--" }
    private var distText: String { String(format: "%.1f", entry.snapshot.distanceKm) }
    private var avgSpeedText: String { String(format: "%.1f", entry.snapshot.avgSpeedKmh) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "heart.fill").font(.system(size: 11)).foregroundColor(.red)
                    Text(hrText).font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }

        case .accessoryInline:
            Label("\(hrText) bpm · \(distText) km", systemImage: "bicycle")

        case .accessoryCorner:
            Text(hrText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .widgetLabel("BikeCom \(distText) km")

        case .accessoryRectangular:
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("BikeCom", systemImage: "bicycle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").foregroundColor(.red).font(.system(size: 11))
                        Text("\(hrText) bpm").font(.system(size: 13, weight: .medium))
                    }
                    Text("⌀ \(avgSpeedText) km/h · \(distText) km")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

        default:
            Text(hrText)
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
        .description("최근 심박·평균속도·주행거리를 표시하고 탭하면 앱을 엽니다.")
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
