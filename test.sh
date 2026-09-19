#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$PROJECT/.build/tests"
mkdir -p "$BUILD/cache"
xcrun clang -g -I "$PROJECT/Sources/AudioBridge/include" "$PROJECT/Tests/bridge_test.c" "$PROJECT/Sources/AudioBridge/AudioBridge.c" -framework CoreAudio -o "$BUILD/bridge-test"
"$BUILD/bridge-test"
xcrun clang -I "$PROJECT/Sources/AudioBridge/include" -c "$PROJECT/Sources/AudioBridge/AudioBridge.c" -o "$BUILD/bridge.o"
xcrun swiftc -module-cache-path "$BUILD/cache" -I "$PROJECT/Sources/AudioBridge/include" "$PROJECT/Sources/AudioRouter/Hardware.swift" "$PROJECT/Tests/discovery_test.swift" "$BUILD/bridge.o" -framework CoreAudio -framework AppKit -o "$BUILD/discovery-test"
"$BUILD/discovery-test"

xcrun swiftc -module-cache-path "$BUILD/cache" "$PROJECT/Sources/AudioRouter/PanelLayout.swift" "$PROJECT/Tests/layout_test.swift" -o "$BUILD/layout-test"
"$BUILD/layout-test"
