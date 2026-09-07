#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Apple Music 歌词悬浮窗"
BUNDLE="$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

echo "==> assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp .build/release/LyricsOverlay "$BUNDLE/Contents/MacOS/LyricsOverlay"
cp Info.plist "$BUNDLE/Contents/Info.plist"

echo "==> ad-hoc codesigning"
codesign --force --deep --sign - "$BUNDLE"

echo "==> done: $(pwd)/$BUNDLE"
