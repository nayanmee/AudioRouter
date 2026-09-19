#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$PROJECT/.build/app"
DIST="$PROJECT/dist"
if ! xcrun --find swiftc >/dev/null 2>&1; then
    printf "Apple Command Line Tools are required. Run xcode-select --install, finish installation, then retry.\n" >&2
    exit 1
fi
mkdir -p "$DIST"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/AudioRouter-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/AudioRouter.app"
mkdir -p "$BUILD/cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARCH="$(uname -m)"
xcrun clang -O2 -target "$ARCH-apple-macos14.2" -I "$PROJECT/Sources/AudioBridge/include" -c "$PROJECT/Sources/AudioBridge/AudioBridge.c" -o "$BUILD/AudioBridge.o"
xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macos14.2" -module-cache-path "$BUILD/cache" -I "$PROJECT/Sources/AudioBridge/include" "$PROJECT"/Sources/AudioRouter/*.swift "$BUILD/AudioBridge.o" -framework CoreAudio -framework AppKit -framework SwiftUI -o "$BUILD/AudioRouter"
cp "$BUILD/AudioRouter" "$APP/Contents/MacOS/AudioRouter.next"
mv -f "$APP/Contents/MacOS/AudioRouter.next" "$APP/Contents/MacOS/AudioRouter"
cp "$PROJECT/Info.plist" "$APP/Contents/Info.plist"
xcrun swiftc -module-cache-path "$BUILD/cache" "$PROJECT/Tools/MakeIcon.swift" -o "$BUILD/make-icon"
"$BUILD/make-icon" "$BUILD/AudioRouter.iconset" "$APP/Contents/Resources/AudioRouter.icns"
# Remove only Finder metadata from this generated bundle; preserve security attributes.
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
ditto -c -k --keepParent --norsrc "$APP" "$DIST/AudioRouter.zip"
printf 'Built, signed, and packaged: %s\nExtract the ZIP and move AudioRouter to Applications before launch.\n' "$DIST/AudioRouter.zip"
