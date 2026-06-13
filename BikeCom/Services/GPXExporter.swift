import Foundation

/// 라이딩 경로를 GPX 1.1 로 내보낸다.
/// 지점별 **고도(ele)·시각(time)·심박·속도**(Garmin `gpxtpx:TrackPointExtension`) 포함.
/// 저장 위치: **iCloud Drive > BikeCom > GPX** (없으면 로컬 Documents/GPX → Files 앱).
enum GPXExporter {

    /// 라이딩 1건을 GPX 로 저장한다. (iCloud 해석이 느릴 수 있어 백그라운드에서 수행)
    /// completion 은 저장된 파일 URL(실패/경로없음 시 nil)을 메인 큐로 돌려준다.
    static func export(_ record: RideRecord, completion: ((URL?) -> Void)? = nil) {
        guard !record.track.isEmpty else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }
        let xml = makeGPX(record)
        let fileName = "\(fileStem(record)).gpx"
        DispatchQueue.global(qos: .utility).async {
            let dir = gpxFolder()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            let coordinator = NSFileCoordinator()
            var err: NSError?
            var ok = false
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
                if let data = xml.data(using: .utf8) {
                    do { try data.write(to: u, options: .atomic); ok = true } catch { ok = false }
                }
            }
            DispatchQueue.main.async { completion?(ok ? url : nil) }
        }
    }

    /// 공유 시트용 임시 GPX 파일 URL 생성.
    static func writeTempGPX(_ record: RideRecord) -> URL? {
        guard !record.track.isEmpty, let data = makeGPX(record).data(using: .utf8) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileStem(record)).gpx")
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// 앱의 전체 라이딩을 라이딩별 GPX 로 쓴 폴더를 만들고 .zip 으로 묶어 임시 URL 반환.
    /// (백그라운드 실행 권장; completion 은 메인 큐로 반환)
    static func exportAllZip(_ records: [RideRecord], completion: @escaping (URL?, Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmm"
            let folderName = "BikeCom-Export-\(df.string(from: Date()))"
            let folder = fm.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
            try? fm.removeItem(at: folder)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

            var used = Set<String>(); var count = 0
            for r in records {
                var stem = fileStem(r); var name = stem; var k = 1
                while used.contains(name.lowercased()) { name = "\(stem)-\(k)"; k += 1 }
                used.insert(name.lowercased())
                if let data = makeGPX(r).data(using: .utf8) {
                    try? data.write(to: folder.appendingPathComponent("\(name).gpx"), options: .atomic)
                    count += 1
                }
            }
            // 라이딩 기록 원본도 함께 백업(재가져오기/보관용).
            if let json = try? JSONEncoder().encode(records) {
                try? json.write(to: folder.appendingPathComponent("rides.json"), options: .atomic)
            }

            // NSFileCoordinator(.forUploading) 가 폴더를 zip 으로 만들어 준다(외부 라이브러리 불필요).
            var zipURL: URL?
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &err) { tmp in
                let dest = fm.temporaryDirectory.appendingPathComponent("\(folderName).zip")
                try? fm.removeItem(at: dest)
                do { try fm.copyItem(at: tmp, to: dest); zipURL = dest } catch { zipURL = nil }
            }
            try? fm.removeItem(at: folder)
            DispatchQueue.main.async { completion(zipURL, count) }
        }
    }

    /// GPX 저장 폴더: iCloud 컨테이너(BikeCom)의 Documents/GPX, 없으면 로컬 Documents/GPX.
    static func gpxFolder() -> URL {
        let useCloud = Thread.isMainThread
            ? CloudDocuments.isAvailable
            : DispatchQueue.main.sync { CloudDocuments.isAvailable }
        if useCloud, let container = CloudDocuments.containerURL() {
            return container.appendingPathComponent("Documents/GPX", isDirectory: true)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("GPX", isDirectory: true)
    }

    // MARK: - GPX 생성

    private static func makeGPX(_ record: RideRecord) -> String {
        let iso = ISO8601DateFormatter()
        let n = record.track.count
        var points = ""
        for (i, c) in record.track.enumerated() {
            let time = c.time ?? record.startedAt.addingTimeInterval(record.totalElapsed * Double(i) / Double(max(1, n - 1)))
            var inner = ""
            if let ele = c.ele { inner += "<ele>\(String(format: "%.1f", ele))</ele>" }
            inner += "<time>\(iso.string(from: time))</time>"

            var ext = ""
            if let hr = c.hr { ext += "<gpxtpx:hr>\(hr)</gpxtpx:hr>" }
            if let sp = c.speed { ext += "<gpxtpx:speed>\(String(format: "%.2f", sp))</gpxtpx:speed>" }
            if !ext.isEmpty {
                inner += "<extensions><gpxtpx:TrackPointExtension>\(ext)</gpxtpx:TrackPointExtension></extensions>"
            }
            points += "      <trkpt lat=\"\(c.lat)\" lon=\"\(c.lon)\">\(inner)</trkpt>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Bike Computer"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <metadata><time>\(iso.string(from: record.startedAt))</time></metadata>
          <trk>
            <name>\(escape(record.name))</name>
            <type>cycling</type>
            <trkseg>
        \(points)    </trkseg>
          </trk>
        </gpx>
        """
    }

    private static func fileStem(_ record: RideRecord) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let safeName = record.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(safeName)-\(df.string(from: record.startedAt))"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
