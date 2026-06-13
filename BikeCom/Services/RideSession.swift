import Foundation
import Combine
import CoreLocation
import UIKit

/// 라이딩 상태 머신.
enum RideState {
    case idle       // 시작 전
    case running    // 라이딩 중
    case paused     // 일시정지
}

/// 현재 속도 출처. 워치(페어링된 CSC 센서) > GPS 폴백.
enum SpeedSource {
    case watch
    case gps
}

/// More 탭 데이터 출처 통계 (Cyclemeter 시드 = 기본, Health = 비중복 보충).
struct DataStats {
    var cyclemeterBase = 0        // 기본 Cyclemeter 시드(트랙 포함) 기록 수
    var healthTotal = 0           // Apple Health 사이클링 워크아웃 총 수
    var healthOverlap = 0         // 기본과 겹쳐 제외된 Health 워크아웃 수
    var healthNonOverlap = 0      // 겹치지 않는 Health 워크아웃 수
    var healthExcludedFilter = 0  // 겹치지 않음 중 거리 5km 이하·속도 0 으로 제외된 수
    var healthSupplemented = 0    // 최종 보충된 Health 기록 수(겹치지 않음 − 제외)

    var healthMonthKm = 0.0, healthYearKm = 0.0, healthTotalKm = 0.0   // Health(보충분)만
    var cycMonthKm = 0.0, cycYearKm = 0.0, cycTotalKm = 0.0            // Cyclemeter(CM)만
    var bothMonthKm = 0.0, bothYearKm = 0.0, bothTotalKm = 0.0         // 합계(Health+CM)

    var firstHealthDate: Date?, firstHealthPlace = ""
    var firstCycDate: Date?, firstCycPlace = ""
}

/// 대시보드의 모든 지표를 모으는 메인 뷰모델.
/// 워치 센서 + GPS 를 결합해 거리·속도·심박·케이던스를 계산하고,
/// 종료 시 RideStore 에 기록을 저장한다.
final class RideSession: ObservableObject {
    // 하위 서비스
    let location = LocationManager()
    let store = RideStore()
    let watch = WatchSensorManager()   // 애플워치 심박·속도·케이던스
    let health = HealthStore()          // Apple Health 누적 거리 + 폰 단독 워크아웃 저장
    let calendarLogger = CalendarLogger()   // Done 시 캘린더에 운동 요약 기록
    let healthImporter = HealthWorkoutImporter()   // 건강의 사이클링 워크아웃 가져오기

    /// 자전거 종류 프리셋(풀다운). 그 외에는 직접 입력.
    static let bikePresets = ["Yeti", "Wilier", "SantaCruz"]

    // 표시 단위
    @Published var unit: DistanceUnit = .kilometers

    /// 등반 고도(누적 상승 고도, m) — GPS 고도의 양(+) 변화량 합.
    /// 등반 고도(누적 상승) — 라이브 갱신값이라 @Published 가 아니다(틱 재렌더 방지).
    private(set) var elevationGainMeters: Double = 0

    /// GPX 가져오기 진행/결과 표시.
    @Published var importStatus: String?

    // MARK: 기준 코스(라이브 지도 오버레이 — 주행 중 따라가기)
    /// 현재 라이브 지도에 겹쳐 보여줄 기준 코스(없으면 nil).
    @Published private(set) var followCourseName: String?
    /// 기준 코스의 GPS 경로(라이브 지도 오버레이용).
    @Published private(set) var followCourseTrack: [CLLocationCoordinate2D] = []
    private var followCourseID: UUID? {
        didSet { UserDefaults.standard.set(followCourseID?.uuidString, forKey: "bike.followCourseID") }
    }

    /// 기준 코스를 선택해 라이브 지도에 오버레이한다(트랙은 디스크에서 지연 로드).
    func setFollowCourse(_ record: RideRecord) {
        followCourseID = record.id
        followCourseName = (record.mapName?.isEmpty == false) ? record.mapName : record.name
        store.loadTrack(for: record) { [weak self] coords in
            self?.followCourseTrack = coords.map { $0.clCoordinate }
        }
    }

    /// 기준 코스 해제.
    func clearFollowCourse() {
        followCourseID = nil
        followCourseName = nil
        followCourseTrack = []
    }

    /// 앱 재시작 후 마지막 기준 코스를 복원한다(레코드 로드 이후 호출).
    func restoreFollowCourseIfNeeded() {
        guard followCourseID == nil, followCourseTrack.isEmpty,
              let s = UserDefaults.standard.string(forKey: "bike.followCourseID"),
              let id = UUID(uuidString: s),
              let rec = store.records.first(where: { $0.id == id }) else { return }
        setFollowCourse(rec)
    }

    /// 데이터 출처 통계(More 탭). 백그라운드에서 계산해 발행.
    @Published var dataStats: DataStats?

    /// 10분 미만 라이딩: 저장/삭제 결정 대기 중인 기록.
    @Published var pendingShortRide: RideRecord?

