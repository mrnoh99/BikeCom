import SwiftUI
import MapKit
import UIKit
import Charts
import UniformTypeIdentifiers

/// 라이딩 목록 정렬 기준.
enum RideSort: String, CaseIterable, Identifiable {
    case newest = "최신순"
    case oldest = "오래된순"
    case distance = "거리순"
    case duration = "시간순"
    var id: String { rawValue }

    func sorted(_ records: [RideRecord]) -> [RideRecord] {
        switch self {
        case .newest:   return records.sorted { $0.startedAt > $1.startedAt }
        case .oldest:   return records.sorted { $0.startedAt < $1.startedAt }
        case .distance: return records.sorted { $0.distanceMeters > $1.distanceMeters }
        case .duration: return records.sorted { $0.duration > $1.duration }
        }
    }
}

private let routeDateFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy.MM.dd HH:mm"; return f
}()

/// 목록 행(이름·거리·시간·날짜).
struct RideRow: View {
    let record: RideRecord
    let unit: DistanceUnit
    private var hasGPS: Bool { record.track.count > 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.name).font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 0)
                // GPS 유무 표시
                Image(systemName: hasGPS ? "mappin.and.ellipse" : "mappin.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(hasGPS ? Theme.green : .secondary)
            }
            HStack(spacing: 14) {
                Label(String(format: "%.2f %@", unit.distance(fromMeters: record.distanceMeters), unit.distanceLabel),
                      systemImage: "ruler")
                Label(formatDuration(record.duration), systemImage: "clock")
            }
            .font(.caption).foregroundColor(.secondary)
            Text(routeDateFormatter.string(from: record.startedAt))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Routes 탭 — 저장된 라이딩 목록(정렬 변경 + 코스별 묶어보기) + 상세.
struct RoutesView: View {
    @EnvironmentObject var session: RideSession
    @State private var sort: RideSort = .newest
    @State private var grouped = false
    @State private var showImporter = false
    @State private var showConsolidateConfirm = false
    @State private var exportFile: ExportFile?
    @State private var exporting = false
    @AppStorage("route.bucketMeters") private var bucketMeters: Double = 250

    private var importTypes: [UTType] {
        [UTType(filenameExtension: "gpx") ?? .xml,
         UTType(filenameExtension: "csv") ?? .commaSeparatedText,
         .xml, .commaSeparatedText, .folder]
    }

