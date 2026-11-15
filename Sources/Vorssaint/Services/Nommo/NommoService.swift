// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import AppKit
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
/// so while RGB lighting is on, Neptater draws the chosen lighting frame by
/// frame (see `RGBLighting`), taking over again after a power-up or a built-in
/// EQ mode's color. Nothing polls: state refreshes when the panel or Settings
/// shows it.
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
    private var observers: [NSObjectProtocol] = []
    /// Whether this service draws the RGB lighting; main thread.
    private var drawsLighting = false

    // Drawing state, touched only on `queue`.
    private var drawingDevice: IOHIDDevice?
    private var program: RGBLightingProgram?
    private var drawnColors: [RGBColor]?
    /// Whether the speakers show host frames; a power-up or a built-in mode ends it.
    private var inFrameMode = false
    private var frameTimer: DispatchSourceTimer?
    private var drawingLevel: Double = 1

    private init() {
        presets = NommoEQPresetStore.decode(UserDefaults.standard.string(forKey: DefaultsKey.nommoEQPresets))
    }

    var selection: NommoEQSelection { NommoEQSelection(state: state.eq, presets: presets, preferring: presetInUse) }
    private var presetInUse: NommoEQPreset?

    // MARK: - Lifecycle

    /// Runs for the speaker's own controls, or to draw RGB lighting.
    func syncWithPreferences() {
        guard AppFeature.nommo.isAvailable || RGBLightingService.shared.isActive else {
            if drawsLighting { handBackLighting(always: true) }
            drawsLighting = false
            stop()
            return
        }
        start()
        let draws = RGBLightingService.shared.isActive
        guard draws != drawsLighting else { return }
        drawsLighting = draws
        draws ? drawChosenLighting() : handBackLighting(always: true)
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
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.queue.async { self?.pauseDrawing() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.queue.async { self?.resumeDrawing() }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                self?.handBackLighting(always: false)
            },
        ]
    }

    private func stop() {
        pendingCurve?.cancel()
        pendingCurve = nil
        pendingLighting?.cancel()
        pendingLighting = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
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
        // The speakers run their own power-up animation first; take over after it.
        guard drawsLighting else { return }
        schedule(after: NommoLighting.connectSettle) { [weak self] in
            guard let self, self.drawsLighting, let device = self.device else { return }
            let settings = RGBLightingService.shared.settings
            self.queue.async { self.takeOver(settings, on: device) }
        }
    }

    private func deviceDisappeared(_ gone: IOHIDDevice) {
        guard let device, CFEqual(device, gone) else { return }
        closeDevice()
    }

    private func closeDevice() {
        pendingLighting?.cancel()
        pendingLighting = nil
        queue.async { [weak self] in self?.stopDrawing() }
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
            guard let device else { return }
            presetInUse = nil
            if drawsLighting {
                // Stop drawing first, or the next frame would cover the mode's color.
                pendingLighting?.cancel()
                queue.async { [weak self] in self?.yield(to: mode) }
            }
            perform { exchange in
                _ = try exchange(.selectBuiltIn(mode))
                return try Self.readState(exchange)
            }
            // The mode's color shows for a moment, then flows into the chosen lighting.
            guard drawsLighting else { return }
            schedule(after: NommoLighting.eqColorHold) { [weak self] in
                guard let self, self.drawsLighting else { return }
                let settings = RGBLightingService.shared.settings
                let indicator = Array(repeating: mode.indicatorColor, count: NommoLighting.ledCount)
                self.queue.async { self.draw(settings, from: indicator, on: device) }
            }
        case let .preset(preset):
            guard let curve = presets[preset] else { return }
            presetInUse = preset
            writeCurve(curve, after: 0)
        case .otherCustom, .unknown:
            break
        }
    }

    /// A drag on the chart: saved to the EQ in use, or for a built-in mode
    /// copied into the preset of the same name, which then plays.
    func editCurve(_ curve: NommoEQCurve) {
        guard let preset = selection.editablePreset else { return }
        update(preset, curve: curve)
    }

    /// Saves an edited preset and plays it, so the change is heard while dragging.
    func update(_ preset: NommoEQPreset, curve: NommoEQCurve) {
        guard preset.isEditable else { return }
        presetInUse = preset
        presets[preset] = curve
        UserDefaults.standard.set(NommoEQPresetStore.encode(presets), forKey: DefaultsKey.nommoEQPresets)
        state.eq = .custom(curve)
        writeCurve(curve, after: Self.curveWriteDelay)
    }

    func restoreRazerCurve(for preset: NommoEQPreset) {
        update(preset, curve: preset.razerCurve)
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

    /// The RGB lighting changed; draw it from whatever shows now.
    func lightingChanged() {
        guard drawsLighting else { return }
        drawChosenLighting()
    }

    /// Takes effect on the next frame, so a slider drag is followed live.
    func lightingLevelChanged() {
        let level = RGBLighting.levelFactor(percent: RGBLightingService.shared.settings.level)
        queue.async { [weak self] in
            guard let self else { return }
            self.drawingLevel = level
            self.drawFrame()
        }
    }

    private func drawChosenLighting() {
        pendingLighting?.cancel()
        guard let device else { return }
        let settings = RGBLightingService.shared.settings
        queue.async { [weak self] in self?.draw(settings, from: nil, on: device) }
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        pendingLighting?.cancel()
        let item = DispatchWorkItem(block: work)
        pendingLighting = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Drawing (on `queue` only)

    /// Starts drawing `settings`, from `start` or, when nil, from whatever is
    /// on the LEDs now, so a change of mind mid-fade carries on from there.
    private func draw(_ settings: RGBLightingChoice, from start: [RGBColor]?, on device: IOHIDDevice) {
        drawingDevice = device
        drawingLevel = RGBLighting.levelFactor(percent: settings.level)
        let origin = start ?? drawnColors.flatMap { $0.allSatisfy { $0 == .black } ? nil : $0 }
        program = RGBLightingProgram(settings, start: origin, began: ProcessInfo.processInfo.systemUptime)
        do {
            if !inFrameMode {
                // Frame first, so entering frame mode shows it rather than an old one.
                try sendFrame(currentFrame().colors, to: device)
                _ = try Self.exchange(.enterFrameMode, with: device)
                inFrameMode = true
            }
        } catch {
            drawingFailed(error)
            return
        }
        drawFrame()
        if program != nil, frameTimer == nil { startFrameTimer() }
    }

    /// After a power-up the speakers run their own animation, whose colors
    /// Neptater can't know, so this one fade goes through the brightness.
    private func takeOver(_ settings: RGBLightingChoice, on device: IOHIDDevice) {
        stopDrawing()
        drawingDevice = device
        let black = Array(repeating: RGBColor.black, count: NommoLighting.ledCount)
        do {
            let brightness = try currentBrightness(on: device)
            try fadeBrightness(from: brightness, to: 0, on: device)
            try sendFrame(black, to: device)
            _ = try Self.exchange(.enterFrameMode, with: device)
            try sendFrame(black, to: device)
            inFrameMode = true
            // Unseen behind black, and where the drawn fade in needs it.
            _ = try Self.exchange(.writeBrightness(brightness), with: device)
        } catch {
            drawingFailed(error)
            return
        }
        draw(settings, from: nil, on: device)
    }

    /// A built-in mode takes the LEDs: stop drawing and leave its color showing.
    private func yield(to mode: NommoBuiltInMode) {
        stopFrameTimer()
        program = nil
        inFrameMode = false
        drawnColors = Array(repeating: mode.indicatorColor, count: NommoLighting.ledCount)
    }

    private func currentFrame() -> (colors: [RGBColor], moving: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        return program?.frame(at: now, effectTime: RGBLightingClock.shared.effectTime(at: now), level: drawingLevel,
                              lights: RGBDesk.nommo, screen: RGBScreenSampler.shared.latest,
                              audio: RGBAudioPulse.shared.latest)
            ?? (Array(repeating: .black, count: NommoLighting.ledCount), false)
    }

    private func drawFrame() {
        guard program != nil, let device = drawingDevice else {
            stopFrameTimer()
            return
        }
        let (colors, moving) = currentFrame()
        do {
            if colors != drawnColors { try sendFrame(colors, to: device) }
        } catch {
            drawingFailed(error)
            return
        }
        if !moving { stopFrameTimer() }
    }

    private func sendFrame(_ colors: [RGBColor], to device: IOHIDDevice) throws {
        _ = try Self.exchange(.frame(colors), with: device)
        drawnColors = colors
    }

    private func startFrameTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + RGBLighting.frameInterval, repeating: RGBLighting.frameInterval,
                       leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.drawFrame() }
        frameTimer = timer
        timer.resume()
    }

    private func stopFrameTimer() {
        frameTimer?.cancel()
        frameTimer = nil
    }

    private func stopDrawing() {
        stopFrameTimer()
        program = nil
        drawnColors = nil
        inFrameMode = false
        drawingDevice = nil
    }

    private func pauseDrawing() {
        stopFrameTimer()
    }

    private func resumeDrawing() {
        guard program != nil, drawingDevice != nil, frameTimer == nil else { return }
        drawFrame()
        if program != nil { startFrameTimer() }
    }

    private func drawingFailed(_ error: Error) {
        stopFrameTimer()
        program = nil
        Self.log.error("speaker lighting failed: \(String(describing: error), privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.failure = .noReply }
    }

    /// On quit a drawn rainbow would freeze, so the speakers' own takes over,
    /// at the brightness the slider set; the next takeover restores theirs.
    /// When RGB lighting is switched off (`always`), the speakers get their own
    /// animation back whatever was drawn.
    private func handBackLighting(always: Bool) {
        let settings = RGBLightingService.shared.settings
        guard always || settings.shownMode.moves else { return }
        let level = always ? 1 : RGBLighting.levelFactor(percent: settings.level)
        pendingLighting?.cancel()
        queue.sync {
            guard let device = drawingDevice else { return }
            stopFrameTimer()
            program = nil
            inFrameMode = false
            let brightness = (try? currentBrightness(on: device)) ?? NommoLighting.fullBrightness
            _ = try? Self.exchange(.writeBrightness(Int((Double(brightness) * level).rounded())), with: device)
            _ = try? Self.exchange(.resumeAnimation, with: device)
        }
    }

    /// The brightness fades return to; the first time, the speakers' own.
    private func currentBrightness(on device: IOHIDDevice) throws -> Int {
        if Self.brightnessIsSaved {
            return NommoLighting.clampedBrightness(UserDefaults.standard.integer(forKey: DefaultsKey.nommoLightingBrightness))
        }
        let current = Int(try Self.exchange(.readBrightness, with: device).arguments[2])
        guard current > 0 else { return NommoLighting.fullBrightness }
        UserDefaults.standard.set(current, forKey: DefaultsKey.nommoLightingBrightness)
        return current
    }

    private static var brightnessIsSaved: Bool {
        guard let domain = Bundle.main.bundleIdentifier else { return false }
        return UserDefaults.standard.persistentDomain(forName: domain)?[DefaultsKey.nommoLightingBrightness] != nil
    }

    /// Paced like frames; the brightness command still stalls now and then.
    private func fadeBrightness(from start: Int, to end: Int, on device: IOHIDDevice) throws {
        let begin = ProcessInfo.processInfo.systemUptime
        var written: Int?
        while true {
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - begin) / RGBLighting.fadeDuration)
            let level = NommoLighting.fadeLevel(from: start, to: end, progress: progress)
            if level != written {
                _ = try Self.exchange(.writeBrightness(level), with: device)
                written = level
            }
            if progress >= 1 { return }
            Thread.sleep(forTimeInterval: RGBLighting.frameInterval)
        }
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
