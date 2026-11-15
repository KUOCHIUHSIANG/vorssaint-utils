// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation

/// One LED's color.
struct RGBColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static let black = RGBColor(red: 0, green: 0, blue: 0)

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Full saturation and brightness, 0° red, 120° green, 240° blue.
    init(hue degrees: Double) {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        let sector = (wrapped < 0 ? wrapped + 360 : wrapped) / 60
        let rising = 1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) {
        case 0: (r, g, b) = (1, rising, 0)
        case 1: (r, g, b) = (rising, 1, 0)
        case 2: (r, g, b) = (0, 1, rising)
        case 3: (r, g, b) = (0, rising, 1)
        case 4: (r, g, b) = (rising, 0, 1)
        default: (r, g, b) = (1, 0, rising)
        }
        self.init(red: UInt8((r * 255).rounded()), green: UInt8((g * 255).rounded()), blue: UInt8((b * 255).rounded()))
    }

    /// The hue in degrees, or nil for black, white and greys.
    var hue: Double? {
        let r = Double(red), g = Double(green), b = Double(blue)
        let high = max(r, g, b), low = min(r, g, b)
        guard high > low else { return nil }
        let span = high - low
        let degrees: Double
        if high == r {
            degrees = 60 * ((g - b) / span).truncatingRemainder(dividingBy: 6)
        } else if high == g {
            degrees = 60 * ((b - r) / span + 2)
        } else {
            degrees = 60 * ((r - g) / span + 4)
        }
        return degrees < 0 ? degrees + 360 : degrees
    }

    func scaled(_ factor: Double) -> RGBColor {
        let share = min(max(factor, 0), 1)
        func scale(_ channel: UInt8) -> UInt8 { UInt8((Double(channel) * share).rounded()) }
        return RGBColor(red: scale(red), green: scale(green), blue: scale(blue))
    }

    /// `fraction` of the way from this color to `other`.
    func mixed(with other: RGBColor, _ fraction: Double) -> RGBColor {
        let share = min(max(fraction, 0), 1)
        func mix(_ from: UInt8, _ to: UInt8) -> UInt8 {
            UInt8((Double(from) + (Double(to) - Double(from)) * share).rounded())
        }
        return RGBColor(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
    }

    /// "#RRGGBB", how the chosen color is saved.
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }
}

/// What the lights show. Every device draws the same lighting, frame by frame
/// on Neptater's clock, so the speakers and the monitor stay in step instead of
/// each running its own built-in effect.
enum RGBLightingMode: String, CaseIterable {
    case off, solid, breathing, cycle, rainbowBreathing, wave, meteor, lightning

    /// The modes the menu offers; off is the switch's job.
    static let choosable = allCases.filter { $0 != .off }

    /// Whether the lights keep changing once a fade is over.
    var moves: Bool { self != .off && self != .solid }
    /// Whether the chosen color shows: as is, breathing, as the meteor, or
    /// under the lightning.
    var usesColor: Bool { [.solid, .breathing, .meteor, .lightning].contains(self) }
    var usesDirection: Bool { self == .wave || self == .meteor }
}

/// Which way a wave flows, as seen from the chair.
enum RGBWaveDirection: String, CaseIterable {
    case down, up, right, left
}

/// Where an LED's light shows, seen from the chair: x from 0 (left) to 1
/// (right), y from 0 (top of the monitor) to 1 (the desk).
struct RGBLightPosition: Equatable {
    let x: Double
    let y: Double

    /// How far along `direction` the light sits: 0 where a wave starts, 1
    /// where it ends.
    func progress(along direction: RGBWaveDirection) -> Double {
        switch direction {
        case .down: return y
        case .up: return 1 - y
        case .right: return x
        case .left: return 1 - x
        }
    }
}

