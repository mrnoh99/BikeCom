import SwiftUI
import MapKit
import CoreLocation
#if canImport(GoogleMaps)
import GoogleMaps
#endif

/// 좌표 → 짧은 지명 역지오코딩 결과 캐시(중복 조회·throttle 방지).
actor PlaceNameCache {
    static let shared = PlaceNameCache()
    private var cache: [String: String] = [:]

    private func key(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.3f,%.3f", c.latitude, c.longitude)   // 약 100m 단위로 묶음
    }

    func name(for coord: CLLocationCoordinate2D) async -> String {
        let k = key(coord)
        if let v = cache[k] { return v }
        let name = await Self.reverseGeocode(coord)
        cache[k] = name
        return name
    }

    private static func reverseGeocode(_ coord: CLLocationCoordinate2D) async -> String {
        let geo = CLGeocoder()
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if let pm = try? await geo.reverseGeocodeLocation(loc).first {
            let parts = [pm.subLocality, pm.locality].compactMap { $0 }
            if !parts.isEmpty { return parts.joined(separator: " ") }
            if let n = pm.name { return n }
        }
        return String(format: "%.3f, %.3f", coord.latitude, coord.longitude)
    }
}

/// 과거(자주 탄) 코스들을 한 지도에 오버레이해서 보는 화면.
/// 지도는 **Google 지도(표준 타입)** 를 사용하고, GoogleMaps SDK/키가 없으면 Apple 지도로 폴백한다.
/// Map 탭의 코스 목록 — 사용자가 '지도 목록에 표시'로 직접 고른 코스만,
/// 지정한 이름으로 리스팅한다. 코스를 고르면 지도에서 경로를 보고 주행 중 따라갈 수 있다.
struct PastCoursesMapView: View {
    @EnvironmentObject var session: RideSession
    @Environment(\.dismiss) private var dismiss
    /// 라이브 지도에서 따라갈 기준 코스를 선택했을 때 호출(코스 1건).
    var onFollow: ((RideRecord) -> Void)? = nil

    private func displayName(_ r: RideRecord) -> String {
        if let n = r.mapName, !n.isEmpty { return n }
        return r.name
    }

    /// 지도 코스 자료(isCourseOnly) + GPS 있는 코스만, 표시 이름순.
    private var courses: [RideRecord] {
        session.store.records
            .filter { $0.isCourseOnly && $0.trackCount > 1 }
            .sorted { displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if courses.isEmpty {
                    ContentUnavailableView {
                        Label("표시할 코스 없음", systemImage: "map")
                    } description: {
                        Text("라이딩 상세 → 코스·자전거 수정에서 '지도 목록에 표시'를 켜면 여기에 코스가 나타납니다.")
                    }
                } else {
                    List(courses) { course in
                        NavigationLink {
                            CourseMapView(record: course, title: displayName(course), onFollow: onFollow)
                        } label: {
                            HStack(spacing: 12) {
                                LazyRouteThumbnail(record: course)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(displayName(course))
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(String(format: "%.1f km", course.distanceMeters / 1000))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let onFollow {
                                Button { onFollow(course) } label: {
                                    Label("따라가기", systemImage: "location.north.line")
                                }.tint(Theme.gold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("코스")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
    }
}

/// 선택한 코스 1개를 지도에 표시(주행 중 따라갈 수 있게 현재 위치도 함께 표시).
struct CourseMapView: View {
    @EnvironmentObject var session: RideSession
    let record: RideRecord
    let title: String
    var onFollow: ((RideRecord) -> Void)? = nil
    @State private var track: [CLLocationCoordinate2D] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("경로 불러오는 중…")
            } else if track.count > 1 {
                PastCoursesMap(tracks: [track]).ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("경로 없음", systemImage: "map")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onFollow {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onFollow(record) } label: {
                        Label("따라가기", systemImage: "location.north.line")
                    }
                }
            }
        }
        .task {
            guard track.isEmpty else { return }
            session.store.loadTrack(for: record) { t in
                track = t.map { $0.clCoordinate }
                loading = false
            }
        }
    }
}

/// 지도 코스 일괄 관리 — GPS 가 있는 라이딩을 한 화면에서 토글/이름 지정.
struct CourseManagerView: View {
    @EnvironmentObject var session: RideSession

    private var courseRecords: [RideRecord] {
        session.store.records
            .filter { $0.isCourseOnly }
            .sorted { ($0.mapName ?? $0.name).localizedStandardCompare($1.mapName ?? $1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ForEach(courseRecords) { rec in
                    CourseManagerRow(record: rec)
                }
                .onDelete { idx in
                    idx.map { courseRecords[$0] }.forEach { session.store.delete($0) }
                }
            } footer: {
                Text("지도 코스 자료만 표시됩니다(주행 통계 제외). 왼쪽으로 밀어 삭제할 수 있습니다. 추가는 라이딩 기록 상세·루트 목록에서 '지도 코스로 복사', 또는 GPX 가져오기에서 '지도 코스 자료'를 선택하세요.")
            }
        }
        .navigationTitle("지도 코스 관리")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if courseRecords.isEmpty {
                ContentUnavailableView("코스 자료 없음", systemImage: "map",
                                       description: Text("라이딩 기록을 '지도 코스로 복사'하거나, GPX 를 '지도 코스 자료'로 가져오면 여기에 나타납니다."))
            }
        }
    }
}

/// 관리 화면의 한 행 — 코스 이름 편집 + 날짜/거리/출발·도착. 변경 시 즉시 저장한다.
private struct CourseManagerRow: View {
    @EnvironmentObject var session: RideSession
    let record: RideRecord
    @State private var name: String
    @State private var startPlace = ""
    @State private var endPlace = ""

    init(record: RideRecord) {
        self.record = record
        _name = State(initialValue: record.mapName ?? "")
    }

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy.MM.dd HH:mm"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("코스 이름", text: $name)
                .font(.system(size: 15, weight: .semibold))
                .submitLabel(.done)
                .onSubmit { commit() }
            Text("\(Self.df.string(from: record.startedAt)) · \(String(format: "%.1f km", record.distanceMeters / 1000))")
                .font(.caption).foregroundColor(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "smallcircle.filled.circle").foregroundColor(Theme.green)
                Text(startPlace.isEmpty ? "출발 …" : "출발 \(startPlace)")
                Image(systemName: "arrow.right").foregroundColor(.secondary)
                Image(systemName: "mappin.circle.fill").foregroundColor(Theme.red)
                Text(endPlace.isEmpty ? "도착 …" : "도착 \(endPlace)")
            }
            .font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
        .task {
            if startPlace.isEmpty, let s = record.startCoord {
                startPlace = await PlaceNameCache.shared.name(for: s.clCoordinate)
            }
            if endPlace.isEmpty, let e = record.endCoord {
                endPlace = await PlaceNameCache.shared.name(for: e.clCoordinate)
            }
        }
    }

