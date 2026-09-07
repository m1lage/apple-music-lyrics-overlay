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
final class LyricsService {
    private struct LRCLibEntry: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private let session = URLSession(configuration: .ephemeral)

    func fetchLyrics(
        track: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        completion: @escaping ([LyricLine]) -> Void
    ) {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]
        guard let url = components.url else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.setValue("AppleMusicLyricsOverlay/1.0", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            if let data,
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let entry = try? JSONDecoder().decode(LRCLibEntry.self, from: data) {
                if let synced = entry.syncedLyrics, !synced.isEmpty {
                    completion(Self.parseLRC(synced))
                    return
                }
                if let plain = entry.plainLyrics, !plain.isEmpty {
                    completion(Self.parsePlain(plain, duration: duration))
                    return
                }
            }
            self.searchFallback(track: track, artist: artist, duration: duration, completion: completion)
        }.resume()
    }

    private func searchFallback(
        track: String,
        artist: String,
        duration: TimeInterval,
        completion: @escaping ([LyricLine]) -> Void
    ) {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components.url else {
            completion([])
            return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data, let results = try? JSONDecoder().decode([LRCLibEntry].self, from: data) else {
                completion([])
                return
            }
            if let synced = results.first(where: { ($0.syncedLyrics?.isEmpty ?? true) == false })?.syncedLyrics {
                completion(Self.parseLRC(synced))
                return
            }
            if let plain = results.first(where: { ($0.plainLyrics?.isEmpty ?? true) == false })?.plainLyrics {
                completion(Self.parsePlain(plain, duration: duration))
                return
            }
            completion([])
        }.resume()
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
