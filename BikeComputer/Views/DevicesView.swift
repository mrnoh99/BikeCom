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
                sensorRow("심박수", value: hrText, active: session.watch.heartRateBPM != nil)
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("""
                Watch 설치: 1) xcodegen generate  2) Xcode BikeComputer 스킴 → Team 서명 → iPhone Run(⌘R)  \
                3) iPhone Watch 앱 → 일반 → BikeComputer → 설치 ON  4) 실패 시 iPhone·Watch에서 앱 삭제 후 재설치. \
                ./scripts/build.sh 는 서명 없이 빌드만 합니다. \
                BLE 센서는 워치 설정 > 블루투스에서 페어링하세요.
                """)
            }

            Section {
                HStack {
                    Text("휠 둘레")
                    Spacer()
                    Text("\(session.wheelCircumferenceMeters, specifier: "%.3f") m")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("속도 센서 설정")
            } footer: {
                Text("휠 규격은 라이딩 설정에서 변경합니다. CSC 센서 페어링은 워치에서만 합니다.")
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
        guard let bpm = session.watch.heartRateBPM else { return "수신 대기" }
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

#Preview {
    let session = RideSession.preview
    return DevicesView()
        .environmentObject(session)
        .preferredColorScheme(.dark)
}
