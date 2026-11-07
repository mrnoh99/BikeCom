import SwiftUI

/// 폭보다 긴 한 줄 텍스트를 왼쪽으로만 흐르듯 보여준다(티커 방식). 폭에 다 들어가면 고정 표시.
/// 끝까지 흐른 뒤에는 시작 위치로 즉시 돌아가고, 다시 흐르기 전 `pauseSeconds` 만큼 멈춰 있는다.
struct MarqueeText: View {
    let text: String
    var font: Font
    var color: Color = .primary
    /// 줄 높이(폰트 크기 기반) — GeometryReader 가 세로로 무한정 늘어나지 않도록 명시적으로 준다.
    var lineHeight: CGFloat
    /// 처음 시작 전, 그리고 한 바퀴 돌아 시작 위치로 돌아올 때마다 멈춰 있는 시간(초).
    var pauseSeconds: Double = 4

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var loopTask: Task<Void, Never>?

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
                            .onChange(of: inner.size.width) { _, w in textWidth = w; restartLoop() }
                    }
                )
                // 폭에 다 들어가면(overflow == 0) 가운데 정렬, 흘러야 하면(overflow > 0)
                // 왼쪽 끝에서 시작해 거기서부터 음수로 offset 을 줘 왼쪽으로 흐르게 한다.
                .frame(width: outer.size.width, alignment: overflow > 0 ? .leading : .center)
                .offset(x: offset)
                .onAppear {
                    containerWidth = outer.size.width
                    restartLoop()
                }
                .onDisappear { loopTask?.cancel() }
                .onChange(of: outer.size.width) { _, w in containerWidth = w; restartLoop() }
                .onChange(of: text) { _, _ in restartLoop() }
        }
        .frame(height: lineHeight)
        .clipped()
    }

    /// 기존 루프를 취소하고 처음(멈춤 → 왼쪽으로 흐름 → 즉시 복귀)부터 다시 시작한다.
    /// 텍스트나 폭이 바뀌어 overflow 가 달라질 때마다(onChange) 호출돼 항상 최신 값으로 돈다.
    private func restartLoop() {
        loopTask?.cancel()
        offset = 0
        let distance = overflow
        guard distance > 0 else { return }
        let duration = Double(distance) / 28
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pauseSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: duration)) {
                    offset = -distance
                }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                offset = 0   // 애니메이션 없이 즉시 시작 위치로 복귀
            }
        }
    }
}
