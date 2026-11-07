import SwiftUI

/// 폭보다 긴 한 줄 텍스트를 좌우로 흐르듯 보여준다(마키 효과). 폭에 다 들어가면 그냥 고정 표시.
struct MarqueeText: View {
    let text: String
    var font: Font
    var color: Color = .primary
    /// 줄 높이(폰트 크기 기반) — GeometryReader 가 세로로 무한정 늘어나지 않도록 명시적으로 준다.
    var lineHeight: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var scrolled = false

    private var overflow: CGFloat { max(textWidth - containerWidth, 0) }

    var body: some View {
        GeometryReader { outer in
            Text(text)
                .font(font)
                .foregroundColor(color)
                .fixedSize()
                .background(
                    GeometryReader { inner in
                        Color.clear
                            .onAppear { textWidth = inner.size.width }
                            .onChange(of: inner.size.width) { _, w in textWidth = w }
                    }
                )
                .offset(x: scrolled ? -overflow : 0)
                .animation(
                    overflow > 0
                        ? .linear(duration: Double(overflow) / 28).repeatForever(autoreverses: true).delay(1)
                        : .default,
                    value: scrolled
                )
                .onAppear {
                    containerWidth = outer.size.width
                    if overflow > 0 { scrolled = true }
                }
                .onChange(of: outer.size.width) { _, w in containerWidth = w }
                .onChange(of: overflow) { _, isOver in scrolled = isOver > 0 }
        }
        .frame(height: lineHeight)
        .clipped()
    }
}