    /// GPX/CSV 가져오기 후 "주행 데이터 / 지도 코스 자료" 선택 대기.
    struct PendingImport: Identifiable {
        let id = UUID()
        var records: [RideRecord]
        var scanned: Int
    }
    @Published var pendingImport: PendingImport?
    /// 주행 종료 후 저장 진행(목록·건강·캘린더·파일).
    @Published var saveProgress: RideSaveProgress?

    struct RideSaveProgress: Identifiable {
        let id = UUID()
        let rideName: String
        var steps: [Step]
        var isComplete = false

        struct Step: Identifiable {
            let id: String
            let title: String
            var status: Status = .pending

            enum Status {
                case pending, running, success, failed
            }
        }

        static func fresh(rideName: String) -> RideSaveProgress {
            RideSaveProgress(rideName: rideName, steps: [
                Step(id: "list", title: "라이딩 기록 저장"),
                Step(id: "health", title: "Health 앱 저장"),
                Step(id: "calendar", title: "캘린더 저장"),
                Step(id: "file", title: "GPX 파일 저장"),
            ])
        }

        mutating func setStep(_ stepID: String, status: Step.Status) {
            guard let i = steps.firstIndex(where: { $0.id == stepID }) else { return }
            steps[i].status = status
        }

        var failedCount: Int { steps.filter { $0.status == .failed }.count }
    }

    /// Apple 건강의 사이클링 워크아웃을 **겹치지 않는 것만 보충**한다(시드 트랙 데이터가 기본).
    func importFromHealth() {
        importStatus = "Health에서 가져오는 중…"
        // 기존 기록(시드 Cyclemeter 등)과 겹치는 워크아웃은 경로 조회 전에 미리 제외(속도 핵심).
        let existing = store.records
        healthImporter.importCyclingWorkouts(skipIfDuplicate: { r in
            existing.contains(where: { RideRecordMerge.isDuplicate(r, of: $0) })
        }, progress: { [weak self] done, total in
            self?.importStatus = "Health에서 가져오는 중… \(done)/\(total)"
        }, completion: { [weak self] records in
            guard let self else { return }
            // 주행시간 0 이거나 거리 5km 이하인 건강 기록은 제외한다.
            let kept = records.filter { $0.duration > 0 && $0.distanceMeters > 5000 }
            self.store.addMany(kept)
            let dropped = records.count - kept.count
            self.importStatus = dropped > 0
                ? "Health 보충 완료: \(kept.count)개 추가 (시간 0·5km 이하 \(dropped)개 제외)"
                : "Health 보충 완료: 겹치지 않는 \(kept.count)개 추가"
            self.refreshDataStats()
        })
    }

    /// Routes 통합 정리 — Cyclemeter 시드(트랙 포함)+앱·GPX 를 기본으로 두고
    /// 겹치지 않는 Apple 건강 기록으로 보충, 5km 이하 일괄 삭제.
    func consolidateRoutes(minKeepKm: Double = 5) {
        importStatus = "기록 통합 정리 중…"
        // 지도 코스 자료는 통합 정리 대상에서 제외하고 항상 보존한다.
        let courses = store.records.filter { $0.isCourseOnly }
        // 기본: 앱 직접 기록 + GPX + Cyclemeter 시드(트랙 포함). (레거시 nil = 앱으로 간주)
        let base = store.records.filter {
            guard !$0.isCourseOnly else { return false }
            let s = $0.source ?? .app
            return s == .app || s == .gpx || s == .cyclemeter
        }
        healthImporter.importCyclingWorkouts(skipIfDuplicate: { r in
            base.contains(where: { RideRecordMerge.isDuplicate(r, of: $0) })
        }, progress: { [weak self] done, total in
            self?.importStatus = "기록 통합 정리 중… \(done)/\(total)"
        }, completion: { [weak self] healthRides in
            guard let self else { return }
            DispatchQueue.main.async {
                var result = base
                // 겹치지 않는 건강 기록 보충. 가져오기와 동일하게 시간 0·5km 이하는 제외.
                for r in healthRides
                where r.duration > 0 && r.distanceMeters > minKeepKm * 1000
                    && !result.contains(where: { RideRecordMerge.isDuplicate(r, of: $0) }) {
                    result.append(r)
                }
                let before = result.count
                result = result.filter { $0.distanceMeters > minKeepKm * 1000 }
                let removed = before - result.count
                result.sort { $0.startedAt > $1.startedAt }
                self.store.replaceAll(courses + result)   // 코스 자료는 맨 앞에 보존
                self.health.refreshTotals()
                self.importStatus = "정리 완료: \(result.count)개 기록 · 5km 이하 \(removed)개 삭제 (Health 후보 \(healthRides.count))"
                self.refreshDataStats()
            }
        })
    }

