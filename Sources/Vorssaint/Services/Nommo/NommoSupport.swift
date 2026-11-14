// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation

// Razer Nommo V2 over USB: the report format, the only commands Neptater sends,
// and the EQ presets. Foundation only, so the tests compile it unchanged.
// The protocol follows Nommo Control's PROTOCOL.md (MIT,
// github.com/feroxes/razer-nommo-v2-macos) and was checked on Jater's speaker
// (firmware 1.6.1).

enum NommoProtocol {
    static let vendorID = 0x1532
    static let productID = 0x055C
    /// The control interface is the one whose feature reports hold a whole command.
    static let minimumControlReportSize = 90
    static let reportID: UInt8 = 0x07
    static let reportLength = 91
    static let transactionID: UInt8 = 0x1F
    static let argumentCapacity = 80
    /// Replies still being prepared; 0x02 is done (also for commands the speaker ignores).
    static let pendingStatuses: Set<UInt8> = [0x00, 0x01]
    static let replyAttempts = 20
    static let replyDelayMicroseconds: UInt32 = 3_000

    private static let statusIndex = 1
    private static let transactionIndex = 2
    private static let sizeIndex = 6
    private static let classIndex = 7
    private static let commandIndex = 8
    private static let argumentsStart = 9
    private static let checksumIndex = 89

    static func request(_ command: NommoCommand) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: reportLength)
        bytes[0] = reportID
        bytes[transactionIndex] = transactionID
        bytes[sizeIndex] = command.size
        bytes[classIndex] = command.commandClass
        bytes[commandIndex] = command.commandID
        for (offset, byte) in command.arguments.prefix(argumentCapacity).enumerated() {
            bytes[argumentsStart + offset] = byte
        }
        bytes[checksumIndex] = bytes[3...88].reduce(0, ^)
        return bytes
    }

    /// GetReport returns either all 91 bytes or the 90 after the report ID,
    /// depending on the path through macOS.
    static func reply(from raw: [UInt8]) -> NommoReply? {
        let bytes: [UInt8]
        if raw.count >= reportLength, raw[0] == reportID {
            bytes = raw
        } else if raw.count >= reportLength - 1 {
            bytes = [reportID] + raw
        } else {
            return nil
        }
        return NommoReply(status: bytes[statusIndex],
                          commandClass: bytes[classIndex],
                          commandID: bytes[commandIndex],
                          arguments: Array(bytes[argumentsStart..<(argumentsStart + argumentCapacity)]))
    }

    /// "1.6.1" from the reply to `.readFirmware`.
    static func firmwareVersion(from arguments: [UInt8]) -> String? {
        guard arguments.count >= 3, arguments.prefix(3).contains(where: { $0 != 0 }) else { return nil }
        return arguments.prefix(3).map(String.init).joined(separator: ".")
    }
}

struct NommoReply: Equatable {
    let status: UInt8
    let commandClass: UInt8
    let commandID: UInt8
    let arguments: [UInt8]

    var isPending: Bool { NommoProtocol.pendingStatuses.contains(status) }

    func answers(_ command: NommoCommand) -> Bool {
        commandClass == command.commandClass && commandID == command.commandID
    }
}

/// Every command Neptater can send. There is deliberately no raw escape hatch:
/// some IDs are destructive (class 08, ID 0A switches the speaker to Bluetooth
/// and drops it from USB until its button is pressed).
enum NommoCommand: Equatable {
    case readFirmware
    case readSubwoofer
    case writeSubwoofer(Int)
    case readEQMode
    case selectBuiltIn(NommoBuiltInMode)
    case readEQCurve
    case writeEQCurve(NommoEQCurve)
    case readAutoStandby
    case writeAutoStandby(Bool)
    case readStandbyDelay
    case writeStandbyDelay(NommoStandbyDelay)
    /// Stops the built-in animation so the LEDs show frames sent by the host.
    case enterFrameMode
    /// The same color on all twelve LEDs; black turns the lighting off.
    case fillFrame(red: UInt8, green: UInt8, blue: UInt8)
    /// Leaves frame mode; the built-in spectrum cycle continues.
    case resumeAnimation
    /// Overall LED brightness, 0 to 255; it scales whatever the LEDs show.
    case readBrightness
    case writeBrightness(Int)

    var commandClass: UInt8 {
        switch self {
        case .readFirmware: return 0x00
        case .readSubwoofer, .writeSubwoofer, .readEQMode, .selectBuiltIn, .readEQCurve, .writeEQCurve:
            return 0x08
        case .readAutoStandby, .writeAutoStandby, .readStandbyDelay, .writeStandbyDelay: return 0x07
        case .enterFrameMode, .fillFrame, .resumeAnimation, .readBrightness, .writeBrightness: return 0x0F
        }
    }

