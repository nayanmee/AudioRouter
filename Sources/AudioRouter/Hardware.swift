import Foundation
import CoreAudio
import AppKit
import AudioBridge

struct RoutingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw RoutingError(message: "\(operation) failed (Core Audio \(status)). If capture is denied, allow AudioRouter in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen it.") }
}
enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func value<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, default initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
        var result = initial, size = UInt32(MemoryLayout<T>.size), a = address(selector, scope)
        try withUnsafeMutablePointer(to: &result) { try check(AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0), "Read property \(selector)") }
        return result
    }
    static func ids(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var a = address(selector, scope), size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size), "Read list size")
        if size == 0 { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size)/4)
        try values.withUnsafeMutableBytes { try check(AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0.baseAddress!), "Read list") }
        return Array(values.prefix(Int(size)/4))
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector), result: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &result) == noErr, let result else { return "" }
        return result.takeRetainedValue() as String
    }
    static func formats(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) throws -> [AudioStreamBasicDescription] {
        try ids(device, kAudioDevicePropertyStreams, scope: scope).map {
            try value($0, kAudioStreamPropertyVirtualFormat, default: AudioStreamBasicDescription())
        }
    }
    static func channels(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) throws -> UInt32 {
        try formats(device, scope).reduce(0) { $0 + $1.mChannelsPerFrame }
    }
}
struct OutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    static func discover() throws -> [Self] {
        try HAL.ids(HAL.system, kAudioHardwarePropertyDevices).compactMap { id in
            let uid = HAL.string(id, kAudioDevicePropertyDeviceUID)
            let transport = try? HAL.value(id, kAudioDevicePropertyTransportType, default: UInt32(0))
            guard !uid.isEmpty, !uid.hasPrefix("local.AudioRouter."),
                  transport != kAudioDeviceTransportTypeAggregate,
                  transport != kAudioDeviceTransportTypeVirtual,
                  (try? HAL.channels(id, kAudioObjectPropertyScopeOutput)) ?? 0 >= 2,
                  (try? HAL.value(id, kAudioDevicePropertyDeviceIsAlive, default: UInt32(0))) == 1 else { return nil }
            return Self(id: id, uid: uid, name: HAL.string(id, kAudioObjectPropertyName))
        }.sorted { $0.name < $1.name }
    }
}
enum Browser: String, CaseIterable, Identifiable {
    case safari = "com.apple.Safari", chrome = "com.google.Chrome"
    var id: String { rawValue }
    var name: String { self == .safari ? "Safari" : "Google Chrome" }
}
struct AudioProcess: Identifiable {
    let id: AudioObjectID
    let pid: pid_t
    let bundle: String
    let name: String
    let path: String
    let browser: Browser?
    let applicationID: String?
    let active: Bool
    static func classify(bundle: String, path: String, ancestors: Set<pid_t>, roots: [Browser: Set<pid_t>], displayName: String = "", safariName: String = "Safari") -> Browser? {
        for browser in Browser.allCases {
            if bundle == browser.rawValue || bundle.hasPrefix(browser.rawValue + ".") { return browser }
            if !(roots[browser] ?? []).isDisjoint(with: ancestors) { return browser }
        }
        if path.contains("/Google Chrome.app/Contents/") { return .chrome }
        if path.contains("/Safari.app/Contents/") { return .safari }
        // Safari's XPC audio helper is parented by launchd, with a generic bundle ID.
        // NSRunningApplication exposes its host-qualified system display name.
        // Require the Apple system executable, exact role/name, and a running Safari.
        // A generic WebKit process or another application's GPU helper is not enough.
        let role: String?
        switch bundle {
        case "com.apple.WebKit.GPU": role = "Graphics and Media"
        case "com.apple.WebKit.WebContent": role = "Web Content"
        default: role = nil
        }
        if let role, !(roots[.safari] ?? []).isEmpty,
           path.hasPrefix("/System/"), path.contains("/WebKit.framework/"),
           displayName == "\(safariName) \(role)" {
            return .safari
        }
        // Unknown/localized role names remain available for explicit assignment.
        return nil
    }
    static func owner(bundle: String, path: String, ancestors: Set<pid_t>, displayName: String, applications: [RoutableApplication]) -> String? {
        // Specific bundle identities win over broader prefixes (e.g. nested apps).
        for app in applications.sorted(by: { $0.id.count > $1.id.count }) {
            if bundle == app.id || bundle.hasPrefix(app.id + ".") { return app.id }
        }
        let parents = applications.filter { !$0.pids.isDisjoint(with: ancestors) }
        if parents.count == 1 { return parents[0].id }
        for app in applications.sorted(by: { $0.bundlePath.count > $1.bundlePath.count }) {
            if !app.bundlePath.isEmpty && path.hasPrefix(app.bundlePath + "/Contents/") { return app.id }
        }
        let roots = Dictionary(uniqueKeysWithValues: Browser.allCases.map { browser in
            (browser, applications.first(where: { $0.id == browser.rawValue })?.pids ?? [])
        })
        let browser = classify(bundle: bundle, path: path, ancestors: ancestors, roots: roots, displayName: displayName,
                               safariName: applications.first(where: { $0.id == Browser.safari.rawValue })?.name ?? "Safari")
        return browser.flatMap { b in applications.contains(where: { $0.id == b.rawValue }) ? b.rawValue : nil }
    }
    static func discover(applications: [RoutableApplication]) throws -> [Self] {
        let apps = NSWorkspace.shared.runningApplications
        let roots = Dictionary(uniqueKeysWithValues: Browser.allCases.map { b in
            (b, Set(apps.filter { $0.bundleIdentifier == b.rawValue }.map(\.processIdentifier)))
        })
        return try HAL.ids(HAL.system, kAudioHardwarePropertyProcessObjectList).compactMap { id in
            guard let pid = try? HAL.value(id, kAudioProcessPropertyPID, default: pid_t(0)), pid > 0, pid != getpid() else { return nil }
            let bundle = HAL.string(id, kAudioProcessPropertyBundleID)
            guard bundle != "local.nayan.AudioRouter", !bundle.hasPrefix("local.nayan.AudioRouter.") else { return nil }
            var buffer = [CChar](repeating: 0, count: 4096)
            let length = ar_path(pid, &buffer, UInt32(buffer.count))
            let app = NSRunningApplication(processIdentifier: pid)
            let path = length > 0 ? String(cString: buffer) : (app?.executableURL?.path ?? "")
            var ancestors: Set<pid_t> = [pid], parent = pid
            for _ in 0..<24 {
                parent = ar_parent(parent)
                if parent <= 1 || ancestors.contains(parent) { break }
                ancestors.insert(parent)
            }
            let name = app?.localizedName ?? (path.isEmpty ? bundle : URL(fileURLWithPath: path).lastPathComponent)
            return Self(id: id, pid: pid, bundle: bundle, name: name, path: path,
                        browser: classify(bundle: bundle, path: path, ancestors: ancestors, roots: roots, displayName: name,
                                          safariName: apps.first(where: { $0.bundleIdentifier == Browser.safari.rawValue })?.localizedName ?? "Safari"),
                        applicationID: owner(bundle: bundle, path: path, ancestors: ancestors, displayName: name, applications: applications),
                        active: (try? HAL.value(id, kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) == 1)
        }
    }
}

struct RoutableApplication: Identifiable, Hashable {
    let id: String
    let name: String
    let bundlePath: String
    let pids: Set<pid_t>
    static let favorites: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.todesktop.230313mzl4w4u92"]
    static func discover() -> [Self] {
        let ownID = Bundle.main.bundleIdentifier ?? "local.nayan.AudioRouter"
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != ownID && $0.bundleIdentifier != "local.nayan.AudioRouter"
        }
        var result: [String: Self] = [:]
        for app in running {
            guard let id = app.bundleIdentifier, let url = app.bundleURL else { continue }
            let pids = (result[id]?.pids ?? []).union([app.processIdentifier])
            result[id] = Self(id: id, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, bundlePath: url.path, pids: pids)
        }
        for id in favorites where result[id] == nil {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            result[id] = Self(id: id, name: url.deletingPathExtension().lastPathComponent, bundlePath: url.path, pids: [])
        }
        return result.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
