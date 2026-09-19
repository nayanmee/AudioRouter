import SwiftUI
import AppKit

// AppKit owns the status item and lifecycle; all controls are native SwiftUI.
// No standalone window is created or required.
@main struct AudioRouterApp {
    @MainActor static let delegate = AppDelegate()
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
@MainActor final class AudioControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: AudioControlPanel?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var currentScreenID: CGDirectDisplayID?
    private var previewMode: Bool { Bundle.main.object(forInfoDictionaryKey: "AudioRouterLayoutPreview") as? Bool == true }

    private func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !previewMode {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2.circle", accessibilityDescription: "AudioRouter")
            button.image?.isTemplate = true
            button.toolTip = "AudioRouter — app outputs and volume"
            button.setAccessibilityLabel("AudioRouter")
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
        }
        let mainMenu = NSMenu()
        let applicationMenu = NSMenuItem()
        applicationMenu.submenu = NSMenu()
        applicationMenu.submenu?.addItem(withTitle: "Quit AudioRouter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(applicationMenu)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        mainMenu.addItem(edit)
        NSApp.mainMenu = mainMenu
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in if self?.previewMode != true { self?.panel?.orderOut(nil) } }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.panel?.isVisible == true { self?.panel?.orderOut(nil); return nil }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel?.isVisible == true else { return }
                guard let screen = NSScreen.screens.first(where: { self.displayID($0) == self.currentScreenID }) else {
                    self.panel?.orderOut(nil); return
                }
                self.present(on: screen, centeredAt: self.panel?.frame.midX ?? screen.visibleFrame.midX, takeFocus: false)
            }
        }
        // Preview builds never activate or place a window on an external display.
        if previewMode {
            DispatchQueue.main.async { self.showBuiltInPreview() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { NSApp.terminate(nil) }
        } else if !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.async { self.showPanel(takeFocus: false) }
        }
    }
    @objc private func togglePanel(_ sender: Any?) {
        if panel?.isVisible == true { panel?.orderOut(sender) } else { showPanel(takeFocus: true) }
    }
    private func showPanel(takeFocus: Bool) {
        if previewMode { showBuiltInPreview(); return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        present(on: screen, centeredAt: pointer.x, takeFocus: takeFocus)
    }
    private func present(on screen: NSScreen, centeredAt x: CGFloat, takeFocus: Bool) {
        let frame = PanelLayout.frame(in: screen.visibleFrame, centeredAt: x)
        currentScreenID = displayID(screen)
        if panel == nil {
            let window = AudioControlPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = previewMode ? "AudioRouter — MacBook layout preview" : "AudioRouter"
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .popUpMenu
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = window
        }
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: MenuPanel(model: AppModel.shared, size: frame.size))
        panel.setFrame(frame, display: true)
        if takeFocus { panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
    }
    private func showBuiltInPreview() {
        guard let screen = NSScreen.screens.first(where: { CGDisplayIsBuiltin(displayID($0)) != 0 }) else {
            writePreviewReport(["error": "Built-in display unavailable; no preview window was opened."])
            return
        }
        present(on: screen, centeredAt: screen.visibleFrame.midX, takeFocus: false)
        guard let panel else { return }
        let frame = panel.frame
        let visible = screen.visibleFrame
        writePreviewReport(["display": screen.localizedName, "builtIn": true, "contained": visible.contains(frame),
                            "window": NSStringFromRect(frame), "visibleFrame": NSStringFromRect(visible),
                            "focusRequested": false, "appActive": NSApp.isActive, "panelKey": panel.isKeyWindow])
    }
    private func writePreviewReport(_ report: [String: Any]) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "AudioRouterPreviewReport") as? String,
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(takeFocus: false); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stopAll()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}

