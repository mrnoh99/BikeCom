import Foundation
import CoreLocation

/// Cyclemeter 등에서 내보낸 GPX 파일을 RideRecord 로 변환한다.
/// `<trkpt>` 의 위/경도·고도·시각 + `gpxtpx` 확장(hr·cad·speed)을 읽어
/// 거리·시간·평균/최고속도·심박·케이던스·경로를 복원한다.
enum GPXImporter {

    /// GPX 한 건을 RideRecord 로 파싱. 트랙이 비어 있으면 nil.
    static func parse(data: Data, fallbackName: String) -> RideRecord? {
        let parser = Parser()
        guard parser.run(data: data), !parser.points.isEmpty else { return nil }
        let pts = parser.points

        var distance = 0.0
        var moving = 0.0
        var maxSpeed = 0.0
        if pts.count > 1 {
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                let d = CLLocation(latitude: b.lat, longitude: b.lon)
                    .distance(from: CLLocation(latitude: a.lat, longitude: a.lon))
                if d < 200 { distance += d }   // 비현실적 점프 무시
                if let ta = a.time, let tb = b.time {
                    let dt = tb.timeIntervalSince(ta)
                    if dt > 0, dt < 60 {
                        let sp = d / dt
                        if sp >= 0.8 { moving += dt }
                        if sp > maxSpeed { maxSpeed = sp }
                    }
                }
            }
        }
        if let explicit = pts.compactMap({ $0.speed }).max() { maxSpeed = max(maxSpeed, explicit) }

        let times = pts.compactMap { $0.time }
        let start = times.min() ?? Date()
        let total = max(0, (times.max() ?? start).timeIntervalSince(start))
        let duration = moving > 0 ? moving : total
        let avgSpeed = duration > 0 ? distance / duration : 0

        let hrs = pts.compactMap { $0.hr }
        let avgHR = hrs.isEmpty ? nil : Int((Double(hrs.reduce(0, +)) / Double(hrs.count)).rounded())

        let coords = pts.map {
            RideRecord.Coordinate(lat: $0.lat, lon: $0.lon, ele: $0.ele, time: $0.time, speed: $0.speed, hr: $0.hr)
        }

        return RideRecord(
            name: parser.name ?? fallbackName,
            source: .gpx,
            startedAt: start,
            duration: duration,
            totalElapsed: total,
            distanceMeters: distance,
            averageSpeedMps: avgSpeed,
            maxSpeedMps: maxSpeed,
            maxHeartRate: hrs.max(),
            avgHeartRate: avgHR,
            maxCadence: pts.compactMap { $0.cad }.max(),
            track: coords)
    }

    // MARK: - XMLParser 델리게이트

    private final class Parser: NSObject, XMLParserDelegate {
        struct Pt { var lat = 0.0; var lon = 0.0; var ele: Double?; var time: Date?; var speed: Double?; var hr: Int?; var cad: Int? }
        var points: [Pt] = []
        var name: String?

        private var cur: Pt?
        private var buffer = ""
        private var inTrk = false
        private var capturedName = false
        private let isoFrac: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
        }()
        private let iso = ISO8601DateFormatter()

        func run(data: Data) -> Bool {
            let xp = XMLParser(data: data)
            xp.delegate = self
            return xp.parse()
        }

        private func local(_ el: String) -> String { (el.components(separatedBy: ":").last ?? el).lowercased() }
        private func date(_ s: String) -> Date? { isoFrac.date(from: s) ?? iso.date(from: s) }

        func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?,
                    qualifiedName: String?, attributes a: [String: String]) {
            buffer = ""
            switch local(el) {
            case "trk": inTrk = true
            case "trkpt":
                var pt = Pt()
                pt.lat = Double(a["lat"] ?? "") ?? 0
                pt.lon = Double(a["lon"] ?? "") ?? 0
                cur = pt
            default: break
            }
        }

        func parser(_ p: XMLParser, foundCharacters s: String) { buffer += s }

        func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch local(el) {
            case "name":
                if inTrk, !capturedName, !text.isEmpty { name = text; capturedName = true }
            case "ele": cur?.ele = Double(text)
            case "time": cur?.time = date(text)
            case "speed": cur?.speed = Double(text)
            case "hr", "heartrate":
                if let v = Double(text), v > 0 { cur?.hr = Int(v) }
            case "cad", "cadence":
                if let v = Double(text), v >= 0 { cur?.cad = Int(v) }
            case "trkpt":
                if let c = cur { points.append(c) }
                cur = nil
            case "trk": inTrk = false
            default: break
            }
            buffer = ""
        }
    }
}