    var commandID: UInt8 {
        switch self {
        case .readFirmware: return 0x87
        case .readSubwoofer: return 0x87
        case .writeSubwoofer: return 0x07
        case .readEQMode: return 0x82
        case .selectBuiltIn: return 0x02
        case .readEQCurve: return 0x84
        case .writeEQCurve: return 0x04
        case .readAutoStandby: return 0x88
        case .writeAutoStandby: return 0x08
        case .readStandbyDelay: return 0x83
        case .writeStandbyDelay: return 0x03
        case .enterFrameMode, .resumeAnimation: return 0x02
        case .fillFrame: return 0x03
        case .readBrightness: return 0x84
        case .writeBrightness: return 0x04
        }
    }

    var size: UInt8 {
        switch self {
        case .readFirmware: return 0x03
        case .readEQCurve, .writeEQCurve: return 0x0B
        case .enterFrameMode, .resumeAnimation: return 0x06
        case .fillFrame: return 0x29
        case .readBrightness, .writeBrightness: return 0x03
        default: return 0x02
        }
    }

    var arguments: [UInt8] {
        switch self {
        case let .writeSubwoofer(level): return [0x00, UInt8(NommoSubwoofer.clamped(level))]
        case let .selectBuiltIn(mode): return [0x01, mode.rawValue]
        case let .writeEQCurve(curve): return [0x00] + curve.bytes
        case let .writeAutoStandby(isOn): return [0x00, isOn ? 0x01 : 0x00]
        case let .writeStandbyDelay(delay): return delay.bytes
        case .enterFrameMode: return [0x00, 0x00, 0x08, 0x00, 0x01]
        case let .fillFrame(red, green, blue):
            return [0x00, 0x00, 0x00, 0x00, 0x0B] + Array([[UInt8]](repeating: [red, green, blue], count: 12).joined())
        case .resumeAnimation: return [0x00, 0x00, 0x00]
        case .readBrightness: return [0x01, 0x00]
        case let .writeBrightness(level): return [0x01, 0x00, UInt8(NommoLighting.clampedBrightness(level))]
        default: return []
        }
    }
}

enum NommoSubwoofer {
    static let range = 1...7

    /// The speaker answers 0 (or anything else out of range) by jumping to its
    /// default of 4, the opposite of what someone asking for less bass wants.
    static func clamped(_ level: Int) -> Int {
        min(max(level, range.lowerBound), range.upperBound)
    }
}

/// Razer's modes built into the firmware. Their curves are not readable, and
/// selecting one resets the custom bands to flat.
enum NommoBuiltInMode: UInt8, CaseIterable {
    case game = 0x01, music = 0x02, movie = 0x03
}

struct NommoEQCurve: Equatable, Codable {
    static let bandCount = 10
    static let levels = -12...12
    /// Band labels by octave, as Nommo Control and Synapse show them.
    static let frequencyLabels = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    /// A band byte is its level plus 0x0C.
    private static let zeroByte = 0x0C

    static let flat = NommoEQCurve(Array(repeating: 0, count: bandCount))

    let bands: [Int]

    /// Always ten bands within ±12, whatever was passed in.
    init(_ bands: [Int]) {
        let padded = Array(bands.prefix(Self.bandCount)) + Array(repeating: 0, count: max(0, Self.bandCount - bands.count))
        self.bands = padded.map { min(max($0, Self.levels.lowerBound), Self.levels.upperBound) }
    }

    init?(bytes: [UInt8]) {
        guard bytes.count >= Self.bandCount else { return nil }
        let levels = bytes.prefix(Self.bandCount).map { Int($0) - Self.zeroByte }
        guard levels.allSatisfy(Self.levels.contains) else { return nil }
        self.init(levels)
    }

    var bytes: [UInt8] { bands.map { UInt8($0 + Self.zeroByte) } }

    func setting(band: Int, to level: Int) -> NommoEQCurve {
        guard bands.indices.contains(band) else { return self }
        var changed = bands
        changed[band] = level
        return NommoEQCurve(changed)
    }

    init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([Int].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bands)
    }
}

/// What the speaker reports: a built-in mode, the custom curve, or a mode byte
/// Neptater doesn't know (such as Razer's default).
enum NommoEQState: Equatable {
    case builtIn(NommoBuiltInMode)
    case custom(NommoEQCurve)
    case other(UInt8)

    static let customModeByte: UInt8 = 0x10

    init(modeByte: UInt8, curve: NommoEQCurve?) {
        if modeByte == Self.customModeByte {
            self = .custom(curve ?? .flat)
        } else if let mode = NommoBuiltInMode(rawValue: modeByte) {
            self = .builtIn(mode)
        } else {
            self = .other(modeByte)
        }
    }
}

/// Neptater's own curves. Game, music and movie start from suggestions drawn
/// from common EQ guides and can be edited (for example to match what Synapse
/// shows); flat is fixed. They live on this Mac because switching to a
/// built-in mode resets the speaker's custom bands.
enum NommoEQPreset: String, CaseIterable, Codable {
    case game, music, movie, flat

    var isEditable: Bool { self != .flat }

