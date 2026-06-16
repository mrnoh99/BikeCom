import SwiftUI
import UIKit

/// 지도(GPS) · 라이딩 기록(속도·케이던스·심박) 센서 통합 설정.
struct SensorSettingsView: View {
    @EnvironmentObject var session: RideSession
    @State private var showSettings = false
    @State private var showAddCourse = false
    @State private var newCourseName = ""

    var body: some View {
        List {
            rideConfigSection
            mapSections
            rideSections
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .navigationTitle("센서")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.location.requestAuthorization() }
        .sheet(isPresented: $showSettings) {
            RideSettingsSheet(showAddCourse: $showAddCourse, newCourseName: $newCourseName)
                .environmentObject(session)
        }
        .alert("코스 추가", isPresented: $showAddCourse) {
            TextField("코스 이름 (예: 한강 라이딩)", text: $newCourseName)
            Button("추가") { session.addCourse(newCourseName) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("새 코스를 만들어 목록에 추가합니다.")
        }
    }

    @ViewBuilder private var rideConfigSection: some View {
        Section("라이딩 설정") {
            HStack {
                Text("라이딩 이름")
                Spacer()
                TextField("", text: $session.routeName)
                    .multilineTextAlignment(.trailing)
            }
            Menu {
                ForEach(RideSession.bikePresets, id: \.self) { name in
                    Button(name) { session.selectBike(name) }
                }
            } label: {
                HStack {
                    Text("자전거")
                    Spacer()
                    Text(session.bikeName).foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down").foregroundColor(.secondary)
                }
            }
            TextField("자전거 직접 입력", text: $session.bikeName)
            Button { showSettings = true } label: {
                Label("휠 규격 · 코스 편집", systemImage: "slider.horizontal.3")
            }
        }
    }

    // MARK: - 지도

    @ViewBuilder private var mapSections: some View {
        Section {
            HStack {
                Text("위치 권한")
                Spacer()
                Text(location.authorized ? "허용됨" : "필요")
                    .foregroundColor(location.authorized ? Theme.green : Theme.red)
            }
            if !location.authorized {
                Button("위치 권한 요청", systemImage: "location") {
                    location.requestAuthorization()
                }
                Button("설정 앱 열기", systemImage: "gear") {
                    openSystemSettings()
                }
            }
            HStack {
                Text("지도 제공")
                Spacer()
                Text(mapProviderLabel).foregroundColor(.secondary)
            }
        } header: {
            Text("지도 · GPS")
        } footer: {
            Text("지도 표시, 라이딩 경로, 거리, 등반(Climb) 기록에 iPhone GPS를 사용합니다. Google Maps API 키가 없으면 Apple 지도로 표시합니다.")
        }

        Section {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Group {
                    statusRow("GPS 정확도", value: accuracyText, active: gpsAccuracyGood)
                    statusRow("GPS 속도", value: gpsSpeedText, active: location.gpsSpeedMetersPerSecond > 0.5)
                    if let alt = location.lastLocation?.altitude {
                        statusRow("고도", value: String(format: "%.0f m", alt), active: true)
                    }
                    statusRow("경로 포인트", value: "\(location.track.count)개", active: session.state != .idle)
                }
            }
        } header: {
            Text("GPS 상태")
        }
    }

    // MARK: - 라이딩 기록

