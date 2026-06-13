import SwiftUI

/// ⚙️ 메뉴로 이동하는 화면들.
enum DashDestination: String, Identifiable {
    case map, routes, devices, more
    var id: String { rawValue }
}

/// 메인(Stopwatch) 대시보드 — 스크린샷 IMG_4260 재현.
struct DashboardView: View {
    @EnvironmentObject var session: RideSession
    @State private var showSettings = false
    @State private var showAddCourse = false
    @State private var newCourseName = ""
    @State private var dest: DashDestination?

    private let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        GeometryReader { geo in
            let layout = DeviceLayout.Dashboard.make(for: geo.size)
            VStack(spacing: 0) {
                header(layout)
                grid(layout)
                controls(layout)
                gpsBar(layout)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .environment(\.dashboardLayout, layout)
        }
        .background(Theme.background)
        .navigationDestination(item: $dest) { d in
            switch d {
            case .map: MapTabView()
            case .routes: RoutesView()
            case .devices: DevicesView()
            case .more: MoreView()
            }
        }
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
        // 10분 미만 라이딩: 저장/삭제 선택
        .alert("10분 미만 라이딩", isPresented: Binding(
            get: { session.pendingShortRide != nil },
            set: { _ in })) {
            Button("저장") { session.savePendingRide() }
            Button("삭제", role: .destructive) { session.discardPendingRide() }
        } message: {
            Text("이 라이딩은 10분 미만입니다. 건강·캘린더·파일에 저장할까요?")
        }
        // 저장 완료 확인(건강·캘린더·파일 3가지)
        .alert("저장 완료", isPresented: Binding(
            get: { session.saveSummary != nil },
            set: { if !$0 { session.saveSummary = nil } })) {
            Button("확인") { session.saveSummary = nil }
        } message: {
            Text(session.saveSummary ?? "")
        }
    }

    // 상단 라벨 칩 (코스 풀다운 / 자전거 종류 풀다운)
    private func header(_ layout: DeviceLayout.Dashboard) -> some View {
        HStack(spacing: 8) {
            courseMenu(layout)
                .frame(maxWidth: .infinity)
            bikeMenu(layout)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, layout.headerHPadding)
        .padding(.top, layout.headerTopPadding)
        .padding(.bottom, layout.headerBottomPadding)
    }

