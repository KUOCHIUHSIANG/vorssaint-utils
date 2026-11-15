// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import AppKit
import CoreMedia
import ScreenCaptureKit
import os

/// Watches the picture on the monitor with the lights, for the screen mode:
/// ScreenCaptureKit scales it down to a few dozen pixels on the GPU, 20 times
/// a second, and each frame becomes an `RGBScreenSample`, blended into the
/// last so the lights follow without flickering. Runs only while the screen
/// mode shows; Neptater's own windows stay out of it.
final class RGBScreenSampler: NSObject, ObservableObject {
    static let shared = RGBScreenSampler()

    enum Status: Equatable {
        case idle
        case running
        case needsPermission
        case failed
    }

    @Published private(set) var status = Status.idle

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "neptater", category: "rgb-screen")
    private static let framesPerSecond: Int32 = 20
    private static let captureWidth = 64
    /// How long the lights take to follow a change most of the way, at speed 1.
    private static let followTime: TimeInterval = 0.15
    private static let retryDelay: TimeInterval = 3

    private let queue = DispatchQueue(label: "io.github.kuochiuhsiang.neptater.rgb-screen", qos: .userInitiated)
    private let lock = NSLock()
    // Guarded by `lock`: read by the devices' drawing queues.
    private var sample: RGBScreenSample?
    // Touched only on `queue`.
    private var sampledAt: TimeInterval?
    // Main thread.
    private var stream: SCStream?
    /// The display being watched and its size, to tell a real change of
    /// screens from the many notices that change nothing for it.
    private var watched: (id: CGDirectDisplayID, size: CGSize)?
    private var wanted = false
    private var starting = false
    private var observers: [NSObjectProtocol] = []

    /// The latest picture, smoothed; nil until the first frame arrives.
    var latest: RGBScreenSample? {
        lock.lock()
        defer { lock.unlock() }
        return sample
    }

    /// Starts or stops watching; main thread.
    func update(wanted: Bool) {
        guard wanted != self.wanted else { return }
        self.wanted = wanted
        if wanted {
            observe()
            start()
        } else {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            observers = []
            stop(keepingColors: false)
            status = .idle
        }
    }

    /// Asks for Screen Recording, from the panel's button.
    func requestPermission() {
        Permissions.shared.requestScreenRecording()
    }

    private func observe() {
        observers = [
            // Going full screen and back sends these too, with nothing changed
            // for the watched display; restarting then made the lights blink.
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                guard let self, self.wanted, self.stream != nil, self.watchedDisplayChanged() else { return }
                self.restart(because: "the screens changed")
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                              object: nil, queue: .main) { [weak self] _ in
                guard let self, self.wanted else { return }
                self.restart(because: "the Mac woke")
            },
            // Permission granted in System Settings shows up when the app comes back.
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                guard let self, self.wanted, self.status == .needsPermission else { return }
                self.start()
            },
        ]
    }

    /// Starts over on a new stream, keeping the last colors meanwhile, so the
    /// lights carry on from them instead of dropping to black.
    private func restart(because reason: String) {
        Self.log.notice("restarting the capture: \(reason, privacy: .public)")
        stop(keepingColors: true)
        start()
    }

    /// Whether the watched display is gone, or another took its place, or
    /// it changed size.
    private func watchedDisplayChanged() -> Bool {
        guard let watched else { return true }
        guard let screen = Self.lightedScreen(),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return true }
        return id != watched.id || screen.frame.size != watched.size
    }

    private func start() {
        guard CGPreflightScreenCaptureAccess() else {
            status = .needsPermission
            return
        }
        Task { @MainActor [weak self] in await self?.startStream() }
    }

    private func stop(keepingColors: Bool) {
        let running = stream
        stream = nil
        watched = nil
        if !keepingColors {
            lock.lock()
            sample = nil
            lock.unlock()
            queue.async { [weak self] in self?.sampledAt = nil }
        }
        if let running { Task { try? await running.stopCapture() } }
    }

    @MainActor
    private func startStream() async {
        guard wanted, stream == nil, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard wanted, let display = Self.lightedDisplay(in: content) else {
                if wanted { status = .failed }
                return
            }
            let own = content.applications.filter { $0.processID == NSRunningApplication.current.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Self.captureWidth
            configuration.height = max(1, Self.captureWidth * display.height / max(display.width, 1))
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.showsCursor = false
            configuration.queueDepth = 3
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            guard wanted, self.stream == nil else {
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            if let screen = Self.lightedScreen(),
               let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                watched = (id, screen.frame.size)
            }
            status = .running
        } catch {
            Self.log.error("screen capture failed: \(String(describing: error), privacy: .public)")
            status = CGPreflightScreenCaptureAccess() ? .failed : .needsPermission
            retryLater()
        }
    }

    private func retryLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            guard let self, self.wanted, self.stream == nil, self.status == .failed else { return }
            self.start()
        }
    }

    /// The display with the lights on its back: the MSI monitor by name, or
    /// else the first one that isn't built in.
    private static func lightedDisplay(in content: SCShareableContent) -> SCDisplay? {
        let id = lightedScreen()?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        return content.displays.first { $0.displayID == id }
            ?? content.displays.first { CGDisplayIsBuiltin($0.displayID) == 0 }
            ?? content.displays.first
    }

    private static func lightedScreen() -> NSScreen? {
        func number(_ screen: NSScreen) -> CGDirectDisplayID? {
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }
        return NSScreen.screens.first {
            $0.localizedName.localizedCaseInsensitiveContains("MSI")
                || $0.localizedName.localizedCaseInsensitiveContains("274URDFW")
        } ?? NSScreen.screens.first { number($0).map { CGDisplayIsBuiltin($0) == 0 } ?? false }
            ?? NSScreen.screens.first
    }

    // MARK: - Frames (on `queue`)

    private func take(_ pixels: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)
        let fresh = RGBScreenSample.averaging(bgra: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height),
                                              width: width, height: height, bytesPerRow: bytesPerRow)
        let now = ProcessInfo.processInfo.systemUptime
        let follow = Self.followTime / max(RGBLightingClock.shared.currentSpeed, 0.01)
        let share = sampledAt.map { 1 - exp(-(now - $0) / follow) } ?? 1
        sampledAt = now
        lock.lock()
        sample = sample.map { $0.blended(toward: fresh, share: share) } ?? fresh
        lock.unlock()
    }
}

extension RGBScreenSampler: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        take(pixels)
    }
}

extension RGBScreenSampler: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Self.log.error("screen capture stopped: \(String(describing: error), privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.status = .failed
            self.retryLater()
        }
    }
}