    private func commit() {
        var r = record
        let m = name.trimmingCharacters(in: .whitespacesAndNewlines)
        r.mapName = m.isEmpty ? nil : m
        r.track = []
        session.store.update(r)
    }
}

/// Google 지도 사용 가능 여부(SDK + Info.plist GMSApiKey).
enum GMapsConfig {
    static var hasKey: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String).map { !$0.isEmpty } ?? false
    }
}

/// 여러 코스 오버레이: Google(가능 시) 또는 Apple.
struct PastCoursesMap: View {
    let tracks: [[CLLocationCoordinate2D]]

    var body: some View {
        #if canImport(GoogleMaps)
        if GMapsConfig.hasKey {
            GoogleRouteMap(tracks: tracks)
        } else {
            MultiRouteAppleMap(tracks: tracks)
        }
        #else
        MultiRouteAppleMap(tracks: tracks)
        #endif
    }
}

/// 단일 경로 정적 지도(라이딩 상세용): Google(가능 시) 또는 Apple(autoFit).
struct StaticRouteMap: View {
    let track: [CLLocationCoordinate2D]

    var body: some View {
        #if canImport(GoogleMaps)
        if GMapsConfig.hasKey {
            GoogleRouteMap(tracks: [track])
        } else {
            appleMap
        }
        #else
        appleMap
        #endif
    }

    private var appleMap: some View {
        RouteMap(track: track, userLocation: track.first,
                 region: .constant(MKCoordinateRegion()), autoFit: true)
    }
}

#if canImport(GoogleMaps)
/// Google 지도(표준 타입)로 여러 코스 폴리라인을 표시.
struct GoogleRouteMap: UIViewRepresentable {
    let tracks: [[CLLocationCoordinate2D]]
    private let palette: [UIColor] = [.systemBlue, .systemRed, .systemGreen, .systemOrange, .systemPurple, .systemTeal]

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView()
        map.mapType = .normal            // 표준 타입만 사용
        map.settings.compassButton = true
        map.isMyLocationEnabled = true
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        map.clear()
        var bounds = GMSCoordinateBounds()
        for (i, track) in tracks.enumerated() where track.count > 1 {
            let path = GMSMutablePath()
            for c in track { path.add(c); bounds = bounds.includingCoordinate(c) }
            let line = GMSPolyline(path: path)
            line.strokeColor = palette[i % palette.count]
            line.strokeWidth = 4
            line.map = map
        }
        if bounds.isValid {
            map.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: 40))
        }
    }
}
#endif

/// 폴백: Apple 지도(표준 타입)로 여러 코스 폴리라인을 표시.
struct MultiRouteAppleMap: UIViewRepresentable {
    let tracks: [[CLLocationCoordinate2D]]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .standard          // 표준 타입만 사용
        map.showsUserLocation = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        var rect = MKMapRect.null
        for track in tracks where track.count > 1 {
            let line = MKPolyline(coordinates: track, count: track.count)
            map.addOverlay(line)
            rect = rect.union(line.boundingMapRect)
        }
        if !rect.isNull {
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth = 4
            return r
        }
    }
}
