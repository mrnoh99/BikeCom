import SwiftUI
import UIKit

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
    /// 첫 열 하단 단위(km/h, bpm, rpm 등).
    var unit: String? = nil
    var subvalue: String? = nil
    /// 값 뒤에 붙는 단위(%, km 등).
    var valueSuffix: String? = nil
    /// true 이면 값보다 작은 글씨(예: %, km).
    var valueSuffixSmall: Bool = true
    /// 지정 시 자동 확대 대신 고정 글자 크기(마지막 줄 Year·Total 등).
    var fixedValueFontSize: CGFloat? = nil
    /// Speed·Cad 첫 열: 워치 센서 연결 상태 점.
    var sensorStatus: SensorLinkStatus? = nil
    var color: Color = Theme.value

    /// Month 열 기준으로 같은 행에 쓸 값 글자 크기를 계산한다.
    static func fittedValueFontSize(
        value: String,
        suffix: String?,
        suffixSmall: Bool,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        unitFont: CGFloat
    ) -> CGFloat {
        var lo: CGFloat = 8
        var hi = maxHeight
        while hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            if fits(value: value, suffix: suffix, suffixSmall: suffixSmall,
                    fontSize: mid, maxWidth: maxWidth, maxHeight: maxHeight, unitFont: unitFont) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return lo
    }

    private static func fits(
        value: String,
        suffix: String?,
        suffixSmall: Bool,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        unitFont: CGFloat
    ) -> Bool {
        let valueFont = metricUIFont(fontSize)
        let valueWidth = (value as NSString).size(withAttributes: [.font: valueFont]).width
        var suffixWidth: CGFloat = 0
        if let suffix {
            let suffixSize = suffixSmall ? max(fontSize * 0.38, unitFont) : fontSize
            suffixWidth = (suffix as NSString).size(withAttributes: [.font: metricUIFont(suffixSize)]).width + 1
        }
        let lineHeight = valueFont.lineHeight
        return valueWidth + suffixWidth <= maxWidth && lineHeight <= maxHeight
    }

    private static func metricUIFont(_ size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .semibold)
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
        return HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(value)
                .font(Theme.metricFont(fontSize))
            if let valueSuffix {
                Text(valueSuffix)
                    .font(valueSuffixSmall
                          ? .system(size: max(fontSize * 0.38, layout.unitFont), weight: .semibold, design: .rounded)
                          : Theme.metricFont(fontSize))
                    .foregroundColor(color)
            }
        }
        .foregroundColor(color)
        .lineLimit(1)
        .minimumScaleFactor(0.01)
        .allowsTightening(true)
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
