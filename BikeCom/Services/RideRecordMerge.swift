import Foundation

/// 라이딩 기록 병합 — 시작 시각(초) 기준으로 중복을 처리한다.
enum RideRecordMerge {
    static func startKey(for date: Date) -> Int { Int(date.timeIntervalSince1970) }

    /// `incomingWins == true` 이면 같은 시작 시각의 기존 기록을 incoming 으로 교체(Health 우선).
    /// `false` 이면 기존 기록을 유지하고 없는 키만 추가(베이스라인 최초 주입).
    static func merge(existing: [RideRecord], incoming: [RideRecord], incomingWins: Bool) -> [RideRecord] {
        var byStart = Dictionary(uniqueKeysWithValues: existing.map { (startKey(for: $0.startedAt), $0) })
        for rec in incoming {
            let key = startKey(for: rec.startedAt)
            if incomingWins || byStart[key] == nil {
                byStart[key] = rec
            }
        }
        return byStart.values.sorted { $0.startedAt > $1.startedAt }
    }

    /// 두 기록이 같은 라이딩인지(소스가 달라도). 시작 시각 ±180초 + 라이딩 시간 ±120초.
    static func isDuplicate(_ a: RideRecord, of b: RideRecord) -> Bool {
        abs(a.startedAt.timeIntervalSince(b.startedAt)) <= 180 &&
        abs(a.duration - b.duration) <= 120
    }
}

/// Cyclemeter(JSON 기록)와 Apple 건강 워크아웃을 합쳐 **중복 없이** 총 라이딩 시간을 구한다.
/// 두 소스의 같은 라이딩은 시작 시각이 몇 초~몇 분 어긋날 수 있으므로,
/// 시작 시각이 허용 오차 안이고 라이딩 시간도 비슷하면 같은 라이딩으로 보고 한 번만 센다.
enum RideTimeAggregator {
    /// 같은 라이딩으로 간주할 시작 시각 허용 오차(초).
    static let startWindow: TimeInterval = 180
    /// 같은 라이딩으로 간주할 라이딩 시간 허용 오차(초).
    static let durationTolerance: TimeInterval = 120

    struct Entry { let start: Date; let duration: TimeInterval }

    /// 두 소스를 합쳐 중복 제거 후 라이딩 시간 합(초)을 돌려준다.
    static func totalRideTime(records: [RideRecord], healthRides: [HealthStore.HealthRide]) -> TimeInterval {
        let entries: [Entry] =
            records.map { Entry(start: $0.startedAt, duration: $0.duration) } +
            healthRides.map { Entry(start: $0.start, duration: $0.duration) }
        return totalRideTime(entries: entries)
    }

    static func totalRideTime(entries: [Entry]) -> TimeInterval {
        // 시작 시각 순으로 정렬한 뒤, 직전에 채택한 라이딩들과 겹치지 않는 것만 더한다.
        let sorted = entries.sorted { $0.start < $1.start }
        var accepted: [Entry] = []
        var total: TimeInterval = 0
        for e in sorted {
            let dur = max(0, e.duration)
            let isDup = accepted.contains { a in
                abs(e.start.timeIntervalSince(a.start)) <= startWindow &&
                abs(dur - a.duration) <= durationTolerance
            }
            if isDup { continue }
            accepted.append(Entry(start: e.start, duration: dur))
            total += dur
        }
        return total
    }
}
