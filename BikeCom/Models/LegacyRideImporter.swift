import Foundation

/// 콜백을 **정확히 한 번만** 실행한다. "성공" 경로와 "타임아웃" 경로가 경쟁할 때, 둘 중
/// 먼저 끝난 쪽만 completion을 부르고 나중에 끝난 쪽은 조용히 버린다.
private final class SingleShotCompletion<T> {
    private let lock = NSLock()
    private var fired = false
    private let action: (T) -> Void
    init(_ action: @escaping (T) -> Void) { self.action = action }
    func fire(_ value: T) {
        lock.lock()
        let shouldFire = !fired
        fired = true
        lock.unlock()
        if shouldFire { action(value) }
    }
}

/// Core Data 전환 이전(파일 기반 `rides.json` + `Tracks/*.json`, iCloud Documents 동기화) 데이터를
/// 1회 Core Data로 이전한다. 기기마다(UserDefaults 플래그) 정확히 한 번만 시도하며, 이미 Core
/// Data에 같은 id의 기록이 있으면 그대로 덮어쓸 뿐 중복되지 않는다 — 그래서 CloudKit이 다른
/// 기기의 마이그레이션 결과를 이 기기에 먼저 동기화해놓았더라도(레코드가 이미 존재해도) 안전하게
/// 또 한 번 시도해, 이 기기에만 있던 로컬 전용 변경(아직 어디에도 동기화 못 한 것)까지 챙긴다.
enum LegacyRideImporter {
    private static let migratedKey = "bike.coreDataMigrated.v1"
    private static let fileName = "rides.json"
    private static let backupFileName = "BikeCom-Backup.json"

    static func importIfNeeded(into store: RideStore) {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let localURL = docs.appendingPathComponent(fileName)
            let localTracksDir = docs.appendingPathComponent("Tracks", isDirectory: true)

            var cloudURL: URL?
            var cloudTracksDir: URL?
            if fm.ubiquityIdentityToken != nil, let container = CloudDocuments.containerURL() {
                let cloudDocs = container.appendingPathComponent("Documents", isDirectory: true)
                cloudURL = cloudDocs.appendingPathComponent(fileName)
                cloudTracksDir = cloudDocs.appendingPathComponent("Tracks", isDirectory: true)
            }

            var decoded: [RideRecord]?
            for url in [cloudURL, localURL].compactMap({ $0 }) {
                if let data = try? Data(contentsOf: url),
                   let arr = try? JSONDecoder().decode([RideRecord].self, from: data), !arr.isEmpty {
                    decoded = arr
                    break
                }
            }
            if decoded == nil {
                // 메인 파일이 없으면(백업만 복원해 쓰던 기기 등) 구버전 자동 백업에서 폴백.
                let localBak = docs.appendingPathComponent(backupFileName)
                let cloudBak = cloudURL?.deletingLastPathComponent()
                    .appendingPathComponent(backupFileName)
                for url in [cloudBak, localBak].compactMap({ $0 }) {
                    if let data = try? Data(contentsOf: url),
                       let b = try? JSONDecoder().decode(RideStore.Backup.self, from: data),
                       !b.records.isEmpty {
                        decoded = b.records
                        break
                    }
                }
            }
            guard var records = decoded, !records.isEmpty else {
                UserDefaults.standard.set(true, forKey: migratedKey)
                return
            }

            // 트랙이 비어 있는 기록(요약본만 디코딩된 경우)은 Tracks/<id>.json 에서 채운다.
            // iCloud 미동기화 파일 1건이 영영 안 끝나는 걸 막기 위해 파일당 최대 5초 기다리고
            // 포기한다 — 실패해도 이전 자체는 계속 진행(그 기록만 트랙 없이 이전됨).
            let tracksDir = cloudTracksDir ?? localTracksDir
            for i in records.indices where records[i].track.isEmpty && records[i].trackCount > 0 {
                let url = tracksDir.appendingPathComponent("\(records[i].id.uuidString).json")
                records[i].track = Self.readTrackBestEffort(url)
            }

            DispatchQueue.main.async {
                store.addMany(records)
                UserDefaults.standard.set(true, forKey: migratedKey)
            }
        }
    }

    private static func readTrackBestEffort(_ url: URL, timeout: TimeInterval = 5) -> [RideRecord.Coordinate] {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        let sema = DispatchSemaphore(value: 0)
        var result: [RideRecord.Coordinate] = []
        let once = SingleShotCompletion<[RideRecord.Coordinate]> { coords in
            result = coords
            sema.signal()
        }
        DispatchQueue.global(qos: .utility).async {
            var r: [RideRecord.Coordinate] = []
            let coordinator = NSFileCoordinator(); var err: NSError?
            coordinator.coordinate(readingItemAt: url, options: [], error: &err) { u in
                if let data = try? Data(contentsOf: u),
                   let coords = try? JSONDecoder().decode([RideRecord.Coordinate].self, from: data) {
                    r = coords
                }
            }
            once.fire(r)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { once.fire([]) }
        sema.wait()
        return result
    }
}
