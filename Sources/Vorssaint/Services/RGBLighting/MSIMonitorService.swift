// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import AppKit
import IOKit.hid
import os

/// The lighting on the back of an MSI monitor (see `MSIMonitorProtocol`),
/// drawn frame by frame like the speakers', from the same clock, while RGB
/// lighting is on.
///
/// Frames need no reply and take about a millisecond, but go out at the same
/// pace as the speakers': OpenRGB found that back-to-back writes tie up the
/// monitor's control pipe until it stops answering. Neptater never writes
/// flash; on quit, or when RGB lighting is switched off, it hands the monitor
/// its own Rainbow Wave, the way the speakers get their spectrum back.
final class MSIMonitorService: ObservableObject {
    static let shared = MSIMonitorService()

    enum Status: Equatable {
        case absent
        /// Asking which lighting layout it speaks.
        case checking
        case ready
        case unsupported(layout: Int)
        case noAnswer
    }

    @Published private(set) var status = Status.absent
    /// The model, as the monitor names itself, without its "Monitor".
    @Published private(set) var name: String?

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "neptater", category: "msi-monitor")
    /// How long the layout answer may take (it comes within milliseconds).
    private static let answerTimeout: TimeInterval = 1
    /// The monitor may still set up its own lighting just after it appears on USB.
    private static let connectSettle: TimeInterval = 2
    /// Its own effect dims out a little quicker than a full fade, so the
    /// lighting isn't long in coming.
    private static let ownFadeDuration: TimeInterval = 0.6

    private let queue = DispatchQueue(label: "io.github.kuochiuhsiang.neptater.msi-monitor", qos: .userInitiated)
    private var manager: IOHIDManager?
    /// Touched only on the main thread; the queue gets the value it needs.
    private var device: IOHIDDevice?
    private var inputReport: UnsafeMutablePointer<UInt8>?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    /// Whether Neptater has read the monitor's own effect and started drawing; main thread.
    private var tookOver = false

    // Drawing state, touched only on `queue`.
    private var drawingDevice: IOHIDDevice?
    private var program: RGBLightingProgram?
    private var drawnColors: [RGBColor]?
    private var frameTimer: DispatchSourceTimer?
    private var drawingLevel: Double = 1

    private init() {}

    // MARK: - Lifecycle

    func syncWithPreferences() {
        if RGBLightingService.shared.isActive {
            start()
        } else if manager != nil {
            handBackLighting(always: true)
            stop()
        }
    }

    private func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Int] = [kIOHIDVendorIDKey: MSIMonitorProtocol.vendorID,
                                    kIOHIDProductIDKey: MSIMonitorProtocol.productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<MSIMonitorService>.fromOpaque(context).takeUnretainedValue().deviceAppeared(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<MSIMonitorService>.fromOpaque(context).takeUnretainedValue().deviceDisappeared(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.queue.async { self?.stopFrameTimer() }
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
        guard device == nil,
              IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        device = candidate
        let product = IOHIDDeviceGetProperty(candidate, kIOHIDProductKey as CFString) as? String
        name = product.map { $0.replacingOccurrences(of: "Monitor ", with: "") }
        status = .checking
        // The layout answer comes back as an input report.
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: MSIMonitorProtocol.queryLength)
        inputReport = buffer
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(candidate, buffer, MSIMonitorProtocol.queryLength,
                                               { context, _, _, _, _, report, length in
            guard let context else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<MSIMonitorService>.fromOpaque(context).takeUnretainedValue().received(bytes)
        }, context)
        IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        queue.async {
            let query = MSIMonitorProtocol.layoutQuery
            let sent = IOHIDDeviceSetReport(candidate, kIOHIDReportTypeOutput, CFIndex(MSIMonitorProtocol.queryReportID),
                                            query, query.count)
            if sent != kIOReturnSuccess { Self.log.error("layout query failed: \(sent, privacy: .public)") }
        }
        schedule(after: Self.answerTimeout) { [weak self] in
            if self?.status == .checking { self?.status = .noAnswer }
        }
    }

    private func received(_ report: [UInt8]) {
        guard status == .checking, let layout = MSIMonitorProtocol.layout(fromReply: report) else { return }
        guard layout == MSIMonitorProtocol.supportedLayout else {
            pending?.cancel()
            status = .unsupported(layout: layout)
            return
        }
        status = .ready
        schedule(after: Self.connectSettle) { [weak self] in
            guard let self, let device = self.device else { return }
            self.tookOver = true
            let settings = RGBLightingService.shared.settings
            self.queue.async { self.takeOver(settings, on: device) }
        }
    }

    private func deviceDisappeared(_ gone: IOHIDDevice) {
        guard let device, CFEqual(device, gone) else { return }
        closeDevice()
    }

    private func closeDevice() {
        pending?.cancel()
        pending = nil
        queue.sync { stopDrawing() }
        if let device {
            if let inputReport {
                IOHIDDeviceRegisterInputReportCallback(device, inputReport, MSIMonitorProtocol.queryLength, nil, nil)
            }
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        inputReport?.deallocate()
        inputReport = nil
        tookOver = false
        device = nil
        name = nil
        status = .absent
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem(block: work)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Lighting

    /// The RGB lighting changed; draw it from whatever shows now.
    func lightingChanged() {
        guard tookOver, let device else { return }
        let settings = RGBLightingService.shared.settings
        queue.async { [weak self] in self?.draw(settings, from: nil, on: device) }
    }

    func lightingLevelChanged() {
        let level = RGBLighting.levelFactor(percent: RGBLightingService.shared.settings.level)
        queue.async { [weak self] in
            guard let self else { return }
            self.drawingLevel = level
            self.drawFrame()
        }
    }

    // MARK: - Drawing (on `queue` only)

    /// After the monitor comes back (powered up, or switched back from another
    /// computer), it shows its own effect, whose colors can't be known: that
    /// fades out through its brightness, then the lighting fades in from
    /// black. A frame Neptater drew earlier is simply faded on from.
    private func takeOver(_ settings: RGBLightingChoice, on device: IOHIDDevice) {
        var report = [UInt8](repeating: 0, count: MSIMonitorProtocol.frameLength)
        var length = report.count
        let read = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(MSIMonitorProtocol.frameReportID),
                                        &report, &length)
        guard read == kIOReturnSuccess else {
            Self.log.error("reading the lighting failed: \(read, privacy: .public)")
            draw(settings, from: nil, on: device)
            return
        }
        let current = Array(report.prefix(length))
        if let drawn = MSIMonitorProtocol.colors(in: current) {
            draw(settings, from: drawn, on: device)
            return
        }
        fadeOut(current, on: device)
        let black = MSIMonitorProtocol.frame([])
        _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(MSIMonitorProtocol.frameReportID),
                                 black, black.count)
        drawnColors = Array(repeating: .black, count: MSIMonitorProtocol.ledCount)
        draw(settings, from: nil, on: device)
    }

    /// Dims the monitor's own effect to dark, paced like frames.
    private func fadeOut(_ effect: [UInt8], on device: IOHIDDevice) {
        guard let full = MSIMonitorProtocol.brightness(of: effect), full > 0 else { return }
        let begin = ProcessInfo.processInfo.systemUptime
        while true {
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - begin) / Self.ownFadeDuration)
            let level = Int((Double(full) * RGBLighting.fadeOutFactor(progress)).rounded())
            if let dimmed = MSIMonitorProtocol.dimmed(effect, to: level) {
                _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(MSIMonitorProtocol.frameReportID),
                                         dimmed, dimmed.count)
            }
            if progress >= 1 { return }
            Thread.sleep(forTimeInterval: RGBLighting.frameInterval)
        }
    }

    private func draw(_ settings: RGBLightingChoice, from start: [RGBColor]?, on device: IOHIDDevice) {
        drawingDevice = device
        drawingLevel = RGBLighting.levelFactor(percent: settings.level)
        let origin = start ?? drawnColors.flatMap { $0.allSatisfy { $0 == .black } ? nil : $0 }
        program = RGBLightingProgram(settings, start: origin, began: ProcessInfo.processInfo.systemUptime)
        drawFrame()
        if program != nil, frameTimer == nil { startFrameTimer() }
    }

    private func drawFrame() {
        guard let program, let device = drawingDevice else {
            stopFrameTimer()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let (colors, moving) = program.frame(at: now, effectTime: RGBLightingClock.shared.effectTime(at: now),
                                             level: drawingLevel, lights: RGBDesk.msiMonitor,
                                             screen: RGBScreenSampler.shared.latest,
                                             audio: RGBAudioPulse.shared.latest)
        if colors != drawnColors {
            let frame = MSIMonitorProtocol.frame(colors)
            let sent = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(MSIMonitorProtocol.frameReportID),
                                            frame, frame.count)
            guard sent == kIOReturnSuccess else {
                Self.log.error("monitor lighting failed: \(sent, privacy: .public)")
                stopFrameTimer()
                self.program = nil
                return
            }
            drawnColors = colors
        }
        if !moving { stopFrameTimer() }
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
        drawingDevice = nil
    }

    private func resumeDrawing() {
        guard program != nil, drawingDevice != nil, frameTimer == nil else { return }
        drawFrame()
        if program != nil { startFrameTimer() }
    }

    /// On quit a moving effect would freeze, so the monitor's Rainbow Wave
    /// takes over, at the brightness the slider set; a still one stays until
    /// the monitor powers off. When RGB lighting is switched off (`always`),
    /// the Rainbow Wave comes back at full brightness either way.
    private func handBackLighting(always: Bool) {
        let settings = RGBLightingService.shared.settings
        guard always || settings.shownMode.moves else { return }
        let level = always ? 1 : RGBLighting.levelFactor(percent: settings.level)
        let own = MSIMonitorProtocol.rainbowWave(brightness: MSIMonitorProtocol.brightness(forLevel: level))
        pending?.cancel()
        queue.sync {
            guard let device = drawingDevice else { return }
            stopFrameTimer()
            program = nil
            _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(MSIMonitorProtocol.frameReportID),
                                     own, own.count)
            drawnColors = nil
        }
    }
}