struct RouteCard: View {
    let app: RoutableApplication
    @ObservedObject var model: AppModel
    var compact = false
    private var enabled: Bool { model.active.contains(app.id) }
    private var volume: Double { model.volume(app.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath)).resizable().frame(width: 24, height: 24)
                Text(app.name).font(.headline).lineLimit(1)
                Spacer()
                Button(enabled ? "Stop" : "Start") {
                    if enabled { model.stop(app.id) } else { model.start(app.id) }
                }.accessibilityLabel("\(enabled ? "Stop" : "Start") \(app.name) routing")
            }
            Picker("Output", selection: Binding(get: { model.selections[app.id] ?? "" }, set: { model.selectOutput(app.id, $0) })) {
                Text("Choose output").tag("")
                ForEach(model.devices) { Text($0.name).tag($0.uid) }
                if let uid = model.selections[app.id], !uid.isEmpty, !model.devices.contains(where: { $0.uid == uid }) {
                    Text("Disconnected output").tag(uid)
                }
            }.accessibilityLabel("\(app.name) output")
            HStack(spacing: 10) {
                Button { model.toggleMute(app.id) } label: {
                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 18)
                }.buttonStyle(.plain).help(volume == 0 ? "Unmute" : "Mute")
                    .accessibilityLabel("\(volume == 0 ? "Unmute" : "Mute") \(app.name)")
                Slider(value: Binding(get: { volume }, set: { model.setVolume(app.id, $0) }), in: 0...1)
                    .accessibilityLabel("\(app.name) volume")
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
            }
            Text(model.statuses[app.id] ?? (model.members(app.id).isEmpty ? "Ready • play a sound in this app" : "Ready"))
                .font(.caption).foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !compact {
                Text("\(model.members(app.id).count) audio process(es)" + (enabled ? " • \(model.sourceBuffers[app.id] ?? 0) source buffers received" : ""))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    var size = CGSize(width: 410, height: 620)
    @State private var search = ""
    private var shown: [RoutableApplication] {
        search.isEmpty ? model.menuApplications : model.applications.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AudioRouter").font(.headline)
                Spacer()
                Text(model.active.isEmpty ? "Ready" : "\(model.active.count) enabled").font(.caption).foregroundStyle(.secondary)
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).accessibilityLabel("Refresh apps and outputs")
            }
            TextField("Find an app", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(shown) { RouteCard(app: $0, model: model, compact: true) }
                    if shown.isEmpty { Text("Open an app and play audio to discover it.").foregroundStyle(.secondary).padding() }
                    Divider().padding(.vertical, 4)
                    DisclosureGroup("Audio helpers and assignments") {
                        HelperAssignmentList(model: model)
                    }.font(.caption)

                }
            }.frame(minHeight: 60, maxHeight: .infinity)
                .scrollIndicators(.visible)
            Toggle("Show all running apps", isOn: $model.showAllApps).font(.caption)
            if !model.discoveryError.isEmpty { Text(model.discoveryError).font(.caption).foregroundStyle(.red).lineLimit(2).help(model.discoveryError) }
            Text("Volume applies while routing. Stop restores ordinary playback.").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("0.2.2").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Stop All") { model.stopAll() }.disabled(model.active.isEmpty)
                Button("Quit") { NSApp.terminate(nil) }
            }.controlSize(.small)
        }.padding(16).frame(width: size.width, height: size.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct HelperAssignmentList: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assign only a helper you have identified. Changing an assignment stops all routes first.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.processes.sorted { a, b in a.active != b.active ? a.active : a.name < b.name }) { process in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(process.name.isEmpty ? "Audio process" : process.name)\(process.active ? " • playing" : "")")
                        .font(.caption).lineLimit(2)
                    if let id = process.applicationID {
                        Text("Matched to \(model.applications.first(where: { $0.id == id })?.name ?? id)")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Picker("Route with", selection: Binding(get: { model.assignments[process.id] ?? "" }, set: { model.assign(process.id, to: $0.isEmpty ? nil : $0) })) {
                            Text("Unassigned").tag("")
                            ForEach(model.applications) { Text($0.name).tag($0.id) }
                        }.accessibilityLabel("Assign \(process.name)")
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }
        }.padding(.top, 8)
    }
}
