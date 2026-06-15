import SwiftUI

/// 라이딩 설정 시트 — 취소/저장으로 변경 사항을 확정하거나 취소한다.
struct RideSettingsSheet: View {
    @EnvironmentObject var session: RideSession
    @Environment(\.dismiss) private var dismiss
    @Binding var showAddCourse: Bool
    @Binding var newCourseName: String

    @State private var routeName = ""
    @State private var bikeName = ""
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
                    Text("속도 센서 — \(bikeName.isEmpty ? "자전거" : bikeName) 휠")
                } footer: {
                    Text("자전거마다 휠 규격을 저장합니다. 다음에 이 자전거를 선택하면 휠 둘레가 자동 적용됩니다. 둘레 = π × 직경으로 속도·거리를 환산합니다.")
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
            // 자전거를 바꾸면 그 자전거에 저장된 휠 규격으로 선택을 맞춘다.
            .onChange(of: bikeName) { _, newName in
                let key = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = session.wheelOptionId(forBike: key) { selectedWheelId = id }
            }
        }
    }

    private func loadDraft() {
        routeName = session.routeName
        bikeName = session.bikeName
        // 현재 자전거에 저장된 휠이 있으면 그것을, 없으면 현재 둘레에 가장 가까운 규격.
        selectedWheelId = session.wheelOptionId(forBike: session.bikeName)
            ?? WheelPresets.nearest(toCircumferenceMeters: session.wheelCircumferenceMeters).id
    }

    private func saveAndDismiss() {
        session.routeName = routeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? session.routeName : routeName
        let bike = bikeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if bike.isEmpty {
            session.wheelCircumferenceMeters = selectedWheel.circumferenceMeters
        } else {
            session.selectBike(bike)                              // 자전거 선택
            session.setWheel(optionId: selectedWheelId, forBike: bike)  // 휠 등록 + 즉시 적용
        }
        session.saveSettings()
        dismiss()
    }
}