    // 풀다운 칩 — 375pt 폭에서 양쪽이 반씩 나뉘도록 축소 허용.
    private func pulldownChip(_ text: String, layout: DeviceLayout.Dashboard) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(size: layout.chipFont, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Image(systemName: "chevron.down")
                .font(.system(size: layout.chipFont - 2, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, layout.chipHPadding)
        .padding(.vertical, layout.chipVPadding)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color(white: 0.14)))
    }

    private func courseMenu(_ layout: DeviceLayout.Dashboard) -> some View {
        Menu {
            ForEach(session.courses, id: \.self) { course in
                Button(course) { session.routeName = course }
            }
            Divider()
            Button("코스 추가…", systemImage: "plus") { newCourseName = ""; showAddCourse = true }
        } label: {
            pulldownChip(session.routeName, layout: layout)
        }
    }

    private func bikeMenu(_ layout: DeviceLayout.Dashboard) -> some View {
        Menu {
            ForEach(RideSession.bikePresets, id: \.self) { name in
                Button(name) { session.bikeName = name }
            }
            Divider()
            Button("직접 입력…") { showSettings = true }
        } label: {
            pulldownChip(session.bikeName, layout: layout)
        }
    }

    // 메트릭 그리드 — 8행이 남은 높이를 균등 분배(스크롤 없음).
    private func grid(_ layout: DeviceLayout.Dashboard) -> some View {
        VStack(spacing: 0) {
            metricRow {
                MetricCell(label: "Clock", value: clockFormatter.string(from: session.clock).prefix5,
                           color: Theme.value)
                MetricCell(label: "Distance", value: fmt(session.displayDistance, 2),
                           color: Theme.gold)
            }
            divider
            metricRow {
                MetricCell(label: "Speed", value: fmt(session.displaySpeed, 2),
                           unit: session.unit.speedLabel,
                           sensorStatus: session.watch.speedSensorConnected ? .connected : .waiting,
                           color: Theme.blue)
                MetricCell(label: "Average", value: fmt(session.displayAverageSpeed, 2),
                           color: Theme.value)
            }
            divider
            metricRow {
                MetricCell(label: "Ride", value: formatDuration(session.rideSeconds),
                           subvalue: formatDuration(session.movingSeconds), color: Theme.gold)
                MetricCell(label: "Total", value: formatDuration(session.totalSeconds),
                           color: Theme.gold)
            }
            divider
            metricRow {
                MetricCell(label: "HR", value: session.heartRate.map(String.init) ?? "– – –",
                           unit: "bpm", color: Theme.red)
                MetricCell(label: "Mean", value: session.avgHeartRate.map(String.init) ?? "– – –",
                           color: Theme.red)
                MetricCell(label: "Max", value: session.maxHeartRate.map(String.init) ?? "– – –",
                           color: Theme.red)
            }
            divider
            metricRow {
                MetricCell(label: "Cad", value: session.cadence.map(String.init) ?? "– – –",
                           unit: "rpm",
                           sensorStatus: session.watch.cadenceSensorConnected ? .connected : .waiting,
                           color: Theme.value)
                MetricCell(label: "Mean", value: session.avgCadence.map(String.init) ?? "– – –",
                           color: Theme.value)
                MetricCell(label: "Max", value: session.maxCadence.map(String.init) ?? "– – –",
                           color: Theme.value)
            }
            divider
            metricRow {
                MetricCell(label: "Climb", value: fmt(session.elevationGainMeters, 0),
                           unit: "m", color: Theme.green)
                MetricCell(label: "SpO2",
                           value: session.spo2Percent.map(String.init) ?? "– – –",
                           subvalue: session.spo2LatestTimeText ?? " ",
                           valueSuffix: session.spo2Percent != nil ? "%" : nil,
                           color: Theme.cyan)
            }
            divider
            distanceStatsRow(layout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, layout.gridHPadding)
    }

    // Month 거리 글자 크기에 Year·Total 을 맞추고, km 는 작은 글씨.
    private func distanceStatsRow(_ layout: DeviceLayout.Dashboard) -> some View {
        let month = fmt(session.thisMonthDistance, 0)
        let year = fmt(session.thisYearDistance, 0)
        let total = fmt(session.totalDistance, 0)
        let unit = session.unit.distanceLabel

        return GeometryReader { geo in
            let labelHeight = layout.labelFont * 1.2
            let footerHeight = layout.unitFont * 1.2
            let valueHeight = max(geo.size.height - labelHeight - footerHeight - 2, 10)
            let colWidth = max(geo.size.width / 3 - 4, 10)
            let fontSize = MetricCell.fittedValueFontSize(
                value: month,
                suffix: " \(unit)",
                suffixSmall: true,
                maxWidth: colWidth,
                maxHeight: valueHeight,
                unitFont: layout.unitFont
            )

            HStack(spacing: 0) {
                MetricCell(label: "Month", value: month,
                           valueSuffix: " \(unit)",
                           fixedValueFontSize: fontSize,
                           color: Theme.purple)
                MetricCell(label: "Year", value: year,
                           fixedValueFontSize: fontSize,
                           color: Theme.purple)
                MetricCell(label: "Total", value: total,
                           fixedValueFontSize: fontSize,
                           color: Theme.purple)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.horizontal, 8)
    }

    // Start / Done 버튼 + 설정 기어
    private func controls(_ layout: DeviceLayout.Dashboard) -> some View {
        HStack(spacing: 10) {
            Button(action: { session.start() }) {
                Text(startLabel)
                    .font(.system(size: layout.controlFont, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.controlHeight)
                    .background(Capsule().fill(startColor))
            }
            if session.state == .paused {
                Button(action: { session.finish() }) {
                    Text("Done")
                        .font(.system(size: layout.controlFont, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: layout.controlHeight)
                        .background(Capsule().fill(Theme.gray))
                }
            }

            Menu {
                Button { dest = .map } label: { Label("지도", systemImage: "map") }
                Button { dest = .routes } label: { Label("라이딩 기록", systemImage: "folder") }
                Button { dest = .devices } label: { Label("장치", systemImage: "dot.radiowaves.left.and.right") }
                Button { dest = .more } label: { Label("더보기 · 가져오기", systemImage: "ellipsis.circle") }
                Divider()
                Button { showSettings = true } label: { Label("라이딩 설정", systemImage: "slider.horizontal.3") }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: layout.gearIcon))
                    .foregroundColor(Theme.gold)
                    .frame(width: layout.gearIcon + 8, height: layout.controlHeight)
            }
        }
        .padding(.horizontal, layout.headerHPadding)
        .padding(.vertical, layout.controlVPadding)
    }

    private var startLabel: String {
        switch session.state {
        case .idle: return "Start"
        case .running: return "Stop"
        case .paused: return "Start"
        }
    }

    private var startColor: Color {
        session.state == .running ? Theme.red : Theme.green
    }

    // GPS 정확도 표시줄
    private func gpsBar(_ layout: DeviceLayout.Dashboard) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: layout.footerFont + 1))
                .foregroundColor(gpsColor)
            Text("GPS")
                .font(.system(size: layout.footerFont + 1, weight: .semibold))
                .foregroundColor(Theme.label)
            Spacer()
            Text("Developed by JaiSung NOH MD 2026")
                .font(.system(size: layout.footerFont))
                .foregroundColor(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, layout.headerHPadding)
        .padding(.bottom, 2)
    }

    private var gpsColor: Color {
        let acc = session.location.horizontalAccuracy
        if acc < 0 { return Theme.gray }
        if acc <= 10 { return Theme.green }
        if acc <= 30 { return Theme.gold }
        return Theme.red
    }

    private func fmt(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v)
    }
}

private extension String {
    /// "HH:mm:ss" → "HH:mm" (스크린샷의 시계 표기)
    var prefix5: String { String(prefix(5)) }
}

#if DEBUG
#Preview("iPhone 12 mini") {
    DashboardView()
        .environmentObject(RideSession.preview)
        .preferredColorScheme(.dark)
        .previewDevice(PreviewDevice(rawValue: "iPhone 12 mini"))
}
#endif
