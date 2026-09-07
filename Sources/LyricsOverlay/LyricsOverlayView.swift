import SwiftUI
import Translation

@MainActor
struct LyricsOverlayView: View {
    @ObservedObject var viewModel: LyricsViewModel

    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isExpanded = false

    var body: some View {
        Group {
            if isExpanded {
                expandedPanel
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
            } else {
                compactPill
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: isExpanded)
        .onHover { hovering in
            isExpanded = hovering
        }
        .onChange(of: viewModel.currentLine) { _, newValue in
            requestTranslation(for: newValue)
        }
        .translationTask(translationConfig) { session in
            let text = viewModel.currentLine
            guard !text.isEmpty, !containsCJK(text) else { return }
            do {
                let response = try await session.translate(text)
                if text == viewModel.currentLine {
                    viewModel.translation = response.targetText
                }
            } catch {
                // Translation unavailable (language pack not installed, etc). Fail silently.
            }
        }
    }

    /// Default, always-visible state: small footprint like the pill concept,
    /// but keeps the translation visible underneath the current line rather
    /// than hiding it behind hover — translation is the point, not an extra.
    private var compactPill: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(Color(red: 0.91, green: 0.7, blue: 0.37))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .shadow(color: Color(red: 0.91, green: 0.7, blue: 0.37).opacity(0.7), radius: 4)

            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(
                    text: pillText,
                    font: .system(size: 18, weight: .medium),
                    color: .white,
                    maxWidth: 400
                )

                if !viewModel.translation.isEmpty {
                    MarqueeText(
                        text: viewModel.translation,
                        font: .system(size: 16, weight: .medium),
                        color: .white.opacity(0.6),
                        maxWidth: 400
                    )
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 15))
        .fixedSize(horizontal: true, vertical: true)
        .background(glassBackground(cornerRadius: 14))
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = viewModel.trackTitle {
                MarqueeText(
                    text: viewModel.isApproximateSync ? "\(title) · 歌词无精确时间轴，为估算同步" : title,
                    font: .system(size: 12, weight: .medium),
                    color: .white.opacity(0.55),
                    maxWidth: 560
                )
            }

            Text(displayLine)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .lineLimit(2)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.2), value: viewModel.currentLine)

            if !viewModel.translation.isEmpty {
                Text(viewModel.translation)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !viewModel.nextLine.isEmpty {
                MarqueeText(
                    text: viewModel.nextLine,
                    font: .system(size: 14),
                    color: .white.opacity(0.35),
                    maxWidth: 560
                )
            }
        }
        .padding(EdgeInsets(top: 15, leading: 19, bottom: 15, trailing: 19))
        .frame(minWidth: 280, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(glassBackground(cornerRadius: 16))
    }

    private func glassBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.black.opacity(0.55))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var pillText: String {
        if viewModel.trackTitle == nil {
            return "未在播放 Apple Music"
        }
        if viewModel.hasNoLyrics {
            return viewModel.trackTitle ?? "未找到歌词"
        }
        return viewModel.currentLine.isEmpty ? (viewModel.trackTitle ?? "♪") : viewModel.currentLine
    }

    private var displayLine: String {
        if viewModel.trackTitle == nil {
            return "未在播放 Apple Music"
        }
        if viewModel.hasNoLyrics {
            return "未找到歌词"
        }
        return viewModel.currentLine.isEmpty ? "♪" : viewModel.currentLine
    }

    private func requestTranslation(for text: String) {
        guard !text.isEmpty, !containsCJK(text) else {
            viewModel.translation = ""
            return
        }
        // Source is pinned to English rather than left to auto-detect (nil):
        // short slang/ad-libs (common in hip-hop lyrics) are too ambiguous
        // for on-device language ID, and an unspecified source makes the
        // system pop up a "confirm language" prompt asking the user to pick
        // one. Everything reaching here already passed the containsCJK
        // filter, so English is the overwhelmingly common case anyway.
        if translationConfig == nil {
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        } else {
            translationConfig?.invalidate()
        }
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value)
        }
    }
}
