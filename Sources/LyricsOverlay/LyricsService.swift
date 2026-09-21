import Foundation

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
    /// true when this line's timing was estimated (evenly spread across the
    /// track) because lrclib only had plain, untimed lyrics for this song —
    /// common for Chinese-language tracks, which are less often contributed
    /// with line-by-line timing than English pop.
    var isApproximate: Bool = false
}

/// Fetches synced (LRC) lyrics from lrclib.net — a free, keyless, community
/// lyrics database. Apple Music itself does not expose lyrics through any
/// public API or AppleScript command, so a third-party lookup by
/// track/artist/album/duration is used instead.
///
/// lrclib is a small volunteer-run service and answers 503 fairly often, so
/// transient failures are retried rather than being mistaken for "this song
/// has no lyrics". Lookups go from most to least precise:
///   1. exact match (track + artist + album + duration)
///   2. search by track + artist, closest duration wins
///   3. search by track alone, only accepting a duration within a few seconds
///      (Apple Music's artist string is often a combo like "A & B" that
///      lrclib's artist filter can't match)
final class LyricsService {
    private struct LRCLibEntry: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    private enum Response<T> {
        case found(T)
        case notFound
        case failed
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        return URLSession(configuration: config)
    }()

    private static let retryDelays: [TimeInterval] = [0.7, 1.6]

    func fetchLyrics(
        track: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        completion: @escaping ([LyricLine]) -> Void
    ) {
        Task {
            let lines = await lookup(track: track, artist: artist, album: album, duration: duration)
            completion(lines)
        }
    }

    private func lookup(track: String, artist: String, album: String, duration: TimeInterval) async -> [LyricLine] {
        let titles = Self.titleVariants(track)

        if case .found(let entry) = await get(
            "https://lrclib.net/api/get",
            [("track_name", track), ("artist_name", artist), ("album_name", album),
             ("duration", String(Int(duration.rounded())))],
            as: LRCLibEntry.self
        ), let lines = Self.lines(from: entry, duration: duration), !lines.isEmpty {
            return lines
        }

        for title in titles {
            if case .found(let entries) = await get(
                "https://lrclib.net/api/search",
                [("track_name", title), ("artist_name", artist)],
                as: [LRCLibEntry].self
            ), let lines = Self.bestMatch(in: entries, duration: duration, maxDurationDiff: nil) {
                return lines
            }
        }

        for title in titles {
            if case .found(let entries) = await get(
                "https://lrclib.net/api/search",
                [("track_name", title)],
                as: [LRCLibEntry].self
            ), let lines = Self.bestMatch(in: entries, duration: duration, maxDurationDiff: 3) {
                return lines
            }
        }

        return []
    }

    /// GET + decode. 404 is a definitive "no such entry"; 5xx and network
    /// errors are retried with a short backoff.
    private func get<T: Decodable>(_ base: String, _ query: [(String, String)], as type: T.Type) async -> Response<T> {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { return .failed }

        var request = URLRequest(url: url)
        request.setValue("AppleMusicLyricsOverlay/1.0", forHTTPHeaderField: "User-Agent")

        for attempt in 0...Self.retryDelays.count {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(Self.retryDelays[attempt - 1] * 1_000_000_000))
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                if http.statusCode == 404 { return .notFound }
                if http.statusCode == 200, let decoded = try? JSONDecoder().decode(T.self, from: data) {
                    return .found(decoded)
                }
            } catch {
                continue
            }
        }
        return .failed
    }

    /// Picks the entry whose duration is closest to the playing track's
    /// (synced lyrics preferred over plain), so a live version or a
    /// same-titled different song doesn't win just by being listed first.
    private static func bestMatch(in entries: [LRCLibEntry], duration: TimeInterval, maxDurationDiff: Double?) -> [LyricLine]? {
        func diff(_ entry: LRCLibEntry) -> Double {
            guard duration > 0 else { return 0 }
            guard let d = entry.duration else { return maxDurationDiff == nil ? 0 : .infinity }
            return abs(d - duration)
        }
        func hasSynced(_ entry: LRCLibEntry) -> Bool { !(entry.syncedLyrics?.isEmpty ?? true) }
        func hasPlain(_ entry: LRCLibEntry) -> Bool { !(entry.plainLyrics?.isEmpty ?? true) }

        let candidates = entries
            .filter { hasSynced($0) || hasPlain($0) }
            .filter { maxDurationDiff == nil || diff($0) <= maxDurationDiff! }
            .sorted { (diff($0) + (hasSynced($0) ? 0 : 20)) < (diff($1) + (hasSynced($1) ? 0 : 20)) }

        for entry in candidates {
            if let lines = lines(from: entry, duration: duration), !lines.isEmpty { return lines }
        }
        return nil
    }

    private static func lines(from entry: LRCLibEntry, duration: TimeInterval) -> [LyricLine]? {
        if let synced = entry.syncedLyrics, !synced.isEmpty { return parseLRC(synced) }
        if let plain = entry.plainLyrics, !plain.isEmpty { return parsePlain(plain, duration: duration) }
        return nil
    }

    /// The title as-is, plus a version with a trailing "(Live)" / "（伴奏）" /
    /// "- Remastered" style suffix removed, since lrclib usually files those
    /// under the bare title.
    private static func titleVariants(_ title: String) -> [String] {
        var stripped = title
        for pattern in [#"\s*[\(（\[【][^\)）\]】]*[\)）\]】]\s*$"#, #"\s+-\s+.*$"#] {
            stripped = stripped.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        stripped = stripped.trimmingCharacters(in: .whitespaces)
        return (stripped.isEmpty || stripped == title) ? [title] : [title, stripped]
    }

    static func parseLRC(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let timeRegex = try! NSRegularExpression(pattern: #"\[(\d{2}):(\d{2})(?:[.:](\d{2,3}))?\]"#)

        for rawLine in text.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = timeRegex.matches(in: rawLine, range: fullRange)
            guard !matches.isEmpty else { continue }

            let lyricText = timeRegex
                .stringByReplacingMatches(in: rawLine, range: fullRange, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !lyricText.isEmpty else { continue }

            for match in matches {
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let fracString = nsLine.substring(with: match.range(at: 3))
                    fraction = Double("0.\(fracString)") ?? 0
                }
                lines.append(LyricLine(time: minutes * 60 + seconds + fraction, text: lyricText))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// Spreads untimed lyric lines evenly across the track's duration so
    /// there's still a progressing display, even though the timing is only
    /// an estimate rather than the song's real line timestamps.
    static func parsePlain(_ text: String, duration: TimeInterval) -> [LyricLine] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }
        guard lines.count > 1, duration > 0 else {
            return [LyricLine(time: 0, text: lines[0], isApproximate: true)]
        }
        let span = max(duration - 2, 1)
        return lines.enumerated().map { index, line in
            let time = span * Double(index) / Double(lines.count - 1)
            return LyricLine(time: time, text: line, isApproximate: true)
        }
    }
}
