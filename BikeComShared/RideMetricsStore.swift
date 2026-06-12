import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 워치 앱 ↔ 워치 컴플리케이션(위젯) 공유 저장소.
/// App Group(`group.com.jaisungnoh.bikecom`) 의 UserDefaults 로 최신 주행 지표를 공유한다.
enum RideMetricsStore {
    static let appGroup = "group.com.jaisungnoh.bikecom"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    struct Snapshot {
        var isRunning: Bool = false
        var heartRate: Int = 0
        var avgHeartRate: Int = 0
        var speedMps: Double = 0
        var avgSpeedMps: Double = 0
        var distanceMeters: Double = 0
        var updatedAt: Date = .distantPast

        /// 표시용 환산값
        var speedKmh: Double { speedMps * 3.6 }
        var avgSpeedKmh: Double { avgSpeedMps * 3.6 }
        var distanceKm: Double { distanceMeters / 1000 }

        static let placeholder = Snapshot(isRunning: true, heartRate: 138, avgHeartRate: 132,
                                          speedMps: 7.5, avgSpeedMps: 6.8,
                                          distanceMeters: 12_300, updatedAt: Date())
    }

    /// 위젯 예산 보호용: reloadAllTimelines 는 최소 간격으로만 호출.
    private static var lastReloadAt: Date = .distantPast
    private static let minReloadInterval: TimeInterval = 20

    static func save(_ s: Snapshot, forceReload: Bool = false) {
        guard let d = defaults else { return }
        d.set(s.isRunning, forKey: "isRunning")
        d.set(s.heartRate, forKey: "heartRate")
        d.set(s.avgHeartRate, forKey: "avgHeartRate")
        d.set(s.speedMps, forKey: "speedMps")
        d.set(s.avgSpeedMps, forKey: "avgSpeedMps")
        d.set(s.distanceMeters, forKey: "distanceMeters")
        d.set(s.updatedAt.timeIntervalSince1970, forKey: "updatedAt")

        #if canImport(WidgetKit)
        let now = Date()
        if forceReload || now.timeIntervalSince(lastReloadAt) >= minReloadInterval {
            lastReloadAt = now
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    static func load() -> Snapshot {
        guard let d = defaults else { return Snapshot() }
        return Snapshot(
            isRunning: d.bool(forKey: "isRunning"),
            heartRate: d.integer(forKey: "heartRate"),
            avgHeartRate: d.integer(forKey: "avgHeartRate"),
            speedMps: d.double(forKey: "speedMps"),
            avgSpeedMps: d.double(forKey: "avgSpeedMps"),
            distanceMeters: d.double(forKey: "distanceMeters"),
            updatedAt: Date(timeIntervalSince1970: d.double(forKey: "updatedAt"))
        )
    }
}
