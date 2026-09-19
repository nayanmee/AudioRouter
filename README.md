# AudioRouter

**Send each Mac app to its own audio output—from your menu bar.**

Play Safari through your speakers, put Google Chrome on your headphones, and adjust each app's volume independently. AudioRouter runs in the background, with output selection, volume, mute, and Start/Stop controls in one menu-bar panel.

Native SwiftUI + Core Audio. Audio stays on your Mac: no uploads, recordings, accounts, or third-party audio drivers.

## When would I use it?

| Situation | Example setup |
| --- | --- |
| Music and meetings on different devices | Play music in Safari through external speakers while a meeting in Chrome plays through AirPods. These must be separate apps; two tabs in the same browser cannot be routed separately. AudioRouter controls playback, not the meeting microphone. |
| A desk with several audio outputs | Send a browser's music to USB speakers, another app's audio to the monitor's audio output, and a third app to headphones. Each device must appear as a compatible output in macOS. |
| Focus while coding | Keep a tutorial in Chrome on headphones, background music in Safari on speakers, and turn down Cursor's own audio independently when it exposes a routable audio process. Shared macOS notification sounds may not belong to the app itself. |

These are intended workflows, not a claim that every app or device combination has been tested. Bluetooth devices can change audio format when their microphone is used; see limitations below.

## Requirements

- **macOS 14.2 or later**, required by the public Core Audio process-tap APIs.
- A compatible stereo output device recognized by macOS.
- System-audio capture permission for AudioRouter.
- To build: **Swift 6.0 or later** and a macOS SDK with process-tap support, supplied by a sufficiently recent Apple Command Line Tools or Xcode installation.

Version **0.2.2** was built and tested on an Apple M4 Mac running macOS 26.5.1 with Swift 6.2.1. Earlier supported macOS versions and Intel Macs have not been runtime-tested. The build script produces an app for the Mac's native architecture, not a universal binary.

## Download the built app