    @ViewBuilder private var rideSections: some View {
        Section {
            Picker("입력 경로", selection: $session.sensorMode) {
                Label("폰 BLE", systemImage: "iphone").tag(SensorMode.phone)
                Label("Apple Watch", systemImage: "applewatch").tag(SensorMode.watch)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("속도 · 케이던스 · 심박")
        } footer: {
            Text("대시보드 📱/⌚ 버튼으로도 전환할 수 있습니다. 선택한 경로만 속도·케이던스·Moving time에 사용됩니다. 심박은 Apple Watch에서 측정합니다.")
        }

        Section {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Group {
                    statusRow("입력", value: session.sensorMode == .phone ? "폰 BLE" : "Apple Watch", active: true)
                    statusRow("속도", value: activeSpeedText, active: session.speedSensorConnected)
                    statusRow("케이던스", value: activeCadenceText, active: session.cadenceSensorConnected)
                    statusRow("심박", value: heartRateText, active: session.watch.heartRateConnected)
                }
            }
        } header: {
            Text("수신 상태")
        }

        SensorWatchConnectionSection(watch: session.watch)

        SensorBLESection(ble: session.ble, unit: session.unit, sensorMode: session.sensorMode)

        Section {
            Stepper(value: $session.wheelCircumferenceMeters, in: 1.000...2.500, step: 0.005) {
                HStack {
                    Text("휠 둘레")
                    Spacer()
                    Text("\(session.wheelCircumferenceMeters, specifier: "%.3f") m")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("휠 규격")
        } footer: {
            Text("폰 BLE 속도 센서의 속도·거리 환산에 사용합니다. 예) 700×25C ≈ 2.105 m.")
        }
    }

    private var location: LocationManager { session.location }

    private var mapProviderLabel: String {
        #if canImport(GoogleMaps)
        GMapsConfig.hasKey ? "Google 지도" : "Apple 지도"
        #else
        "Apple 지도"
        #endif
    }

    private var accuracyText: String {
        let acc = location.horizontalAccuracy
        if acc < 0 { return "수신 대기" }
        return String(format: "±%.0f m", acc)
    }

    private var gpsAccuracyGood: Bool {
        let acc = location.horizontalAccuracy
        return acc >= 0 && acc <= 30
    }

    private var gpsSpeedText: String {
        let mps = location.gpsSpeedMetersPerSecond
        guard mps > 0.05 else { return "0" }
        return String(format: "%.1f %@", session.unit.speed(fromMetersPerSecond: mps), session.unit.speedLabel)
    }

    private var activeSpeedText: String {
        switch session.sensorMode {
        case .phone where session.ble.speedConnected:
            return String(format: "%.1f %@",
                          session.unit.speed(fromMetersPerSecond: session.ble.speedMps),
                          session.unit.speedLabel)
        case .watch:
            guard let mps = session.watch.watchSpeedMps else { return "수신 대기" }
            return String(format: "%.1f %@", session.unit.speed(fromMetersPerSecond: mps), session.unit.speedLabel)
        default:
            return "수신 대기"
        }
    }

    private var activeCadenceText: String {
        switch session.sensorMode {
        case .phone where session.ble.cadenceConnected:
            return "\(session.ble.cadenceRPM) rpm"
        case .watch:
            guard let rpm = session.watch.watchCadenceRPM else { return "수신 대기" }
            return "\(rpm) rpm"
        default:
            return "수신 대기"
        }
    }

    private var heartRateText: String {
        guard session.watch.heartRateConnected, let bpm = session.watch.heartRateBPM else { return "수신 대기" }
        return "\(bpm) bpm"
    }

    private func statusRow(_ label: String, value: String, active: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(active ? Theme.green : .secondary)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Apple Watch 연결 상태(속도·케이던스는 수신 상태 섹션에 통합).
private struct SensorWatchConnectionSection: View {
    @ObservedObject var watch: WatchSensorManager

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Group {
                    HStack {
                        Label("Apple Watch", systemImage: "applewatch")
                        Spacer()
                        Text(watch.watchReachable ? "연결됨" : "대기 중")
                            .foregroundColor(watch.watchReachable ? Theme.green : .secondary)
                    }
                    row("WatchConnectivity", value: watch.sessionActivated ? "활성" : "비활성",
                        active: watch.sessionActivated)
                    row("상태", value: watch.statusMessage, active: watch.didReceiveWatchDataThisRide)
                    if let err = watch.lastError {
                        Text(err).font(.caption).foregroundColor(Theme.red)
                    }
                }
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            Text("⌚ 모드: CSC 센서는 워치 Bluetooth에 페어링. 📱 모드로 바꾸면 워치 BLE 연결을 해제한 뒤 폰 BLE가 자동 재연결됩니다.")
        }
    }

    private func row(_ label: String, value: String, active: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(active ? Theme.green : .secondary)
        }
    }
}

/// 폰 BLE 속도·케이던스 연결(⌚ 모드일 때는 스캔 비활성).
private struct SensorBLESection: View {
    @ObservedObject var ble: BLECSCManager
    let unit: DistanceUnit
    let sensorMode: SensorMode

