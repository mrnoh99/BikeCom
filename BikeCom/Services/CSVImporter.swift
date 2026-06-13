import Foundation
import CoreLocation

/// Cyclemeter·Garmin 등에서 내보낸 **요약 CSV**(한 행 = 라이딩 1건) 또는
/// 위·경도 열이 있는 **트랙 CSV** 를 RideRecord 로 변환한다.
enum CSVImporter {

    /// CSV 파일 전체를 파싱해 0개 이상의 RideRecord 를 반환한다.
    static func parse(data: Data, fallbackName: String) -> [RideRecord] {
        guard var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16) else { return [] }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let delimiter = detectDelimiter(text)
        let rows = parseCSV(text, delimiter: delimiter)
        guard rows.count >= 2 else { return [] }

        let headers = rows[0]
        let map = columnMap(headers)
        let dataRows = Array(rows.dropFirst()).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

        if map[.lat] != nil, map[.lon] != nil {
            if let ride = parseTrackRows(dataRows, map: map, fallbackName: fallbackName) {
                return [ride]
            }
        }

        return dataRows.compactMap { parseSummaryRow($0, map: map, headers: headers, fallbackName: fallbackName) }
    }

    // MARK: - Summary (한 행 = 라이딩)

    /// Cyclemeter 요약 가져오기 시 이 시점 이전 기록은 제외한다(2013-01-01).
    static let cyclemeterCutoff: Date = {
        var c = DateComponents(); c.year = 2013; c.month = 1; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantPast
    }()

    private static func parseSummaryRow(_ row: [String], map: ColumnMap, headers: [String],
                                        fallbackName: String) -> RideRecord? {
        guard let started = parseDate(map.value(.date, in: row) ?? map.value(.start, in: row)) else {
            return nil
        }
        // 2013년 이전 Cyclemeter 기록은 가져오지 않는다.
        guard started >= cyclemeterCutoff else { return nil }

        let route = map.value(.title, in: row)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activity = map.value(.activity, in: row)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name: String = {
            if !route.isEmpty, route.lowercased() != "new route" { return route }
            if !activity.isEmpty { return activity }
            return fallbackName
        }()

        let distanceHeader = map.header(.distance, in: headers) ?? ""
        let distanceRaw = map.value(.distance, in: row)
        let distanceMeters = parseDistance(distanceRaw, header: distanceHeader)

        let duration = parseDurationSeconds(map.value(.durationSecs, in: row))
            ?? parseDuration(map.value(.duration, in: row))
            ?? parseDuration(map.value(.time, in: row))
            ?? parseDuration(map.value(.movingTime, in: row))
            ?? 0
        var stopped = parseDurationSeconds(map.value(.stoppedSecs, in: row)) ?? 0
        // 일부 Cyclemeter 내보내기는 Stopped Time 값이 손상돼 비현실적으로 크다(수억 초).
        // 라이딩 시간(duration)에는 영향 없지만 총 경과가 터무니없어지므로 무시한다.
        if !(0...(86400 * 14)).contains(stopped) { stopped = 0 }
        var elapsed = parseDuration(map.value(.elapsed, in: row)) ?? (duration + stopped)
        if !(0...(86400 * 14)).contains(elapsed) { elapsed = duration + stopped }

        let speedHeader = map.header(.avgSpeed, in: headers) ?? map.header(.maxSpeed, in: headers) ?? ""
        var avgSpeed = parseSpeed(map.value(.avgSpeed, in: row), header: speedHeader)
        let maxSpeed = parseSpeed(map.value(.maxSpeed, in: row), header: speedHeader)
        if avgSpeed <= 0, duration > 0, distanceMeters > 0 {
            avgSpeed = distanceMeters / duration
        }

        let avgHR = parseInt(map.value(.avgHR, in: row))
        let maxHR = parseInt(map.value(.maxHR, in: row))
        let maxCad = parseInt(map.value(.maxCadence, in: row) ?? map.value(.avgCadence, in: row))
        let bike: String? = {
            let b = map.value(.bike, in: row)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (b?.isEmpty == false && b?.lowercased() != "none") ? b : nil
        }()
        let place = map.value(.location, in: row)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isPlausibleRide(distanceMeters: distanceMeters, duration: duration) else { return nil }

        return RideRecord(
            name: name,
            bikeName: bike,
            source: .cyclemeter,
            location: (place?.isEmpty == false) ? place : nil,
            startedAt: started,
            duration: duration > 0 ? duration : elapsed,
            totalElapsed: elapsed > 0 ? elapsed : duration,
            distanceMeters: max(0, distanceMeters),
            averageSpeedMps: max(0, avgSpeed),
            maxSpeedMps: max(maxSpeed, avgSpeed),
            maxHeartRate: maxHR,
            avgHeartRate: avgHR,
            maxCadence: maxCad,
            track: [])
    }

    private static func isPlausibleRide(distanceMeters: Double, duration: TimeInterval) -> Bool {
        guard duration >= 0, duration <= 86400 * 14 else { return false }
        guard distanceMeters >= 0, distanceMeters <= 2_000_000 else { return false }
        return distanceMeters > 0 || duration >= 60
    }

    private static func parseDurationSeconds(_ raw: String?) -> TimeInterval? {
        guard let v = parseDouble(raw), v >= 0 else { return nil }
        return v
    }

    // MARK: - Track (좌표 열)

    private static func parseTrackRows(_ rows: [[String]], map: ColumnMap,
                                       fallbackName: String) -> RideRecord? {
        struct Pt { var lat: Double; var lon: Double; var ele: Double?; var time: Date?; var speed: Double?; var hr: Int?; var cad: Int? }
        var points: [Pt] = []

        for row in rows {
            guard let lat = parseDouble(map.value(.lat, in: row)),
                  let lon = parseDouble(map.value(.lon, in: row)) else { continue }
            let pt = Pt(
                lat: lat, lon: lon,
                ele: map.value(.elevation, in: row).flatMap(parseDouble),
                time: map.value(.time, in: row).flatMap(parseDate) ?? map.value(.date, in: row).flatMap(parseDate),
                speed: map.value(.speed, in: row).flatMap { parseSpeed($0, header: "") },
                hr: map.value(.hr, in: row).flatMap(parseInt),
                cad: map.value(.cadence, in: row).flatMap(parseInt))
            points.append(pt)
        }
        guard !points.isEmpty else { return nil }

        var distance = 0.0
        var moving = 0.0
        var maxSp = 0.0
        if points.count > 1 {
            for i in 1..<points.count {
                let a = points[i - 1], b = points[i]
                let d = CLLocation(latitude: b.lat, longitude: b.lon)
                    .distance(from: CLLocation(latitude: a.lat, longitude: a.lon))
                if d < 200 { distance += d }
                if let ta = a.time, let tb = b.time {
                    let dt = tb.timeIntervalSince(ta)
                    if dt > 0, dt < 60 {
                        let sp = d / dt
                        if sp >= 0.8 { moving += dt }
                        if sp > maxSp { maxSp = sp }
                    }
                }
            }
        }
        if let explicit = points.compactMap(\.speed).max() { maxSp = max(maxSp, explicit) }

        let times = points.compactMap(\.time)
        let start = times.min() ?? Date()
        let total = max(0, (times.max() ?? start).timeIntervalSince(start))
        let duration = moving > 0 ? moving : total
        let avgSpeed = duration > 0 ? distance / duration : 0
        let hrs = points.compactMap(\.hr)
        let avgHR = hrs.isEmpty ? nil : Int((Double(hrs.reduce(0, +)) / Double(hrs.count)).rounded())

        let track = points.map {
            RideRecord.Coordinate(lat: $0.lat, lon: $0.lon, ele: $0.ele, time: $0.time,
                                  speed: $0.speed, hr: $0.hr)
        }

        return RideRecord(
            name: fallbackName,
            source: .gpx,
            startedAt: start,
            duration: duration,
            totalElapsed: total,
            distanceMeters: distance,
            averageSpeedMps: avgSpeed,
            maxSpeedMps: maxSp,
            maxHeartRate: hrs.max(),
            avgHeartRate: avgHR,
            maxCadence: points.compactMap(\.cad).max(),
            track: track)
    }

    // MARK: - Column mapping

    private enum Col: CaseIterable {
        case date, start, title, name, activity, distance, time, duration, durationSecs, movingTime, elapsed, stoppedSecs
        case avgSpeed, maxSpeed, avgHR, maxHR, avgCadence, maxCadence, bike, location
        case lat, lon, elevation, speed, hr, cadence
    }

    private struct ColumnMap {
        private var indices: [Col: Int] = [:]
        private let headers: [String]

        init(_ headers: [String]) {
            self.headers = headers
            for (i, h) in headers.enumerated() {
                let n = Self.norm(h)
                for col in Col.allCases where indices[col] == nil {
                    if Self.aliases[col]?.contains(n) == true { indices[col] = i }
                }
            }
        }

        func value(_ col: Col, in row: [String]) -> String? {
            guard let i = indices[col], i < row.count else { return nil }
            let v = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        func header(_ col: Col, in headers: [String]) -> String? {
            guard let i = indices[col], i < headers.count else { return nil }
            return headers[i]
        }

        subscript(col: Col) -> Int? { indices[col] }

        private static let aliases: [Col: Set<String>] = [
            .date: ["date", "datetime", "startdate", "activitydate", "starttime"],
            .start: ["start", "starttime", "begintime"],
            .title: ["title", "activityname", "workoutname", "route"],
            .name: ["name"],
            .activity: ["activity"],
            .distance: ["distance", "dist", "distancekm", "distancemi", "odometer"],
            .time: ["timestamp"],
            .duration: ["duration", "ridetime", "activitytime", "time"],
            .durationSecs: ["timesecs", "durationsecs", "movingtimesecs", "elapsedsecs"],
            .movingTime: ["movingtime", "movetime"],
            .elapsed: ["elapsedtime", "elapsed", "totaltime"],
            .stoppedSecs: ["stoppedtimesecs", "stoppedtime"],
            .avgSpeed: ["avgspeed", "averagespeed", "meanspeed", "averagespeedkmh"],
            .maxSpeed: ["maxspeed", "maximumspeed", "topspeed", "fastestspeed", "fastestspeedkmh"],
            .avgHR: ["avghr", "avgheartrate", "averageheartrate", "averagehr", "heartrateavg", "averageheartratebpm"],
            .maxHR: ["maxhr", "maxheartrate", "maximumheartrate", "heartratemax", "maximumheartratebpm"],
            .avgCadence: ["avgcadence", "averagecadence", "averagecadencerpm"],
            .maxCadence: ["maxcadence", "maxbikecadence", "maximumcadence", "maximumcadencerpm"],
            .bike: ["bike", "bicycle", "gear"],
            .location: ["location", "place", "city"],
            .lat: ["lat", "latitude", "latdeg"],
            .lon: ["lon", "long", "longitude", "lng", "londeg"],
            .elevation: ["ele", "elevation", "alt", "altitude"],
            .speed: ["speed", "velocity"],
            .hr: ["hr", "heartrate", "heart"],
            .cadence: ["cadence", "cad", "rpm"]
        ]

        private static func norm(_ s: String) -> String {
            s.lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)
                .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        }
    }

    private static func columnMap(_ headers: [String]) -> ColumnMap { ColumnMap(headers) }

    // MARK: - CSV parse

    private static func detectDelimiter(_ text: String) -> Character {
        guard let line = text.split(whereSeparator: \.isNewline).first else { return "," }
        let commas = line.filter { $0 == "," }.count
        let semis = line.filter { $0 == ";" }.count
        return semis > commas ? ";" : ","
    }

    private static func parseCSV(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let ch = text[i]
            if inQuotes {
                if ch == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                row.append(field)
                field = ""
            } else if ch == "\n" || ch == "\r" {
                if ch == "\r", text.index(after: i) < text.endIndex, text[text.index(after: i)] == "\n" {
                    i = text.index(after: i)
                }
                row.append(field)
                field = ""
                if !row.isEmpty { rows.append(row) }
                row = []
            } else {
                field.append(ch)
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // MARK: - Value parsing

    private static func parseDouble(_ s: String?) -> Double? {
        guard var t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        t = t.replacingOccurrences(of: ",", with: "")
        if t.hasSuffix("%") { t.removeLast() }
        return Double(t)
    }

    private static func parseInt(_ s: String?) -> Int? {
        guard let d = parseDouble(s) else { return nil }
        return Int(d.rounded())
    }

    private static func parseDistance(_ raw: String?, header: String) -> Double {
        guard let raw else { return 0 }
        let h = header.lowercased()
        let v = parseDouble(raw) ?? 0
        if h.contains("mi") && !h.contains("min") { return v * 1609.344 }
        if h.contains("km") || h.contains("kilometer") { return v * 1000 }
        if h.contains("meter") || h.contains("(m)") { return v }
        // Cyclemeter 기본: Distance (km)
        if v > 500 { return v }
        return v * 1000
    }

    private static func parseSpeed(_ raw: String?, header: String) -> Double {
        guard let v = parseDouble(raw), v > 0 else { return 0 }
        let h = header.lowercased()
        if h.contains("mph") || (h.contains("mi") && !h.contains("min")) { return v / 2.23694 }
        if h.contains("km") || h.contains("kph") || h.contains("km/h") { return v / 3.6 }
        // 큰 값(>25)이면 km/h, 작으면 m/s
        if v > 25 { return v / 3.6 }
        return v
    }

    private static func parseDuration(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains(":") {
            let parts = raw.split(separator: ":").map { String($0) }
            switch parts.count {
            case 3:
                let h = Double(parts[0]) ?? 0
                let m = Double(parts[1]) ?? 0
                let s = Double(parts[2]) ?? 0
                return h * 3600 + m * 60 + s
            case 2:
                let m = Double(parts[0]) ?? 0
                let s = Double(parts[1]) ?? 0
                return m * 60 + s
            default:
                break
            }
        }
        return parseDouble(raw)
    }

    private static let dateFormatters: [DateFormatter] = {
        let fmts = [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy",
            "M/d/yyyy H:mm", "d/M/yyyy H:mm", "dd MMM yyyy HH:mm", "MMM d, yyyy HH:mm"
        ]
        return fmts.map {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = $0
            return f
        }
    }()

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let isoFrac: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        if let d = isoFrac.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return d }
        for f in dateFormatters {
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }
}
