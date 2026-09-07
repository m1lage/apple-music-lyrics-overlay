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

    var lyrics: [LyricLine] = [] {
        didSet {
            currentIndex = -1
            hasNoLyrics = lyrics.isEmpty
            isApproximateSync = lyrics.first?.isApproximate ?? false
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