    /// More 탭 데이터 출처 통계를 백그라운드에서 계산해 발행한다.
    func refreshDataStats() {
        let records = store.records.filter { !$0.isCourseOnly }   // 코스 자료는 통계 제외
        let healthWorkouts = health.rideWorkouts   // Apple Health 사이클링 워크아웃(시작·시간·거리)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var st = DataStats()
            let cal = Calendar.current
            let now = Date()
            func inMonth(_ d: Date) -> Bool { cal.isDate(d, equalTo: now, toGranularity: .month) }
            func inYear(_ d: Date) -> Bool { cal.isDate(d, equalTo: now, toGranularity: .year) }
            func km(_ rs: [RideRecord], _ pred: (Date) -> Bool) -> Double {
                rs.filter { pred($0.startedAt) }.reduce(0) { $0 + $1.distanceMeters } / 1000
            }

            let health = records.filter { $0.source == .health }
            let cyc = records.filter { $0.source == .cyclemeter }
            st.cyclemeterBase = cyc.count

            // 기본(앱·GPX·Cyclemeter)과 Health 워크아웃의 겹침/제외/보충을 직접 계산.
            let base = records.filter {
                let s = $0.source ?? .app
                return s == .app || s == .gpx || s == .cyclemeter
            }
            func overlapsBase(_ w: HealthStore.HealthRide) -> Bool {
                base.contains { abs($0.startedAt.timeIntervalSince(w.start)) <= 180
                    && abs($0.duration - w.duration) <= 120 }
            }
            let nonOverlap = healthWorkouts.filter { !overlapsBase($0) }
            // 겹치지 않음 중 거리 5km 이하 또는 속도 0(주행시간 0)으로 제외.
            let excluded = nonOverlap.filter { $0.duration <= 0 || $0.distanceMeters <= 5000 }
            st.healthTotal = healthWorkouts.count
            st.healthNonOverlap = nonOverlap.count
            st.healthOverlap = healthWorkouts.count - nonOverlap.count
            st.healthExcludedFilter = excluded.count
            st.healthSupplemented = nonOverlap.count - excluded.count

            st.healthMonthKm = km(health, inMonth); st.healthYearKm = km(health, inYear); st.healthTotalKm = km(health) { _ in true }
            st.cycMonthKm = km(cyc, inMonth); st.cycYearKm = km(cyc, inYear); st.cycTotalKm = km(cyc) { _ in true }
            let both = health + cyc
            st.bothMonthKm = km(both, inMonth); st.bothYearKm = km(both, inYear); st.bothTotalKm = km(both) { _ in true }

            if let fh = health.min(by: { $0.startedAt < $1.startedAt }) {
                st.firstHealthDate = fh.startedAt; st.firstHealthPlace = fh.location ?? fh.name
            }
            if let fc = cyc.min(by: { $0.startedAt < $1.startedAt }) {
                st.firstCycDate = fc.startedAt; st.firstCycPlace = fc.location ?? fc.name
            }

            DispatchQueue.main.async { self?.dataStats = st }
        }
    }

    /// 선택한 GPX·CSV 파일/폴더(들)에서 라이딩을 일괄 가져온다.
    func importRideFiles(from urls: [URL]) {
        importStatus = "가져오는 중…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var parsed: [RideRecord] = []
            var readErrors = 0
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                var files: [URL] = []
                if isDir.boolValue {
                    if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let f as URL in en {
                            let ext = f.pathExtension.lowercased()
                            if ext == "gpx" || ext == "csv" || ext == "txt" || ext.isEmpty { files.append(f) }
                        }
                    }
                } else {
                    files = [url]
                }
                for f in files {
                    guard let data = try? Data(contentsOf: f), !data.isEmpty else {
                        readErrors += 1
                        continue
                    }
                    let name = f.deletingPathExtension().lastPathComponent
                    switch detectImportKind(url: f, data: data) {
                    case .gpx:
                        if let rec = GPXImporter.parse(data: data, fallbackName: name) {
                            parsed.append(rec)
                        }
                    case .csv:
                        parsed.append(contentsOf: CSVImporter.parse(data: data, fallbackName: name))
                    case .unknown:
                        readErrors += 1
                    }
                }
            }
            DispatchQueue.main.async {
                guard !parsed.isEmpty else {
                    self.importStatus = readErrors > 0
                        ? "CSV/GPX 파일을 읽지 못했습니다. 파일 형식·인코딩을 확인하세요."
                        : "가져올 라이딩이 없습니다."
                    return
                }
                self.pendingImport = PendingImport(records: parsed, scanned: parsed.count)
                self.importStatus = nil
            }
        }
    }

    private enum ImportFileKind { case gpx, csv, unknown }

    /// 확장자가 없거나 .txt 인 Files 앱 CSV 도 내용으로 판별한다.
    private func detectImportKind(url: URL, data: Data) -> ImportFileKind {
        switch url.pathExtension.lowercased() {
        case "gpx": return .gpx
        case "csv": return .csv
        case "txt": return CSVImporter.canParse(data) ? .csv : .unknown
        default: break
        }
        if let head = String(data: data.prefix(512), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           head.hasPrefix("<?xml") || head.hasPrefix("<gpx") {
            return .gpx
        }
        if CSVImporter.canParse(data) { return .csv }
        return .unknown
    }

    /// 가져오기 종류 선택 완료 처리.
    /// asCourse=true: 지도 코스 자료(통계 제외, 목록 맨 위, 중복 허용).
    /// asCourse=false: 주행 데이터(시각 기준 중복 제외 후 추가).
    func finishPendingImport(asCourse: Bool) {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        if asCourse {
            let courses = pending.records.map { rec -> RideRecord in
                var r = rec
                r.isCourseOnly = true
                r.includeInMap = true
                if r.mapName?.isEmpty != false { r.mapName = r.name }
                return r
            }
            store.addMany(courses)
            importStatus = "지도 코스 자료 \(courses.count)개 추가 (통계 제외)"
        } else {
            let existing = Set(store.records.filter { !$0.isCourseOnly }
                .map { $0.startedAt.timeIntervalSince1970 })
            let fresh = pending.records.filter { !existing.contains($0.startedAt.timeIntervalSince1970) }
            store.addMany(fresh)
            let skipped = pending.records.count - fresh.count
            if fresh.isEmpty {
                importStatus = "가져온 \(pending.scanned)개가 모두 기존 기록과 중복입니다."
            } else if skipped > 0 {
                importStatus = "가져오기 완료: \(fresh.count)개 추가 · 중복 \(skipped)개 제외"
            } else {
                importStatus = "가져오기 완료: \(fresh.count)개 추가"
            }
        }
        refreshDataStats()
    }

    func cancelPendingImport() {
        pendingImport = nil
        importStatus = "가져오기 취소됨"
    }

    /// 주행 기록을 지도 코스로 복제한다(원본은 통계 유지, 복사본은 코스 전용·맨 위).
    func addCourseCopy(of record: RideRecord, name: String? = nil) {
        store.loadTrack(for: record) { [weak self] coords in
            guard let self else { return }
            let trimmed = (name ?? record.mapName ?? record.name).trimmingCharacters(in: .whitespacesAndNewlines)
            let courseName = trimmed.isEmpty ? record.name : trimmed
            let copy = RideRecord(
                name: record.name, bikeName: record.bikeName, source: record.source,
                location: record.location, startedAt: record.startedAt, duration: record.duration,
                totalElapsed: record.totalElapsed, distanceMeters: record.distanceMeters,
                averageSpeedMps: record.averageSpeedMps, maxSpeedMps: record.maxSpeedMps,
                maxHeartRate: record.maxHeartRate, avgHeartRate: record.avgHeartRate,
                maxCadence: record.maxCadence, track: coords,
                includeInMap: true, mapName: courseName, isCourseOnly: true)
            self.store.add(copy)
            self.importStatus = "지도 코스로 추가됨: \(courseName)"
        }
    }

    func importGPX(from urls: [URL]) { importRideFiles(from: urls) }

    // 라벨(스크린샷의 "1.출근길" / "6.Yeti" 자리)
    @Published var routeName: String = UserDefaults.standard.string(forKey: "bike.routeName") ?? "1.라이딩"
    @Published var bikeName: String = UserDefaults.standard.string(forKey: "bike.bikeName") ?? "내 자전거"

    /// 속도 센서 휠 둘레(미터). 워치 설정·참고용(실제 CSC 는 워치 OS 가 처리).
    @Published var wheelCircumferenceMeters: Double = (UserDefaults.standard.object(forKey: "bike.wheelCircumference") as? Double) ?? 2.105 {
        didSet { UserDefaults.standard.set(wheelCircumferenceMeters, forKey: "bike.wheelCircumference") }
    }

    /// 라이딩 설정을 저장한다(이름·자전거·휠 둘레·코스·자동 일시정지).
    func saveSettings() {
        UserDefaults.standard.set(routeName, forKey: "bike.routeName")
        UserDefaults.standard.set(bikeName, forKey: "bike.bikeName")
        UserDefaults.standard.set(wheelCircumferenceMeters, forKey: "bike.wheelCircumference")
        persistCourses()
    }

    /// 코스(경로) 목록 — 기본 출근/퇴근, 사용자가 만들어 추가·삭제. UserDefaults 영속.
    @Published var courses: [String] = UserDefaults.standard.stringArray(forKey: "bike.courses") ?? ["출근", "퇴근"]

    /// 코스를 추가(중복 제외)하고 현재 코스로 선택.
    func addCourse(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if !courses.contains(n) { courses.append(n); persistCourses() }
        routeName = n
    }

    func removeCourse(at offsets: IndexSet) {
        courses.remove(atOffsets: offsets)
        persistCourses()
    }

    private func persistCourses() {
        UserDefaults.standard.set(courses, forKey: "bike.courses")
    }

    // 상태
    @Published private(set) var state: RideState = .idle {
        didSet { updateScreenAwake() }
    }
    /// 라이브 주행 지표 — 0.5초 tick 으로 갱신되지만 @Published 가 아니어서 session 의
    /// objectWillChange 를 발행하지 않는다(Routes·More 등이 매 틱 재렌더되는 것 방지).
    /// 표시는 주행 화면(Dashboard·Map)이 TimelineView 로 주기 갱신해 읽는다.
    private(set) var clock: Date = Date()

    // 누적/계산 지표 (표시는 항상 단위 변환 후)
    private(set) var distanceMeters: Double = 0
    @Published private(set) var currentSpeedMps: Double = 0
    private(set) var rideSeconds: TimeInterval = 0    // 라이딩 시간(정지 제외)
    private(set) var totalSeconds: TimeInterval = 0   // 총 경과(시작~지금)
    @Published private(set) var maxSpeedMps: Double = 0
    private(set) var movingSeconds: TimeInterval = 0  // 실제 움직인 시간(평균속도용)

    // 심박/케이던스
    @Published private(set) var heartRate: Int?
    @Published private(set) var maxHeartRate: Int?
    @Published private(set) var cadence: Int?
    @Published private(set) var maxCadence: Int?

    private var heartRateSamples: [Int] = []
    private var cadenceSamples: [Int] = []
    private var hrSeries: [(time: Date, bpm: Int)] = []   // GPX 트랙 심박 매칭용(시각 포함)
    private var startedAt: Date?
    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    private let movingSpeedThresholdMps = 0.8  // 이 속도 이상이면 "움직이는 중"
    private var lastAltitude: Double?           // 등반 고도 계산용 기준 고도

    init() {
        // 시계 + 라이딩 타이머 (0.5초 간격)
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }

        // 속도: 워치(페어링된 CSC) → GPS 폴백.
        watch.$watchSpeedMps
            .compactMap { $0 }
            .sink { [weak self] v in self?.ingestSpeed(v, fromSource: .watch) }
            .store(in: &cancellables)

        location.$gpsSpeedMetersPerSecond
            .sink { [weak self] v in self?.ingestSpeed(v, fromSource: .gps) }
            .store(in: &cancellables)

        // 케이던스·심박: 애플워치만.
        watch.$watchCadenceRPM
            .sink { [weak self] rpm in self?.ingestCadence(rpm) }
            .store(in: &cancellables)

        watch.$heartRateBPM
            .sink { [weak self] bpm in self?.ingestHeartRate(bpm) }
            .store(in: &cancellables)

        // 중첩 ObservableObject 변경을 상위로 전달해 관련 뷰가 갱신되게 한다.
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        watch.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        health.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        location.requestAuthorization()
        watch.requestAuthorization()

        // 워치 CONNECT/DISCONNECT 는 폰에 '요청'만 보낸다. 폰 ride 상태가 단일 기준이며,
        // 폰이 ride 를 시작/종료하면 그 레벨을 워치가 따라가 세션을 켜고/끈다(desync 방지).
        watch.onWatchRequest = { [weak self] start in
            guard let self else { return }
            if start {
                if self.state != .running { self.start() }   // idle→시작, paused→재개
            } else {
                if self.state != .idle { self.finish() }
            }
        }
        watch.isRideActive = { [weak self] in (self?.state ?? .idle) != .idle }

        health.start()   // Apple Health 누적 거리 관찰 시작
        importBaselineHistoryIfNeeded()
    }

    // V4: 시드 트랙을 라이딩당 최대 150포인트로 다운샘플(메모리 대폭 절감). 기존 설치는
    // 키가 바뀌면서 다음 실행에 조밀한 Cyclemeter 시드를 가벼운 시드로 교체 저장한다.
    private static let baselineImportedKey = "bike.cyclemeterSeedV4"

    /// 앱 번들 Cyclemeter 시드(트랙 포함 JSON)를 1회 기본 기록으로 주입한다.
    /// 기존 Cyclemeter 기록은 제거 후 시드로 교체하고, 앱·건강·GPX 기록은 유지한다.
    private func importBaselineHistoryIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.baselineImportedKey) else { return }
        let existing = store.records   // 메인 스레드(init)에서 스냅샷
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            // 디코드·병합 등 무거운 작업은 백그라운드에서 처리하고, 큰 버퍼는 즉시 해제.
            autoreleasepool {
                let seed = SeedRides.load()
                guard !seed.isEmpty else { return }
                // 기존 Cyclemeter 기록 제거 후 시드(트랙 포함) 주입. 앱·건강·GPX 기록은 유지.
                let kept = existing.filter { $0.source != .cyclemeter }
                // 첫 설치(기존 기록 없음)면 병합 복제 없이 시드를 그대로 사용 → 피크 메모리 절감.
                let merged = kept.isEmpty
                    ? seed
                    : RideRecordMerge.merge(existing: kept, incoming: seed, incomingWins: false)
                DispatchQueue.main.async {
                    self.store.replaceAll(merged)
                    UserDefaults.standard.set(true, forKey: Self.baselineImportedKey)
                    self.refreshDataStats()
                }
            }
        }
    }

    deinit {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// 앱이 켜져 있는 동안에는 라이딩 여부와 관계없이 항상 화면 자동 잠금을 끈다.
    func refreshScreenAwake() {
        updateScreenAwake()
    }

    private func updateScreenAwake() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    // MARK: - 라이딩 제어 (Start / Pause / Done)

    func start() {
        switch state {
        case .idle:
            resetRide()
            startedAt = Date()
            location.startRecording()
            watch.startWatchWorkout()   // 워치 워크아웃(심박·속도·케이던스) 시작
            state = .running
        case .paused:
            location.resumeRecording()
            state = .running
        case .running:
            pause()
        }
    }

    func pause() {
        guard state == .running else { return }
        location.pauseRecording()
        state = .paused
    }

    /// "Done" — 라이딩 종료 후 기록 저장, idle 로 복귀.
    func finish() {
        guard state != .idle, let started = startedAt else {
            state = .idle
            return
        }
        location.stopRecording()
        watch.stopWatchWorkout()   // 워치 워크아웃 세션 종료(저장은 폰이 담당)

        let record = makeRecord(startedAt: started)
        state = .idle

        if record.duration >= 600 {     // 10분 이상 → 자동 저장
            performSave(record)
        } else {                         // 10분 미만 → 저장/삭제 선택지
            pendingShortRide = record
        }
    }

    private func makeRecord(startedAt started: Date) -> RideRecord {
        let avgSpeed = rideSeconds > 1 ? distanceMeters / rideSeconds : 0   // 라이딩 시간 기준
        return RideRecord(
            name: routeName,
            bikeName: bikeName,
            source: .app,
            startedAt: started,
            duration: rideSeconds,
            totalElapsed: totalSeconds,
            distanceMeters: distanceMeters,
            averageSpeedMps: avgSpeed,
            maxSpeedMps: maxSpeedMps,
            maxHeartRate: maxHeartRate,
            avgHeartRate: avgHeartRate,
            maxCadence: maxCadence,
            track: buildTrackPoints())
    }

    /// 10분 미만 라이딩: 저장 선택.
    func savePendingRide() {
        guard let record = pendingShortRide else { return }
        pendingShortRide = nil
        performSave(record)
    }

    /// 10분 미만 라이딩: 삭제(건강·캘린더·파일 저장 안 함).
    func discardPendingRide() {
        pendingShortRide = nil
    }

    /// 건강·캘린더·파일 3가지 저장을 수행하고, 단계별 진행을 발행한다.
    private func performSave(_ record: RideRecord) {
        saveProgress = .fresh(rideName: record.name)
        store.add(record)
        setSaveStep("list", .success)
        setSaveStep("health", .running)
        setSaveStep("calendar", .running)
        setSaveStep("file", .running)

        let group = DispatchGroup()
        group.enter()
        health.saveRide(record) { [weak self] ok in
            DispatchQueue.main.async { self?.setSaveStep("health", ok ? .success : .failed) }
            group.leave()
        }
        group.enter()
        calendarLogger.logRide(record, bikeName: bikeName) { [weak self] ok in
            DispatchQueue.main.async { self?.setSaveStep("calendar", ok ? .success : .failed) }
            group.leave()
        }
        group.enter()
        GPXExporter.export(record) { [weak self] url in
            DispatchQueue.main.async { self?.setSaveStep("file", url != nil ? .success : .failed) }
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.health.refreshTotals()
            guard var p = self.saveProgress else { return }
            p.isComplete = true
            self.saveProgress = p
        }
    }

    private func setSaveStep(_ stepID: String, _ status: RideSaveProgress.Step.Status) {
        guard var p = saveProgress else { return }
        p.setStep(stepID, status: status)
        saveProgress = p
    }

    func dismissSaveProgress() {
        saveProgress = nil
    }

    // MARK: - 표시용 계산값 (단위 변환)

    var displayDistance: Double { unit.distance(fromMeters: distanceMeters) }
    var displaySpeed: Double { unit.speed(fromMetersPerSecond: currentSpeedMps) }
    var displayMaxSpeed: Double { unit.speed(fromMetersPerSecond: maxSpeedMps) }
    var displayAverageSpeed: Double {
        guard rideSeconds > 1 else { return 0 }
        return unit.speed(fromMetersPerSecond: distanceMeters / rideSeconds)
    }
    // 누적 거리: **Routes(라이딩 기록) 주행거리 총합** 기준(통합 정리로 중복 제거된 목록).
    // 진행 중 라이딩은 현재 거리(distanceMeters)를 더해 실시간 표시.
    var thisMonthDistance: Double {
        unit.distance(fromMeters: routeBased(store.thisMonthMeters))
    }
    var thisYearDistance: Double {
        unit.distance(fromMeters: routeBased(store.thisYearMeters))
    }
    var totalDistance: Double {
        unit.distance(fromMeters: routeBased(store.totalMeters))
    }

    private func routeBased(_ storeMeters: Double) -> Double {
        storeMeters + (state == .idle ? 0 : distanceMeters)
    }

    /// 총 라이딩 시간(초) — Cyclemeter(로컬 JSON 기록) + Apple 건강 워크아웃을
    /// 시작 시각·시간 기준으로 중복 제거해 합산한다. 진행 중 라이딩은 실시간으로 더한다.
    var totalRideTime: TimeInterval {
        let merged = RideTimeAggregator.totalRideTime(records: store.records.filter { !$0.isCourseOnly },
                                                      healthRides: health.rideWorkouts)
        return merged + (state == .idle ? 0 : rideSeconds)
    }

    /// 라이딩 중 평균 심박수(bpm). 표시용 누적 평균.
    var avgHeartRate: Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        return Int((Double(heartRateSamples.reduce(0, +)) / Double(heartRateSamples.count)).rounded())
    }

    /// 라이딩 중 평균 케이던스(rpm). 표시용 누적 평균.
    var avgCadence: Int? {
        guard !cadenceSamples.isEmpty else { return nil }
        return Int((Double(cadenceSamples.reduce(0, +)) / Double(cadenceSamples.count)).rounded())
    }

    /// 최근 산소포화도 — 워치 'SpO2 측정' 버튼 값과 HealthKit 최근값 중 더 최신을 선택.
    /// (워치 버튼은 WCSession 으로 즉시 도착, HealthKit 은 동기화가 늦을 수 있음.)
    private var bestSpO2: (pct: Double, date: Date)? {
        let h: (Double, Date)? = health.latestSpO2.flatMap { v in health.latestSpO2Date.map { (v, $0) } }
        let w: (Double, Date)? = watch.spo2.flatMap { v in watch.spo2Date.map { (v, $0) } }
        switch (h, w) {
        case let (.some(a), .some(b)): return b.1 >= a.1 ? b : a
        case let (.some(a), nil): return a
        case let (nil, .some(b)): return b
        default: return nil
        }
    }

    /// SpO2 — 최근 / 24시간 최저 / 24시간 최고 (%).
    var spo2Percent: Int? { bestSpO2.map { Int(($0.pct * 100).rounded()) } }
    var spo2MinPercent: Int? { health.minSpO2.map { Int(($0 * 100).rounded()) } }
    var spo2MaxPercent: Int? { health.maxSpO2.map { Int(($0 * 100).rounded()) } }

    /// 각 SpO2 값의 측정 시각(작은 글씨용). 오늘=HH:mm, 어제='어제 HH:mm', 그 외=M/d HH:mm.
    var spo2LatestTimeText: String? { Self.clockText(bestSpO2?.date) }
    var spo2MinTimeText: String? { Self.clockText(health.minSpO2Date) }
    var spo2MaxTimeText: String? { Self.clockText(health.maxSpO2Date) }

    private static func clockText(_ d: Date?) -> String? {
        guard let d else { return nil }
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) { f.dateFormat = "HH:mm" }
        else if cal.isDateInYesterday(d) { f.dateFormat = "'어제' HH:mm" }
        else { f.dateFormat = "M/d HH:mm" }
        return f.string(from: d)
    }

    // MARK: - 내부

    private func tick() {
        // 앱이 켜져 있는 동안 매 틱 화면 자동 잠금을 끈다(시스템이 초기화해도 항상 켜짐 유지).
        if !UIApplication.shared.isIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // 라이딩 중이 아닐 땐 어떤 @Published 값도 갱신하지 않는다.
        // (idle 상태에서 매 0.5초 session 이 바뀌면 전체 화면이 재렌더되어 탭이 씹히고 깜빡인다.)
        guard state == .running, let started = startedAt else { return }
        clock = Date()
        totalSeconds = Date().timeIntervalSince(started)
        rideSeconds += 0.5
        if currentSpeedMps >= movingSpeedThresholdMps {
            movingSeconds += 0.5
        }
        // 거리는 항상 폰 GPS 기준.
        distanceMeters = location.distanceMeters
        accumulateElevationGain()
    }

    /// GPS 고도의 양(+) 변화량을 누적해 등반 고도를 계산(0.5m 히스테리시스로 노이즈 제거).
    private func accumulateElevationGain() {
        guard let loc = location.lastLocation, loc.verticalAccuracy >= 0 else { return }
        let alt = loc.altitude
        guard let last = lastAltitude else { lastAltitude = alt; return }
        let delta = alt - last
        if delta > 0.5 {
            elevationGainMeters += delta
            lastAltitude = alt
        } else if delta < -0.5 {
            lastAltitude = alt
        }
    }

    private let speedFreshness: TimeInterval = 5   // 이 시간 내 값이면 "최근"으로 간주
    private var lastSpeedAt: [SpeedSource: Date] = [:]
    private func isFresh(_ source: SpeedSource, _ now: Date) -> Bool {
        guard let t = lastSpeedAt[source] else { return false }
        return now.timeIntervalSince(t) <= speedFreshness
    }

    /// 속도 표시: 워치 > GPS. 워치 값이 최근이면 GPS 는 무시.
    private func ingestSpeed(_ mps: Double, fromSource source: SpeedSource) {
        let now = Date()
        lastSpeedAt[source] = now
        if source == .gps, isFresh(.watch, now) { return }
        currentSpeedMps = mps
        if mps > maxSpeedMps { maxSpeedMps = mps }
    }

    /// 케이던스: 워치에서만 수신.
    private func ingestCadence(_ rpm: Int?) {
        cadence = rpm
        if let rpm, rpm > 0 {
            maxCadence = max(maxCadence ?? 0, rpm)
            if state == .running { cadenceSamples.append(rpm) }
        }
    }

    private func ingestHeartRate(_ bpm: Int?) {
        heartRate = bpm
        if let bpm, bpm > 0 {
            maxHeartRate = max(maxHeartRate ?? 0, bpm)
            if state == .running {
                heartRateSamples.append(bpm)
                hrSeries.append((Date(), bpm))
            }
        }
    }

    /// 트랙 지점별 좌표 + 고도·시각·속도(GPS) + 심박(시계열 매칭)을 만든다.
    private func buildTrackPoints() -> [RideRecord.Coordinate] {
        location.locations.map { loc in
            RideRecord.Coordinate(
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                ele: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
                time: loc.timestamp,
                speed: loc.speed >= 0 ? loc.speed : nil,
                hr: hrAt(loc.timestamp))
        }
    }

    /// 해당 시각과 가장 가까운(±15초) 심박 샘플.
    private func hrAt(_ time: Date) -> Int? {
        guard !hrSeries.isEmpty else { return nil }
        var best: (dt: TimeInterval, bpm: Int)?
        for s in hrSeries {
            let dt = abs(s.time.timeIntervalSince(time))
            if best == nil || dt < best!.dt { best = (dt, s.bpm) }
        }
        if let best, best.dt <= 15 { return best.bpm }
        return nil
    }

    private func resetRide() {
        distanceMeters = 0
        currentSpeedMps = 0
        rideSeconds = 0
        totalSeconds = 0
        maxSpeedMps = 0
        movingSeconds = 0
        maxHeartRate = nil
        maxCadence = nil
        heartRateSamples = []
        cadenceSamples = []
        hrSeries = []
        elevationGainMeters = 0
        lastAltitude = nil
    }
}

