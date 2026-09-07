import SwiftUI

/// A single line of text that scrolls left-and-back when it's wider than
/// `maxWidth`, instead of being cut off with an ellipsis. Sits at its full
/// width and hugs short content when there's nothing to scroll.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let maxWidth: CGFloat
    var speed: Double = 34

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var generation = 0

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: MarqueeWidthKey.self, value: geo.size.width)
                }
            )
            .offset(x: -offset)
            .onPreferenceChange(MarqueeWidthKey.self) { width in
                guard abs(width - textWidth) > 0.5 else { return }
                textWidth = width
                restart()
            }
            .frame(width: min(textWidth == 0 ? maxWidth : textWidth, maxWidth), alignment: .leading)
            .clipped()
            .onAppear { restart() }
            .onChange(of: text) { _, _ in restart() }
    }

    private func restart() {
        generation += 1
        let myGeneration = generation
        offset = 0

        let overflow = textWidth - maxWidth
        guard overflow > 1 else { return }
        let duration = max(Double(overflow) / speed, 1.2)

        func cycle() {
            guard myGeneration == generation else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                guard myGeneration == generation else { return }
                withAnimation(.linear(duration: duration)) { offset = overflow }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.3) {
                    guard myGeneration == generation else { return }
                    withAnimation(.linear(duration: duration)) { offset = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        cycle()
                    }
                }
            }
        }
        cycle()
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
