import Foundation

/// 라이딩 기록 병합 — 시작 시각(초) 기준으로 중복을 처리한다.
enum RideRecordMerge {
    static func startKey(for date: Date) -> Int { Int(date.timeIntervalSince1970) }

    /// `incomingWins == true` 이면 같은 시작 시각의 기존 기록을 incoming 으로 교체(Health 우선).
    /// `false` 이면 기존 기록을 유지하고 없는 키만 추가(베이스라인 최초 주입).
    static func merge(existing: [RideRecord], incoming: [RideRecord], incomingWins: Bool) -> [RideRecord] {
        // 지도 코스 자료는 병합/중복 제거 대상에서 제외하고 항상 보존한다(같은 시작 시각 복사본 허용).
        let courses = (existing + incoming).filter { $0.isCourseOnly }
        let mergeable = existing.filter { !$0.isCourseOnly }
        // 같은 시작 시각이 둘 이상이어도 크래시하지 않도록 uniquingKeysWith 사용(먼저 것 유지).
        var byStart = Dictionary(mergeable.map { (startKey(for: $0.startedAt), $0) },
                                 uniquingKeysWith: { first, _ in first })
        for rec in incoming where !rec.isCourseOnly {
            let key = startKey(for: rec.startedAt)
            if incomingWins || byStart[key] == nil {
                byStart[key] = rec
            }
        }
        return courses + byStart.values.sorted { $0.startedAt > $1.startedAt }
    }

    /// 두 기록이 같은 라이딩인지(소스가 달라도). 시작 시각 ±180초 +
    /// 활동시간(duration) 또는 전체시간(totalElapsed) 중 하나가 ±120초 안이면 같은 라이딩으로 본다.
    /// (앱이 건강에 저장한 워크아웃은 일시정지 포함 전체시간이 duration 으로 들어오므로,
    ///  활동시간만 비교하면 일시정지가 긴 라이딩이 재가져오기 때 중복으로 남는 문제를 막는다.)
    static func isDuplicate(_ a: RideRecord, of b: RideRecord) -> Bool {
        guard abs(a.startedAt.timeIntervalSince(b.startedAt)) <= 180 else { return false }
        if abs(a.duration - b.duration) <= 120 { return true }
        // 전체시간은 둘 다 기록된 경우에만 비교(legacy 기록은 0이라 비교 제외).
        return a.totalElapsed > 0 && b.totalElapsed > 0 &&
               abs(a.totalElapsed - b.totalElapsed) <= 120
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