#if DEBUG
extension RideSession {
    /// SwiftUI 프리뷰용 더미 세션. 누적 통계/대시보드 값을 보기 위해 가짜 데이터를 채운다.
    static var preview: RideSession {
        let s = RideSession()
        s.routeName = "1.출근길"
        s.bikeName = "Yeti SB130"
        // 누적 통계용 더미 기록(Health 미인증 → store 폴백으로 표시됨).
        let now = Date()
        s.store.add(RideRecord(name: "어제 라이딩", startedAt: now.addingTimeInterval(-86_400),
                               duration: 3_600, totalElapsed: 3_900, distanceMeters: 24_500,
                               averageSpeedMps: 6.8, maxSpeedMps: 12.4, maxHeartRate: 168,
                               avgHeartRate: 142, maxCadence: 96, track: []))
        s.store.add(RideRecord(name: "주말 장거리", startedAt: now.addingTimeInterval(-6 * 86_400),
                               duration: 7_200, totalElapsed: 7_500, distanceMeters: 58_300,
                               averageSpeedMps: 8.1, maxSpeedMps: 15.2, maxHeartRate: 175,
                               avgHeartRate: 150, maxCadence: 102, track: []))
        // 라이브 표시값.
        s.distanceMeters = 12_340
        s.currentSpeedMps = 7.5
        s.maxSpeedMps = 13.9
        s.rideSeconds = 1_830
        s.totalSeconds = 1_980
        s.movingSeconds = 1_780
        s.heartRate = 148
        s.maxHeartRate = 165
        s.heartRateSamples = [138, 142, 145, 148, 150, 147]   // 평균 ≈ 145
        s.cadence = 88
        s.maxCadence = 97
        s.cadenceSamples = [80, 84, 86, 88, 90, 87]           // 평균 ≈ 86
        s.health.seedPreviewSpO2(latest: 98, latestAt: now.addingTimeInterval(-12 * 60),
                                 min: 95, minAt: now.addingTimeInterval(-7 * 3600),
                                 max: 99, maxAt: now.addingTimeInterval(-3 * 3600))
        return s
    }
}
#endif