    var body: some View {
        Group {
            if session.store.records.isEmpty {
                emptyState
            } else if grouped {
                groupedList
            } else {
                flatList
            }
        }
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { statusBanner }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { dataMenu }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("정렬", selection: $sort) {
                        ForEach(RideSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Divider()
                    Toggle("코스별 보기", isOn: $grouped)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { session.importRideFiles(from: urls) }
        }
        .confirmationDialog("기록 통합 정리", isPresented: $showConsolidateConfirm, titleVisibility: .visible) {
            Button("정리 실행 (5km 이하 삭제)", role: .destructive) { session.consolidateRoutes() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("Cyclemeter(트랙)·앱·GPX 기록을 기본으로 두고, 겹치지 않는 Apple 건강 기록을 보충합니다. 주행거리 5km 이하는 일괄 삭제합니다.")
        }
        .sheet(item: $exportFile) { f in
            ActivityView(items: [f.url])
        }
    }

    // 데이터 가져오기/정리 메뉴 (라이딩 기록 첫 페이지)
    private var dataMenu: some View {
        Menu {
            Button { session.importStatus = nil; showConsolidateConfirm = true } label: {
                Label("기록 통합 정리", systemImage: "arrow.triangle.merge")
            }
            Divider()
            Button { session.importStatus = nil; session.importFromHealth() } label: {
                Label("Apple 건강에서 가져오기", systemImage: "heart.text.square")
            }
            Button { session.importStatus = nil; showImporter = true } label: {
                Label("GPX / CSV 파일 가져오기", systemImage: "square.and.arrow.down")
            }
            Divider()
            Button { exportAll() } label: {
                Label(exporting ? "내보내는 중…" : "전체 데이터 내보내기 (GPX zip)",
                      systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(exporting || session.store.records.isEmpty)
        } label: {
            Image(systemName: "tray.and.arrow.down")
        }
    }

    // 전체 라이딩을 라이딩별 GPX + rides.json 으로 묶어 zip 내보내기(공유 시트).
    private func exportAll() {
        guard !exporting else { return }
        exporting = true
        session.importStatus = "전체 내보내는 중… (\(session.store.records.count)건)"
        GPXExporter.exportAllZip(session.store.records) { url, count in
            exporting = false
            if let url {
                session.importStatus = "내보내기 준비됨: GPX \(count)개 → 공유 시트에서 저장/전송"
                exportFile = ExportFile(url: url)
            } else {
                session.importStatus = "내보내기 실패"
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if let status = session.importStatus {
            Text(status)
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.vertical, 6)
                .background(.ultraThinMaterial)
        }
    }

    private var emptyState: some View {
        List {
            Text("아직 저장된 라이딩이 없습니다.\nStopwatch 에서 Start 후 Done 을 누르면 기록됩니다.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 평면 목록(정렬 적용)
    private var flatList: some View {
        let records = sort.sorted(session.store.records)
        return List {
            ForEach(records) { record in
                NavigationLink {
                    RideDetailView(record: record, unit: session.unit)
                } label: {
                    RideRow(record: record, unit: session.unit)
                }
            }
            .onDelete { idx in
                idx.map { records[$0] }.forEach { session.store.delete($0) }
            }
        }
    }

    // 코스별 묶음(시작/끝 GPS + 거리로 분류)
    private var groupedList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("코스 인식 반경")
                        Spacer()
                        Text("\(Int(bucketMeters)) m").foregroundColor(.secondary)
                    }
                    Slider(value: $bucketMeters, in: 100...1000, step: 50)
                }
            } footer: {
                Text("시작·끝 위치가 이 반경 안이고 거리가 비슷하면 같은 코스로 묶습니다.")
            }
            ForEach(RouteGrouping.groups(session.store.records, radiusMeters: bucketMeters)) { group in
                NavigationLink {
                    RouteGroupView(group: group, sort: sort)
                } label: {
                    groupRow(group)
                }
            }
        }
    }

    private func groupRow(_ g: RouteGroup) -> some View {
        HStack(spacing: 12) {
            RouteThumbnail(coords: (g.representative?.track ?? []).map { $0.clCoordinate })
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(g.title).font(.system(size: 16, weight: .semibold))
                    if let label = g.commuteLabel { commuteChip(label) }
                    Spacer()
                    Text("\(g.rides.count)회").font(.caption).foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    Label(String(format: "평균 %.1f km", g.averageMeters / 1000), systemImage: "ruler")
                    Label(String(format: "합계 %.0f km", g.totalMeters / 1000), systemImage: "sum")
                }
                .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 12) {
                    if g.bestTime > 0 {
                        Label("베스트 \(formatDuration(g.bestTime))", systemImage: "stopwatch")
                            .foregroundColor(Theme.gold)
                    }
                    if g.bestAvgSpeedMps > 0 {
                        Label(String(format: "최고평속 %.1f km/h", g.bestAvgSpeedMps * 3.6), systemImage: "speedometer")
                            .foregroundColor(Theme.blue)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private func commuteChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(label == "출근" ? Theme.gold : Theme.purple))
    }
}

/// 추세 그래프 지표.
enum TrendMetric: String, CaseIterable, Identifiable {
    case speed = "평균 속도"
    case time = "라이딩 시간"
    var id: String { rawValue }
}

/// 한 코스에 묶인 라이딩 목록 + 추세 그래프.
struct RouteGroupView: View {
    @EnvironmentObject var session: RideSession
    let group: RouteGroup
    let sort: RideSort
    @State private var metric: TrendMetric = .speed

    private var chrono: [RideRecord] { group.rides.sorted { $0.startedAt < $1.startedAt } }

    var body: some View {
        List {
            Section {
                Picker("지표", selection: $metric) {
                    ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                trendChart.frame(height: 170)
            } header: {
                Text("추세 (시간순)")
            }

            Section("요약") {
                summaryRow("라이딩 수", "\(group.rides.count)회")
                summaryRow("합계 거리", String(format: "%.0f km", group.totalMeters / 1000))
                summaryRow("평균 거리", String(format: "%.1f km", group.averageMeters / 1000))
                if group.bestTime > 0 {
                    summaryRow("베스트 타임", formatDuration(group.bestTime), Theme.gold)
                }
                if group.bestAvgSpeedMps > 0 {
                    summaryRow("최고 평속", String(format: "%.1f km/h", group.bestAvgSpeedMps * 3.6), Theme.blue)
                }
            }

            Section("라이딩") {
                ForEach(sort.sorted(group.rides)) { record in
                    NavigationLink {
                        RideDetailView(record: record, unit: session.unit)
                    } label: {
                        HStack {
                            RideRow(record: record, unit: session.unit)
                            if record.id == group.bestAvgSpeedRideID {
                                Image(systemName: "star.fill").foregroundColor(Theme.blue).font(.caption)
                            }
                        }
                    }
                }
                .onDelete { idx in
                    let arr = sort.sorted(group.rides)
                    idx.map { arr[$0] }.forEach { session.store.delete($0) }
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navTitle: String {
        if let label = group.commuteLabel, !group.title.contains(label) {
            return "\(group.title) · \(label)"
        }
        return group.title
    }

    @ViewBuilder private var trendChart: some View {
        Chart(chrono) { r in
            let y = metric == .speed ? r.averageSpeedMps * 3.6 : r.duration / 60
            LineMark(x: .value("날짜", r.startedAt), y: .value(metric.rawValue, y))
                .foregroundStyle(metric == .speed ? Theme.blue : Theme.gold)
            PointMark(x: .value("날짜", r.startedAt), y: .value(metric.rawValue, y))
                .foregroundStyle(metric == .speed ? Theme.blue : Theme.gold)
        }
        .chartYAxisLabel(metric == .speed ? "km/h" : "분")
    }

    private func summaryRow(_ label: String, _ value: String, _ color: Color = .primary) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundColor(color) }
    }
}

// MARK: - 코스 분류 (시작 GPS + 끝 GPS + 거리)

struct RouteGroup: Identifiable {
    let id: String
    var title: String
    var rides: [RideRecord]
    var totalMeters: Double { rides.reduce(0) { $0 + $1.distanceMeters } }
    var averageMeters: Double { rides.isEmpty ? 0 : totalMeters / Double(rides.count) }
    /// 베스트 타임(가장 빠른 라이딩 시간).
    var bestTime: TimeInterval { rides.map { $0.duration }.filter { $0 > 0 }.min() ?? 0 }
    /// 평균 속도 기준 베스트(가장 빠른 평속, m/s)와 그 라이딩.
    var bestAvgSpeedMps: Double { rides.map { $0.averageSpeedMps }.max() ?? 0 }
    var bestAvgSpeedRideID: RideRecord.ID? { rides.max { $0.averageSpeedMps < $1.averageSpeedMps }?.id }
    /// 썸네일용 대표 라이딩(트랙 점이 가장 많은 것).
    var representative: RideRecord? {
        rides.filter { !$0.track.isEmpty }.max { $0.track.count < $1.track.count }
    }
    /// 시간대 기반 자동 라벨(출근/퇴근). 강한 다수일 때만.
    var commuteLabel: String? {
        let hours = rides.compactMap { Calendar.current.dateComponents([.hour], from: $0.startedAt).hour }
        guard !hours.isEmpty else { return nil }
        let morning = hours.filter { (4...10).contains($0) }.count
        let evening = hours.filter { (16...22).contains($0) }.count
        if morning > evening, morning * 2 >= hours.count { return "출근" }
        if evening > morning, evening * 2 >= hours.count { return "퇴근" }
        return nil
    }
}

enum RouteGrouping {
    /// 시작 좌표·끝 좌표(반경 radiusMeters)·거리(1km 버킷)가 같으면 같은 코스로 본다.
    static func groups(_ records: [RideRecord], radiusMeters: Double = 250) -> [RouteGroup] {
        var buckets: [String: [RideRecord]] = [:]
        var noGPS: [RideRecord] = []
        for r in records {
            if let key = signature(r, radiusMeters: radiusMeters) {
                buckets[key, default: []].append(r)
            } else {
                noGPS.append(r)
            }
        }
        var result = buckets.map { key, rides -> RouteGroup in
            RouteGroup(id: key, title: title(for: rides), rides: rides)
        }
        // 자주 탄 코스 먼저.
        result.sort { $0.rides.count > $1.rides.count }
        if !noGPS.isEmpty {
            result.append(RouteGroup(id: "no-gps", title: "경로 없음", rides: noGPS))
        }
        return result
    }

    private static func signature(_ r: RideRecord, radiusMeters: Double) -> String? {
        guard let s = r.track.first, let e = r.track.last else { return nil }
        let dk = Int((r.distanceMeters / 1000).rounded())
        return "\(cell(s.lat, s.lon, radiusMeters))|\(cell(e.lat, e.lon, radiusMeters))|\(dk)km"
    }

    /// 좌표를 radius 크기의 격자 셀로 양자화.
    private static func cell(_ lat: Double, _ lon: Double, _ radius: Double) -> String {
        let mPerDegLat = 111_320.0
        let latStep = radius / mPerDegLat
        let lonStep = radius / max(1, mPerDegLat * cos(lat * .pi / 180))
        return "\(Int((lat / latStep).rounded())),\(Int((lon / lonStep).rounded()))"
    }

    /// 그룹 제목 = 가장 많이 쓰인 라이딩 이름.
    private static func title(for rides: [RideRecord]) -> String {
        var counts: [String: Int] = [:]
        for r in rides { counts[r.name, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? "코스"
    }
}

/// 라이딩 상세 — 지도 + 핵심 지표.
struct RideDetailView: View {
    @EnvironmentObject var session: RideSession
    @Environment(\.dismiss) private var dismiss
    let unit: DistanceUnit
    @State private var record: RideRecord
    @State private var gpxURL: URL?
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    init(record: RideRecord, unit: DistanceUnit) {
        _record = State(initialValue: record)
        self.unit = unit
    }

    private var coords: [CLLocationCoordinate2D] { record.track.map { $0.clCoordinate } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. 지도 — GPX 트랙(경로)이 있으면 코스를 그리고, 없으면 안내.
                if coords.count > 1 {
                    StaticRouteMap(track: coords)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    emptyTrackPlaceholder
                }

                // 코스명 · 자전거
                VStack(spacing: 4) {
                    Text(record.name).font(.system(size: 20, weight: .bold))
                    Text(record.bikeName?.isEmpty == false ? record.bikeName! : "자전거 미지정")
                        .font(.subheadline).foregroundColor(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    stat("거리", String(format: "%.2f %@", unit.distance(fromMeters: record.distanceMeters), unit.distanceLabel), Theme.gold)
                    stat("라이딩 시간", formatDuration(record.duration), Theme.gold)
                    stat("평균 속도", String(format: "%.1f %@", unit.speed(fromMetersPerSecond: record.averageSpeedMps), unit.speedLabel), Theme.value)
                    stat("최고 속도", String(format: "%.1f %@", unit.speed(fromMetersPerSecond: record.maxSpeedMps), unit.speedLabel), Theme.blue)
                    stat("최대 심박", record.maxHeartRate.map { "\($0) bpm" } ?? "–", Theme.red)
                    stat("평균 심박", record.avgHeartRate.map { "\($0) bpm" } ?? "–", Theme.red)
                    stat("최대 케이던스", record.maxCadence.map { "\($0) rpm" } ?? "–", Theme.value)
                    stat("총 경과", formatDuration(record.totalElapsed), Theme.value)
                }
                .padding(.horizontal)

                if let gpxURL {
                    ShareLink(item: gpxURL) {
                        Label("GPX 공유", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(white: 0.14), in: Capsule())
                    }
                    .padding(.horizontal)
                }

                // 3. 기록 삭제
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("기록 삭제", systemImage: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.red.opacity(0.16), in: Capsule())
                }
                .tint(Theme.red)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("코스·자전거 수정", systemImage: "pencil") }
                    if let gpxURL {
                        ShareLink(item: gpxURL) { Label("GPX 공유", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: { Label("기록 삭제", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // 2. 코스명·자전거 종류 수정
        .sheet(isPresented: $showEdit) {
            RideEditSheet(record: record) { updated in
                session.store.update(updated)
                record = updated
                gpxURL = GPXExporter.writeTempGPX(updated)
            }
        }
        // 3. 삭제 확인
        .confirmationDialog("이 라이딩 기록을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                session.store.delete(record)
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제하면 목록에서 제거됩니다. (Apple 건강·캘린더 기록은 영향받지 않습니다)")
        }
        .onAppear { if gpxURL == nil { gpxURL = GPXExporter.writeTempGPX(record) } }
    }

    private var emptyTrackPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.1))
            VStack(spacing: 6) {
                Image(systemName: "map").font(.system(size: 30)).foregroundColor(.secondary)
                Text("GPX 경로 없음").font(.subheadline).foregroundColor(.secondary)
                Text("요약만 가져온 기록은 지도에 표시할 좌표가 없습니다.")
                    .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
        .frame(height: 160)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 라이딩 기록의 코스명·자전거 종류 편집 시트.
struct RideEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: RideRecord
    let onSave: (RideRecord) -> Void

    @State private var name: String
    @State private var bikeName: String

    init(record: RideRecord, onSave: @escaping (RideRecord) -> Void) {
        self.record = record
        self.onSave = onSave
        _name = State(initialValue: record.name)
        _bikeName = State(initialValue: record.bikeName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("코스명") {
                    TextField("코스 이름", text: $name)
                }
                Section("자전거 종류") {
                    Menu {
                        ForEach(RideSession.bikePresets, id: \.self) { b in
                            Button(b) { bikeName = b }
                        }
                    } label: {
                        HStack {
                            Text("종류 선택")
                            Spacer()
                            Text(bikeName.isEmpty ? "미지정" : bikeName).foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down").foregroundColor(.secondary)
                        }
                    }
                    TextField("직접 입력", text: $bikeName)
                }
            }
            .navigationTitle("기록 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        var updated = record
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.name = trimmed.isEmpty ? record.name : trimmed
                        let b = bikeName.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.bikeName = b.isEmpty ? nil : b
                        onSave(updated)
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}

/// 코스 대표 경로의 지도 썸네일(MKMapSnapshotter 로 1회 렌더 후 캐시).
struct RouteThumbnail: View {
    let coords: [CLLocationCoordinate2D]
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15))
                Image(systemName: "map").font(.system(size: 16)).foregroundColor(.secondary)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: coords.count) { await render() }
    }

    @MainActor private func render() async {
        guard image == nil, coords.count > 1, let region = boundingRegion(coords) else { return }
        let pts = downsample(coords, max: 200)
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 120, height: 120)

        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { cont in
            MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snap, _ in
                cont.resume(returning: snap)
            }
        }
        guard let snapshot else { return }

        let rendered = UIGraphicsImageRenderer(size: options.size).image { _ in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, c) in pts.enumerated() {
                let p = snapshot.point(for: c)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            UIColor.systemBlue.setStroke()
            path.lineWidth = 3
            path.lineJoinStyle = .round
            path.stroke()
        }
        image = rendered
    }

    private func downsample(_ c: [CLLocationCoordinate2D], max n: Int) -> [CLLocationCoordinate2D] {
        guard c.count > n else { return c }
        let step = Double(c.count) / Double(n)
        return (0..<n).map { c[Int(Double($0) * step)] }
    }

    private func boundingRegion(_ c: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = c.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for p in c {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.002, (maxLat - minLat) * 1.3),
                                    longitudeDelta: max(0.002, (maxLon - minLon) * 1.3))
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// 전체 내보내기 zip URL 래퍼(sheet item 용).
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// 공유 시트(UIActivityViewController) 래퍼.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
