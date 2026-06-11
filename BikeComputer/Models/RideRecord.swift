import Foundation
import Combine
import CoreLocation

/// 완료된 라이딩 1건. Routes 탭과 누적 통계(이번달/올해/총) 계산에 쓰인다.
struct RideRecord: Identifiable, Codable {
    let id: UUID
    var name: String
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
    var track: [Coordinate]

    struct Coordinate: Codable {
        var lat: Double
        var lon: Double
        var ele: Double? = nil      // 고도(m)
        var time: Date? = nil       // 측정 시각
        var speed: Double? = nil    // 속도(m/s)
        var hr: Int? = nil          // 심박(bpm)
        var clCoordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    }

    init(id: UUID = UUID(), name: String, startedAt: Date, duration: TimeInterval,
         totalElapsed: TimeInterval, distanceMeters: Double, averageSpeedMps: Double,
         maxSpeedMps: Double, maxHeartRate: Int?, avgHeartRate: Int?, maxCadence: Int?,
         track: [Coordinate]) {
        self.id = id
        self.name = name
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
    }
}

/// 라이딩 기록 저장소 + 누적 거리 통계.
/// `rides.json` 을 **iCloud Documents 컨테이너**에 저장해 기기 간 동기화한다.
/// iCloud 를 못 쓰면 로컬 Documents 로 폴백한다.
final class RideStore: ObservableObject {
    @Published private(set) var records: [RideRecord] = []

    private let fileName = "rides.json"
    private let localURL: URL
    private var cloudURL: URL?            // iCloud 사용 가능 시 설정
    private var metadataQuery: NSMetadataQuery?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        localURL = docs.appendingPathComponent(fileName)
        load()   // 우선 로컬에서 즉시 로드
        // iCloud 는 계정·컨테이너 준비 후 시도(미설정 시 accounts Code=7 로그만 나고 로컬 폴백)
        DispatchQueue.main.async { [weak self] in
            guard let self, CloudDocuments.isAvailable else { return }
            self.resolveCloud()
        }
    }

    private var fileURL: URL { cloudURL ?? localURL }

    func add(_ record: RideRecord) {
        records.insert(record, at: 0)
        save()
    }

    /// 대량 가져오기용: 한 번에 추가하고 1회만 저장(최신순 정렬).
    func addMany(_ newRecords: [RideRecord]) {
        guard !newRecords.isEmpty else { return }
        records.append(contentsOf: newRecords)
        records.sort { $0.startedAt > $1.startedAt }
        save()
    }

    func delete(_ record: RideRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    // MARK: 누적 거리(미터)

    var thisMonthMeters: Double {
        let cal = Calendar.current
        return records.filter { cal.isDate($0.startedAt, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.distanceMeters }
    }

    var thisYearMeters: Double {
        let cal = Calendar.current
        return records.filter { cal.isDate($0.startedAt, equalTo: Date(), toGranularity: .year) }
            .reduce(0) { $0 + $1.distanceMeters }
    }

    var totalMeters: Double {
        records.reduce(0) { $0 + $1.distanceMeters }
    }

    // MARK: 영속화 (파일 코디네이터 — iCloud 안전 읽기/쓰기)

    private func load() {
        let url = fileURL
        let coordinator = NSFileCoordinator()
        var err: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &err) { u in
            guard let data = try? Data(contentsOf: u),
                  let decoded = try? JSONDecoder().decode([RideRecord].self, from: data) else { return }
            DispatchQueue.main.async { self.records = decoded }
        }
    }

    private func save() {
        let url = fileURL
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator()
        var err: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            try? data.write(to: u, options: .atomic)
        }
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
    static let containerID = "iCloud.com.jaisungnoh.bikecomputer"

    /// iCloud 계정 로그인 여부. 메인 스레드에서 호출.
    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// 컨테이너 URL. 백그라운드에서 호출.
    static func containerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerID)
    }
}
