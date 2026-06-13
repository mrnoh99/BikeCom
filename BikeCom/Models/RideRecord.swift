import Foundation
import Combine
import CoreLocation

/// 라이딩 기록의 출처(통합 정리 시 우선순위: app > health > cyclemeter).
enum RideSource: String, Codable {
    case app        // 앱에서 직접 Start→Done
    case health     // Apple 건강에서 가져옴
    case cyclemeter // Cyclemeter 요약 CSV
    case gpx        // GPX 파일 가져옴
}

/// 완료된 라이딩 1건. Routes 탭과 누적 통계(이번달/올해/총) 계산에 쓰인다.
struct RideRecord: Identifiable, Codable {
    let id: UUID
    var name: String
    var bikeName: String?              // 자전거 종류(편집 가능, 가져온 기록은 없을 수 있음)
    var source: RideSource?            // 데이터 출처(통합 정리 우선순위용; 레거시는 nil)
    var location: String?              // 장소(Cyclemeter Location 열 등)
    var startedAt: Date
    var duration: TimeInterval        // 실제 라이딩 시간(정지 제외)
    var totalElapsed: TimeInterval     // 시작~종료 총 경과
    var distanceMeters: Double
    var averageSpeedMps: Double
    var maxSpeedMps: Double
    var maxHeartRate: Int?
    var avgHeartRate: Int?
    var maxCadence: Int?
    /// 경로 좌표 + 지점별 고도·시각·속도·심박(GPX 확장 태그용).
    /// 메모리 절약을 위해 목록/통계에서는 비워 두고(요약), 상세·내보내기 때만 디스크에서 로드한다.
    var track: [Coordinate]
    /// 트랙 포인트 수(트랙을 비운 요약에서도 GPS 유무 판단용).
    var trackCount: Int
    /// 시작·끝 좌표(코스 그룹핑용 — 트랙을 로드하지 않고도 분류 가능).
    var startCoord: Coordinate?
    var endCoord: Coordinate?
    /// 지도(코스) 목록에 표시할지 여부 — 주행 중 따라갈 코스를 직접 선별.
    var includeInMap: Bool
    /// 지도 목록에 보일 이름(비우면 라이딩 이름 사용).
    var mapName: String?
    /// 지도 코스 전용 자료 여부. true 면 거리·시간 등 통계 계산에서 제외하고
    /// 지도 보조(코스)로만 사용하며, 목록 맨 위에 고정한다.
    var isCourseOnly: Bool

    struct Coordinate: Codable {
        var lat: Double
        var lon: Double
        var ele: Double? = nil      // 고도(m)
        var time: Date? = nil       // 측정 시각
        var speed: Double? = nil    // 속도(m/s)
        var hr: Int? = nil          // 심박(bpm)
        var clCoordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    }

    init(id: UUID = UUID(), name: String, bikeName: String? = nil, source: RideSource? = nil,
         location: String? = nil,
         startedAt: Date, duration: TimeInterval,
         totalElapsed: TimeInterval, distanceMeters: Double, averageSpeedMps: Double,
         maxSpeedMps: Double, maxHeartRate: Int?, avgHeartRate: Int?, maxCadence: Int?,
         track: [Coordinate], includeInMap: Bool = false, mapName: String? = nil,
         isCourseOnly: Bool = false) {
        self.id = id
        self.name = name
        self.bikeName = bikeName
        self.source = source
        self.location = location
        self.startedAt = startedAt
        self.duration = duration
        self.totalElapsed = totalElapsed
        self.distanceMeters = distanceMeters
        self.averageSpeedMps = averageSpeedMps
        self.maxSpeedMps = maxSpeedMps
        self.maxHeartRate = maxHeartRate
        self.avgHeartRate = avgHeartRate
        self.maxCadence = maxCadence
        self.track = track
        self.trackCount = track.count
        self.startCoord = track.first
        self.endCoord = track.last
        self.includeInMap = includeInMap
        self.mapName = mapName
        self.isCourseOnly = isCourseOnly
    }

    enum CodingKeys: String, CodingKey {
        case id, name, bikeName, source, location, startedAt, duration, totalElapsed,
             distanceMeters, averageSpeedMps, maxSpeedMps, maxHeartRate, avgHeartRate,
             maxCadence, track, trackCount, startCoord, endCoord, includeInMap, mapName,
             isCourseOnly
    }

