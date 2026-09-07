import AppKit
import SwiftUI

/// A borderless, non-activating panel that floats above every other window
/// (including full-screen apps) and appears on every Space, so switching to
/// another app or desktop never hides or interrupts it.
///
/// Its SwiftUI content toggles between a small pill and an expanded panel,
/// so the window resizes itself to fit — every resize keeps the window's own
/// top-right corner fixed (wherever the user last dragged it to), instead of
/// AppKit's default of anchoring the bottom-left.
final class OverlayWindow: NSPanel {
    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [.standardBounds, .intrinsicContentSize]
        contentView = hosting

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - frame.width - 24
            let y = screen.visibleFrame.maxY - frame.height - 24
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(topRightPinned(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(topRightPinned(frameRect), display: displayFlag, animate: animateFlag)
    }

    private func topRightPinned(_ frameRect: NSRect) -> NSRect {
        guard frame.size != frameRect.size, frame.size != .zero else { return frameRect }
        let topRight = NSPoint(x: frame.maxX, y: frame.maxY)
        var newFrame = frameRect
        newFrame.origin.x = topRight.x - newFrame.width
        newFrame.origin.y = topRight.y - newFrame.height
        return newFrame
    }
}
