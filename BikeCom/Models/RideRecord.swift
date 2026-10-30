import Foundation
import Combine
import CoreData
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
    var avgCadence: Int?
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

    /// 이 레코드가 변환돼 나온 실제 Core Data 객체의 식별자(`NSManagedObjectID` URI 문자열).
    /// CloudKit은 유니크 제약(unique constraint)을 지원하지 않아 `id`(UUID)가 **기기 간 동기화
    /// 과정에서 우연히 중복**될 수 있다 — 예를 들어 레거시 백업을 서로 다른 두 기기가 거의
    /// 동시에 재가져오기하면, 둘 다 자기 로컬 저장소엔 그 id가 없다고 보고 각자 새 Core Data
    /// 객체를 만들어 CloudKit에 올리고, 그 결과 "같은 id를 가진 서로 다른 두 레코드"가 모든
    /// 기기에 그대로 동기화돼 버린다. 이렇게 되면 `id`만으로는 두 레코드를 구분할 수 없어
    /// (삭제·선택 모두 엉뚱한 쪽을 건드리거나 둘 다 건드리는 등) 중복 삭제가 제대로 안 된다.
    /// `objectIDURI`는 Core Data가 보장하는 진짜 유니크 값이라 이런 충돌이 없다 — 백업
    /// zip·GPX 등 내보내기엔 의미가 없으므로(기기·저장소마다 다름) Codable 대상에서 제외하고
    /// `summary(of:)`/`full(of:)`에서만 채운다.
    var objectIDURI: String? = nil

    /// 목록 표시·삭제 대상 지정에 쓸 진짜 유니크 키. `id`가 위 이유로 중복될 수 있으므로
    /// `SwiftUI List`/`ForEach`의 identity나 삭제 대상 선택엔 `id` 대신 이 값을 써야 한다.
    var uniqueKey: String { objectIDURI ?? id.uuidString }

    struct Coordinate: Codable {
        var lat: Double
        var lon: Double
        var ele: Double? = nil      // 고도(m)
        var time: Date? = nil       // 측정 시각
        var speed: Double? = nil    // 속도(m/s)
        var hr: Int? = nil          // 심박(bpm)
        var clCoordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
        /// 표시용 GPS 좌표 문자열(위도, 경도).
        var gpsText: String { String(format: "%.4f, %.4f", lat, lon) }
    }

    init(id: UUID = UUID(), name: String, bikeName: String? = nil, source: RideSource? = nil,
         location: String? = nil,
         startedAt: Date, duration: TimeInterval,
         totalElapsed: TimeInterval, distanceMeters: Double, averageSpeedMps: Double,
         maxSpeedMps: Double, maxHeartRate: Int?, avgHeartRate: Int?, maxCadence: Int?, avgCadence: Int? = nil,
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
        self.avgCadence = avgCadence
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
             maxCadence, avgCadence, track, trackCount, startCoord, endCoord, includeInMap, mapName,
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
        avgCadence = try c.decodeIfPresent(Int.self, forKey: .avgCadence)
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
///
/// **Core Data + `NSPersistentCloudKitContainer`로 저장한다** (기존엔 `rides.json` 파일 하나를
/// iCloud Documents로 동기화하는 방식이었다). 여러 기기를 동시에 쓸 때 파일 하나를 통째로
/// 덮어쓰는 방식은 한 기기의 새 기록이 다른 기기의 저장으로 조용히 사라지는 위험이 있었다
/// (각 기기가 메모리의 전체 배열을 그대로 다시 썼기 때문). Core Data + CloudKit은 레코드
/// 단위로 동기화하고 충돌도 Apple 프레임워크가 처리해서 이 위험을 구조적으로 없앤다.
/// 트랙(GPS 좌표 배열)은 `trackData`에 JSON으로 인코딩해 저장하고, "Allows External Storage"로
/// 표시해 큰 트랙도 CloudKit의 레코드당 용량 제한에 걸리지 않게 한다.
///
/// 트랙 읽기가 로컬 SQLite 저장소에서 바로 이뤄지므로, 예전에 `NSFileCoordinator`가 iCloud
/// 파일을 기다리다 영영 반환하지 않을 수 있었던 문제("경로 불러오는 중"이 끝없이 도는 것으로
/// 확인된 원인 중 하나) 자체가 이제 구조적으로 발생하지 않는다 — 로컬 읽기는 항상 빠르고,
/// CloudKit과의 동기화는 완전히 분리된 백그라운드 과정이다.
final class RideStore: ObservableObject {
    @Published private(set) var records: [RideRecord] = [] {
        didSet { recomputeAggregates() }
    }

    /// 가장 최근 수동 백업(zip 내보내기) 시도가 실패했는지. Core Data 전환 이전엔 "자동 백업"이
    /// 조용히 실패할 수 있었지만, 지금은 CloudKit이 실시간 동기화를 맡고 있어 이 플래그는
    /// 사용자가 직접 누른 "백업 zip 내보내기"에만 해당한다.
    @Published private(set) var lastBackupFailed = false

    /// 가장 최근 add/update/delete 저장이 실패했는지. 실패해도 `records`(화면)는 그 틱까지는
    /// 정상으로 보일 수 있다 — Core Data는 저장 실패와 무관하게 컨텍스트의 미저장 변경을
    /// 그대로 들고 있어서, 다음 fetch가 같은 컨텍스트에서 일어나는 한 화면엔 추가한 게 그대로
    /// 보인다. 문제는 앱을 껐다 켜면(퍼시스턴트 스토어에서 새로 읽음) 그 기록이 사라진
    /// 것처럼 보인다는 것 — 실제로 디스크에 저장된 적이 없기 때문이다. 이 플래그를 세워서
    /// 그 순간 바로 알 수 있게 한다(예전엔 print()만 해서 콘솔을 안 보면 알 길이 없었다).
    @Published private(set) var lastSaveFailed = false

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

    /// 백업 봉투(수동 zip 내보내기·복원 포맷). `BackupZip.swift`가 `RideStore.Backup`으로
    /// 직접 참조하므로 이름·형태를 그대로 유지한다.
    struct Backup: Codable {
        var version: Int = 1
        var savedAt: Date = Date()
        var count: Int
        var records: [RideRecord]
    }

    static let lastBackupKey = "bike.lastBackupAt"

    private let container: NSPersistentCloudKitContainer
    private var viewContext: NSManagedObjectContext { container.viewContext }

    init() {
        container = BikeComPersistence.makeContainer()
        loadPersistedAggregates()   // 레코드 로드 전에도 누적 거리 즉시 표시
        NotificationCenter.default.addObserver(self, selector: #selector(storeRemoteChange),
                                               name: .NSPersistentStoreRemoteChange,
                                               object: container.persistentStoreCoordinator)
        // loadPersistentStores 는 비동기다 — 완료 전에 fetch를 먼저 돌리면(레이스) 스토어가
        // 아직 안 붙어 있어 빈 결과를 받을 수 있다. 완료 핸들러 안에서만 읽기 시작한다.
        // 핸들러는 메인 스레드 호출이 보장되지 않으므로 명시적으로 메인에 올린다.
        container.loadPersistentStores { [weak self] _, error in
            if let error {
                // 스토어 로드 실패는 드물지만(기기 저장 공간 고갈 등) 크래시 대신 로그만
                // 남긴다 — 빈 스토어로라도 앱은 계속 쓸 수 있어야 한다.
                print("Core Data 스토어 로드 실패: \(error)")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshRecords()
            }
        }
    }

    /// 다른 기기의 변경이 CloudKit을 통해 들어오면(NSPersistentCloudKitContainer가 알아서 병합)
    /// 알려준다 — 화면에 반영하기 위해 다시 읽기만 하면 된다(병합 자체는 이미 끝난 뒤).
    @objc private func storeRemoteChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshRecords()
            // 드물게 이 알림 시점에 메인 컨텍스트 병합이 아직 안 끝나 있어도(관찰됨: 앱을 켜둔
            // 채로는 최신 기록이 한동안 안 보이다가, 완전히 종료 후 재실행하면 바로 보였다)
            // 한 번 더 뒤늦게 재확인해서 그 틈을 메운다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.refreshRecords() }
        }
    }

    private func refreshRecords() {
        // CloudKit이 백그라운드 컨텍스트로 가져온 변경을 viewContext가 병합했다고
        // (automaticallyMergesChangesFromParent) 반드시 이 fetch 시점까지 다 반영했다는
        // 보장은 없다 — 실기기에서 "앱을 켜둔 채로는 가끔 최신 기록이 안 보이다가, 완전히
        // 종료했다 다시 열면 바로 보인다"는 게 재현됐다(= 새 컨테이너로 다시 로드할 때만
        // 확실히 반영됨). refreshAllObjects()로 이미 등록된 객체의 캐시를 비워 다음 fetch가
        // 퍼시스턴트 스토어 코디네이터에서 다시 읽어오도록 강제한다.
        viewContext.refreshAllObjects()
        let req = CDRide.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        guard let rows = try? viewContext.fetch(req) else { return }
        records = rows.map { Self.summary(of: $0) }
    }

    // MARK: 변경 (기존 공개 API 그대로 — 호출부는 전혀 바뀌지 않는다)

    func add(_ record: RideRecord) {
        Self.upsert(record, in: viewContext)
        saveContext()
        refreshRecords()
    }

    /// 대량 가져오기용: 한 번에 추가하고 1회만 저장(최신순 정렬은 refreshRecords 가 다시 계산).
    func addMany(_ newRecords: [RideRecord]) {
        guard !newRecords.isEmpty else { return }
        for r in newRecords { Self.upsert(r, in: viewContext) }
        saveContext()
        refreshRecords()
    }

    /// 병합 결과 등으로 전체 기록을 교체한다.
    func replaceAll(_ newRecords: [RideRecord]) {
        if let all = try? viewContext.fetch(CDRide.fetchRequest()) {
            for o in all { viewContext.delete(o) }
        }
        for r in newRecords { Self.upsert(r, in: viewContext) }
        saveContext()
        refreshRecords()
    }

    /// id 가 같은 기록을 교체(코스명·자전거 종류 등 편집 반영).
    func update(_ record: RideRecord) {
        guard records.contains(where: { $0.id == record.id }) else { return }
        Self.upsert(record, in: viewContext)
        saveContext()
        refreshRecords()
    }

    func delete(_ record: RideRecord) {
        Self.delete(record, in: viewContext)
        saveContext()
        refreshRecords()
    }

    /// 여러 기록을 한 번에 삭제한다. 하나씩 `delete(_:)`를 반복 호출하면 그때마다 `@Published`
    /// 변경을 발행해 화면이 중간 상태를 여러 번 다시 그리므로, 모아서 한 번에 저장·발행한다.
    func deleteMany(_ toDelete: [RideRecord]) {
        guard !toDelete.isEmpty else { return }
        for r in toDelete { Self.delete(r, in: viewContext) }
        saveContext()
        refreshRecords()
    }

    private func saveContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            lastSaveFailed = false
        } catch {
            // Core Data 저장 실패는 드물지만(디스크 공간, CloudKit이 거부하는 값 등), 크래시
            // 대신 로그 + 플래그로 남긴다. 저장이 실패해도 방금 추가/수정한 내용은 이 컨텍스트
            // 안에 미저장 변경으로 남아 있어서 화면(records)엔 당장 정상으로 보일 수 있다 —
            // 앱을 재시작하면(디스크에서 다시 읽으므로) 저장 안 된 내용은 사라진다.
            print("RideStore Core Data 저장 실패: \(error)")
            lastSaveFailed = true
        }
    }

    // MARK: CDRide ↔ RideRecord 매핑

    /// 요약본(트랙 비움)으로 변환 — 목록·통계용. `cd.trackData`를 건드리지 않으므로(Core Data의
    /// Binary External Storage는 접근하기 전까진 로드되지 않는다) 목록을 그릴 때 큰 트랙
    /// 데이터를 메모리에 올리지 않는다.
    private static func summary(of cd: CDRide) -> RideRecord {
        var r = RideRecord(
            id: cd.id ?? UUID(),
            name: cd.name ?? "라이딩",
            bikeName: cd.bikeName,
            source: cd.source.flatMap(RideSource.init(rawValue:)),
            location: cd.location,
            startedAt: cd.startedAt ?? Date(),
            duration: cd.duration,
            totalElapsed: cd.totalElapsed,
            distanceMeters: cd.distanceMeters,
            averageSpeedMps: cd.averageSpeedMps,
            maxSpeedMps: cd.maxSpeedMps,
            maxHeartRate: cd.maxHeartRate?.intValue,
            avgHeartRate: cd.avgHeartRate?.intValue,
            maxCadence: cd.maxCadence?.intValue,
            avgCadence: cd.avgCadence?.intValue,
            track: [],
            includeInMap: cd.includeInMap,
            mapName: cd.mapName,
            isCourseOnly: cd.isCourseOnly
        )
        r.objectIDURI = cd.objectID.uriRepresentation().absoluteString
        r.trackCount = Int(cd.trackCount)
        if let data = cd.startCoordData {
            r.startCoord = try? JSONDecoder().decode(RideRecord.Coordinate.self, from: data)
        }
        if let data = cd.endCoordData {
            r.endCoord = try? JSONDecoder().decode(RideRecord.Coordinate.self, from: data)
        }
        return r
    }

    /// 트랙까지 포함한 완전한 변환 — 백업 내보내기·상세 화면용.
    private static func full(of cd: CDRide) -> RideRecord {
        var r = summary(of: cd)
        if let data = cd.trackData,
           let coords = try? JSONDecoder().decode([RideRecord.Coordinate].self, from: data) {
            r.track = coords
        }
        return r
    }

    /// NaN/Infinity를 0으로 바꾼다. GPS 신호 불량(터널·지하철 환승 등 "출근" 라이딩에서
    /// 특히 흔함) 때는 거리/속도 계산이 0으로 나누거나 비정상 값이 섞일 수 있는데, 이런 값을
    /// 그대로 두면 `JSONEncoder`가 던지거나(트랙 인코딩 실패) CloudKit이 그 레코드 전체를
    /// 거부할 수 있다(CloudKit은 NaN/Infinity 필드를 아예 받지 않는다) — 저장은 됐는데 다른
    /// 기기로 동기화가 안 되거나, 최악의 경우 저장 자체가 조용히 실패해 기록이 통째로
    /// 사라지는 것처럼 보일 수 있다.
    private static func finite(_ d: Double) -> Double { d.isFinite ? d : 0 }

    /// 트랙에서 위경도가 유효하지 않은(NaN 등) 포인트를 제거하고, 나머지 필드의 비정상 값은
    /// 0/nil로 정리한다. 이렇게 해야 트랙 전체를 JSON으로 인코딩할 때 실패하지 않는다.
    private static func sanitized(_ track: [RideRecord.Coordinate]) -> [RideRecord.Coordinate] {
        track.compactMap { c in
            guard c.lat.isFinite, c.lon.isFinite, CLLocationCoordinate2DIsValid(c.clCoordinate) else { return nil }
            var c = c
            if let e = c.ele, !e.isFinite { c.ele = nil }
            if let s = c.speed, !s.isFinite { c.speed = nil }
            return c
        }
    }

    /// `id`가 같은 행을 찾아 갱신하거나 없으면 새로 만든다. 트랙은 **비어 있지 않을 때만**
    /// 갱신하고(= 상세 화면에서 트랙을 올린 전체본으로 저장할 때), 요약본으로 `update(_:)`를
    /// 호출해도 이미 저장된 트랙은 보존한다.
    @discardableResult
    private static func upsert(_ r: RideRecord, in ctx: NSManagedObjectContext) -> CDRide {
        var r = r
        r.duration = finite(r.duration)
        r.totalElapsed = finite(r.totalElapsed)
        r.distanceMeters = finite(r.distanceMeters)
        r.averageSpeedMps = finite(r.averageSpeedMps)
        r.maxSpeedMps = finite(r.maxSpeedMps)
        r.track = sanitized(r.track)

        let req = CDRide.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", r.id as CVarArg)
        req.fetchLimit = 1
        let cd = (try? ctx.fetch(req).first) ?? CDRide(context: ctx)
        cd.id = r.id
        cd.name = r.name
        cd.bikeName = r.bikeName
        cd.source = r.source?.rawValue
        cd.location = r.location
        cd.startedAt = r.startedAt
        cd.duration = r.duration
        cd.totalElapsed = r.totalElapsed
        cd.distanceMeters = r.distanceMeters
        cd.averageSpeedMps = r.averageSpeedMps
        cd.maxSpeedMps = r.maxSpeedMps
        cd.maxHeartRate = r.maxHeartRate.map { NSNumber(value: $0) }
        cd.avgHeartRate = r.avgHeartRate.map { NSNumber(value: $0) }
        cd.maxCadence = r.maxCadence.map { NSNumber(value: $0) }
        cd.avgCadence = r.avgCadence.map { NSNumber(value: $0) }
        cd.includeInMap = r.includeInMap
        cd.mapName = r.mapName
        cd.isCourseOnly = r.isCourseOnly
        if !r.track.isEmpty {
            cd.trackData = try? JSONEncoder().encode(r.track)
            cd.trackCount = Int32(r.track.count)
            cd.startCoordData = r.track.first.flatMap { try? JSONEncoder().encode($0) }
            cd.endCoordData = r.track.last.flatMap { try? JSONEncoder().encode($0) }
        } else {
            cd.trackCount = Int32(r.trackCount)
            if let s = r.startCoord, s.lat.isFinite, s.lon.isFinite {
                cd.startCoordData = try? JSONEncoder().encode(s)
            }
            if let e = r.endCoord, e.lat.isFinite, e.lon.isFinite {
                cd.endCoordData = try? JSONEncoder().encode(e)
            }
        }
        return cd
    }

    /// `id`만으로 지우면(`deleteByID`) 위 `objectIDURI` 주석에서 설명한 중복 상황에서 둘 중
    /// 하나만(어느 쪽인지 알 수 없게) 지워진다 — 중복 기록 정리에서 "이 행만" 지우려 해도
    /// 안 지워지거나 엉뚱한 쪽이 지워지는 원인. `objectIDURI`가 있으면 그 정확한 객체를
    /// 지워서 이 문제를 피하고, 없을 때만(한 번도 Core Data를 거치지 않은 등 드문 경우)
    /// id 기반으로 폴백한다.
    private static func delete(_ r: RideRecord, in ctx: NSManagedObjectContext) {
        if let uriString = r.objectIDURI,
           let uri = URL(string: uriString),
           let coordinator = ctx.persistentStoreCoordinator,
           let objectID = coordinator.managedObjectID(forURIRepresentation: uri),
           let obj = try? ctx.existingObject(with: objectID) {
            ctx.delete(obj)
            return
        }
        deleteByID(r.id, in: ctx)
    }

    private static func deleteByID(_ id: UUID, in ctx: NSManagedObjectContext) {
        let req = CDRide.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        if let obj = try? ctx.fetch(req).first { ctx.delete(obj) }
    }

    // MARK: 트랙 로드 (상세·내보내기용)

    /// 라이딩의 GPS 트랙을 로드한다. 로컬 Core Data 저장소에서 읽으므로 항상 빠르고(네트워크
    /// 대기 없음) 결과는 메인 큐로 반환한다.
    func loadTrack(for record: RideRecord, completion: @escaping ([RideRecord.Coordinate]) -> Void) {
        if !record.track.isEmpty { completion(record.track); return }
        guard record.trackCount > 0 else { completion([]); return }
        let id = record.id
        container.performBackgroundTask { ctx in
            let coords = Self.fetchTrack(id: id, in: ctx)
            DispatchQueue.main.async { completion(coords) }
        }
    }

    /// 동기 트랙 로드(이미 백그라운드 스레드인 내보내기에서 사용).
    func loadTrackSync(_ record: RideRecord) -> [RideRecord.Coordinate] {
        if !record.track.isEmpty { return record.track }
        guard record.trackCount > 0 else { return [] }
        var result: [RideRecord.Coordinate] = []
        let ctx = container.newBackgroundContext()
        ctx.performAndWait { result = Self.fetchTrack(id: record.id, in: ctx) }
        return result
    }

    private static func fetchTrack(id: UUID, in ctx: NSManagedObjectContext) -> [RideRecord.Coordinate] {
        let req = CDRide.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let cd = try? ctx.fetch(req).first, let data = cd.trackData,
              let coords = try? JSONDecoder().decode([RideRecord.Coordinate].self, from: data) else {
            return []
        }
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

    // MARK: 백업(zip) — 사용자가 직접 누르는 수동 내보내기/복원. 기기 간 동기화 자체는 더
    // 이상 이 경로에 의존하지 않는다(CloudKit이 실시간으로 처리) — 이건 이동·보관용 스냅샷이다.

    /// 현재 전체 기록(트랙 포함)을 백업 형식(JSON)으로 인코딩한다. progress 는 메인 큐에서 호출된다.
    func makeBackupData(progress: ((Int, Int) -> Void)? = nil, completion: @escaping (Data?) -> Void) {
        container.performBackgroundTask { ctx in
            let req = CDRide.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
            guard let rows = try? ctx.fetch(req) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let total = rows.count
            var full: [RideRecord] = []
            full.reserveCapacity(total)
            for (i, cd) in rows.enumerated() {
                full.append(Self.full(of: cd))
                let done = i + 1
                if done == total || done % 25 == 0 {
                    DispatchQueue.main.async { progress?(done, total) }
                }
            }
            let data = try? JSONEncoder().encode(Backup(count: full.count, records: full))
            DispatchQueue.main.async { completion(data) }
        }
    }

    /// 현재 전체 기록(트랙 포함)을 zip 백업 파일로 만든다(공유·복원용). progress 는 메인 큐에서 호출된다.
    func makeBackupZip(progress: ((Int, Int) -> Void)? = nil, completion: @escaping (URL?) -> Void) {
        makeBackupData(progress: progress) { data in
            guard let data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmm"
                let stamp = df.string(from: Date())
                let folder = fm.temporaryDirectory.appendingPathComponent("BikeCom-Backup-\(stamp)", isDirectory: true)
                try? fm.removeItem(at: folder)
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let jsonURL = folder.appendingPathComponent("BikeCom-Backup.json")
                let zipURL = fm.temporaryDirectory.appendingPathComponent("BikeCom-Backup-\(stamp).zip")
                do {
                    try data.write(to: jsonURL, options: .atomic)
                    try BackupZip.createArchive(jsonURL: jsonURL, zipURL: zipURL)
                    try? fm.removeItem(at: folder)
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastBackupKey)
                    DispatchQueue.main.async {
                        self.lastBackupFailed = false
                        completion(zipURL)
                    }
                } catch {
                    try? fm.removeItem(at: folder)
                    DispatchQueue.main.async {
                        self.lastBackupFailed = true
                        completion(nil)
                    }
                }
            }
        }
    }

    /// 사용자가 고른 백업 파일(JSON 또는 zip)을 병합 복원한다. 기존 기록은 그대로 두고(겹치는
    /// 시작 시각이면 기존 걸 유지) 없는 기록만 Core Data에 추가한다 — 덮어쓰기·삭제가 없으므로
    /// 이 복원으로 현재 기기나 다른 기기의 최신 데이터가 사라지는 일은 없다.
    /// progress: 파일명·건수·저장 진행을 메인 큐로 보고한다.
    func restoreBackup(from url: URL,
                       existing: [RideRecord],
                       progress: @escaping (String) -> Void,
                       completion: @escaping (Int) -> Void) {
        let fileName = url.lastPathComponent
        container.performBackgroundTask { [weak self] ctx in
            guard let self else { DispatchQueue.main.async { completion(0) }; return }
            DispatchQueue.main.async { progress("백업 읽는 중: \(fileName)") }

            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            var extractedDir: URL?
            defer {
                if let extractedDir { try? FileManager.default.removeItem(at: extractedDir) }
            }

            let incoming: [RideRecord]
            if url.pathExtension.lowercased() == "zip" {
                DispatchQueue.main.async { progress("zip 압축 해제 중: \(fileName)") }
                do {
                    extractedDir = try BackupZip.extract(url)
                } catch {
                    DispatchQueue.main.async { completion(0) }
                    return
                }
                DispatchQueue.main.async { progress("백업 분석 중: \(fileName)") }
                guard let records = BackupZip.loadRecords(from: extractedDir!), !records.isEmpty else {
                    DispatchQueue.main.async { completion(0) }
                    return
                }
                incoming = records
            } else {
                guard let data = try? Data(contentsOf: url) else {
                    DispatchQueue.main.async { completion(0) }
                    return
                }
                DispatchQueue.main.async { progress("백업 분석 중: \(fileName)") }
                if let b = try? JSONDecoder().decode(Backup.self, from: data), !b.records.isEmpty {
                    incoming = b.records
                } else if let arr = try? JSONDecoder().decode([RideRecord].self, from: data), !arr.isEmpty {
                    incoming = arr
                } else {
                    DispatchQueue.main.async { completion(0) }
                    return
                }
            }

            let merged = RideRecordMerge.merge(existing: existing, incoming: incoming, incomingWins: false)
            let total = merged.count
            DispatchQueue.main.async {
                progress("복원 중: \(fileName) · 0/\(total)")
            }

            for (index, record) in merged.enumerated() {
                Self.upsert(record, in: ctx)
                let done = index + 1
                if done == total || done % 25 == 0 {
                    DispatchQueue.main.async {
                        progress("복원 중: \(fileName) · \(done)/\(total)")
                    }
                }
            }
            do { try ctx.save() } catch { print("restoreBackup 저장 실패: \(error)") }

            DispatchQueue.main.async {
                progress("저장 중: \(fileName)")
                self.refreshRecords()
                completion(total)
            }
        }
    }
}

/// iCloud Documents 컨테이너 접근(GPX 내보내기 폴더 위치용). 미로그인·권한 없으면 nil → 로컬 폴백.
/// Core Data/CloudKit 동기화와는 별개로, 사용자가 직접 보는 GPX 파일을 iCloud Drive에
/// 두기 위한 것이라 그대로 유지한다.
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
