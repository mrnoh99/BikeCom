import Foundation
import ZIPFoundation

/// BikeCom 백업 zip — BikeCom-Backup.json 또는 rides.json + GPX(전체 내보내기) 복원.
enum BackupZip {

    /// json 파일 하나를 zip 으로 묶는다(공유·Files 저장용).
    static func createArchive(jsonURL: URL, zipURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            throw BackupZipError.createFailed
        }
        try archive.addEntry(with: jsonURL.lastPathComponent, relativeTo: jsonURL.deletingLastPathComponent())
    }

    /// zip 을 임시 폴더에 풀고 루트 URL 반환.
    static func extract(_ zipURL: URL) throws -> URL {
        let fm = FileManager.default
        let dest = fm.temporaryDirectory.appendingPathComponent("BikeCom-restore-\(UUID().uuidString)", isDirectory: true)
        try? fm.removeItem(at: dest)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.unzipItem(at: zipURL, to: dest)
        return dest
    }

    /// 풀린 폴더에서 기록 JSON 을 찾아 디코딩(GPX 트랙 보강 포함).
    static func loadRecords(from extractedRoot: URL) -> [RideRecord]? {
        guard let jsonURL = findBackupJSON(in: extractedRoot) else { return nil }
        guard var records = decodeRecords(from: jsonURL), !records.isEmpty else { return nil }
        records = enrichWithGPX(records, in: extractedRoot)
        return records
    }

    // MARK: - 내부

    enum BackupZipError: Error {
        case createFailed
    }

    private static func findBackupJSON(in root: URL) -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        var backupJSON: URL?
        var ridesJSON: URL?
        var anyJSON: URL?
        for case let url as URL in en where url.pathExtension.lowercased() == "json" {
            let name = url.lastPathComponent.lowercased()
            if name.contains("backup") { backupJSON = url }
            else if name == "rides.json" { ridesJSON = url }
            else if anyJSON == nil { anyJSON = url }
        }
        return backupJSON ?? ridesJSON ?? anyJSON
    }

    private static func decodeRecords(from url: URL) -> [RideRecord]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let b = try? JSONDecoder().decode(RideStore.Backup.self, from: data), !b.records.isEmpty {
            return b.records
        }
        if let arr = try? JSONDecoder().decode([RideRecord].self, from: data), !arr.isEmpty {
            return arr
        }
        return nil
    }

    private static func enrichWithGPX(_ records: [RideRecord], in root: URL) -> [RideRecord] {
        let gpxURLs = allGPX(in: root)
        guard !gpxURLs.isEmpty else { return records }

        var parsed: [RideRecord] = []
        for url in gpxURLs {
            guard let data = try? Data(contentsOf: url),
                  let rec = GPXImporter.parse(data: data, fallbackName: url.deletingPathExtension().lastPathComponent)
            else { continue }
            parsed.append(rec)
        }
        guard !parsed.isEmpty else { return records }

        return records.map { record in
            guard record.track.isEmpty else { return record }
            guard let match = parsed.first(where: { RideRecordMerge.isDuplicate($0, of: record) })
                ?? parsed.min(by: { abs($0.startedAt.timeIntervalSince(record.startedAt))
                    < abs($1.startedAt.timeIntervalSince(record.startedAt)) })
            else { return record }
            guard abs(match.startedAt.timeIntervalSince(record.startedAt)) <= 180 else { return record }
            var r = record
            r.track = match.track
            r.trackCount = match.track.count
            r.startCoord = match.track.first
            r.endCoord = match.track.last
            if r.maxSpeedMps < match.maxSpeedMps { r.maxSpeedMps = match.maxSpeedMps }
            return r
        }
    }

    private static func allGPX(in root: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return en.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension.lowercased() == "gpx" else { return nil }
            return url
        }
    }
}
