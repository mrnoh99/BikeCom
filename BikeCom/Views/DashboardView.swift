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
                statusRow(layout)
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
            Text("이 라이딩은 10분 미만입니다. Health·캘린더·파일에 저장할까요?")
        }
        // 저장 완료 확인(Health·캘린더·파일 3가지)
        .sheet(item: $session.saveProgress) { _ in
            RideSaveProgressView()
                .environmentObject(session)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
        .frame(maxWidth: .infinity, minHeight: layout.chipFont + layout.chipVPadding * 2 + 4)
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
                Button(name) { session.selectBike(name) }   // 등록된 휠 규격 자동 적용
            }
            Divider()
            Button("직접 입력…") { showSettings = true }
        } label: {
            pulldownChip(session.bikeName, layout: layout)
        }
    }

    // 메트릭 그리드 — 8행이 남은 높이를 균등 분배(스크롤 없음).
    private func grid(_ layout: DeviceLayout.Dashboard) -> some View {
        let dash = MetricDash.symbol
        // 그리드 전체를 TimelineView 로 감싸 1초마다 스스로 갱신한다. 라이브 값(거리·시간·
        // 등반)이 @Published 가 아니므로 session 재렌더에 의존하지 않는다 → Routes·More 는
        // 0.5초 tick 에 재렌더되지 않는다(재렌더는 주행 화면에만 한정).
        return TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let cadConnected = session.cadenceSensorConnected
            let hrConnected = session.watch.heartRateConnected
            VStack(spacing: 0) {
            metricRow {
                MetricCell(label: "Clock", value: clockFormatter.string(from: ctx.date).prefix5,
                           rowIndex: 0)
                MetricCell(label: "Distance", value: fmt(session.displayDistance, 2),
                           rowIndex: 0, unit: session.unit.distanceLabel,
                           valueFontWeight: .bold)
            }
            divider
            metricRow {
                MetricCell(label: "Speed",
                           value: fmt(session.displaySpeed, 2),
                           rowIndex: 1,
                           unit: session.unit.speedLabel,
                           sensorStatus: session.speedSensorConnected ? .connected : .waiting,
                           valueFontWeight: .bold)
                MetricCell(label: "Average", value: fmt(session.displayAverageSpeed, 2),
                           rowIndex: 1, unit: session.unit.speedLabel)
            }
            divider
            metricRow {
                MetricCell(label: "Ride", value: formatDuration(session.movingSeconds),
                           rowIndex: 2, subvalue: formatDuration(session.rideSeconds))
                MetricCell(label: "Total", value: formatDuration(session.totalSeconds),
                           rowIndex: 2)
            }
            divider
            metricRow {
                MetricCell(label: "HR",
                           value: hrConnected ? (session.heartRate.map(String.init) ?? dash) : dash,
                           rowIndex: 3, unit: "bpm",
                           sensorStatus: hrConnected ? .connected : .waiting,
                           valueColorOverride: Theme.red,
                           valueFontWeight: .bold)
                MetricCell(label: "Mean",
                           value: session.avgHeartRate.map(String.init) ?? dash,
                           rowIndex: 3, unit: "bpm",
                           valueColorOverride: Theme.red)
                MetricCell(label: "Max",
                           value: session.maxHeartRate.map(String.init) ?? dash,
                           rowIndex: 3, unit: "bpm",
                           valueColorOverride: Theme.red)
            }
            divider
            metricRow {
                MetricCell(label: "Cad",
                           value: cadConnected ? (session.cadence.map(String.init) ?? dash) : dash,
                           rowIndex: 4, unit: "rpm",
                           sensorStatus: cadConnected ? .connected : .waiting)
                MetricCell(label: "Mean",
                           value: session.avgCadence.map(String.init) ?? dash,
                           rowIndex: 4, unit: "rpm")
                MetricCell(label: "Max",
                           value: session.maxCadence.map(String.init) ?? dash,
                           rowIndex: 4, unit: "rpm")
            }
            divider
            metricRow {
                MetricCell(label: "Climb", value: fmt(session.elevationGainMeters, 0),
                           rowIndex: 5, unit: "m")
                MetricCell(label: "SpO2",
                           value: session.spo2Percent.map(String.init) ?? dash,
                           rowIndex: 5,
                           subvalue: session.spo2Percent != nil ? (session.spo2LatestTimeText ?? " ") : " ",
                           valueSuffix: session.spo2Percent != nil ? "%" : nil)
            }
            divider
            distanceStatsRow(layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, layout.gridHPadding)
        }
    }

    // Month·Year·Total — km 단위는 값 아래 작은 글씨.
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
            let fitted = MetricCell.fittedValueFontSize(
                value: month,
                maxWidth: colWidth,
                maxHeight: valueHeight
            )
            let fontSize = fitted * 0.82   // 누적 거리 행은 다른 행보다 약간 작게

            HStack(spacing: 0) {
                MetricCell(label: "Month", value: month, rowIndex: 6,
                           unit: unit, fixedValueFontSize: fontSize)
                MetricCell(label: "Year", value: year, rowIndex: 6,
                           unit: unit, fixedValueFontSize: fontSize)
                MetricCell(label: "Total", value: total, rowIndex: 6,
                           unit: unit, fixedValueFontSize: fontSize)
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

    // Start 버튼 위 얇은 상태 줄 — GPS/HR/CD 연결등 + 시계/폰 선택. (다른 줄의 ~절반 높이)
    private func statusRow(_ layout: DeviceLayout.Dashboard) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 12) {
                statusIcon("location.fill", "GPS", gpsColor)
                statusDot("HR", hrDotColor)
                statusDot("SPD", spdDotColor)
                statusDot("CD", cdDotColor)
                Spacer(minLength: 0)
                // 시계/폰 선택 — 탭=모드 전환(상대 경로 BLE/워치 중계 상호 배타). 길게 누르면 Devices.
                Button {
                    session.sensorMode = (session.sensorMode == .phone) ? .watch : .phone
                } label: {
                    Image(systemName: session.sensorMode == .phone ? "iphone" : "applewatch")
                        .font(.system(size: layout.footerFont + 6, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(session.sensorMode == .phone ? Theme.green.opacity(0.85)
                                                                                : Theme.blue.opacity(0.85)))
                }
                .onLongPressGesture(minimumDuration: 0.4) { dest = .devices }
            }
            .frame(height: max(layout.controlHeight * 0.6, 28))
            .padding(.horizontal, layout.headerHPadding)
        }
    }

    private func statusDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            // 애플워치 연결등과 동일한 크기(22px).
            Circle().fill(color).frame(width: 22, height: 22)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.label)
        }
    }

    /// GPS 는 점 대신 GPS 아이콘으로 표시(신호 정확도 색).
    private func statusIcon(_ symbol: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.label)
        }
    }

    /// 연결안됨=회색, 워치연결=파랑, 폰연결=초록.
    private var hrDotColor: Color {
        session.watch.heartRateConnected ? Theme.red : Color.gray
    }
    private var spdDotColor: Color {
        switch session.sensorMode {
        case .phone:
            return session.ble.speedConnected ? Theme.green : Color.gray
        case .watch:
            return session.watch.speedSensorConnected ? Theme.blue : Color.gray
        }
    }
    private var cdDotColor: Color {
        switch session.sensorMode {
        case .phone:
            return session.ble.cadenceConnected ? Theme.green : Color.gray
        case .watch:
            return session.watch.cadenceSensorConnected ? Theme.blue : Color.gray
        }
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
                // 설정 아이콘 크게 + 폭 확대 → Start 버튼 폭은 조금 줄어든다.
                Image(systemName: "gearshape.fill")
                    .font(.system(size: layout.gearIcon * 1.5, weight: .semibold))
                    .foregroundColor(Theme.gold)
                    .frame(width: layout.gearIcon * 1.5 + 24, height: layout.controlHeight)
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

    // 하단 크레딧(가운데 정렬). GPS 표시는 상단 상태 줄로 이동했다.
    private func gpsBar(_ layout: DeviceLayout.Dashboard) -> some View {
        Text("Developed by JaiSung NOH MD 2026")
            .font(.system(size: layout.footerFont))
            .foregroundColor(Theme.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
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
