import SwiftUI
import UIKit

/// 대시보드 빈 값 표시(막대 1개).
enum MetricDash {
    static let symbol = "–"
}

/// 워치 BLE 센서 연결 표시(녹색=연결, 주황=대기 깜박임).
enum SensorLinkStatus {
    case connected
    case waiting
}

private struct SensorLinkDot: View {
    let status: SensorLinkStatus
    @State private var blinkOn = true

    var body: some View {
        Circle()
            .fill(status == .connected ? Theme.green : Color.orange)
            .frame(width: 7, height: 7)
            .opacity(status == .connected ? 1 : (blinkOn ? 1 : 0.2))
            .onAppear { restartBlinkIfNeeded() }
            .onChange(of: status) { _, _ in restartBlinkIfNeeded() }
    }

    private func restartBlinkIfNeeded() {
        blinkOn = true
        guard status == .waiting else { return }
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            blinkOn = false
        }
    }
}

/// 대시보드 셀 하나: 고정 크기 라벨 + 가용 공간을 채우는 데이터 값(+ 단위/보조값).
struct MetricCell: View {
    @Environment(\.dashboardLayout) private var layout

    let label: String
    let value: String
    /// 행마다 흰색·노란색을 번갈아 적용(짝수=흰색, 홀수=노란색). 같은 행의 모든 열에 동일 값.
    var rowIndex: Int = 0
    /// 첫 열 하단 단위(km/h, bpm, rpm, km 등).
    var unit: String? = nil
    var subvalue: String? = nil
    /// 값 뒤에 붙는 단위(%, km 등) — unit 과 동시 사용하지 않는다.
    var valueSuffix: String? = nil
    var valueSuffixSmall: Bool = true
    var fixedValueFontSize: CGFloat? = nil
    var sensorStatus: SensorLinkStatus? = nil
    /// 행 기본색(흰/금) 대신 지표별 강조색을 쓸 때(예: HR=red).
    var valueColorOverride: Color? = nil
    /// Distance·Speed·HR 등 주요 지표 값 굵기.
    var valueFontWeight: Font.Weight = .semibold

    private var valueColor: Color {
        valueColorOverride ?? (rowIndex.isMultiple(of: 2) ? Theme.value : Theme.gold)
    }

    /// Month 열 기준으로 같은 행에 쓸 값 글자 크기를 계산한다.
    static func fittedValueFontSize(
        value: String,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        weight: UIFont.Weight = .semibold
    ) -> CGFloat {
        var lo: CGFloat = 8
        var hi = maxHeight
        while hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            if fits(value: value, fontSize: mid, maxWidth: maxWidth, maxHeight: maxHeight, weight: weight) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return lo
    }

    private static func fits(
        value: String,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        weight: UIFont.Weight = .semibold
    ) -> Bool {
        let valueFont = metricUIFont(fontSize, weight: weight)
        let valueWidth = (value as NSString).size(withAttributes: [.font: valueFont]).width
        let lineHeight = valueFont.lineHeight
        return valueWidth <= maxWidth && lineHeight <= maxHeight
    }

    private static func metricUIFont(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    var body: some View {
        GeometryReader { geo in
            let labelHeight = layout.labelFont * 1.2
            let footerHeight = layout.unitFont * 1.2
            let valueHeight = max(geo.size.height - labelHeight - footerHeight - 2, 10)
            let valueWidth = max(geo.size.width - 4, 10)

            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    if let sensorStatus {
                        SensorLinkDot(status: sensorStatus)
                    }
                    Text(label.uppercased())
                        .font(.system(size: layout.labelFont, weight: .semibold))
                        .foregroundColor(Theme.label)
                        .tracking(0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .frame(height: labelHeight)

                valueBlock(valueHeight: valueHeight, valueWidth: valueWidth)

                footerLine
                    .frame(height: footerHeight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func valueBlock(valueHeight: CGFloat, valueWidth: CGFloat) -> some View {
        let fontSize = fixedValueFontSize ?? valueHeight
        let isDash = value == MetricDash.symbol
        return HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(value)
                .font(Theme.metricFont(isDash ? fontSize * 0.55 : fontSize, weight: valueFontWeight))
            if let valueSuffix {
                Text(valueSuffix)
                    .font(valueSuffixSmall
                          ? .system(size: max(fontSize * 0.38, layout.unitFont), weight: valueFontWeight, design: .rounded)
                          : Theme.metricFont(fontSize, weight: valueFontWeight))
                    .foregroundColor(valueColor)
            }
        }
        .foregroundColor(valueColor)
        .lineLimit(1)
        .minimumScaleFactor(isDash ? 1 : 0.01)
        .allowsTightening(!isDash)
        .frame(width: valueWidth, height: valueHeight)
    }

    @ViewBuilder
    private var footerLine: some View {
        if let unit {
            Text(unit)
                .font(.system(size: layout.unitFont, weight: .medium))
                .foregroundColor(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if let subvalue {
            Text(subvalue)
                .font(.system(size: layout.unitFont, weight: .medium))
                .foregroundColor(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text(" ")
                .font(.system(size: layout.unitFont))
        }
    }
}
