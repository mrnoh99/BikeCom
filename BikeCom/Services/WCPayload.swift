import Foundation

/// WatchConnectivity 페이로드 파싱 — WCSession 은 숫자를 NSNumber 로 넘기는 경우가 많다.
enum WCPayload {
    static func int(_ dict: [String: Any], _ key: String) -> Int? {
        if let v = dict[key] as? Int { return v }
        if let v = dict[key] as? NSNumber { return v.intValue }
        return nil
    }

    static func double(_ dict: [String: Any], _ key: String) -> Double? {
        if let v = dict[key] as? NSNumber { return v.doubleValue }
        if let v = dict[key] as? Double { return v }
        if let v = dict[key] as? Float { return Double(v) }
        return nil
    }

    static func bool(_ dict: [String: Any], _ key: String) -> Bool? {
        if let v = dict[key] as? Bool { return v }
        if let v = dict[key] as? NSNumber { return v.boolValue }
        return nil
    }

    static func hasSensorData(_ dict: [String: Any]) -> Bool {
        dict["hr"] != nil || dict["speedMps"] != nil || dict["cadence"] != nil
    }
}