    var suggestedCurve: NommoEQCurve {
        switch self {
        // Less rumble, more of the 1–4 kHz range where footsteps and cues sit.
        case .game: return NommoEQCurve([-5, -4, -3, -1, -1, 1, 3, 4, 2, 0])
        // A gentle lift at both ends; the subwoofer already carries the lows.
        case .music: return NommoEQCurve([0, 1, 1, 0, -1, 0, 1, 2, 2, 1])
        // Less boxiness at 250 Hz, more of the 1–4 kHz range where dialogue sits.
        case .movie: return NommoEQCurve([-1, 0, -1, -2, 0, 2, 3, 2, -1, 1])
        case .flat: return .flat
        }
    }
}

enum NommoEQPresetStore {
    static let defaultStorage = encode(suggestedCurves)

    static var suggestedCurves: [NommoEQPreset: NommoEQCurve] {
        Dictionary(uniqueKeysWithValues: NommoEQPreset.allCases.map { ($0, $0.suggestedCurve) })
    }

    /// Saved curves, with every preset present: a missing or damaged entry
    /// falls back to its suggestion, and flat is always flat.
    static func decode(_ storage: String?) -> [NommoEQPreset: NommoEQCurve] {
        var curves = suggestedCurves
        guard let data = storage?.data(using: .utf8),
              let saved = try? JSONDecoder().decode([String: NommoEQCurve].self, from: data) else {
            return curves
        }
        for (key, curve) in saved {
            if let preset = NommoEQPreset(rawValue: key), preset.isEditable {
                curves[preset] = curve
            }
        }
        return curves
    }

    static func encode(_ curves: [NommoEQPreset: NommoEQCurve]) -> String {
        let editable = Dictionary(uniqueKeysWithValues: curves.compactMap { preset, curve in
            preset.isEditable ? (preset.rawValue, curve) : nil
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(editable), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

/// What the EQ menu shows as chosen.
enum NommoEQSelection: Hashable {
    case builtIn(NommoBuiltInMode)
    case preset(NommoEQPreset)
    /// A custom curve that matches none of the presets, say one set in Synapse.
    case otherCustom
    case unknown

    init(state: NommoEQState?, presets: [NommoEQPreset: NommoEQCurve]) {
        switch state {
        case let .builtIn(mode):
            self = .builtIn(mode)
        case let .custom(curve):
            if let preset = NommoEQPreset.allCases.first(where: { presets[$0] == curve }) {
                self = .preset(preset)
            } else {
                self = .otherCustom
            }
        case .other, .none:
            self = .unknown
        }
    }
}

/// Silence before standby. The speaker accepts only these three; it ignores
/// any other value.
enum NommoStandbyDelay: Int, CaseIterable {
    case fifteen = 900, thirty = 1_800, fortyFive = 2_700

    var minutes: Int { rawValue / 60 }

    /// Seconds, big-endian.
    var bytes: [UInt8] { [UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)] }

    init?(bytes: [UInt8]) {
        guard bytes.count >= 2 else { return nil }
        self.init(rawValue: Int(bytes[0]) << 8 | Int(bytes[1]))
    }
}

/// The lighting Neptater keeps the speakers on. They can't report theirs, and
/// both powering up and a built-in EQ mode replace it (Game turns them green,
/// Music red, Movie yellow, and that color stays), so Neptater puts it back.
enum NommoLighting: String, CaseIterable {
    case off, spectrum

    /// How long a built-in mode's color shows before the lighting returns.
    /// The strings say 3 seconds.
    static let eqColorHold: TimeInterval = 3
    /// The speakers reset their lighting during their first seconds on USB (up
    /// to 2.5 s after power-on); frames sent before that are lost.
    static let connectSettle: TimeInterval = 5

    /// Turning off and on fades through the brightness, the way the speakers
    /// fade on power-off and power-on, rather than cutting. A fade steps as
    /// fast as the speakers answer (a brightness write takes about 11 ms, so
    /// roughly 90 steps a second), each step placed by the time elapsed.
    static let fadeDuration: TimeInterval = 1.0
    /// Between linear and perceptual (2.2): dim enough steps to look even,
    /// without lingering on the coarse 3, 2, 1 levels at the bottom.
    static let fadeGamma = 1.6
    static let fullBrightness = 255

    static func clampedBrightness(_ level: Int) -> Int { min(max(level, 0), fullBrightness) }

    /// The brightness `progress` (0 to 1) of the way from `start` to `end`.
    static func fadeLevel(from start: Int, to end: Int, progress: Double) -> Int {
        func perceived(_ level: Int) -> Double {
            pow(Double(clampedBrightness(level)) / Double(fullBrightness), 1 / fadeGamma)
        }
        let share = min(max(progress, 0), 1)
        let level = perceived(start) + (perceived(end) - perceived(start)) * share
        return Int((pow(level, fadeGamma) * Double(fullBrightness)).rounded())
    }

    var commands: [NommoCommand] {
        switch self {
        case .off: return [.enterFrameMode, .fillFrame(red: 0, green: 0, blue: 0)]
        case .spectrum: return [.resumeAnimation]
        }
    }
}
