import Foundation
import CoreAudio
import AudioBridge

// One aggregate clock drives tap input and chosen output. Core Audio performs
// sample-rate conversion / drift compensation for the tap at the device clock.
final class RouteSession {
    let device: OutputDevice
    let processes: Set<AudioObjectID>
    private var initialGain: Float = 1
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var bridge: OpaquePointer?
    private var description: CATapDescription?
    private var started = false
    private(set) var armed = false
    private var lastCycles: UInt64 = 0
    private var lastProgress = Date()
    private let created = Date()
    private var formatSignature: [AudioStreamBasicDescription] = []
    var signalBuffers: UInt64 { bridge.map { ar_signals($0) } ?? 0 }
    var callbackCount: UInt64 { bridge.map { ar_cycles($0) } ?? 0 }

    init(device: OutputDevice, processes: Set<AudioObjectID>, gain: Float = 1) throws {
        self.device = device; self.processes = processes; self.initialGain = gain
        guard !processes.isEmpty else { throw RoutingError(message: "No audio processes found. Play audio in this app first, or assign its helper below.") }
        do { try prepare() } catch { stop(); throw error }
    }
    private func prepare() throws {
        let d = CATapDescription(stereoMixdownOfProcesses: processes.sorted())
        d.name = "AudioRouter application tap"
        d.uuid = UUID(); d.isPrivate = true
        // Original playback remains intact until valid audio reaches our output callback.
        d.muteBehavior = .unmuted
        description = d
        try check(AudioHardwareCreateProcessTap(d, &tap), "Create process tap")
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioRouter → \(device.name)",
            kAudioAggregateDeviceUIDKey: "local.AudioRouter.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: device.uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.uid]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: d.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: false
        ]
        try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "Create private routing device")
        let rate = try HAL.value(device.id, kAudioDevicePropertyNominalSampleRate, default: Float64(0))
        var aggregateRate = rate, a = HAL.address(kAudioDevicePropertyNominalSampleRate)
        try check(AudioObjectSetPropertyData(aggregate, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &aggregateRate), "Match output sample rate")
        let hardwareInputs = try HAL.channels(device.id, kAudioObjectPropertyScopeInput)
        let inputs = try HAL.formats(aggregate, kAudioObjectPropertyScopeInput)
        let outputs = try HAL.formats(aggregate, kAudioObjectPropertyScopeOutput)
        // Aggregate streams are physical subdevice streams followed by subtap streams.
        // Reject anything inconsistent instead of copying microphone/unknown channels.
        guard inputs.reduce(0, { $0 + $1.mChannelsPerFrame }) == hardwareInputs + 2,
              inputs.last?.mChannelsPerFrame == 2,
              outputs.reduce(0, { $0 + $1.mChannelsPerFrame }) >= 2 else {
            throw RoutingError(message: "Unsupported aggregate channel layout. Ordinary playback is preserved. Try built-in speakers or a stereo USB output.")
        }
        for f in inputs + outputs {
            guard f.mFormatID == kAudioFormatLinearPCM,
                  f.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  f.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                  f.mBitsPerChannel == 32,
                  f.mFramesPerPacket == 1,
                  f.mBytesPerFrame == (f.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 4 : 4 * f.mChannelsPerFrame),
                  abs(f.mSampleRate - rate) < 1 else {
                throw RoutingError(message: "Unsupported device format. Requires stereo Float32 at the output clock rate; original playback has been restored.")
            }
        }
        formatSignature = inputs + outputs
        guard let b = ar_create(hardwareInputs, initialGain) else { throw RoutingError(message: "Unable to allocate audio state.") }
        bridge = b
        try check(ar_install(aggregate, b, &io), "Create audio callback")
        try check(ar_tap_input_only(aggregate, io, UInt32(inputs.count)), "Disable physical input streams")
        try check(AudioDeviceStart(aggregate, io), "Start routing")
        started = true
    }
    func setGain(_ gain: Float) { if let bridge { ar_set_gain(bridge, gain) } }
    func poll() throws -> String {
        guard let bridge else { throw RoutingError(message: "Routing stopped.") }
        guard (try HAL.value(device.id, kAudioDevicePropertyDeviceIsAlive, default: UInt32(0))) == 1 else {
            throw RoutingError(message: "Output disconnected. Routing stopped; ordinary playback restored.")
        }
        let formats = try HAL.formats(aggregate, kAudioObjectPropertyScopeInput) + HAL.formats(aggregate, kAudioObjectPropertyScopeOutput)
        guard formats.count == formatSignature.count, zip(formats, formatSignature).allSatisfy({ a, b in
            a.mSampleRate == b.mSampleRate && a.mChannelsPerFrame == b.mChannelsPerFrame && a.mFormatID == b.mFormatID && a.mFormatFlags == b.mFormatFlags && a.mBytesPerFrame == b.mBytesPerFrame
        }) else { throw RoutingError(message: "Device format changed. Routing stopped; press Start to reconnect.") }
        guard ar_errors(bridge) == 0 else { throw RoutingError(message: "Audio buffer layout changed. Routing stopped; ordinary playback restored.") }
        let cycles = ar_cycles(bridge)
        if cycles != lastCycles { lastProgress = Date(); lastCycles = cycles }
        if Date().timeIntervalSince(lastProgress) > 2 { throw RoutingError(message: "Output callbacks stalled. Routing stopped; check capture permission and output connection.") }
        if !armed, ar_signals(bridge) > 0, let d = description {
            d.muteBehavior = .mutedWhenTapped
            var a = HAL.address(kAudioTapPropertyDescription), ref = Unmanaged.passUnretained(d).toOpaque()
            try check(AudioObjectSetPropertyData(tap, &a, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &ref), "Suppress original playback")
            armed = true
        }
        if !armed && Date().timeIntervalSince(created) > 20 {
            return "Waiting for audio • if media is playing, check capture permission"
        }
        return armed ? "Routing" : "Waiting for audio • original playback remains on"
    }
    @discardableResult func stop() -> String? {
        var errors: [String] = []
        if tap != 0, let d = description {
            d.muteBehavior = .unmuted
            var a = HAL.address(kAudioTapPropertyDescription), ref = Unmanaged.passUnretained(d).toOpaque()
            let status = AudioObjectSetPropertyData(tap, &a, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &ref)
            if status != noErr { errors.append("unmute \(status)") }
        }
        if let bridge { ar_disable(bridge) }
        var callbackDetached = io == nil
        if aggregate != 0, let io {
            if started {
                let status = AudioDeviceStop(aggregate, io)
                if status != noErr { errors.append("stop \(status)") }
            }
            let status = AudioDeviceDestroyIOProcID(aggregate, io)
            callbackDetached = status == noErr
            if status != noErr { errors.append("detach callback \(status)") }
        }
        io = nil; started = false
        if aggregate != 0 {
            let status = AudioHardwareDestroyAggregateDevice(aggregate)
            if status == noErr { callbackDetached = true }
            else { errors.append("destroy device \(status)") }
            aggregate = 0
        }
        if tap != 0 {
            let status = AudioHardwareDestroyProcessTap(tap)
            if status != noErr { errors.append("destroy tap \(status)") }
            tap = 0
        }
        if let bridge {
            // If HAL failed to detach, deliberately retain disabled C state until
            // process exit instead of freeing memory a callback might still use.
            if callbackDetached { ar_free(bridge) }
            self.bridge = nil
        }
        armed = false
        return errors.isEmpty ? nil : "Core Audio cleanup reported: \(errors.joined(separator: ", ")). Quit AudioRouter if ordinary playback has not returned."
    }
    deinit { stop() }
}
