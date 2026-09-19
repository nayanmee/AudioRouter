# AudioRouter development notes

For current installation and usage, see [the README](../README.md). These notes document implementation and earlier verification.

## App and helper discovery

Discovery uses public Core Audio process objects, bundle identities, executable paths, parent-process ancestry, and running applications. Helpers inside an application's bundle or belonging to its process tree are grouped with that application. Cursor's actual installed bundle identity was checked on this Mac. AudioRouter excludes its own process and other AudioRouter copies.

Safari's launchd-owned audio helper can report only a generic WebKit bundle identity. The existing Safari fix is retained: the system-provided name `Safari Graphics and Media` (or `Safari Web Content`), a system WebKit executable path, and a running Safari host identify that helper. Other apps' WebKit processes remain excluded. The fallback currently recognizes those English role names; unknown/localized helpers remain available for explicit assignment.

Do not assign a generic helper merely because it says WebKit. Compare playback activity and confirm its owner first. Manual choices expire when process identity changes. App restarts and new helpers are rediscovered; enabled routes wait or reconnect as needed.

Some notifications are played by shared system services rather than the app itself. Those cannot always be safely isolated to one app and are not automatically attributed. Protected/DRM media can also be unavailable for capture. Tab-level routing is not implemented.

## Listening checks

`Listening-Test.html` generates quiet tones locally, without downloads or recording. Open it in Safari or Chrome using Finder's **Open With**, then click the corresponding test tone.

- Start one route to an output different from ordinary playback. Confirm the chosen output plays it and the original output does not duplicate it.
- Change that app's volume, mute it, and unmute it. Confirm another app's volume is unaffected.
- Dismiss the popup and confirm playback continues. Reopen it and confirm the route remains enabled.
- Route Safari and Chrome to separate devices and check isolation by listening. Stop them independently.
- Disconnect a selected output. Its route should stop with a clear message; other routes should continue. Reconnection does not automatically restart a disconnected route.
- Test Quit and sleep/wake. Quit stops all routes; sleep stops routing and requires Start again after waking.

“Routing” indicates that Core Audio delivered nonzero source audio through the callback and original-output suppression was enabled. Physical audibility, exact device selection, and the absence of duplicated playback still need listening verification.

## Verified for version 0.2.2

- Build succeeded; the extracted release passed strict code-signature validation and the app icon decoded correctly.
- Popup geometry tests passed for side-by-side, stacked, negative-origin, and short displays.
- A separate preview was visually checked on this MacBook’s built-in Retina display. Its entire 410 × 620-point panel fit within that display’s visible area; header, search, app controls, and footer were visible. The app list scrolls to additional apps.
- The preview reported that it was neither the active app nor the key window. No testing clicks were sent to the Dell display.
- Audio health monitoring now continues during control tracking. Audio routing and listening checks were not repeated for this layout update.

## Earlier routing and control verification (0.2.1)

- Native build and clean ZIP bundle signature verification.
- C tests for stereo forwarding, physical-input exclusion, mismatched-buffer silence, independent routes, invalid-sample sanitization, disabled-callback silence, per-app gain, smooth gain changes, initial mute, and gain bounds.
- Discovery tests for Safari's special helper, rejecting unrelated WebKit helpers, bundle/path boundaries, and Cursor helper, path, and parent attribution.
- Live popup inspection: output pickers, Start/Stop, sliders, mute buttons, search, all-app selection, and helper controls are inside the popup itself. Cursor, Chrome, and Safari are listed first.
- Live UI volume changes, mute/unmute restoration, and volume persistence across app restarts.
- A local Safari tone was captured by the final build, including starting at 0% and unmuting to 100%. Routing remained active after switching away from the popup and reopening it. The test tone/tab were removed afterward and routes were stopped.
- The earlier Safari routing fix was also confirmed audibly by the user. This does not substitute for listening checks of the new volume controls or every other app/device.

Cursor discovery and ownership logic are verified; actual Cursor sound playback, hot unplug, and physical two-device volume isolation were not retested for this version. A sanitizer-instrumented executable previously stalled under the restricted execution environment, so sanitizer validation is not claimed.

## Architecture and build environment

Source is a Swift Package (`Package.swift`) with a native app-bundle build script. The app uses SwiftUI views hosted in a native AppKit status-item panel. The C callback handles audio without allocation, locks, dispatch, logging, or file/network writes.

Use `./test.sh` and `./build.sh` from the project folder. Caches are local to `.build/` and the archive is `dist/AudioRouter.zip`.

Inspected on this Mac: macOS 26.5.1, Apple silicon (arm64), Swift 6.2.1, and Apple's Command Line Tools. Full Xcode is absent and unnecessary for the tested build. Deployment target remains macOS 14.2; earlier supported macOS releases were not runtime-tested. If tools are missing on another Mac, run `xcode-select --install`, finish Apple's installer, and verify `swift --version` plus `xcrun --show-sdk-path`.

Each route has a private process tap and aggregate device clocked by its selected hardware output, with tap drift compensation. The audio callback copies the stereo tap into the first two output channels and applies a lock-free per-route gain with a one-buffer ramp. Physical input streams are disabled. Unsupported formats/layouts fail safely. Virtual, aggregate, and mono output devices are excluded; unusual multichannel or Bluetooth formats may be unsupported.

Health checks run every 250 ms; process/device discovery refreshes every second. Disconnection stops the affected route on detection, and stalled callbacks stop it after two seconds. Waiting for an idle app does not suppress its original playback. Source detection occurs before applying gain so starting at 0% can still activate source suppression. Stop explicitly unmutes and tears down the tap; cleanup failures are reported, and callback memory is retained rather than freed if HAL cannot detach it safely.

Apple references: [Core Audio process taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), [CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription). The installed SDK headers were checked for API availability and stream/tap semantics.