    /// 하위호환 디코딩: 옛 데이터(인라인 track, trackCount 없음)도 안전히 읽는다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "라이딩"
        bikeName = try c.decodeIfPresent(String.self, forKey: .bikeName)
        source = try c.decodeIfPresent(RideSource.self, forKey: .source)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        totalElapsed = try c.decodeIfPresent(TimeInterval.self, forKey: .totalElapsed) ?? 0
        distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
        averageSpeedMps = try c.decodeIfPresent(Double.self, forKey: .averageSpeedMps) ?? 0
        maxSpeedMps = try c.decodeIfPresent(Double.self, forKey: .maxSpeedMps) ?? 0
        maxHeartRate = try c.decodeIfPresent(Int.self, forKey: .maxHeartRate)
        avgHeartRate = try c.decodeIfPresent(Int.self, forKey: .avgHeartRate)
        maxCadence = try c.decodeIfPresent(Int.self, forKey: .maxCadence)
        let t = try c.decodeIfPresent([Coordinate].self, forKey: .track) ?? []
        track = t
        trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? t.count
        startCoord = try c.decodeIfPresent(Coordinate.self, forKey: .startCoord) ?? t.first
        endCoord = try c.decodeIfPresent(Coordinate.self, forKey: .endCoord) ?? t.last
        includeInMap = try c.decodeIfPresent(Bool.self, forKey: .includeInMap) ?? false
        mapName = try c.decodeIfPresent(String.self, forKey: .mapName)
        isCourseOnly = try c.decodeIfPresent(Bool.self, forKey: .isCourseOnly) ?? false
    }

    /// 메모리에 둘 요약본(트랙 비움). trackCount·시작/끝 좌표는 유지한다.
    func summary() -> RideRecord {
        var r = self
        if !track.isEmpty {
            r.trackCount = track.count
            r.startCoord = track.first
            r.endCoord = track.last
        }
        r.track = []
        return r
    }
}

/// 라이딩 기록 저장소 + 누적 거리 통계.
/// `rides.json` 을 **iCloud Documents 컨테이너**에 저장해 기기 간 동기화한다.
/// iCloud 를 못 쓰면 로컬 Documents 로 폴백한다.
final class RideStore: ObservableObject {
    @Published private(set) var records: [RideRecord] = [] {
        didSet { recomputeAggregates() }
    }

    // MARK: 누적 거리 캐시 (오도미터 방식)
    // 렌더마다 records 전체를 합산하지 않도록, 변경 시에만 1회 갱신해 캐시한다.
    // 월별 버킷(year*100+month → m)을 들고 있으면 이번 달·올해·전체를 즉시 계산할 수 있고,
    // 월/연 경계가 바뀌어도(앱을 켜둔 채 자정/연초) 현재 날짜 기준으로 정확하다.
    private(set) var totalMeters: Double = 0
    private var monthlyMeters: [Int: Double] = [:]
    private static let totalKey = "bike.odometer.totalMeters"
    private static let monthlyKey = "bike.odometer.monthlyMeters"

    var thisMonthMeters: Double {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        guard let y = c.year, let m = c.month else { return 0 }
        return monthlyMeters[y * 100 + m] ?? 0
    }
    var thisYearMeters: Double {
        let y = Calendar.current.component(.year, from: Date())
        return monthlyMeters.reduce(0) { $0 + ($1.key / 100 == y ? $1.value : 0) }
    }

    private let fileName = "rides.json"
    private let localURL: URL
    private var cloudURL: URL?            // iCloud 사용 가능 시 설정
    private var metadataQuery: NSMetadataQuery?