    var body: some View {
        Section {
            HStack {
                Label("폰 Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                if sensorMode == .watch {
                    Text("⌚ 모드 — 중단").foregroundColor(.secondary)
                } else {
                    Text(ble.poweredOn ? "켜짐" : "꺼짐/권한 필요")
                        .foregroundColor(ble.poweredOn ? Theme.green : .secondary)
                }
            }
        } header: {
            Text("폰 BLE")
        } footer: {
            Text("속도·케이던스 센서를 각각 연결·저장합니다. 📱 모드에서 자동 재연결됩니다.")
        }

        slotSection(title: "속도 센서", slot: .speed,
                    connectedName: ble.connectedSpeedName,
                    valueText: speedText, isConnected: ble.speedConnected)
        slotSection(title: "케이던스 센서", slot: .cadence,
                    connectedName: ble.connectedCadenceName,
                    valueText: cadenceText, isConnected: ble.cadenceConnected)
    }

    @ViewBuilder
    private func slotSection(
        title: String,
        slot: BLECSCManager.Slot,
        connectedName: String?,
        valueText: String,
        isConnected: Bool
    ) -> some View {
        Section {
            if let connectedName {
                row("연결됨", value: connectedName, active: true)
                if sensorMode == .phone {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        row("수신", value: valueText, active: isConnected)
                    }
                }
                Button(role: .destructive) { ble.forget(slot) } label: {
                    Label("연결 해제·저장 삭제", systemImage: "xmark.circle")
                }
            } else if ble.scanning, ble.scanTarget == slot {
                Button { ble.stopScan() } label: {
                    Label("스캔 중지", systemImage: "stop.circle")
                }
                ForEach(ble.discovered) { dev in
                    Button { ble.connect(dev.id, slot: slot) } label: {
                        HStack {
                            Label(dev.name, systemImage: "dot.radiowaves.left.and.right")
                            Spacer()
                            Image(systemName: "link")
                        }
                    }
                }
                if ble.discovered.isEmpty {
                    Text("주변 CSC 센서 검색 중…").foregroundColor(.secondary)
                }
            } else {
                Button { ble.startScan(for: slot) } label: {
                    Label("\(title) 스캔", systemImage: "magnifyingglass")
                }
                .disabled(sensorMode == .watch || !ble.poweredOn || !ble.connectionsActive)
            }
        } header: {
            Text(title)
        }
    }

    private var speedText: String {
        guard ble.speedConnected else { return "수신 대기" }
        return String(format: "%.1f %@", unit.speed(fromMetersPerSecond: ble.speedMps), unit.speedLabel)
    }

    private var cadenceText: String {
        guard ble.cadenceConnected else { return "수신 대기" }
        return "\(ble.cadenceRPM) rpm"
    }

    private func row(_ label: String, value: String, active: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(active ? Theme.green : .secondary)
        }
    }
}

/// 대시보드 ⌚/📱 길게 누르기 등 기존 진입점.
typealias DevicesView = SensorSettingsView
typealias RideSensorSettingsView = SensorSettingsView
typealias MapSensorSettingsView = SensorSettingsView

#if DEBUG
#Preview {
    NavigationStack {
        SensorSettingsView()
            .environmentObject(RideSession.preview)
    }
    .preferredColorScheme(.dark)
}
#endif
