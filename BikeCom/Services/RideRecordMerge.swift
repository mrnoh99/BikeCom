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
}
