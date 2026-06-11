import SwiftUI
import MapKit
#if canImport(GoogleMaps)
import GoogleMaps
#endif

/// 과거(자주 탄) 코스들을 한 지도에 오버레이해서 보는 화면.
/// 지도는 **Google 지도(표준 타입)** 를 사용하고, GoogleMaps SDK/키가 없으면 Apple 지도로 폴백한다.
struct PastCoursesMapView: View {
    @EnvironmentObject var session: RideSession
    @Environment(\.dismiss) private var dismiss

    /// 코스별 대표 경로(상위 40개)만 오버레이.
    private var tracks: [[CLLocationCoordinate2D]] {
        RouteGrouping.groups(session.store.records)
            .prefix(40)
            .compactMap { group in group.representative?.track.map { $0.clCoordinate } }
            .filter { $0.count > 1 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if tracks.isEmpty {
                    ContentUnavailableView("과거 코스 없음", systemImage: "map",
                                           description: Text("경로가 있는 라이딩이 쌓이면 여기에 코스가 겹쳐 표시됩니다."))
                } else {
                    PastCoursesMap(tracks: tracks).ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("과거 코스")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
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
