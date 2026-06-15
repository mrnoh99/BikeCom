import SwiftUI

/// Devices 탭 — 워치 연결 상태·워치 경유 속도·케이던스·심박.
struct DevicesView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        List {
            DevicesWatchSection(watch: session.watch, unit: session.unit)
            DevicesBLESection(ble: session.ble, unit: session.unit)

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
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DevicesWatchSection: View {
    @ObservedObject var watch: WatchSensorManager
    let unit: DistanceUnit

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
                    sensorRow("WatchConnectivity", value: watch.sessionActivated ? "활성" : "비활성",
                                active: watch.sessionActivated)
                    sensorRow("상태", value: watch.statusMessage, active: watch.didReceiveWatchDataThisRide)
                    if let err = watch.lastError {
                        Text(err).font(.caption).foregroundColor(Theme.red)
                    }
                    sensorRow("속도", value: speedText, active: watch.watchSpeedMps != nil)
                    sensorRow("케이던스", value: cadenceText, active: watch.watchCadenceRPM != nil)
                    sensorRow("심박수", value: hrText, active: watch.heartRateConnected)
                }
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            Text("""
            ⌚→📱 전환: 워치 CONNECT 끄기 → 📱 선택 → 2~3초 후 폰 BLE 자동 재연결. \
            그래도 안 되면 워치 설정 > Bluetooth 에서 CSC 센서 연결 해제(센서는 한 기기만 연결). \
            ⌚ 모드: CSC 는 워치 Bluetooth 에만 페어링.
            """)
        }
    }

    private var speedText: String {
        guard let mps = watch.watchSpeedMps else { return "수신 대기" }
        return String(format: "%.1f %@", unit.speed(fromMetersPerSecond: mps), unit.speedLabel)
    }

    private var cadenceText: String {
        guard let rpm = watch.watchCadenceRPM else { return "수신 대기" }
        return "\(rpm) rpm"
    }

    private var hrText: String {
        guard watch.heartRateConnected, let bpm = watch.heartRateBPM else { return "수신 대기" }
        return "\(bpm) bpm"
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

private struct DevicesBLESection: View {
    @ObservedObject var ble: BLECSCManager
    let unit: DistanceUnit

    var body: some View {
        Section {
            HStack {
                Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                if !ble.connectionsActive {
                    Text("⌚ 모드 — 중단")
                        .foregroundColor(.secondary)
                } else {
                    Text(ble.poweredOn ? "켜짐" : "꺼짐/권한 필요")
                        .foregroundColor(ble.poweredOn ? Theme.green : .secondary)
                }
            }
        } header: {
            Text("폰 직접 연결 (BLE)")
        } footer: {
            Text("속도·케이던스 센서를 각각 연결합니다. 저장된 센서는 📱 모드에서 자동 재연결됩니다. ⌚ 모드 선택 시 폰 BLE 연결은 일시 중단됩니다.")
        }

        slotSection(
            title: "속도 센서",
            slot: .speed,
            connectedName: ble.connectedSpeedName,
            valueText: bleSpeedText,
            isConnected: ble.speedConnected
        )

        slotSection(
            title: "케이던스 센서",
            slot: .cadence,
            connectedName: ble.connectedCadenceName,
            valueText: bleCadenceText,
            isConnected: ble.cadenceConnected
        )
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
                sensorRow("연결됨", value: connectedName, active: true)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    sensorRow("수신", value: valueText, active: isConnected)
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
                Button {
                    ble.startScan(for: slot)
                } label: {
                    Label("\(title) 스캔", systemImage: "magnifyingglass")
                }
                .disabled(!ble.poweredOn || !ble.connectionsActive)
            }
        } header: {
            Text(title)
        }
    }

    private var bleSpeedText: String {
        guard ble.speedConnected else { return "수신 대기" }
        return String(format: "%.1f %@", unit.speed(fromMetersPerSecond: ble.speedMps), unit.speedLabel)
    }

    private var bleCadenceText: String {
        guard ble.cadenceConnected else { return "수신 대기" }
        return "\(ble.cadenceRPM) rpm"
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
