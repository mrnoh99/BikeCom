import SwiftUI

/// Devices 탭 — 워치 연결 상태·워치 경유 속도·케이던스·심박.
struct DevicesView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Apple Watch", systemImage: "applewatch")
                    Spacer()
                    Text(session.watch.watchReachable ? "연결됨" : "대기 중")
                        .foregroundColor(session.watch.watchReachable ? Theme.green : .secondary)
                }
                sensorRow("WatchConnectivity", value: session.watch.sessionActivated ? "활성" : "비활성",
                            active: session.watch.sessionActivated)
                sensorRow("상태", value: session.watch.statusMessage, active: session.watch.didReceiveWatchDataThisRide)
                if let err = session.watch.lastError {
                    Text(err).font(.caption).foregroundColor(Theme.red)
                }
                sensorRow("속도", value: speedText, active: session.watch.watchSpeedMps != nil)
                sensorRow("케이던스", value: cadenceText, active: session.watch.watchCadenceRPM != nil)
                sensorRow("심박수", value: hrText, active: session.watch.heartRateConnected)
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("""
                Watch 설치: 1) xcodegen generate  2) Xcode BikeCom 스킴 → Team 서명 → iPhone Run(⌘R)  \
                3) iPhone Watch 앱 → 일반 → BikeCom → 설치 ON  4) 실패 시 iPhone·Watch에서 앱 삭제 후 재설치. \
                ./scripts/build.sh 는 서명 없이 빌드만 합니다. \
                BLE 센서는 워치 설정 > 블루투스에서 페어링하세요.
                """)
            }

            // 폰 직접 연결(BLE CSC 센서) — 워치 중계 없이 폰에 바로 페어링.
            Section {
                HStack {
                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Text(session.ble.poweredOn ? "켜짐" : "꺼짐/권한 필요")
                        .foregroundColor(session.ble.poweredOn ? Theme.green : .secondary)
                }
                if let name = session.ble.connectedName {
                    sensorRow("연결된 센서", value: name, active: true)
                    sensorRow("속도(BLE)", value: bleSpeedText, active: session.ble.speedConnected)
                    sensorRow("케이던스(BLE)", value: bleCadenceText, active: session.ble.cadenceConnected)
                    Button(role: .destructive) { session.ble.forget() } label: {
                        Label("연결 해제·해제 저장", systemImage: "xmark.circle")
                    }
                } else {
                    Button {
                        session.ble.scanning ? session.ble.stopScan() : session.ble.startScan()
                    } label: {
                        Label(session.ble.scanning ? "스캔 중지" : "센서 스캔",
                              systemImage: session.ble.scanning ? "stop.circle" : "magnifyingglass")
                    }
                    .disabled(!session.ble.poweredOn)
                    ForEach(session.ble.discovered) { dev in
                        Button { session.ble.connect(dev.id) } label: {
                            HStack {
                                Label(dev.name, systemImage: "dot.radiowaves.left.and.right")
                                Spacer()
                                Image(systemName: "link")
                            }
                        }
                    }
                }
            } header: {
                Text("폰 직접 연결 (BLE 속도·케이던스)")
            } footer: {
                Text("표준 CSC(0x1816) 속도·케이던스 센서를 폰에 직접 연결합니다. 폰 BLE 가 연결되면 워치 중계보다 우선합니다. 휠 둘레로 속도를 계산하므로 아래 값을 정확히 설정하세요.")
            }

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
                Text("속도 센서 설정 (BLE 속도 계산용)")
            } footer: {
                Text("예) 700×25C ≈ 2.105 m, 26\" MTB ≈ 2.070 m. 폰 직결 속도 센서의 속도 계산에 사용됩니다.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var speedText: String {
        guard let mps = session.watch.watchSpeedMps else { return "수신 대기" }
        return String(format: "%.1f %@", session.unit.speed(fromMetersPerSecond: mps), session.unit.speedLabel)
    }

    private var cadenceText: String {
        guard let rpm = session.watch.watchCadenceRPM else { return "수신 대기" }
        return "\(rpm) rpm"
    }

    private var hrText: String {
        guard session.watch.heartRateConnected, let bpm = session.watch.heartRateBPM else { return "수신 대기" }
        return "\(bpm) bpm"
    }

    private var bleSpeedText: String {
        guard session.ble.speedConnected else { return "수신 대기" }
        return String(format: "%.1f %@", session.unit.speed(fromMetersPerSecond: session.ble.speedMps), session.unit.speedLabel)
    }

    private var bleCadenceText: String {
        guard session.ble.cadenceConnected else { return "수신 대기" }
        return "\(session.ble.cadenceRPM) rpm"
    }

    private func sensorRow(_ label: String, value: String, active: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(active ? Theme.green : .secondary)
        }
    }
}

#if DEBUG
#Preview {
    DevicesView()
        .environmentObject(RideSession.preview)
        .preferredColorScheme(.dark)
}
#endif
