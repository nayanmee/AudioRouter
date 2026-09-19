import SwiftUI
import AppKit
import CoreAudio

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var devices: [OutputDevice] = []
    @Published var applications: [RoutableApplication] = []
    @Published var processes: [AudioProcess] = []
    @Published private(set) var selections: [String: String] = [:]
    @Published private(set) var volumes: [String: Double] = [:]
    @Published var statuses: [String: String] = [:]
    @Published var assignments: [AudioObjectID: String] = [:]
    @Published var active: Set<String> = []
    @Published var sourceBuffers: [String: UInt64] = [:]
    @Published var discoveryError = ""
    @Published var showAllApps = false
    private var sessions: [String: RouteSession] = [:]
    private var unmutedVolumes: [String: Double] = [:]
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var tick = 0
    private let defaults: UserDefaults
    var menuApplications: [RoutableApplication] {
        applications.filter { showAllApps || RoutableApplication.favorites.contains($0.id) || !members($0.id).isEmpty || active.contains($0.id) }.sorted { a, b in
            let first = RoutableApplication.favorites.contains(a.id), second = RoutableApplication.favorites.contains(b.id)
            return first != second ? first : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    init(defaults: UserDefaults = .standard, monitor: Bool = true) {
        self.defaults = defaults
        selections = defaults.dictionary(forKey: "outputSelections") as? [String: String] ?? [:]
        volumes = (defaults.dictionary(forKey: "appVolumes") as? [String: Double] ?? [:]).mapValues { $0.isFinite ? min(1, max(0, $0)) : 1 }
        guard monitor else { return }
        refresh()
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopAll(message: "Stopped for sleep; press Start after waking.") }
        }
    }
    func refresh() {
        do {
            let newDevices = try OutputDevice.discover()
            var newApps = RoutableApplication.discover()
            let newProcesses = try AudioProcess.discover(applications: newApps)
            let old = Dictionary(uniqueKeysWithValues: processes.map { ($0.id, $0.pid) })
            assignments = assignments.filter { id, _ in newProcesses.contains { $0.id == id && $0.pid == old[id] && $0.applicationID == nil } }
            // Keep an explicitly enabled application visible while it exits/restarts.
            newApps += applications.filter { previous in active.contains(previous.id) && !newApps.contains(where: { $0.id == previous.id }) }
            devices = newDevices; applications = newApps.sorted { $0.name < $1.name }; processes = newProcesses
            discoveryError = ""
            let defaultID = try? HAL.value(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
            let defaultUID = devices.first(where: { $0.id == defaultID })?.uid ?? devices.first?.uid
            for app in applications where selections[app.id] == nil { selections[app.id] = defaultUID }
        } catch {
            discoveryError = "Discovery failed: \(error.localizedDescription)"
            stopAll(message: "Stopped because device/process discovery failed.")
        }
    }
    func members(_ id: String) -> Set<AudioObjectID> {
        Set(processes.filter { (assignments[$0.id] ?? $0.applicationID) == id }.map(\.id))
    }
    func volume(_ id: String) -> Double { volumes[id] ?? 1 }
    func setVolume(_ id: String, _ value: Double) {
        let value = value.isFinite ? min(1, max(0, value)) : 0
        volumes[id] = value
        if value > 0 { unmutedVolumes[id] = value }
        sessions[id]?.setGain(Float(value))
        defaults.set(volumes, forKey: "appVolumes")
    }
    func toggleMute(_ id: String) {
        let current = volume(id)
        if current > 0 { unmutedVolumes[id] = current; setVolume(id, 0) }
        else { setVolume(id, unmutedVolumes[id] ?? 1) }
    }
    func selectOutput(_ id: String, _ uid: String) {
        let restart = active.contains(id)
        let clean = !restart || stop(id)
        selections[id] = uid; defaults.set(selections, forKey: "outputSelections")
        if restart && clean { start(id) }
    }
    func start(_ id: String) {
        guard !active.contains(id) else { return }
        refresh()
        guard devices.contains(where: { $0.uid == selections[id] }) else {
            statuses[id] = "Select a connected stereo hardware output."; return
        }
        active.insert(id)
        connect(id)
    }
    private func connect(_ id: String) {
        guard let device = devices.first(where: { $0.uid == selections[id] }) else {
            stop(id, message: "Output disconnected. Ordinary playback restored."); return
        }
        let ids = members(id)
        guard !ids.isEmpty else {
            statuses[id] = "Waiting for app audio • open the app and play a sound"; return
        }
        guard sessions.values.allSatisfy({ $0.processes.isDisjoint(with: ids) }) else {
            stop(id, message: "An audio helper is already routed by another app."); return
        }
        do {
            sessions[id] = try RouteSession(device: device, processes: ids, gain: Float(volume(id)))
            statuses[id] = "Starting • waiting for app audio"
        } catch { stop(id, message: error.localizedDescription) }
    }
    @discardableResult func stop(_ id: String, message: String = "Stopped • ordinary playback restored") -> Bool {
        let cleanup = sessions.removeValue(forKey: id)?.stop()
        active.remove(id); sourceBuffers[id] = nil; statuses[id] = cleanup ?? message
        return cleanup == nil
    }
    func stopAll(message: String = "Stopped • ordinary playback restored") {
        for id in Array(active) { stop(id, message: message) }
    }
    func assign(_ process: AudioObjectID, to appID: String?) {
        stopAll(message: "Stopped for helper reassignment. Press Start to apply.")
        assignments[process] = appID
    }
    private func poll() {
        tick += 1
        if tick % 4 == 0 { refresh() }
        for id in Array(active) {
            guard devices.contains(where: { $0.uid == selections[id] }) else {
                stop(id, message: "Output disconnected. Ordinary playback restored; select an output and press Start."); continue
            }
            guard let session = sessions[id] else { connect(id); continue }
            guard devices.contains(where: { $0.uid == session.device.uid && $0.id == session.device.id }) else {
                stop(id, message: "Output changed or disconnected. Press Start to reconnect."); continue
            }
            if members(id) != session.processes {
                if stop(id, message: "Audio processes changed; reconnecting…") { active.insert(id); connect(id) }
                continue
            }
            do {
                let status = try session.poll()
                statuses[id] = session.armed && volume(id) == 0 ? "Muted • routing remains active" : status
                sourceBuffers[id] = session.signalBuffers
            } catch { stop(id, message: error.localizedDescription) }
        }
    }
}
