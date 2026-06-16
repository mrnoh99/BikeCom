import SwiftUI

/// 통계·설정 — 라이딩·누적·데이터·진단 등.
struct SettingsExtrasView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        List {
            Section {
                statRow("이번 달", session.thisMonthDistance)
                statRow("올해", session.thisYearDistance)
                statRow("전체", session.totalDistance)
                HStack {
                    Text("총 라이딩 시간")
                    Spacer()
                    Text(formatDuration(session.totalRideTime)).foregroundColor(Theme.gold)
                }
                HStack {
                    Text("총 라이딩 수")
                    Spacer()
                    Text("\(session.store.records.filter { !$0.isCourseOnly }.count)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("누적 통계")
            } footer: {
                Text("총 라이딩 시간은 Cyclemeter(가져온 JSON 기록)와 Apple Health의 사이클링 운동을 시작 시각 기준으로 중복 없이 합산합니다.")
            }
            Section("지도 코스") {
                NavigationLink {
                    CourseManagerView()
                } label: {
                    Label("지도 코스 관리", systemImage: "map")
                }
            }
            dataSourceSection
            Section {
                HStack {
                    Text("워치 세션 복구")
                    Spacer()
                    Text("\(session.watch.watchRecoveryCount)회")
                        .foregroundColor(session.watch.watchRecoveryCount > 0 ? Theme.gold : .secondary)
                }
                if let at = session.watch.watchRecoveryAt {
                    HStack {
                        Text("최근 복구")
                        Spacer()
                        Text(at.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("워치 진단")
            } footer: {
                Text("라이딩 중 워치 앱이 watchOS 에 의해 강제 종료된 뒤 자동 복귀한 누적 횟수입니다(워치가 보고). 장시간 라이딩에서 1~2회는 정상 메모리 관리 범위입니다.")
            }
            Section {
                HStack { Text("버전"); Spacer(); Text("1.0").foregroundColor(.secondary) }
                HStack {
                    Text("개발")
                    Spacer()
                    Text("Developed by JaiSung NOH MD 2026").foregroundColor(.secondary)
                }
            } footer: {
                Text("데이터 가져오기·기록 통합 정리는 라이딩 기록 첫 페이지의 ⤓ 메뉴로 옮겼습니다.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .navigationTitle("통계")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.refreshDataStats() }
    }

    @ViewBuilder private var dataSourceSection: some View {
        if let s = session.dataStats {
            Section {
                kv("Cyclemeter 기본(트랙 포함)", "\(s.cyclemeterBase)개", Theme.green)
                kv("Health 전체(Apple Health)", "\(s.healthTotal)개")
                kv("Health 겹침(제외)", "\(s.healthOverlap)개")
                kv("Health 겹치지 않음", "\(s.healthNonOverlap)개")
                kv("└ 1.5km 이하·속도 0 제외", "\(s.healthExcludedFilter)개", Theme.gold)
                kv("최종 Health 보충", "\(s.healthSupplemented)개", Theme.red)
            } header: {
                Text("데이터 출처 — 기록 수")
            } footer: {
                Text("Health \(s.healthTotal)건 중 겹치지 않는 \(s.healthNonOverlap)건에서, 거리 1.5km 이하·속도 0 인 \(s.healthExcludedFilter)건을 제외해 최종 \(s.healthSupplemented)건을 보충했습니다(겹침 \(s.healthOverlap)건 제외).")
            }
            Section {
                distRow("이번 달", s.healthMonthKm, s.cycMonthKm, s.bothMonthKm)
                distRow("올해", s.healthYearKm, s.cycYearKm, s.bothYearKm)
                distRow("전체", s.healthTotalKm, s.cycTotalKm, s.bothTotalKm)
            } header: {
                Text("거리 — Health / CM / 합계")
            }
            Section {
                firstRow("첫 Health 기록", s.firstHealthDate, s.firstHealthPlace)
                firstRow("첫 Cyclemeter 기록", s.firstCycDate, s.firstCycPlace)
            } header: {
                Text("첫 기록 (날짜·시간·장소)")
            }
        } else {
            Section("데이터 출처") {
                HStack { Text("계산 중…"); Spacer(); ProgressView() }
            }
        }
    }

    private func kv(_ l: String, _ r: String, _ color: Color = .secondary) -> some View {
        HStack { Text(l); Spacer(); Text(r).foregroundColor(color) }
    }

    private func distRow(_ label: String, _ healthKm: Double, _ cycKm: Double, _ bothKm: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Spacer()
            Text("H \(Int(healthKm.rounded()))").foregroundColor(Theme.red)
            Text("/").foregroundColor(.secondary)
            Text("CM \(Int(cycKm.rounded()))").foregroundColor(Theme.green)
            Text("/").foregroundColor(.secondary)
            Text("합계 \(Int(bothKm.rounded())) km").foregroundColor(Theme.purple)
        }.font(.callout)
    }

    private func firstRow(_ label: String, _ date: Date?, _ place: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline)
            if let date {
                Text("\(Self.dateFmt.string(from: date))" + (place.isEmpty ? "" : " · \(place)"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("기록 없음").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()

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
    NavigationStack {
        SettingsExtrasView()
            .environmentObject(RideSession.preview)
    }
    .preferredColorScheme(.dark)
}
#endif
