import SwiftUI
import MapKit
#if canImport(GoogleMaps)
import GoogleMaps
#endif

/// Map 탭 — 현재 위치 + 진행 중인 라이딩 경로(폴리라인).
struct MapTabView: View {
    @EnvironmentObject var session: RideSession
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    @State private var showPastCourses = false
    @State private var recenterToken = 0

    private var navigating: Bool { !session.followCourseTrack.isEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            LiveMap(track: session.location.track,
                    userLocation: session.location.lastLocation?.coordinate,
                    courseTrack: session.followCourseTrack,
                    navigationMode: navigating,
                    recenterToken: recenterToken,
                    region: $region)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 8) {
                // 상단 요약 바
                HStack(spacing: 20) {
                    summary("거리", "\(String(format: "%.2f", session.displayDistance)) \(session.unit.distanceLabel)")
                    summary("속도", "\(String(format: "%.1f", session.displaySpeed)) \(session.unit.speedLabel)")
                    summary("시간", formatDuration(session.rideSeconds))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                // 기준 코스 오버레이 배너(이름 + 해제)
                if let name = session.followCourseName {
                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .foregroundColor(Theme.gold)
                        Text("따라가는 코스: \(name)").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Button { session.clearFollowCourse() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if navigating {
                    Button { recenterToken += 1 } label: {
                        Label("내비 재중심", systemImage: "location.north.line.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                Button { showPastCourses = true } label: {
                    Label("코스", systemImage: "map")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showPastCourses) {
            PastCoursesMapView(onFollow: { course in
                session.setFollowCourse(course)
                showPastCourses = false
            })
        }
        .onAppear { session.restoreFollowCourseIfNeeded() }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(size: 15, weight: .bold))
        }
    }
}

/// UIKit MKMapView 래퍼 — 폴리라인 경로 표시.
/// `autoFit` 이 true 면 경로 전체가 보이도록 맞추고(상세 화면),
/// false 면 사용자 위치를 따라간다(라이딩 중 지도 탭).
struct RouteMap: UIViewRepresentable {
    let track: [CLLocationCoordinate2D]
    let userLocation: CLLocationCoordinate2D?
    @Binding var region: MKCoordinateRegion
    var autoFit: Bool = false
    var courseTrack: [CLLocationCoordinate2D] = []   // 기준 코스 오버레이(주행 중 따라가기)
    var navigationMode: Bool = false                  // 따라가기: 헤딩업 + 3D + 근접 추적
    var recenterToken: Int = 0                        // 값이 바뀌면 내비 추적 재적용

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        if !autoFit { map.userTrackingMode = .follow }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // 재중심 버튼: 토큰이 바뀌면 내비 추적을 다시 적용(사용자가 지도를 움직여 추적이 풀린 경우).
        if context.coordinator.recenterToken != recenterToken {
            context.coordinator.recenterToken = recenterToken
            context.coordinator.navApplied = false
            if !navigationMode, let loc = userLocation {
                map.setUserTrackingMode(.follow, animated: true)
                map.setRegion(MKCoordinateRegion(center: loc,
                              span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)),
                              animated: true)
            }
        }
        map.removeOverlays(map.overlays)
        context.coordinator.coursePolyline = nil

        // 기준 코스(있으면 먼저 깔아 배경처럼 표시).
        if courseTrack.count > 1 {
            let course = MKPolyline(coordinates: courseTrack, count: courseTrack.count)
            context.coordinator.coursePolyline = course
            map.addOverlay(course)
        }

        guard track.count > 1 || userLocation != nil || courseTrack.count > 1 else { return }

        if track.count > 1 {
            let line = MKPolyline(coordinates: track, count: track.count)
            map.addOverlay(line)
            if autoFit {
                map.setVisibleMapRect(line.boundingMapRect,
                                      edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                                      animated: false)
                return
            }
        }
        if !autoFit, navigationMode, let loc = userLocation {
            // 내비게이션 모드: 사용자 위치를 화면 하단 1/5(좌우 중앙)에 두고 진행 방향이
            // 위로 오도록 회전 + 3D 기울기로 추적. 위쪽 여백을 키워 추적 중심을 아래로 내린다.
            let topInset = map.bounds.height * 0.6   // 중심이 화면 80% 높이 → 하단 1/5 지점
            let margins = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
            if map.layoutMargins != margins { map.layoutMargins = margins }
            if !context.coordinator.navApplied {
                let cam = MKMapCamera(lookingAtCenter: loc, fromDistance: 550, pitch: 55,
                                      heading: map.camera.heading)
                map.setCamera(cam, animated: true)
                map.setUserTrackingMode(.followWithHeading, animated: true)
                context.coordinator.navApplied = true
            }
            // followWithHeading 가 중심·회전을 계속 갱신하므로 수동 setRegion 생략.
        } else if !autoFit, let loc = userLocation {
            if context.coordinator.navApplied {
                // 내비게이션 모드 해제: 평면(탑다운) 추적으로 복귀.
                map.setUserTrackingMode(.follow, animated: true)
                map.layoutMargins = .zero
                let cam = map.camera
                cam.pitch = 0
                cam.heading = 0
                map.setCamera(cam, animated: true)
                context.coordinator.navApplied = false
            }
            let span = map.region.span.latitudeDelta > 0.2
                ? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                : map.region.span
            map.setRegion(MKCoordinateRegion(center: loc, span: span), animated: true)
        } else if autoFit, track.count <= 1, let course = context.coordinator.coursePolyline {
            // 라이브 트랙이 아직 없으면 기준 코스 전체가 보이게 맞춘다.
            map.setVisibleMapRect(course.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                                  animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var coursePolyline: MKPolyline?
        var navApplied = false
        var recenterToken = 0
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            if line === coursePolyline {
                r.strokeColor = UIColor.systemOrange   // 기준 코스
                r.lineWidth = 6
                r.alpha = 0.7
            } else {
                r.strokeColor = UIColor.systemBlue     // 현재 주행 경로
                r.lineWidth = 5
            }
            return r
        }
    }
}

/// 라이브 지도: Google(가능 시) 또는 Apple(`RouteMap`).
struct LiveMap: View {
    let track: [CLLocationCoordinate2D]
    let userLocation: CLLocationCoordinate2D?
    var courseTrack: [CLLocationCoordinate2D] = []
    var navigationMode: Bool = false
    var recenterToken: Int = 0
    @Binding var region: MKCoordinateRegion

    var body: some View {
        #if canImport(GoogleMaps)
        if GMapsConfig.hasKey {
            GoogleLiveMap(track: track, userLocation: userLocation, courseTrack: courseTrack, navigationMode: navigationMode, recenterToken: recenterToken)
        } else {
            RouteMap(track: track, userLocation: userLocation, region: $region, courseTrack: courseTrack, navigationMode: navigationMode, recenterToken: recenterToken)
        }
        #else
        RouteMap(track: track, userLocation: userLocation, region: $region, courseTrack: courseTrack, navigationMode: navigationMode, recenterToken: recenterToken)
        #endif
    }
}

#if canImport(GoogleMaps)
/// Google 지도(표준 타입) 라이브 추적 — 경로 폴리라인 + 사용자 추적(직접 조작 전까지).
struct GoogleLiveMap: UIViewRepresentable {
    let track: [CLLocationCoordinate2D]
    let userLocation: CLLocationCoordinate2D?
    var courseTrack: [CLLocationCoordinate2D] = []
    var navigationMode: Bool = false
    var recenterToken: Int = 0

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView()
        map.mapType = .normal
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = true
        map.settings.compassButton = true
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        // 재중심 버튼: 토큰이 바뀌면 사용자 추적을 다시 켠다.
        if context.coordinator.recenterToken != recenterToken {
            context.coordinator.recenterToken = recenterToken
            context.coordinator.userMoved = false
        }
        map.clear()
        if courseTrack.count > 1 {
            let path = GMSMutablePath()
            for c in courseTrack { path.add(c) }
            let line = GMSPolyline(path: path)
            line.strokeColor = UIColor.systemOrange.withAlphaComponent(0.7)
            line.strokeWidth = 6
            line.map = map
        }
        if track.count > 1 {
            let path = GMSMutablePath()
            for c in track { path.add(c) }
            let line = GMSPolyline(path: path)
            line.strokeColor = .systemBlue
            line.strokeWidth = 5
            line.map = map
        }
        if let loc = userLocation, !context.coordinator.userMoved {
            if navigationMode {
                // 내비게이션 모드: 근접 줌 + 3D 기울기로 추적. 위쪽 padding 을 키워
                // 사용자 위치를 화면 하단 1/5(좌우 중앙)에 둔다.
                let topPad = map.bounds.height * 0.6
                let pad = UIEdgeInsets(top: topPad, left: 0, bottom: 0, right: 0)
                if map.padding != pad { map.padding = pad }
                let cam = GMSCameraPosition(target: loc, zoom: 17,
                                            bearing: map.camera.bearing, viewingAngle: 55)
                map.animate(to: cam)
            } else {
                if map.padding != .zero { map.padding = .zero }
                map.animate(toLocation: loc)
                if map.camera.zoom < 14 { map.animate(toZoom: 16) }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var userMoved = false
        var recenterToken = 0
        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture { userMoved = true }   // 사용자가 직접 움직이면 자동 추적 중단
        }
    }
}
#endif
