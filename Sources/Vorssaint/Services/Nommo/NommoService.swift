// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation
import IOKit.hid
import os

/// Subwoofer, EQ and standby for a Razer Nommo V2 on USB.
///
/// Commands go out one at a time on a serial queue, each waiting for the
/// speaker's reply before the next: back-to-back writes have left the left
/// speaker stuck dim. A good status doesn't prove the speaker applied a write,
/// so every write is read back, and the panel shows what the speaker reports.
///
/// The speaker keeps its subwoofer level, EQ and standby settings while off,
/// so connecting only reads them. Its lighting it can neither keep nor report,
/// so Neptater stores the chosen lighting and puts it back after a power-up or
/// a built-in EQ mode's color. Nothing polls: state refreshes when the panel or
/// Settings shows it.
final class NommoService: ObservableObject {
    static let shared = NommoService()

    struct State: Equatable {
        var firmware: String?
        var subwoofer: Int?
        var eq: NommoEQState?
        var autoStandby: Bool?
        var standbyDelay: NommoStandbyDelay?
    }

    enum Failure: Equatable {
        case noReply
    }

    @Published private(set) var isConnected = false
    @Published private(set) var state = State()
    @Published private(set) var failure: Failure?
    @Published private(set) var presets: [NommoEQPreset: NommoEQCurve]
    @Published private(set) var lighting: NommoLighting

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "neptater", category: "nommo")
    private static let readAttempts = 3
    private static let readRetryDelay: TimeInterval = 0.5
    /// Slider drags arrive many times a second; only the last curve is sent.
    private static let curveWriteDelay: TimeInterval = 0.2

    private let queue = DispatchQueue(label: "io.github.kuochiuhsiang.neptater.nommo", qos: .userInitiated)
    private var manager: IOHIDManager?
    /// Touched only on the main thread; the queue gets the value it needs.
    private var device: IOHIDDevice?
    private var pendingCurve: DispatchWorkItem?
    private var pendingLighting: DispatchWorkItem?

    private init() {
        presets = NommoEQPresetStore.decode(UserDefaults.standard.string(forKey: DefaultsKey.nommoEQPresets))
        lighting = UserDefaults.standard.string(forKey: DefaultsKey.nommoLighting)
            .flatMap(NommoLighting.init(rawValue:)) ?? .off
    }

    var selection: NommoEQSelection { NommoEQSelection(state: state.eq, presets: presets) }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        AppFeature.nommo.isAvailable ? start() : stop()
    }

    private func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Int] = [kIOHIDVendorIDKey: NommoProtocol.vendorID,
                                    kIOHIDProductIDKey: NommoProtocol.productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<NommoService>.fromOpaque(context).takeUnretainedValue().deviceAppeared(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<NommoService>.fromOpaque(context).takeUnretainedValue().deviceDisappeared(device)
        }, context)
        // Only the control interface gets opened, in deviceAppeared; opening the
        // manager would open every interface of the speaker.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
    }

    private func stop() {
        pendingCurve?.cancel()
        pendingCurve = nil
        pendingLighting?.cancel()
        pendingLighting = nil
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        manager = nil
        closeDevice()
    }

    private func deviceAppeared(_ candidate: IOHIDDevice) {
        let reportSize = IOHIDDeviceGetProperty(candidate, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
        guard device == nil, reportSize >= NommoProtocol.minimumControlReportSize,
              IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        device = candidate
        isConnected = true
        failure = nil
        refresh()
        restoreLighting(after: NommoLighting.connectSettle)
    }

    private func deviceDisappeared(_ gone: IOHIDDevice) {
        guard let device, CFEqual(device, gone) else { return }
        closeDevice()
    }

    private func closeDevice() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        isConnected = false
        state = State()
    }

    // MARK: - Reading

    /// Re-reads everything; called on connect and whenever a view appears.
    /// The first reads after the speaker powers on can fail, hence the retries.
    func refresh() {
        perform { exchange in
            var lastError: Error?
            for attempt in 1...Self.readAttempts {
                do {
                    return try Self.readState(exchange)
                } catch {
                    lastError = error
                    if attempt < Self.readAttempts { Thread.sleep(forTimeInterval: Self.readRetryDelay) }
                }
            }
            throw lastError ?? ExchangeError.noReply
        }
    }

    private static func readState(_ exchange: Exchange) throws -> State {
        var state = State()
        state.firmware = (try? exchange(.readFirmware)).flatMap { NommoProtocol.firmwareVersion(from: $0.arguments) }
        state.subwoofer = Int(try exchange(.readSubwoofer).arguments[1])
        state.eq = try readEQ(exchange)
        state.autoStandby = try exchange(.readAutoStandby).arguments[1] == 0x01
        state.standbyDelay = NommoStandbyDelay(bytes: try exchange(.readStandbyDelay).arguments)
        return state
    }

    private static func readEQ(_ exchange: Exchange) throws -> NommoEQState {
        let mode = try exchange(.readEQMode).arguments[1]
        guard mode == NommoEQState.customModeByte else { return NommoEQState(modeByte: mode, curve: nil) }
        let curve = NommoEQCurve(bytes: Array(try exchange(.readEQCurve).arguments.dropFirst()))
        return NommoEQState(modeByte: mode, curve: curve)
    }

    // MARK: - Writing

    func setSubwoofer(_ level: Int) {
        let level = NommoSubwoofer.clamped(level)
        state.subwoofer = level
        perform { exchange in
            _ = try exchange(.writeSubwoofer(level))
            return try Self.readState(exchange)
        }
    }

    func select(_ selection: NommoEQSelection) {
        switch selection {
        case let .builtIn(mode):
            perform { exchange in
                _ = try exchange(.selectBuiltIn(mode))
                return try Self.readState(exchange)
            }
            // The mode's color shows for a moment, then the chosen lighting returns.
            restoreLighting(after: NommoLighting.eqColorHold)
        case let .preset(preset):
            guard let curve = presets[preset] else { return }
            writeCurve(curve, after: 0)
        case .otherCustom, .unknown:
            break
        }
    }

    /// Saves an edited preset and plays it, so the change is heard while dragging.
    func update(_ preset: NommoEQPreset, curve: NommoEQCurve) {
        guard preset.isEditable else { return }
        presets[preset] = curve
        UserDefaults.standard.set(NommoEQPresetStore.encode(presets), forKey: DefaultsKey.nommoEQPresets)
        state.eq = .custom(curve)
        writeCurve(curve, after: Self.curveWriteDelay)
    }

    func restoreSuggestion(for preset: NommoEQPreset) {
        update(preset, curve: preset.suggestedCurve)
    }

    func setAutoStandby(_ isOn: Bool) {
        state.autoStandby = isOn
        perform { exchange in
            _ = try exchange(.writeAutoStandby(isOn))
            return try Self.readState(exchange)
        }
    }

    func setStandbyDelay(_ delay: NommoStandbyDelay) {
        state.standbyDelay = delay
        perform { exchange in
            _ = try exchange(.writeStandbyDelay(delay))
            return try Self.readState(exchange)
        }
    }

    func setLighting(_ lighting: NommoLighting) {
        self.lighting = lighting
        UserDefaults.standard.set(lighting.rawValue, forKey: DefaultsKey.nommoLighting)
        restoreLighting(after: 0)
    }

    private func restoreLighting(after delay: TimeInterval) {
        pendingLighting?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let commands = self.lighting.commands
            self.perform { exchange in
                for command in commands { _ = try exchange(command) }
                return nil
            }
        }
        pendingLighting = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func writeCurve(_ curve: NommoEQCurve, after delay: TimeInterval) {
        pendingCurve?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.perform { exchange in
                // Writing a curve also switches the speaker to its custom mode.
                _ = try exchange(.writeEQCurve(curve))
                return try Self.readState(exchange)
            }
        }
        pendingCurve = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Transport

    private typealias Exchange = (NommoCommand) throws -> NommoReply

    private enum ExchangeError: Error {
        case transport(IOReturn)
        case noReply
        case unexpectedReply
    }

    /// Runs `work` on the serial queue with the current device and publishes
    /// the state it returns (nil leaves it as it is), or the failure.
    private func perform(_ work: @escaping (Exchange) throws -> State?) {
        guard let device else { return }
        queue.async { [weak self] in
            let result = Result { try work { try Self.exchange($0, with: device) } }
            DispatchQueue.main.async {
                guard let self, self.device.map({ CFEqual($0, device) }) == true else { return }
                switch result {
                case let .success(state):
                    if let state { self.state = state }
                    self.failure = nil
                case let .failure(error):
                    Self.log.error("speaker exchange failed: \(String(describing: error), privacy: .public)")
                    self.failure = .noReply
                }
            }
        }
    }

    /// One command, then polling until the speaker has its reply ready.
    @discardableResult
    private static func exchange(_ command: NommoCommand, with device: IOHIDDevice) throws -> NommoReply {
        let request = NommoProtocol.request(command)
        let sent = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(NommoProtocol.reportID),
                                        request, request.count)
        guard sent == kIOReturnSuccess else { throw ExchangeError.transport(sent) }
        for _ in 0..<NommoProtocol.replyAttempts {
            usleep(NommoProtocol.replyDelayMicroseconds)
            var buffer = [UInt8](repeating: 0, count: NommoProtocol.reportLength)
            var length = buffer.count
            let received = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(NommoProtocol.reportID),
                                                &buffer, &length)
            guard received == kIOReturnSuccess else { throw ExchangeError.transport(received) }
            guard let reply = NommoProtocol.reply(from: Array(buffer.prefix(length))), !reply.isPending else {
                continue
            }
            guard reply.answers(command) else { throw ExchangeError.unexpectedReply }
            return reply
        }
        throw ExchangeError.noReply
    }
}
