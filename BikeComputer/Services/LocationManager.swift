import Foundation
import CoreLocation

/// GPS 기반 속도·거리·경로 기록. 속도 센서가 없을 때의 기본 속도원이자
/// 지도/경로 탭의 트랙(좌표 목록)을 만든다.
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var gpsSpeedMetersPerSecond: Double = 0
    @Published private(set) var horizontalAccuracy: Double = -1
    @Published private(set) var lastLocation: CLLocation?

    /// 현재 라이딩의 누적 GPS 거리(미터)와 경로 좌표.
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var track: [CLLocationCoordinate2D] = []
    /// 트랙과 동일 지점의 전체 위치(고도·속도·시각 포함) — GPX 확장 태그용.
    @Published private(set) var locations: [CLLocation] = []

    private let manager = CLLocationManager()
    private var recording = false
    private var previousLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// 라이딩 시작: 거리·트랙 초기화 후 백그라운드 추적까지 시작.
    func startRecording() {
        distanceMeters = 0
        track = []
        locations = []
        previousLocation = nil
        recording = true
        manager.allowsBackgroundLocationUpdates = (manager.authorizationStatus == .authorizedAlways)
        manager.startUpdatingLocation()
    }

    func pauseRecording() {
        recording = false
        previousLocation = nil
    }

    func resumeRecording() {
        recording = true
        previousLocation = nil
    }

    /// 라이딩 종료: 추적은 유지하되(현재 속도 표시용) 거리 누적만 멈춘다.
    func stopRecording() {
        recording = false
        previousLocation = nil
        manager.allowsBackgroundLocationUpdates = false
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authorized = true
            manager.startUpdatingLocation()
        default:
            authorized = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        horizontalAccuracy = loc.horizontalAccuracy

        // 정확도가 너무 낮은 측정은 거리 계산에서 제외.
        let usable = loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 30

        // CLLocation.speed 가 음수면 무효 → 0 처리.
        gpsSpeedMetersPerSecond = max(0, loc.speed)

        guard recording, usable else { return }
        if let prev = previousLocation {
            let d = loc.distance(from: prev)
            // 비현실적 점프(>100m, 표류) 무시.
            if d < 100 { distanceMeters += d }
        }
        previousLocation = loc
        track.append(loc.coordinate)
        self.locations.append(loc)
    }
}
