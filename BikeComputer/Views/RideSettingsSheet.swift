import SwiftUI

/// 라이딩 설정 시트 — 취소/저장으로 변경 사항을 확정하거나 취소한다.
struct RideSettingsSheet: View {
    @EnvironmentObject var session: RideSession
    @Environment(\.dismiss) private var dismiss
    @Binding var showAddCourse: Bool
    @Binding var newCourseName: String

    @State private var routeName = ""
    @State private var bikeName = ""
    @State private var autoPauseEnabled = true
    @State private var autoPauseThresholdKmh = 2.5
    @State private var autoPauseDelay = 3.0
    @State private var selectedWheelId = WheelPresets.defaultOptionId

    private var selectedWheel: WheelPresets.Option {
        WheelPresets.option(id: selectedWheelId)
            ?? WheelPresets.option(id: WheelPresets.defaultOptionId)!
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("라이딩 이름", text: $routeName)
                }
                Section("코스") {
                    ForEach(session.courses, id: \.self) { course in
                        Button {
                            routeName = course
                        } label: {
                            HStack {
                                Text(course).foregroundColor(.primary)
                                Spacer()
                                if routeName == course {
                                    Image(systemName: "checkmark").foregroundColor(Theme.gold)
                                }
                            }
                        }
                    }
                    .onDelete { session.removeCourse(at: $0) }
                    Button("코스 추가…", systemImage: "plus") {
                        newCourseName = ""
                        showAddCourse = true
                    }
                }
                Section("자전거 종류") {
                    Menu {
                        ForEach(RideSession.bikePresets, id: \.self) { name in
                            Button(name) { bikeName = name }
                        }
                    } label: {
                        HStack {
                            Text("종류 선택")
                            Spacer()
                            Text(bikeName).foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down").foregroundColor(.secondary)
                        }
                    }
                    TextField("직접 입력", text: $bikeName)
                }
                Section("자동 일시정지") {
                    Toggle("바퀴 멈추면 자동 일시정지", isOn: $autoPauseEnabled)
                    if autoPauseEnabled {
                        HStack {
                            Text("임계 속도")
                            Spacer()
                            Text("\(autoPauseThresholdKmh, specifier: "%.1f") km/h")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $autoPauseThresholdKmh, in: 1...10, step: 0.5)
                        HStack {
                            Text("지연 시간")
                            Spacer()
                            Text("\(Int(autoPauseDelay))초").foregroundColor(.secondary)
                        }
                        Slider(value: $autoPauseDelay, in: 1...10, step: 1)
                    }
                    Text("바퀴가 임계 속도 미만으로 지연 시간만큼 멈추면 자동 일시정지되고, 다시 구르면 자동 재개됩니다.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section {
                    HStack {
                        Text("휠 직경")
                        Spacer()
                        Text("\(selectedWheel.diameterMm, specifier: "%.0f") mm")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("계산된 둘레")
                        Spacer()
                        Text("\(selectedWheel.circumferenceMm, specifier: "%.0f") mm")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("속도 센서")
                } footer: {
                    Text("일반 휠 규격을 선택합니다. 둘레 = π × 직경으로 속도·거리를 환산합니다.")
                }
                ForEach(WheelPresets.categories) { category in
                    Section(category.title) {
                        ForEach(category.options) { option in
                            Button {
                                selectedWheelId = option.id
                            } label: {
                                HStack {
                                    Text(option.label).foregroundColor(.primary)
                                    Spacer()
                                    if selectedWheelId == option.id {
                                        Image(systemName: "checkmark").foregroundColor(Theme.gold)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("라이딩 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { saveAndDismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadDraft)
        }
    }

    private func loadDraft() {
        routeName = session.routeName
        bikeName = session.bikeName
        autoPauseEnabled = session.autoPauseEnabled
        autoPauseThresholdKmh = session.autoPauseThresholdMps * 3.6
        autoPauseDelay = session.autoPauseDelay
        selectedWheelId = WheelPresets.nearest(
            toCircumferenceMeters: session.wheelCircumferenceMeters
        ).id
    }

    private func saveAndDismiss() {
        session.routeName = routeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? session.routeName : routeName
        session.bikeName = bikeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? session.bikeName : bikeName
        session.autoPauseEnabled = autoPauseEnabled
        session.autoPauseThresholdMps = autoPauseThresholdKmh / 3.6
        session.autoPauseDelay = autoPauseDelay
        session.wheelCircumferenceMeters = selectedWheel.circumferenceMeters
        session.saveSettings()
        dismiss()
    }
}