The [v0.2.2 release](https://github.com/nayanmee/AudioRouter/releases/tag/v0.2.2) includes **AudioRouter-0.2.2-arm64.zip** for Apple silicon Macs running macOS 14.2 or later. This is an early, ad-hoc-signed build, not an Apple-notarized installer. Intel Macs should use the source-build instructions below; Intel behavior has not been verified.

1. Download the app ZIP from the release assets and double-click it in Finder.
2. Quit any running AudioRouter copy, then drag **AudioRouter.app** into **Applications**.
3. Open AudioRouter from Applications and use its speaker-in-a-circle menu-bar icon.
4. If macOS blocks the downloaded build, follow the security guidance below or build from source. Do not disable macOS security protections.

**Repository visibility:** this repository and its release downloads are private. Only the owner and explicitly authorized collaborators can access them.

## Install from source

A notarized, one-click public installer is not available yet. You can build the app locally without a paid developer account or a full Xcode installation.

1. Download this repository using GitHub's **Code → Download ZIP**, extract it, and find the **AudioRouter** project folder containing `build.sh`.
2. Open Terminal. If Apple Command Line Tools are missing, run:

   ```sh
   xcode-select --install
   ```

   Finish Apple's installer, then check `swift --version`. If it is older than 6.0, update the Command Line Tools or select a recent Xcode toolchain.
3. In Terminal, type `cd ` (with a trailing space), drag the AudioRouter project folder from Finder into Terminal, and press Return. Then run:

   ```sh
   ./test.sh
   ./build.sh
   ```

4. Open the project's **dist** folder and double-click **AudioRouter.zip**.
5. Drag the extracted **AudioRouter.app** into **Applications**. If updating, first choose **Quit** in the running AudioRouter panel, then replace the previous app.
6. Open **Applications → AudioRouter**. Look for the speaker-in-a-circle icon in the menu bar. There is intentionally no Dock icon. Spotlight can find the installed app after macOS indexes it.

The app is **locally ad-hoc signed**, not notarized by Apple. Do not disable Gatekeeper or SIP or strip quarantine attributes. If macOS blocks a downloaded build, use a local source build or consult [Apple's guidance for opening apps safely](https://support.apple.com/102445); review the source and trust the publisher before allowing an app. An administrator-managed Mac may prohibit it.

Installing the app does not enable automatic launch at login.

## Use AudioRouter

1. **Connect your outputs.** Confirm your headphones, monitor audio, or speakers appear in macOS sound settings.
2. **Open the menu-bar panel.** Cursor, Google Chrome, and Safari appear first when installed. Other apps with audio clients follow. Use **Find an app**, **Show all running apps**, or the refresh button to find another app.
3. **Choose Output** for an app and press **Start**. Play a sound in that app. AudioRouter waits if its audio process has not appeared yet.
4. **Allow system-audio capture** if macOS asks. If permission was denied, check **System Settings → Privacy & Security → Screen & System Audio Recording** (the label varies by macOS version), enable AudioRouter's audio permission, quit it, and reopen it.
5. **Set the volume or mute.** Each app has its own 0–100% slider and speaker button. These controls apply while routing; they do not change hardware volume or amplify above the source level.
6. **Repeat for another app.** Choose a different output and press Start. Routes operate independently.
7. **Close the panel** by clicking outside it. Routing continues in the background. Reopen it from the menu bar at any time.
8. **Stop** a single route, **Stop All**, or **Quit**. Stopping restores ordinary playback, including for an app you had muted through AudioRouter.

Output and volume choices are remembered. Active routes are not automatically restarted after launch or sleep. A disconnected output stops the affected route and shows a status message; reconnect it and press Start again.

## Status and troubleshooting

| What you see | What to do |
| --- | --- |
| **Ready** | Select an output and press Start. Changing a volume slider alone does not enable routing. |
| **Waiting for audio** | Play audio in the app. If it is already playing, check capture permission and whether its audio helper was discovered. |
| **Routing** | Audio is reaching the routing callback and original playback suppression is enabled. Listen to confirm the intended physical output and no duplicate playback. |
| **Disconnected output** | Reconnect the device or select another one, then press Start. |
| **Unsupported device format** | Try built-in speakers or a stereo USB output. Bluetooth headsets may switch to an unsupported format while their microphone is in use. |
| App or audio helper is missing | Refresh, enable Show all running apps, and play a sound. Advanced users can inspect **Audio helpers and assignments** at the bottom of the list. Assign only a helper whose owner you can identify. |
| Permission is enabled but capture fails after an update | Keep the app installed in Applications, quit and reopen it, and check its capture permission again. Ad-hoc builds may require renewed permission. |
| No sound after stopping | Check the app's own volume and macOS output/mute settings. If AudioRouter reports a cleanup error, quit it. |

Safari audio often comes from a WebKit helper rather than the Safari main process. AudioRouter uses process ancestry, bundle paths, and Safari-specific helper names to identify ownership; it does not assign every WebKit process to Safari. The Safari-specific name fallback currently recognizes English role names.

## Current limits

- **App-level routing only.** Tabs within the same browser share an app route. Use different browser apps when you need different destinations.
- Routes a stereo mix; virtual/aggregate and mono outputs are excluded. Some multichannel and Bluetooth device configurations are unsupported.
- Meeting microphone selection remains in the meeting app/macOS. AudioRouter handles output audio only.
- Shared system notification services and protected/DRM media may not be separately capturable or attributable.
- Original playback is suppressed only after nonzero source audio reaches the output callback. There can be a brief overlap while routing starts.
- Device disconnection or a detected routing failure restores ordinary playback where Core Audio cleanup succeeds. Cleanup failures are displayed rather than silently ignored.
- This is an early release. Safari routing has been confirmed by listening; simultaneous hardware-device isolation, meeting/AirPods behavior, and every supported OS version still require broader testing.

## Privacy and implementation

Audio processing happens locally in memory. AudioRouter does not save recordings, send audio over the network, or capture screen images. Physical microphone input streams are excluded from the routing path. The bundle includes audio-capture permission descriptions.

Each route uses a private [Core Audio process tap](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) and private aggregate device attached to the selected output. AudioRouter excludes its own processes to avoid feedback. The C audio callback applies per-route gain without allocating memory, acquiring locks, or doing file/network I/O. Swift handles discovery, device health, and the menu-bar interface.

## Development and verification

From the project folder:

```sh
./test.sh
./build.sh
```

Build caches stay in `.build/`; the app archive is `dist/AudioRouter.zip`. Both are ignored by Git. Launch the app bundle, not a raw `swift run` executable, so macOS sees the permission descriptions.

Automated tests cover stereo forwarding, microphone-channel exclusion, invalid-buffer handling, independent gain controls, mute and gain ramps, browser/helper ownership, and panel placement across different display arrangements. Compilation and these tests do **not** prove audible routing on a physical device.

For a listening test, open [Listening-Test.html](Listening-Test.html) locally in Safari and Chrome. It generates quiet tones without downloading or recording audio:

- Route Safari to an output different from ordinary playback; confirm sound moves and is not duplicated.
- Route Chrome to a second output; confirm independent audio, volume, and mute.
- Dismiss the panel; confirm routes remain active.
- Stop one route; confirm ordinary playback resumes and the other route continues.
- Disconnect an output; confirm the affected route stops with a clear status.
- Test Quit and sleep/wake, and record your macOS version, chip, and device models.

Version 0.2.2 passed the native build, strict bundle signature validation, and automated tests. Its panel was visually checked on the built-in MacBook display without taking keyboard focus. Listening tests were not repeated for that layout-only update.

See [release instructions](docs/RELEASE.md) for packaging, architecture labels, and the remaining steps for notarized distribution. Report issues in the containing repository and include **AudioRouter**, your macOS version, chip, output-device model, app being routed, and exact status/error message. Avoid posting private meeting audio or personal logs.
