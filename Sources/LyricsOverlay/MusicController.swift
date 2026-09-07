import Foundation
import AppKit

struct TrackInfo: Equatable {
    let name: String
    let artist: String
    let album: String
    let trackId: String
    let position: TimeInterval
    let duration: TimeInterval
}

enum MusicPlaybackState {
    case notRunning
    case stopped
    case playing(TrackInfo)
    case paused(TrackInfo)
}

/// Polls Apple Music (Music.app) via AppleScript/Apple Events for the current
/// track and playback position. Requires the user to grant Automation
/// permission for controlling "Music" the first time it runs.
final class MusicController {
    var onUpdate: ((MusicPlaybackState) -> Void)?

    private var timer: Timer?
    private let scriptQueue = DispatchQueue(label: "MusicController.applescript")

    private static let query = """
    tell application "System Events"
        set musicRunning to (name of processes) contains "Music"
    end tell
    if musicRunning is false then
        return "NOTRUNNING"
    end if
    tell application "Music"
        if player state is playing or player state is paused then
            set trackName to name of current track
            set artistName to artist of current track
            set albumName to album of current track
            set trackIdent to (database ID of current track) as string
            set pos to player position as string
            set dur to (duration of current track) as string
            set stateStr to player state as string
            return trackName & "<|>" & artistName & "<|>" & albumName & "<|>" & trackIdent & "<|>" & pos & "<|>" & dur & "<|>" & stateStr
        else
            return "NONE"
        end if
    end tell
    """

    func start() {
        poll()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        scriptQueue.async { [weak self] in
            guard let self else { return }
            let result = self.runAppleScript(Self.query)
            DispatchQueue.main.async {
                self.handle(result: result)
            }
        }
    }

    private func handle(result: String?) {
        guard let result else {
            onUpdate?(.notRunning)
            return
        }
        if result == "NOTRUNNING" {
            onUpdate?(.notRunning)
            return
        }
        if result == "NONE" {
            onUpdate?(.stopped)
            return
        }
        let parts = result.components(separatedBy: "<|>")
        guard parts.count == 7 else {
            onUpdate?(.stopped)
            return
        }
        let info = TrackInfo(
            name: parts[0],
            artist: parts[1],
            album: parts[2],
            trackId: parts[3],
            position: TimeInterval(parts[4]) ?? 0,
            duration: TimeInterval(parts[5]) ?? 0
        )
        if parts[6] == "paused" {
            onUpdate?(.paused(info))
        } else {
            onUpdate?(.playing(info))
        }
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        if let error {
            NSLog("LyricsOverlay: AppleScript error: \(error)")
            return nil
        }
        return output.stringValue
    }
}
