import SwiftUI

/// More 탭 — 센서·정보 등 기타 설정. (데이터 가져오기/정리는 Routes 첫 페이지로 이동)
struct MoreView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        List {
                Section("라이딩") {
                    HStack { Text("라이딩 이름"); Spacer(); TextField("", text: $session.routeName).multilineTextAlignment(.trailing) }
                }
                Section("자전거 종류") {
                    Menu {
                        ForEach(RideSession.bikePresets, id: \.self) { name in
                            Button(name) { session.bikeName = name }
                        }
                    } label: {
                        HStack {
                            Text("종류")
                            Spacer()
                            Text(session.bikeName).foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down").foregroundColor(.secondary)
                        }
                    }
                    TextField("직접 입력", text: $session.bikeName)
                }
                Section {
                    statRow("이번 달", session.thisMonthDistance)
                    statRow("올해", session.thisYearDistance)
                    statRow("전체", session.totalDistance)
                    HStack {
                        Text("총 라이딩 시간")
                        Spacer()
                        Text(formatDuration(session.totalRideTime)).foregroundColor(Theme.gold)
                    }
                    HStack { Text("총 라이딩 수"); Spacer(); Text("\(session.store.records.count)").foregroundColor(.secondary) }
                } header: {
                    Text("누적 통계")
                } footer: {
                    Text("총 라이딩 시간은 Cyclemeter(가져온 JSON 기록)와 Apple 건강의 사이클링 운동을 시작 시각 기준으로 중복 없이 합산합니다.")
                }
                Section("센서") {
                    HStack {
                        Text("위치 권한")
                        Spacer()
                        Text(session.location.authorized ? "허용됨" : "필요")
                            .foregroundColor(session.location.authorized ? Theme.green : Theme.red)
                    }
                    HStack {
                        Text("심박 측정")
                        Spacer()
                        Text(session.watch.watchReachable ? "Apple Watch 연결됨" : "Apple Watch")
                            .foregroundColor(session.watch.watchReachable ? Theme.green : .secondary)
                    }
                    HStack {
                        Text("워치 속도")
                        Spacer()
                        Text(session.watch.watchSpeedMps.map { String(format: "%.1f %@", session.unit.speed(fromMetersPerSecond: $0), session.unit.speedLabel) } ?? "수신 대기")
                            .foregroundColor(session.watch.watchSpeedMps != nil ? Theme.green : .secondary)
                    }
                    HStack {
                        Text("워치 케이던스")
                        Spacer()
                        Text(session.watch.watchCadenceRPM.map { "\($0) rpm" } ?? "수신 대기")
                            .foregroundColor(session.watch.watchCadenceRPM != nil ? Theme.green : .secondary)
                    }
                }
                Section {
                    HStack { Text("버전"); Spacer(); Text("1.0").foregroundColor(.secondary) }
                    HStack { Text("디자인"); Spacer(); Text("Designed by Jaisung NOH MD 2026").foregroundColor(.secondary) }
                } footer: {
                    Text("데이터 가져오기·기록 통합 정리는 Routes(라이딩 기록) 첫 페이지의 ⤓ 메뉴로 옮겼습니다. 속도·케이던스는 워치에 페어링한 BLE 센서만 사용합니다.")
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.0f %@", value, session.unit.distanceLabel)).foregroundColor(Theme.purple)
        }
    }
}

#if DEBUG
#Preview {
    MoreView()
        .environmentObject(RideSession.preview)
        .preferredColorScheme(.dark)
}
#endif