/// Jater's desk, LED by LED (each mapped by lighting one at a time).
enum RGBDesk {
    /// Razer Nommo V2: LEDs 0–5 light the wall behind the right speaker, 6–11
    /// behind the left. They stack upright, but the wall blends a speaker's six
    /// into one glow, so each speaker sits at one point, on the desk.
    static let nommo: [RGBLightPosition] = (0..<NommoLighting.ledCount).map {
        RGBLightPosition(x: $0 < 6 ? 1 : 0, y: 1)
    }

    /// MSI MPG 274URDFW E16M: 22 rows down the back, from the top, each lighting
    /// the left and the right side alike. It spans the monitor's height, above
    /// the speakers.
    static let msiMonitor: [RGBLightPosition] = (0..<MSIMonitorProtocol.ledCount).map {
        RGBLightPosition(x: 0.5, y: 0.8 * Double($0) / Double(MSIMonitorProtocol.ledCount - 1))
    }
}

/// The lighting as chosen in the panel.
struct RGBLightingChoice: Equatable {
    var mode: RGBLightingMode
    /// Which way a wave or a meteor goes.
    var direction: RGBWaveDirection
    /// The color the modes that take one show, before the brightness.
    var color: RGBColor
    /// The brightness slider, in percent.
    var level: Int
    /// How fast the moving modes move, 1 being the periods below.
    var speed: Double = RGBLighting.defaultSpeed
    /// The switch: off fades the lights to black and keeps everything else.
    var isOn = true

    /// What the lights show: the mode, or off while switched off.
    var shownMode: RGBLightingMode { isOn ? mode : .off }
}

enum RGBLighting {
    /// Frames go out at this pace while something moves. The speakers stall
    /// now and then when sent frames back to back, and once froze for 5 s.
    static let frameInterval: TimeInterval = 1.0 / 30
    static let fadeDuration: TimeInterval = 1.0
    /// Between linear and perceptual (2.2): dim enough steps to look even,
    /// without lingering on the coarse 3, 2, 1 levels at the bottom.
    static let fadeGamma = 1.6
    /// One trip round the color wheel.
    static let rainbowPeriod: TimeInterval = 10
    /// How much of the color wheel a wave spans from start to end: the monitor
    /// shows most of a rainbow, and the speakers follow on from it.
    static let waveSpread = 240.0
    /// One breath, dark to dark. A rainbow breath takes the next sixth of the
    /// color wheel while dark, so the change never shows.
    static let breathPeriod: TimeInterval = 4
    /// A meteor crosses the desk and is gone in this time; its tail trails a
    /// share of the way behind it.
    static let meteorPeriod: TimeInterval = 2.5
    static let meteorTail = 0.4
    /// Lightning is decided per slice of time, the same on every device, so
    /// they flash together: a strike in about one slice in thirty (one every
    /// three seconds or so), half of them striking twice, each flash fading
    /// to the background color in a quarter of a second.
    static let lightningSlice: TimeInterval = 0.1
    static let lightningChance = 1.0 / 30
    static let lightningFade: TimeInterval = 0.25
    /// The brightness slider runs from 5 % (dim but on) to 100 %.
    static let levelRange = 5...100
    /// The speed slider runs from a quarter of the speed to three times it.
    static let speedRange = 0.25...3.0
    static let defaultSpeed = 1.0

