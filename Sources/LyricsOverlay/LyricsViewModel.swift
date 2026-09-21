import Combine
import Foundation

final class LyricsViewModel: ObservableObject {
    @Published var trackTitle: String?
    @Published var currentLine: String = ""
    @Published var nextLine: String = ""
    @Published var translation: String = ""
    @Published var isPaused: Bool = false
    @Published var hasNoLyrics: Bool = false
    @Published var isApproximateSync: Bool = false
    @Published var isFavorited: Bool = false

    /// Language the current song's lyrics are in, decided per song rather
    /// than per line: a Japanese song has plenty of kanji-only lines that
    /// look identical to Chinese, so one kana anywhere marks the whole track.
    /// Everything else is assumed English (or Chinese, which is skipped).
    @Published var sourceLanguageCode: String = "en"

    var lyrics: [LyricLine] = [] {
        didSet {
            currentIndex = -1
            hasNoLyrics = lyrics.isEmpty
            isApproximateSync = lyrics.first?.isApproximate ?? false
            sourceLanguageCode = Self.hasKana(lyrics) ? "ja" : "en"
        }
    }

    private static func hasKana(_ lines: [LyricLine]) -> Bool {
        lines.contains { line in
            line.text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        }
    }

    private var currentIndex: Int = -1

    func reset() {
        trackTitle = nil
        currentLine = ""
        nextLine = ""
        translation = ""
        hasNoLyrics = false
        isApproximateSync = false
        isFavorited = false
        lyrics = []
    }

    func updateCurrentLine(position: TimeInterval) {
        guard !lyrics.isEmpty else { return }

        var idx = -1
        for (i, line) in lyrics.enumerated() {
            if line.time <= position {
                idx = i
            } else {
                break
            }
        }
        guard idx != currentIndex else { return }
        currentIndex = idx
        currentLine = idx >= 0 ? lyrics[idx].text : ""
        nextLine = (idx + 1) < lyrics.count ? lyrics[idx + 1].text : ""
    }
}
