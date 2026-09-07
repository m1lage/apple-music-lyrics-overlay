# Apple Music Lyrics Overlay

A native macOS floating overlay that shows synced lyrics (with optional Chinese translation) for whatever's currently playing in Apple Music — always on top, on every desktop Space, and never interrupted when you switch to another app.

## Features

- **Truly floating**: an `NSPanel` with `level = .floating` and `collectionBehavior` set to `canJoinAllSpaces` + `fullScreenAuxiliary`, so it stays visible across every Space, including full-screen apps, without stealing focus or showing up in the Dock.
- **Lyrics source**: Apple Music doesn't expose an official lyrics API, so lyrics are looked up on [lrclib.net](https://lrclib.net) (a free, open lyrics database) by track name + artist + album + duration, matching synced (LRC) lyrics. When only untimed plain lyrics are available (common for Chinese-language songs), it falls back to evenly estimating timestamps across the track's duration so something still shows.
- **Chinese translation**: non-Chinese lines are translated on-device via Apple's Translation framework. The source language is pinned to English to avoid the system popping up a "confirm language" prompt when it can't confidently identify short slang/ad-libs.
- **Two display states**:
  - Collapsed pill (default): a dot + the current line + its translation, always visible without needing to hover.
  - Expanded panel (on hover): adds the track title and the next line.
- **Marquee for long lines**: a line that doesn't fit scrolls back and forth to show its full text instead of being cut off with an ellipsis.
- **Menu bar icon**: show/hide the overlay, toggle click-through (lets clicks pass through to whatever is behind it).
- The window is draggable, and any resize — whether from expanding/collapsing or content changing — keeps the window's own top-right corner pinned in place.

## Requirements

- macOS 15 (Sequoia) or later — uses the Translation framework
- Apple Music.app installed, with a track loaded/playing
- On first launch, macOS will ask for permission to control Music.app (used to read what's currently playing) — you only need to approve this once

## Build & run

```bash
./build_app.sh
open "Apple Music 歌词悬浮窗.app"
```

`build_app.sh` compiles with `swift build -c release` and packages the result into a double-clickable `.app` bundle (ad-hoc signed).

## Project structure

```
Sources/LyricsOverlay/
  main.swift              Entry point, sets up NSApplication
  AppDelegate.swift        Wires up MusicController / LyricsService / the view model, menu bar
  MusicController.swift    Polls Apple Music via AppleScript
  LyricsService.swift      lrclib.net lookup + LRC parsing + plain-lyrics fallback
  LyricsViewModel.swift    Current/next line state
  LyricsOverlayView.swift  SwiftUI views for the compact pill and expanded panel
  MarqueeText.swift        Scrolling text for lines that overflow
  OverlayWindow.swift      The floating NSPanel, pins its top-right corner across resizes
```

## Development notes

This tool went through a few rounds of polish. A few bugs worth remembering:

- **The AppleScript variable name `st` causes a syntax error.** `set st to player state as string` fails to compile; renaming it to `stateStr` fixed it. The exact cause is unclear — possibly collides with a reserved abbreviation.
- **A control character used as a field delimiter got lost somewhere in NSAppleScript's bridging.** The original code joined fields with `\u{1F}` (a unit separator), but that byte didn't survive intact through NSAppleScript's script source. Switching to a plain `<|>` string fixed it.
- **"No lyrics found" for Chinese songs.** Many Chinese-language tracks on lrclib.net only have untimed plain lyrics, and the original code only accepted `syncedLyrics`, silently discarding those matches. Adding a plain-lyrics fallback (with evenly estimated timestamps) fixed it.
- **SwiftUI's `.frame(maxWidth:)` combined with `.fixedSize()` makes a view always render at the max width**, instead of shrinking to fit short content. The fix is to put the width cap only on the innermost `Text`, and apply `.fixedSize()` to an outer container that has no `maxWidth` of its own — that lets short text hug its natural width while long text correctly triggers truncation/scrolling.
- **The Translation framework's `source: nil` (auto-detect) triggers a system "confirm language" dialog** when it can't confidently identify short slang/ad-libs common in hip-hop lyrics. Pinning `source` to `.init(identifier: "en")` stopped the prompt, since anything reaching the translation step has already been filtered to exclude Chinese text.

## Known limitations

- lrclib.net's coverage is inconsistent — obscure or very new songs may have no lyrics at all.
- The plain-lyrics fallback's timing is only an estimate, not the song's real line-by-line timestamps.
- The translation source language is pinned to English; other languages (Japanese, Korean, etc.) aren't translated yet.
