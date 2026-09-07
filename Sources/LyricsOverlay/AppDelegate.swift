import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow!
    private var statusItem: NSStatusItem!

    private let musicController = MusicController()
    private let lyricsService = LyricsService()
    private let viewModel = LyricsViewModel()

    private var lastTrackId: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        setupStatusItem()

        musicController.onUpdate = { [weak self] state in
            self?.handle(state: state)
        }
        musicController.start()
    }

    private func setupWindow() {
        let content = LyricsOverlayView(viewModel: viewModel)
        window = OverlayWindow(rootView: content)
        window.orderFrontRegardless()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Lyrics Overlay")
        }

        let menu = NSMenu()

        let toggleShow = NSMenuItem(title: "显示 / 隐藏歌词", action: #selector(toggleVisibility), keyEquivalent: "")
        toggleShow.target = self
        menu.addItem(toggleShow)

        let toggleClickThrough = NSMenuItem(title: "开启点击穿透", action: #selector(toggleClickThrough), keyEquivalent: "")
        toggleClickThrough.target = self
        menu.addItem(toggleClickThrough)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出歌词悬浮窗", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func toggleVisibility() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        window.ignoresMouseEvents.toggle()
        window.isMovableByWindowBackground = !window.ignoresMouseEvents
        sender.title = window.ignoresMouseEvents ? "关闭点击穿透" : "开启点击穿透"
    }

    private func handle(state: MusicPlaybackState) {
        switch state {
        case .notRunning, .stopped:
            lastTrackId = nil
            viewModel.reset()

        case .playing(let info), .paused(let info):
            if info.trackId != lastTrackId {
                lastTrackId = info.trackId
                viewModel.trackTitle = "\(info.name) — \(info.artist)"
                viewModel.lyrics = []
                lyricsService.fetchLyrics(
                    track: info.name,
                    artist: info.artist,
                    album: info.album,
                    duration: info.duration
                ) { [weak self] lines in
                    DispatchQueue.main.async {
                        guard self?.lastTrackId == info.trackId else { return }
                        self?.viewModel.lyrics = lines
                    }
                }
            }
            viewModel.updateCurrentLine(position: info.position)
        }
    }
}
