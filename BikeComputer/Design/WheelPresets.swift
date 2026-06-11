import Foundation

/// 속도 센서용 휠 직경법 — 알려진 일반 규격(인치·700C)과 대표 둘레.
/// 둘레(mm) → 직경(mm) = C / π, 속도 환산은 둘레(m) = C / 1000.
enum WheelPresets {
    struct Option: Identifiable, Equatable {
        let id: String
        let label: String
        /// 대표 롤링 둘레(mm). 속도·거리 환산에 사용.
        let circumferenceMm: Double

        var diameterMm: Double { circumferenceMm / .pi }
        var circumferenceMeters: Double { circumferenceMm / 1000 }
    }

    struct Category: Identifiable {
        let id: String
        let title: String
        let options: [Option]
    }

    static let categories: [Category] = [
        Category(id: "700c", title: "700C (로드·그래벨)", options: [
            .init(id: "700x23", label: "700 × 23C", circumferenceMm: 2097),
            .init(id: "700x25", label: "700 × 25C", circumferenceMm: 2105),
            .init(id: "700x28", label: "700 × 28C", circumferenceMm: 2136),
            .init(id: "700x30", label: "700 × 30C", circumferenceMm: 2146),
            .init(id: "700x32", label: "700 × 32C", circumferenceMm: 2155),
            .init(id: "700x35", label: "700 × 35C", circumferenceMm: 2168),
            .init(id: "700x38", label: "700 × 38C", circumferenceMm: 2180),
            .init(id: "700x40", label: "700 × 40C", circumferenceMm: 2200),
        ]),
        Category(id: "29", title: "29\"", options: [
            .init(id: "29x1.9", label: "29 × 1.9\"", circumferenceMm: 2281),
            .init(id: "29x2.0", label: "29 × 2.0\"", circumferenceMm: 2288),
            .init(id: "29x2.1", label: "29 × 2.1\"", circumferenceMm: 2315),
            .init(id: "29x2.25", label: "29 × 2.25\"", circumferenceMm: 2332),
            .init(id: "29x2.3", label: "29 × 2.3\"", circumferenceMm: 2346),
            .init(id: "29x2.4", label: "29 × 2.4\"", circumferenceMm: 2359),
            .init(id: "29x2.6", label: "29 × 2.6\"", circumferenceMm: 2385),
        ]),
        Category(id: "27.5", title: "27.5\" (650B)", options: [
            .init(id: "27.5x1.9", label: "27.5 × 1.9\"", circumferenceMm: 2091),
            .init(id: "27.5x2.0", label: "27.5 × 2.0\"", circumferenceMm: 2116),
            .init(id: "27.5x2.1", label: "27.5 × 2.1\"", circumferenceMm: 2145),
            .init(id: "27.5x2.25", label: "27.5 × 2.25\"", circumferenceMm: 2169),
            .init(id: "27.5x2.4", label: "27.5 × 2.4\"", circumferenceMm: 2205),
            .init(id: "27.5x2.6", label: "27.5 × 2.6\"", circumferenceMm: 2240),
            .init(id: "27.5x2.8", label: "27.5 × 2.8\"", circumferenceMm: 2272),
        ]),
        Category(id: "26", title: "26\"", options: [
            .init(id: "26x1.5", label: "26 × 1.5\"", circumferenceMm: 2026),
            .init(id: "26x1.75", label: "26 × 1.75\"", circumferenceMm: 2038),
            .init(id: "26x1.95", label: "26 × 1.95\"", circumferenceMm: 2055),
            .init(id: "26x2.0", label: "26 × 2.0\"", circumferenceMm: 2068),
            .init(id: "26x2.1", label: "26 × 2.1\"", circumferenceMm: 2074),
            .init(id: "26x2.25", label: "26 × 2.25\"", circumferenceMm: 2089),
            .init(id: "26x2.3", label: "26 × 2.3\"", circumferenceMm: 2097),
        ]),
        Category(id: "24", title: "24\"", options: [
            .init(id: "24x1.5", label: "24 × 1.5\"", circumferenceMm: 1890),
            .init(id: "24x1.95", label: "24 × 1.95\"", circumferenceMm: 1925),
            .init(id: "24x2.0", label: "24 × 2.0\"", circumferenceMm: 1938),
        ]),
        Category(id: "20", title: "20\"", options: [
            .init(id: "20x1.75", label: "20 × 1.75\"", circumferenceMm: 1615),
            .init(id: "20x1.95", label: "20 × 1.95\"", circumferenceMm: 1630),
            .init(id: "20x2.125", label: "20 × 2.125\"", circumferenceMm: 1651),
        ]),
    ]

    static let allOptions: [Option] = categories.flatMap(\.options)

    static let defaultOptionId = "700x25"

    static func option(id: String) -> Option? {
        allOptions.first { $0.id == id }
    }

    /// 저장된 둘레(m)와 가장 가까운 일반 규격.
    static func nearest(toCircumferenceMeters meters: Double) -> Option {
        let mm = meters * 1000
        return allOptions.min(by: {
            abs($0.circumferenceMm - mm) < abs($1.circumferenceMm - mm)
        }) ?? option(id: defaultOptionId)!
    }
}