    /// 저장/로드(인코딩·디코딩·파일 IO)를 메인 스레드 밖에서 직렬 처리한다.
    private let ioQueue = DispatchQueue(label: "com.bikecom.rides.io", qos: .utility)
    /// 마지막으로 디스크에 쓰거나 읽은 rides.json 의 **해시**. ioQueue 에서만 접근.
    /// 전체 바이트를 보관하면 메모리(수십 MB)를 영구 점유하므로 해시만 들고 비교한다.
    /// 우리가 쓴 파일이 iCloud 알림으로 되돌아왔을 때 불필요한 재로딩을 막는다.
    private var lastPersistedHash: Int?
    /// 연속 변경(대량 삭제 등) 시 전체 인코딩을 매번 하지 않도록 저장을 디바운스한다.
    private var saveWorkItem: DispatchWorkItem?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        localURL = docs.appendingPathComponent(fileName)
        loadPersistedAggregates()   // 레코드 로드 전에도 누적 거리 즉시 표시
        load()   // 우선 로컬에서 즉시 로드
        // iCloud 는 계정·컨테이너 준비 후 시도(미설정 시 accounts Code=7 로그만 나고 로컬 폴백)
        DispatchQueue.main.async { [weak self] in
            guard let self, CloudDocuments.isAvailable else { return }
            self.resolveCloud()
        }
    }

    private var fileURL: URL { cloudURL ?? localURL }

    func add(_ record: RideRecord) {
        writeTrackFile(record)
        records.insert(record.summary(), at: 0)
        save()
    }

    /// 대량 가져오기용: 한 번에 추가하고 1회만 저장(최신순 정렬).
    func addMany(_ newRecords: [RideRecord]) {
        guard !newRecords.isEmpty else { return }
        for r in newRecords { writeTrackFile(r) }
        records.append(contentsOf: newRecords.map { $0.summary() })
        records.sort { $0.startedAt > $1.startedAt }
        save()
    }

    /// 병합 결과 등으로 전체 기록을 교체한다.
    func replaceAll(_ newRecords: [RideRecord]) {
        for r in newRecords { writeTrackFile(r) }
        records = newRecords.map { $0.summary() }
        save()
    }

    /// id 가 같은 기록을 교체(코스명·자전거 종류 등 편집 반영).
    func update(_ record: RideRecord) {
        guard let i = records.firstIndex(where: { $0.id == record.id }) else { return }
        writeTrackFile(record)   // 트랙이 있으면 갱신, 없으면 기존 파일 유지
        records[i] = record.summary()
        save()
    }

    func delete(_ record: RideRecord) {
        records.removeAll { $0.id == record.id }
        deleteTrackFile(record.id)
        save()
    }

    // MARK: 트랙 파일 (라이딩별 GPS 트랙을 분리 저장 — 메모리 절약)

    private var tracksDir: URL {
        localURL.deletingLastPathComponent().appendingPathComponent("Tracks", isDirectory: true)
    }
    private func trackFileURL(_ id: UUID) -> URL {
        tracksDir.appendingPathComponent("\(id.uuidString).json")
    }

    /// 트랙이 비어 있지 않으면 라이딩별 파일로 저장(백그라운드). 비어 있으면 기존 파일을 보존.
    private func writeTrackFile(_ record: RideRecord) {
        guard !record.track.isEmpty else { return }
        let url = trackFileURL(record.id)
        let track = record.track
        ioQueue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(track) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func deleteTrackFile(_ id: UUID) {
        let url = trackFileURL(id)
        ioQueue.async { try? FileManager.default.removeItem(at: url) }
    }

    /// 라이딩의 GPS 트랙을 디스크에서 비동기로 로드(상세·내보내기용). 메인 큐로 반환.
    func loadTrack(for record: RideRecord, completion: @escaping ([RideRecord.Coordinate]) -> Void) {
        if !record.track.isEmpty { completion(record.track); return }
        guard record.trackCount > 0 else { completion([]); return }
        let url = trackFileURL(record.id)
        ioQueue.async {
            let coords = Self.readTrack(url)
            DispatchQueue.main.async { completion(coords) }
        }
    }

    /// 동기 트랙 로드(이미 백그라운드 스레드인 내보내기에서 사용).
    func loadTrackSync(_ record: RideRecord) -> [RideRecord.Coordinate] {
        if !record.track.isEmpty { return record.track }
        guard record.trackCount > 0 else { return [] }
        return Self.readTrack(trackFileURL(record.id))
    }

    private static func readTrack(_ url: URL) -> [RideRecord.Coordinate] {
        guard let data = try? Data(contentsOf: url),
              let coords = try? JSONDecoder().decode([RideRecord.Coordinate].self, from: data) else { return [] }
        return coords
    }

    // MARK: 누적 거리 집계 (records 변경 시 1회 갱신 + 영속화)

    /// records 전체를 한 번 훑어 전체·월별 누적 거리를 다시 계산하고 디스크에 저장한다.
    private func recomputeAggregates() {
        var total = 0.0
        var monthly: [Int: Double] = [:]
        let cal = Calendar.current
        for r in records where !r.isCourseOnly {
            total += r.distanceMeters
            let c = cal.dateComponents([.year, .month], from: r.startedAt)
            if let y = c.year, let m = c.month {
                monthly[y * 100 + m, default: 0] += r.distanceMeters
            }
        }
        totalMeters = total
        monthlyMeters = monthly
        persistAggregates()
    }

    private func persistAggregates() {
        let d = UserDefaults.standard
        d.set(totalMeters, forKey: Self.totalKey)
        // UserDefaults dictionary 키는 String 이어야 하므로 변환해 저장.
        let dict = Dictionary(uniqueKeysWithValues: monthlyMeters.map { (String($0.key), $0.value) })
        d.set(dict, forKey: Self.monthlyKey)
    }

    /// 앱 실행 직후(레코드 비동기 로드 전)에도 즉시 표시되도록 마지막 집계를 복원한다.
    private func loadPersistedAggregates() {
        let d = UserDefaults.standard
        totalMeters = d.double(forKey: Self.totalKey)
        if let dict = d.dictionary(forKey: Self.monthlyKey) as? [String: Double] {
            monthlyMeters = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                Int(k).map { ($0, v) }
            })
        }
    }

    // MARK: 영속화 (파일 코디네이터 — iCloud 안전 읽기/쓰기)

    /// 디스크 읽기·디코딩을 **백그라운드(ioQueue)** 에서 수행하고 결과만 메인으로 반영한다.
    /// (큰 rides.json 을 메인에서 디코딩하면 삭제·편집 직후 화면이 늦게 반응한다.)
    private func load() {
        let url = fileURL
        let localBak = backupLocalURL
        let cloudBak = backupCloudURL
        ioQueue.async { [weak self] in
            guard let self else { return }
            let coordinator = NSFileCoordinator()
            var err: NSError?
            var fileData: Data?
            coordinator.coordinate(readingItemAt: url, options: [], error: &err) { u in
                fileData = try? Data(contentsOf: u)
            }
            // 우리가 방금 쓴 내용이 그대로 돌아온 경우(자기 쓰기 에코) 재로딩 생략.
            if let data = fileData, data.hashValue == self.lastPersistedHash { return }

            if let data = fileData,
               let decoded = try? JSONDecoder().decode([RideRecord].self, from: data),
               !decoded.isEmpty {
                // 마이그레이션: 옛 형식(인라인 트랙)이면 라이딩별 트랙 파일로 분리하고
                // rides.json 은 요약본으로 다시 쓴다. 이후 메모리엔 트랙을 두지 않는다.
                let needsMigration = decoded.contains { !$0.track.isEmpty }
                if needsMigration {
                    try? FileManager.default.createDirectory(at: self.tracksDir,
                                                             withIntermediateDirectories: true)
                    for r in decoded where !r.track.isEmpty {
                        if let d = try? JSONEncoder().encode(r.track) {
                            try? d.write(to: self.trackFileURL(r.id), options: .atomic)
                        }
                    }
                } else {
                    self.lastPersistedHash = data.hashValue
                }
                let summaries = decoded.map { $0.summary() }
                DispatchQueue.main.async {
                    self.records = summaries
                    if needsMigration { self.save() }   // rides.json 을 요약본으로 재기록
                }
                return
            }
            // 메인 파일이 없거나 비었으면(재설치 직후 등) 백업에서 자동 복원.
            if let restored = Self.loadBackupRecords(localURL: localBak, cloudURL: cloudBak) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.records.isEmpty else { return }
                    self.replaceAll(restored)   // 트랙 분리 저장 + 요약본 기록
                }
            }
        }
    }

    /// 저장은 **백그라운드(ioQueue)** 에서 수행하며, 연속 호출은 디바운스로 1회로 합친다.
    /// 한 번 인코딩한 data 를 rides.json 과 백업 파일에 재사용한다(autoreleasepool).
    private func save() {
        let snapshot = records
        let mainURL = fileURL
        let localBak = backupLocalURL
        let cloudBak = backupCloudURL
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            autoreleasepool {
                guard let self, let data = try? JSONEncoder().encode(snapshot) else { return }
                self.lastPersistedHash = data.hashValue
                try? FileManager.default.createDirectory(at: mainURL.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                let coordinator = NSFileCoordinator()
                var err: NSError?
                coordinator.coordinate(writingItemAt: mainURL, options: .forReplacing, error: &err) { u in
                    try? data.write(to: u, options: .atomic)
                }
                try? data.write(to: localBak, options: .atomic)
                if let cloudBak {
                    let c = NSFileCoordinator(); var e: NSError?
                    c.coordinate(writingItemAt: cloudBak, options: .forReplacing, error: &e) { u in
                        try? data.write(to: u, options: .atomic)
                    }
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastBackupKey)
            }
        }
        saveWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: 자동 백업 (재설치·기기변경 시 라이딩 데이터 보존)
    // rides.json 과 별개로 메타데이터가 포함된 백업 파일을 로컬(Files 앱에서 열람 가능)과
    // iCloud(재설치해도 자동 복원)에 함께 저장한다.

    static let lastBackupKey = "bike.lastBackupAt"
    let backupFileName = "BikeCom-Backup.json"
    private var backupLocalURL: URL {
        localURL.deletingLastPathComponent().appendingPathComponent(backupFileName)
    }
    private var backupCloudURL: URL? {
        cloudURL?.deletingLastPathComponent().appendingPathComponent(backupFileName)
    }

    /// 백업 봉투: 버전·저장시각·건수 + 전체 기록(트랙 포함).
    struct Backup: Codable {
        var version: Int = 1
        var savedAt: Date = Date()
        var count: Int
        var records: [RideRecord]
    }

    /// 현재 전체 기록을 백업 형식(JSON)으로 인코딩한다(수동 내보내기·공유용).
    func makeBackupData() -> Data? {
        try? JSONEncoder().encode(Backup(count: records.count, records: records))
    }

    /// 백업 파일에서 기록을 읽는다(iCloud 우선, 없으면 로컬). 백그라운드에서 호출.
    private static func loadBackupRecords(localURL: URL, cloudURL: URL?) -> [RideRecord]? {
        for url in [cloudURL, localURL].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let b = try? JSONDecoder().decode(Backup.self, from: data), !b.records.isEmpty {
                return b.records
            }
            if let data = try? Data(contentsOf: url),
               let arr = try? JSONDecoder().decode([RideRecord].self, from: data), !arr.isEmpty {
                return arr
            }
        }
        return nil
    }

    /// 사용자가 고른 백업 파일을 복원(병합)한다. 백업 봉투·rides.json 둘 다 허용. 복원 후 총 건수 반환.
    @discardableResult
    func restoreBackup(from url: URL) -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return 0 }
        var incoming: [RideRecord] = []
        if let b = try? JSONDecoder().decode(Backup.self, from: data) {
            incoming = b.records
        } else if let arr = try? JSONDecoder().decode([RideRecord].self, from: data) {
            incoming = arr
        }
        guard !incoming.isEmpty else { return 0 }
        let merged = RideRecordMerge.merge(existing: records, incoming: incoming, incomingWins: false)
        replaceAll(merged)
        return merged.count
    }

    // MARK: iCloud 동기화

    private func resolveCloud() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let container = CloudDocuments.containerURL() else { return }
            let docs = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            let url = docs.appendingPathComponent(self.fileName)
            DispatchQueue.main.async {
                self.cloudURL = url
                self.migrateLocalToCloudIfNeeded()
                self.load()
                self.startMetadataQuery()
            }
        }
    }

    /// 로컬에만 기록이 있고 iCloud 엔 아직 없으면 1회 업로드.
    private func migrateLocalToCloudIfNeeded() {
        guard let cloudURL else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: cloudURL.path), fm.fileExists(atPath: localURL.path),
           let data = try? Data(contentsOf: localURL) {
            try? data.write(to: cloudURL, options: .atomic)
        }
    }

    /// 다른 기기에서 바뀐 rides.json 을 감지해 다시 불러온다.
    private func startMetadataQuery() {
        guard cloudURL != nil, CloudDocuments.isAvailable else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
        NotificationCenter.default.addObserver(self, selector: #selector(cloudChanged),
                                               name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.addObserver(self, selector: #selector(cloudChanged),
                                               name: .NSMetadataQueryDidUpdate, object: q)
        q.start()
        metadataQuery = q
    }

    @objc private func cloudChanged() {
        load()
    }
}

/// iCloud Documents 컨테이너 접근. 미로그인·권한 없으면 nil → 로컬 폴백.
enum CloudDocuments {
    static let containerID = "iCloud.com.jaisungnoh.bikecom"

    /// iCloud 계정 로그인 여부. 메인 스레드에서 호출.
    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// 컨테이너 URL. 백그라운드에서 호출.
    static func containerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerID)
    }
}
