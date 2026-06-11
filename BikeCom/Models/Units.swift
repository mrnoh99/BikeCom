import Foundation

/// 거리·속도 표시 단위. 기본은 km / km·h.
enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case kilometers
    case miles

    var id: String { rawValue }

    var distanceLabel: String { self == .kilometers ? "km" : "mi" }
    var speedLabel: String { self == .kilometers ? "km/h" : "mph" }

    /// 미터 → 표시 거리
    func distance(fromMeters m: Double) -> Double {
        self == .kilometers ? m / 1000.0 : m / 1609.344
    }

    /// m/s → 표시 속도
    func speed(fromMetersPerSecond v: Double) -> Double {
        self == .kilometers ? v * 3.6 : v * 2.2369362921
    }
}

/// 초 → "M:SS" 또는 "H:MM:SS"
func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}
