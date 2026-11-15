// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import CoreMedia
import Foundation
import os

/// Listens to the Mac's sound for the music modes, through the recorder's
/// tap on every app but this one (it follows output changes and asks for the
/// audio permission the first time). Each buffer goes through an
/// `RGBBeatDetector` on the audio thread; the devices read the result when
/// they draw. Runs only while a music mode shows, and keeps nothing but the
/// last beat and the loudness: no sound is stored.
final class RGBAudioPulse {
    static let shared = RGBAudioPulse()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "neptater", category: "rgb-audio")
    private let lock = NSLock()
    // Guarded by `lock`: written by the audio thread, read by the drawing queues.
    private var state: RGBAudioSample?
    // The audio thread only.
    private var detector = RGBBeatDetector()
    private var beatsSinceReport = 0
    private var loudestSinceReport = 0.0
    private var reportedAt = 0.0
    // Main thread.
    private var tap: RecorderSystemAudioTap?
    private var wanted = false
    private var generation = 0

    private init() {}

    /// The music so far; nil until the tap runs.
    var latest: RGBAudioSample? {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Starts or stops listening; main thread.
    func update(wanted: Bool) {
        guard wanted != self.wanted else { return }
        Self.log.notice("wanted: \(wanted, privacy: .public)")
        self.wanted = wanted
        generation += 1
        if wanted {
            start(generation)
        } else {
            let running = tap
            tap = nil
            lock.lock()
            state = nil
            lock.unlock()
            if let running { Task { await running.stop() } }
        }
    }

    private func start(_ generation: Int) {
        Task { @MainActor [weak self] in
            Self.log.notice("making the tap")
            guard let tap = await RecorderSystemAudioTap.make(hearing: nil) else {
                Self.log.error("the audio system refused a tap")
                return
            }
            guard let self, self.wanted, self.generation == generation else {
                await tap.stop()
                return
            }
            self.prepare()
            tap.onSample = { [weak self] sample in self?.receive(sample) }
            self.tap = tap
            let running = await tap.start(synchronizingTo: CMClockGetHostTimeClock())
            Self.log.notice("listening: \(running, privacy: .public)")
        }
    }

    /// Before the tap runs: a fresh detector, and quiet so far.
    private func prepare() {
        detector = RGBBeatDetector()
        lock.lock()
        state = RGBAudioSample(lastBeat: -.infinity, beatHue: 0, level: 0)
        lock.unlock()
    }

    /// On the audio thread.
    private func receive(_ sample: CMSampleBuffer) {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32,
              let block = CMSampleBufferGetDataBuffer(sample) else { return }
        var length = 0
        var data: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil,
                                          dataPointerOut: &data) == kCMBlockBufferNoErr, let data else { return }
        let count = length / MemoryLayout<Float>.size
        let now = ProcessInfo.processInfo.systemUptime
        let beat = data.withMemoryRebound(to: Float.self, capacity: count) {
            detector.feed($0, count: count, channels: Int(format.mChannelsPerFrame),
                          sampleRate: format.mSampleRate, at: now)
        }
        let level = detector.level
        beatsSinceReport += beat ? 1 : 0
        loudestSinceReport = max(loudestSinceReport, level)
        if now - reportedAt >= 5 {
            Self.log.debug("beats \(self.beatsSinceReport, privacy: .public), level \(self.loudestSinceReport, privacy: .public)")
            beatsSinceReport = 0
            loudestSinceReport = 0
            reportedAt = now
        }
        lock.lock()
        if var current = state {
            current.level = level
            if beat {
                current.lastBeat = now
                // Far enough round the wheel that each beat looks new.
                current.beatHue = (current.beatHue + Double.random(in: 100...260)).truncatingRemainder(dividingBy: 360)
            }
            state = current
        }
        lock.unlock()
    }
}