    static func clampedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return defaultSpeed }
        return min(max(speed, speedRange.lowerBound), speedRange.upperBound)
    }
    static let defaultColor = RGBColor(red: 255, green: 255, blue: 255)
    /// White, red, orange, yellow, green, cyan, blue, purple, pink.
    static let swatches: [RGBColor] = [
        defaultColor, RGBColor(hex: "#FF2A2A")!, RGBColor(hex: "#FF8A00")!, RGBColor(hex: "#FFD400")!,
        RGBColor(hex: "#22E05A")!, RGBColor(hex: "#00D5FF")!, RGBColor(hex: "#2F6BFF")!,
        RGBColor(hex: "#9B4DFF")!, RGBColor(hex: "#FF4FB8")!,
    ]

    /// Colors added with "+", after the swatches; at most one more row of them.
    static let maxCustomColors = 9

    /// Saved as "#RRGGBB,#RRGGBB", skipping anything unreadable or repeated,
    /// including a repeat of a fixed swatch.
    static func decodeCustomColors(_ storage: String?) -> [RGBColor] {
        var colors: [RGBColor] = []
        for part in (storage ?? "").split(separator: ",") {
            guard let color = RGBColor(hex: part.trimmingCharacters(in: .whitespaces)),
                  !swatches.contains(color), !colors.contains(color),
                  colors.count < maxCustomColors else { continue }
            colors.append(color)
        }
        return colors
    }

    static func encodeCustomColors(_ colors: [RGBColor]) -> String {
        colors.prefix(maxCustomColors).map(\.hex).joined(separator: ",")
    }

    /// The slider's percentage as a factor on each channel, even to the eye.
    static func levelFactor(percent: Int) -> Double {
        pow(Double(min(max(percent, levelRange.lowerBound), levelRange.upperBound)) / 100, fadeGamma)
    }

    /// Eases a change in and out, so a cross-fade has no visible start or stop.
    static func eased(_ progress: Double) -> Double {
        let share = min(max(progress, 0), 1)
        return share * share * (3 - 2 * share)
    }

    /// How lit a fade is `progress` (0 to 1) of the way out (or in), as a
    /// factor on each channel, even to the eye.
    static func fadeOutFactor(_ progress: Double) -> Double { pow(1 - min(max(progress, 0), 1), fadeGamma) }
    static func fadeInFactor(_ progress: Double) -> Double { pow(min(max(progress, 0), 1), fadeGamma) }

    /// The rainbow's hue at `time`, seconds on the monotonic clock. Every
    /// device reads the same clock, which is what keeps them in step.
    static func rainbowHue(at time: TimeInterval) -> Double {
        360 * time.truncatingRemainder(dividingBy: rainbowPeriod) / rainbowPeriod
    }

    /// How lit a breath is at `time`: dark on each whole period, full halfway.
    static func breath(at time: TimeInterval) -> Double {
        let phase = time.truncatingRemainder(dividingBy: breathPeriod) / breathPeriod
        return pow(0.5 - 0.5 * cos(2 * .pi * phase), fadeGamma)
    }

    /// The hue of the breath under way at `time`: a sixth of the wheel on per breath.
    static func breathHue(at time: TimeInterval) -> Double {
        60 * (time / breathPeriod).rounded(.down).truncatingRemainder(dividingBy: 6)
    }

    /// How bright a meteor is at `progress` along its way (see
    /// `RGBLightPosition.progress`) at `time`: full at its head, fading down
    /// its tail, dark ahead of it.
    static func meteor(at time: TimeInterval, progress: Double) -> Double {
        let head = time.truncatingRemainder(dividingBy: meteorPeriod) / meteorPeriod * (1 + meteorTail + 0.1)
        let behind = head - progress
        guard behind >= 0, behind < meteorTail else { return 0 }
        return pow(1 - behind / meteorTail, 2.2)
    }

    /// How much of a lightning flash shows at `time`, 0 to 1.
    static func lightning(at time: TimeInterval) -> Double {
        let slice = Int((time / lightningSlice).rounded(.down))
        var flash = 0.0
        for back in 0...Int((lightningFade / lightningSlice).rounded(.up)) {
            let strike = slice - back
            // A strike, or the second of a double one two slices after it.
            guard chance(strike, 1) < lightningChance
                    || (chance(strike - 2, 1) < lightningChance && chance(strike - 2, 2) < 0.5) else { continue }
            let age = time - Double(strike) * lightningSlice
            guard age >= 0, age < lightningFade else { continue }
            flash = max(flash, pow(1 - age / lightningFade, 2))
        }
        return flash
    }

    /// A number from 0 up to 1 that only depends on its inputs, so every
    /// device rolls the same dice.
    static func chance(_ slice: Int, _ salt: UInt64) -> Double {
        var value = UInt64(bitPattern: Int64(slice)) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}

