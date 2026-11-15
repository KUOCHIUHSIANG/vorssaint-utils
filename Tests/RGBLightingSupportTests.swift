// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation

enum RGBLightingSupportTests {
    private static func settings(_ mode: RGBLightingMode, _ direction: RGBWaveDirection = .down,
                                 color: RGBColor = RGBLighting.defaultColor) -> RGBLightingChoice {
        RGBLightingChoice(mode: mode, direction: direction, color: color, level: 100)
    }

    static func run(_ suite: TestSuite) {
        // MARK: Colors

        suite.expect(RGBColor(hue: 0) == RGBColor(red: 255, green: 0, blue: 0)
                        && RGBColor(hue: 120) == RGBColor(red: 0, green: 255, blue: 0)
                        && RGBColor(hue: 420) == RGBColor(hue: 60) && RGBColor(hue: -60) == RGBColor(hue: 300),
                     "hues wrap round the color wheel")
        suite.expect(RGBColor.black.hue == nil, "black has no hue")
        suite.expect(RGBColor(red: 200, green: 100, blue: 0).scaled(0.5) == RGBColor(red: 100, green: 50, blue: 0),
                     "scaling dims every channel alike")
        let green = RGBColor(hex: "#22E05A")!
        suite.expect(green.hex == "#22E05A" && RGBColor(hex: "22e05a") == green && RGBColor(hex: "#12345") == nil,
                     "a color saves as #RRGGBB and reads back")
        suite.expect(RGBLighting.swatches.count == 9 && Set(RGBLighting.swatches.map(\.hex)).count == 9,
                     "nine distinct swatches")
        let added = RGBLighting.decodeCustomColors("#123456, #abcdef,#123456,#FFFFFF,nope,#12345")
        suite.expect(added.map(\.hex) == ["#123456", "#ABCDEF"],
                     "added colors read back once each, without repeats of a fixed swatch or unreadable ones")
        suite.expect(RGBLighting.encodeCustomColors(added) == "#123456,#ABCDEF"
                        && RGBLighting.decodeCustomColors(RGBLighting.encodeCustomColors(added)) == added
                        && RGBLighting.decodeCustomColors(nil).isEmpty && RGBLighting.decodeCustomColors("").isEmpty,
                     "added colors save and read back unchanged")
        let many = (1...12).map { RGBColor(red: UInt8($0), green: 0, blue: 0) }
        suite.expect(RGBLighting.decodeCustomColors(RGBLighting.encodeCustomColors(many)).count
                        == RGBLighting.maxCustomColors, "at most nine colors can be added")
        suite.expect(RGBLighting.levelFactor(percent: 100) == 1 && RGBLighting.levelFactor(percent: 0)
                        == RGBLighting.levelFactor(percent: 5) && RGBLighting.levelFactor(percent: 50) < 0.5,
                     "the slider bottoms out at 5 % and its middle looks half as bright")
        suite.expect(RGBLighting.frameInterval >= 1.0 / 30, "frames are paced, never sent back to back")

        // MARK: The desk

        let nommo = RGBDesk.nommo, monitor = RGBDesk.msiMonitor
        let blueStart = Array(repeating: RGBColor(red: 0, green: 0, blue: 200), count: 12)
        suite.expect(nommo.count == 12 && nommo[0..<6].allSatisfy { $0.x == 1 } && nommo[6...].allSatisfy { $0.x == 0 }
                        && nommo.allSatisfy { $0.y == 1 },
                     "speaker LEDs 0-5 light the right wall, 6-11 the left, both down on the desk")
        suite.expect(monitor.count == 22 && monitor.first?.y == 0 && zip(monitor, monitor.dropFirst()).allSatisfy { $0.y < $1.y }
                        && monitor.allSatisfy { $0.x == 0.5 && $0.y < 1 },
                     "the monitor's 22 rows run from its top down, above the speakers, left and right alike")
        suite.expect(RGBLightPosition(x: 0.2, y: 0.3).progress(along: .down) == 0.3
                        && RGBLightPosition(x: 0.2, y: 0.3).progress(along: .up) == 0.7
                        && RGBLightPosition(x: 0.2, y: 0.3).progress(along: .right) == 0.2
                        && RGBLightPosition(x: 0.2, y: 0.3).progress(along: .left) == 0.8,
                     "each direction measures from where the wave starts")
        var switchedOff = settings(.cycle)
        switchedOff.isOn = false
        let dimming = RGBLightingProgram(switchedOff, start: blueStart, began: 0)
        suite.expect(switchedOff.mode == .cycle && switchedOff.shownMode == .off
                        && dimming.frame(at: 1, lights: nommo) == (Array(repeating: .black, count: 12), false)
                        && dimming.frame(at: 0.5, lights: nommo).moving,
                     "the switch fades the lights to black and keeps the mode for later")
        suite.expect(!RGBLightingMode.choosable.contains(.off) && RGBLightingMode.choosable.count == 10,
                     "the menu leaves off to the switch")
        suite.expect(RGBLightingMode.allCases.filter(\.usesColor) == [.solid, .breathing, .meteor, .lightning, .music]
                        && RGBLightingMode.allCases.filter(\.listens) == [.music, .musicRainbow]
                        && RGBLightingMode.allCases.filter(\.usesDirection) == [.wave, .meteor]
                        && RGBLightingMode.allCases.filter { !$0.moves } == [.off, .solid],
                     "only the modes that use a color or a direction ask for one")

        // MARK: Fades

        let music = NommoBuiltInMode.music.indicatorColor
        let fromMusic = Array(repeating: music, count: 12)
        let fadeOff = RGBLightingProgram(settings(.off), start: fromMusic, began: 100)
        suite.expect(fadeOff.frame(at: 100, lights: nommo) == (fromMusic, true),
                     "off starts from the mode's color, so taking over shows no jump")
        suite.expect(fadeOff.frame(at: 100.5, lights: nommo).colors[0].red < music.red / 2,
                     "off fades the color out, under half way at the halfway point")
        suite.expect(fadeOff.frame(at: 101, lights: nommo) == (Array(repeating: .black, count: 12), false),
                     "off ends black and stops drawing")
        suite.expect(RGBLightingProgram(settings(.off), start: nil, began: 0).frame(at: 0, lights: nommo)
                        == (Array(repeating: .black, count: 12), false),
                     "off from off draws one black frame and stops")
        let solidIn = RGBLightingProgram(settings(.solid, color: green), start: nil, began: 0)
        suite.expect(solidIn.frame(at: 0, lights: monitor).colors.allSatisfy { $0 == .black }
                        && solidIn.frame(at: 1, lights: monitor) == (Array(repeating: green, count: 22), false),
                     "a solid color fades in from off, then holds")
        let crossFade = RGBLightingProgram(settings(.solid, color: green), start: fromMusic, began: 0)
        let middle = crossFade.frame(at: 0.5, lights: nommo)
        suite.expect(crossFade.frame(at: 0, lights: nommo).colors == fromMusic && middle.moving
                        && middle.colors[0] != music && middle.colors[0] != green,
                     "a solid color cross-fades from the mode's color")
        suite.expect(solidIn.frame(at: 2, level: 0.5, lights: monitor).colors[0] == green.scaled(0.5),
                     "the brightness scales the settled color")
        suite.expect(RGBLightingProgram(settings(.solid), start: [music], began: 0).frame(at: 0, lights: nommo).colors[0]
                        == .black,
                     "start colors for another device are ignored and the fade starts from black")

        // MARK: In step

        let cycleSpeakers = RGBLightingProgram(settings(.cycle), start: fromMusic, began: 3)
        let cycleMonitor = RGBLightingProgram(settings(.cycle), start: nil, began: 1)
        let at = 7.5
        let expected = RGBColor(hue: RGBLighting.rainbowHue(at: at))
        suite.expect(cycleSpeakers.frame(at: at, lights: nommo).colors.allSatisfy { $0 == expected }
                        && cycleMonitor.frame(at: at, lights: monitor).colors.allSatisfy { $0 == expected },
                     "devices that started at different times show the same rainbow color, from the shared clock")
        suite.expect(cycleSpeakers.frame(at: 3, lights: nommo).colors == fromMusic,
                     "the rainbow picks up from the mode's color, then joins the others")
        suite.expect(RGBLighting.rainbowHue(at: RGBLighting.rainbowPeriod / 4) == 90, "the rainbow goes round once a period")

        let waveDown = RGBLightingProgram(settings(.wave, .down), start: nil, began: 0)
        let top = waveDown.frame(at: 5, lights: monitor).colors
        let speakers = waveDown.frame(at: 5, lights: nommo).colors
        let base = RGBLighting.rainbowHue(at: 5)
        suite.expect(top[0] == RGBColor(hue: base) && top[21] == RGBColor(hue: base - RGBLighting.waveSpread * 0.8)
                        && speakers.allSatisfy { $0 == RGBColor(hue: base - RGBLighting.waveSpread) },
                     "top to bottom, the monitor runs down the rainbow and both speakers follow on below it")
        let waveRight = RGBLightingProgram(settings(.wave, .right), start: nil, began: 0)
        let rightMonitor = waveRight.frame(at: 5, lights: monitor).colors
        let rightSpeakers = waveRight.frame(at: 5, lights: nommo).colors
        suite.expect(Set(rightMonitor.map(\.hex)).count == 1 && rightSpeakers[6] == RGBColor(hue: base)
                        && rightSpeakers[0] == RGBColor(hue: base - RGBLighting.waveSpread),
                     "left to right, the monitor is one color between the left speaker and the right")

        // MARK: Speed

        let clock = RGBLightingClock()
        suite.expect(clock.effectTime(at: 10) == 10, "at the usual speed, effects run on the clock itself")
        clock.setSpeed(2, at: 10)
        suite.expect(clock.effectTime(at: 10) == 10 && clock.effectTime(at: 12) == 14,
                     "a faster speed carries on from where the effect is, without a jump")
        clock.setSpeed(0.01, at: 12)
        suite.expect(clock.effectTime(at: 12) == 14 && clock.effectTime(at: 16) == 15,
                     "the speed never drops below a quarter")
        suite.expect(RGBLighting.clampedSpeed(.nan) == 1 && RGBLighting.clampedSpeed(9) == 3, "the speed stays in range")
        let quick = RGBLightingProgram(settings(.cycle), start: nil, began: 0)
        suite.expect(quick.frame(at: 5, effectTime: 7.5, lights: nommo).colors[0] == RGBColor(hue: RGBLighting.rainbowHue(at: 7.5)),
                     "effects follow the effect time, while fades keep to the clock")

        // MARK: Effects

        suite.expect(RGBLighting.breath(at: 0) == 0 && abs(RGBLighting.breath(at: RGBLighting.breathPeriod / 2) - 1) < 1e-9,
                     "a breath is dark at its start and full halfway")
        let hues = stride(from: 0.0, to: RGBLighting.breathPeriod * 3, by: 0.05).map(RGBLighting.breathHue)
        let changes = zip(hues, hues.dropFirst()).enumerated().filter { $0.element.0 != $0.element.1 }.map { $0.offset + 1 }
        suite.expect(changes.count == 2 && changes.allSatisfy {
                        RGBLighting.breath(at: Double($0) * 0.05) < 0.01 },
                     "a rainbow breath changes color only while dark, once per breath")
        suite.expect(RGBLighting.breathHue(at: RGBLighting.breathPeriod * 1.5) == 60, "each breath takes the next sixth of the wheel")
        let atHead = (0..<100).map { Double($0) / 100 * RGBLighting.meteorPeriod }
            .map { time in RGBLighting.meteor(at: time, progress: 0.5) }
        suite.expect(atHead.contains { $0 > 0.9 } && atHead.contains(0),
                     "a meteor passes each light once a period, full at its head")
        suite.expect(RGBLighting.meteor(at: RGBLighting.meteorPeriod * 0.25, progress: 0.9) == 0,
                     "nothing lights ahead of the meteor")
        let samples = stride(from: 0.0, to: 600, by: 0.02).map(RGBLighting.lightning)
        let lit = samples.filter { $0 > 0.5 }.count
        suite.expect(lit > 0 && Double(lit) / Double(samples.count) < 0.1,
                     "lightning strikes now and then, and the background shows most of the time")
        suite.expect(RGBLighting.lightning(at: 123.45) == RGBLighting.lightning(at: 123.45)
                        && (0..<1000).allSatisfy { (0..<1).contains(RGBLighting.chance($0, 1)) },
                     "lightning depends only on the clock, so every device flashes together")
        let red = RGBColor(red: 255, green: 0, blue: 0)
        let strike = stride(from: 0.0, to: 600, by: 0.02).first { RGBLighting.lightning(at: $0) == 1 }
        let storm = RGBLightingProgram(settings(.lightning, color: red), start: nil, began: 0)
        let calm = stride(from: 2.0, to: 600, by: 0.02).first { RGBLighting.lightning(at: $0) == 0 }
        suite.expect(calm.map { storm.frame(at: $0, lights: nommo).colors[0] == red } == true
                        && strike.map { storm.frame(at: max($0, 2), lights: nommo).colors[0] } != nil,
                     "between strikes the lights show the chosen color")
        if let strike, strike >= 1 {
            suite.expect(storm.frame(at: strike, lights: nommo).colors[0] == RGBLighting.defaultColor,
                         "a strike flashes white")
        }

        // MARK: Screen colors

        // A 32×22 picture: red on the left third, blue on the right, green in between, one white band at the top.
        let width = 32, height = 22
        var bgra = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b): (UInt8, UInt8, UInt8) = y == 0 ? (255, 255, 255)
                    : x < 12 ? (255, 0, 0) : x >= 20 ? (0, 0, 255) : (0, 255, 0)
                bgra.replaceSubrange((y * width + x) * 4..<(y * width + x) * 4 + 4, with: [b, g, r, 255])
            }
        }
        let picture = bgra.withUnsafeBytes {
            RGBScreenSample.averaging(bgra: $0, width: width, height: height, bytesPerRow: width * 4)
        }
        let rowColors = monitor.map(picture.color(for:))
        suite.expect(rowColors[0] == RGBColor(red: 255, green: 255, blue: 255),
                     "the top monitor row takes the top band of the picture")
        suite.expect(rowColors[10].red > 100 && rowColors[10].blue > 100 && rowColors[10].green < 30,
                     "a monitor row mixes its band's left and right edges, both sides lit alike")
        suite.expect(picture.color(for: nommo[6]).red == 255 && picture.color(for: nommo[6]).blue < 30
                        && picture.color(for: nommo[0]).blue == 255 && picture.color(for: nommo[0]).red < 30,
                     "the left speaker takes the left of the picture, the right speaker the right")
        suite.expect(RGBColor(red: 200, green: 100, blue: 100).saturated(by: 1.3) == RGBColor(red: 200, green: 70, blue: 70)
                        && RGBColor(red: 90, green: 90, blue: 90).saturated(by: 2) == RGBColor(red: 90, green: 90, blue: 90),
                     "saturation deepens a color at the same brightness and leaves greys alone")
        let dark = RGBScreenSample(channels: [])
        let halfway = dark.blended(toward: picture, share: 0.5)
        suite.expect(halfway.color(for: monitor[0]).red == 128 && dark.blended(toward: picture, share: 1) == picture,
                     "smoothing moves part of the way to the newest picture")
        let watching = RGBLightingProgram(settings(.screen), start: nil, began: 0)
        suite.expect(watching.frame(at: 5, lights: nommo, screen: picture).colors[6] == picture.color(for: nommo[6])
                        && watching.frame(at: 5, lights: nommo).colors.allSatisfy { $0 == .black }
                        && watching.frame(at: 5, lights: nommo).moving,
                     "the screen mode shows the picture, dark until the first one arrives, and keeps drawing")

        // MARK: Music

        // A kick (60 Hz, loud) every half second over a quiet hum, in 512-frame stereo buffers at 48 kHz.
        var detector = RGBBeatDetector()
        let rate = 48_000.0, framesPerBuffer = 512
        var beats: [Double] = []
        var buffer = [Float](repeating: 0, count: framesPerBuffer * 2)
        for index in 0..<(Int(4 * rate) / framesPerBuffer) {
            let start = Double(index * framesPerBuffer) / rate
            for frame in 0..<framesPerBuffer {
                let time = start + Double(frame) / rate
                let sinceKick = time.truncatingRemainder(dividingBy: 0.5)
                let kick = sinceKick < 0.08 ? 0.8 * sin(2 * .pi * 60 * time) * (1 - sinceKick / 0.08) : 0
                let hum = 0.02 * sin(2 * .pi * 440 * time)
                buffer[frame * 2] = Float(kick + hum)
                buffer[frame * 2 + 1] = Float(kick + hum)
            }
            if buffer.withUnsafeBufferPointer({ detector.feed($0.baseAddress!, count: buffer.count, channels: 2,
                                                              sampleRate: rate, at: start) }) {
                beats.append(start)
            }
        }
        let onKicks = beats.filter { abs($0 - ($0 / 0.5).rounded() * 0.5) < 0.05 }
        suite.expect(onKicks.count >= 6 && onKicks.count == beats.count,
                     "each kick is a beat, and nothing between kicks is (\(beats.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) }))")
        var quiet = RGBBeatDetector()
        let silence = [Float](repeating: 0, count: 1024)
        suite.expect(!(0..<200).contains { step in
            silence.withUnsafeBufferPointer { quiet.feed($0.baseAddress!, count: 1024, channels: 2, sampleRate: rate,
                                                        at: Double(step) * 0.01) }
        } && quiet.level == 0, "silence has no beats")
        let pulse = RGBAudioSample(lastBeat: 10, beatHue: 200, level: 0.4)
        suite.expect(pulse.brightness(at: 10, speed: 1) == 1 && pulse.brightness(at: 10.2, speed: 1) < 0.4
                        && abs(pulse.brightness(at: 12, speed: 1) - RGBAudioSample.glow * 0.4) < 1e-9
                        && pulse.brightness(at: 10.2, speed: 2) < pulse.brightness(at: 10.2, speed: 1),
                     "a beat flashes full, fades to a glow that follows the loudness, quicker when faster")
        let beatProgram = RGBLightingProgram(settings(.music, color: red), start: nil, began: 0)
        let rainbowMusic = RGBLightingProgram(settings(.musicRainbow), start: nil, began: 0)
        suite.expect(beatProgram.frame(at: 10, lights: monitor, audio: pulse).colors.allSatisfy { $0 == red }
                        && rainbowMusic.frame(at: 10, lights: nommo, audio: pulse).colors.allSatisfy { $0 == RGBColor(hue: 200) }
                        && beatProgram.frame(at: 10, lights: nommo).colors.allSatisfy { $0 == .black },
                     "on a beat every light flashes the chosen color or the beat's color, dark until the sound is heard")

        // MARK: MSI monitor

        let query = MSIMonitorProtocol.layoutQuery
        suite.expect(query.count == 64 && query[0] == 0x01 && query[1] == 0xB0 && query[2...].allSatisfy { $0 == 0 },
                     "the layout query is 0xB0 on report 0x01")
        suite.expect(MSIMonitorProtocol.layout(fromReply: [0x01, 0x5A, 0x63, 0x2A] + Array(repeating: 0, count: 60)) == 42
                        && MSIMonitorProtocol.layout(fromReply: [0x01, 0x00, 0x63, 0x2A]) == nil,
                     "the answer Jater's monitor gives reads as layout 42")
        let rainbow = (0..<22).map { RGBColor(hue: Double($0) * 15) }
        let frame = MSIMonitorProtocol.frame(rainbow)
        suite.expect(frame.count == 168 && frame[0] == 0x72 && Array(frame[1...11]) == Array(frame[12...22])
                        && frame[1] == 0x01 && frame[6] == 100 && frame[10] == 0x80,
                     "a frame is static, full brightness, painted from the LED colors, in both control blocks")
        suite.expect(frame[23..<95].allSatisfy { $0 == 0 } && frame[167] == 0 && Array(frame[95..<98]) == [255, 0, 0],
                     "only the second color array is used, and nothing is written to flash")
        let orange = MSIMonitorProtocol.frame([RGBColor(hex: "#FF8A00")!])
        let pink = MSIMonitorProtocol.frame([RGBColor(hex: "#FF4FB8")!])
        suite.expect(Array(orange[95..<98]) == [0xFF, 0x2E, 0x00] && Array(pink[95..<98]) == [0xFF, 0x0A, 0x66],
                     "colors go out through the 2.8 gamma Jater matched to the speakers' orange and pink")
        let readBack = MSIMonitorProtocol.colors(in: frame) ?? []
        suite.expect(MSIMonitorProtocol.isDrawnFrame(frame) && readBack.count == 22 && readBack[0] == rainbow[0]
                        && zip(readBack, rainbow).allSatisfy { abs(Int($0.green) - Int($1.green)) <= 24 },
                     "a drawn frame read back gives its colors, close enough to fade on from")
        var original = [UInt8](repeating: 0, count: 168)
        original.replaceSubrange(0..<23, with: [0x72, 0x1A, 0xFF, 0xFF, 0xFF, 0x01, 0x64, 0x00, 0xFF, 0x00, 0x00, 0x00,
                                                0x1A, 0x00, 0x00, 0x00, 0x01, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00])
        suite.expect(MSIMonitorProtocol.rainbowWave(brightness: 100) == original,
                     "the handed back Rainbow Wave is the monitor's own, as first read, without a flash write")
        let dim = MSIMonitorProtocol.rainbowWave(brightness: MSIMonitorProtocol.brightness(forLevel: 0.5))
        suite.expect(dim[6] == dim[17] && dim[6] < 50 && dim[6] >= 1 && MSIMonitorProtocol.brightness(forLevel: 1) == 100,
                     "the Rainbow Wave comes back as bright as the slider, never fully dark")
        suite.expect(!MSIMonitorProtocol.isDrawnFrame(original) && MSIMonitorProtocol.colors(in: original) == nil,
                     "the monitor's own effect has no colors to fade on from")
        var fromWindows = original
        fromWindows[167] = 0x82
        let dimmedOwn = MSIMonitorProtocol.dimmed(fromWindows, to: 30)
        suite.expect(MSIMonitorProtocol.brightness(of: fromWindows) == 100 && dimmedOwn?[6] == 30 && dimmedOwn?[17] == 30
                        && dimmedOwn?[167] == 0 && dimmedOwn?[1] == 0x1A,
                     "an effect set elsewhere fades out through its own brightness, never written to flash")
    }
}