/// The time the moving modes run on: the monotonic clock at the chosen
/// speed. A change of speed leaves every effect where it is and only changes
/// how fast it goes on from there, and every device reads this one clock, so
/// they stay in step.
final class RGBLightingClock {
    static let shared = RGBLightingClock()

    private let lock = NSLock()
    private var anchor: TimeInterval = 0
    private var effectAtAnchor: TimeInterval = 0
    private var speed = RGBLighting.defaultSpeed

    /// Effect time for `time`, seconds on the monotonic clock.
    func effectTime(at time: TimeInterval) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return effectAtAnchor + (time - anchor) * speed
    }

    func setSpeed(_ newSpeed: Double, at time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        effectAtAnchor += (time - anchor) * speed
        anchor = time
        speed = RGBLighting.clampedSpeed(newSpeed)
    }
}

/// What each LED shows over time on the way to the chosen lighting: from black
/// or from the colors already showing (a built-in EQ mode's, or the last
/// frame), cross-fading into the target and then holding or moving with it.
/// The brightness applies at drawing time, so a slider drag shows on the next
/// frame.
struct RGBLightingProgram: Equatable {
    let mode: RGBLightingMode
    let direction: RGBWaveDirection
    let color: RGBColor
    /// One color per LED, or nil for black.
    let start: [RGBColor]?
    /// Seconds on the monotonic clock.
    let began: TimeInterval

    init(_ settings: RGBLightingChoice, start: [RGBColor]?, began: TimeInterval) {
        mode = settings.shownMode
        direction = settings.direction
        color = settings.color
        self.start = start
        self.began = began
    }

    /// The frame for `time` at brightness factor `level`, one color per light,
    /// and whether later frames will differ. Fades run on `time`; the effects
    /// run on `effectTime` (see `RGBLightingClock`), `time` itself by default.
    func frame(at time: TimeInterval, effectTime: TimeInterval? = nil, level: Double = 1,
               lights: [RGBLightPosition]) -> (colors: [RGBColor], moving: Bool) {
        let fade = max(0, time - began) / RGBLighting.fadeDuration
        let from = start?.count == lights.count ? start : nil
        let effect = effectTime ?? time
        let colors = lights.indices.map { index -> RGBColor in
            let goal = target(at: effect, light: lights[index]).scaled(level)
            guard fade < 1 else { return goal }
            guard let from else { return goal.scaled(RGBLighting.fadeInFactor(fade)) }
            if mode == .off { return from[index].scaled(RGBLighting.fadeOutFactor(fade)) }
            return from[index].mixed(with: goal, RGBLighting.eased(fade))
        }
        let settling = fade < 1 && !(from == nil && mode == .off)
        return (colors, settling || mode.moves)
    }

    private func target(at time: TimeInterval, light: RGBLightPosition) -> RGBColor {
        switch mode {
        case .off: return .black
        case .solid: return color
        case .breathing: return color.scaled(RGBLighting.breath(at: time))
        case .cycle: return RGBColor(hue: RGBLighting.rainbowHue(at: time))
        case .rainbowBreathing:
            return RGBColor(hue: RGBLighting.breathHue(at: time)).scaled(RGBLighting.breath(at: time))
        case .wave:
            return RGBColor(hue: RGBLighting.rainbowHue(at: time)
                                - RGBLighting.waveSpread * light.progress(along: direction))
        case .meteor:
            return color.scaled(RGBLighting.meteor(at: time, progress: light.progress(along: direction)))
        case .lightning:
            return color.mixed(with: RGBLighting.defaultColor, RGBLighting.lightning(at: time))
        }
    }
}
