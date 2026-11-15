// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation

/// The Nommo V2 report format, the commands Neptater may send, and the EQ
/// presets kept on this Mac.
enum NommoSupportTests {
    private static let editedGame = NommoEQCurve([4, 3, 0, -2, 0, 0, 0, 1, 2, 3])

    /// The Razer curves with Game edited, as after dragging it.
    private static func withEditedGame(_ presets: [NommoEQPreset: NommoEQCurve]) -> [NommoEQPreset: NommoEQCurve] {
        var presets = presets
        presets[.game] = editedGame
        return presets
    }

    static func run(_ suite: TestSuite) {
        // MARK: Reports

        // PROTOCOL.md's worked example: subwoofer level 2.
        let request = NommoProtocol.request(.writeSubwoofer(2))
        suite.expect(request.count == 91, "a request is 91 bytes including the report ID")
        suite.expect(Array(request.prefix(11)) == [0x07, 0x00, 0x1F, 0x00, 0x00, 0x00, 0x02, 0x08, 0x07, 0x00, 0x02],
                     "a request carries report ID, transaction, size, class, command and arguments")
        suite.expect(request[89] == 0x0F, "the checksum is the XOR of bytes 3 to 88")

        var reply = [UInt8](repeating: 0, count: 91)
        reply[0] = 0x07; reply[1] = 0x02; reply[7] = 0x08; reply[8] = 0x87; reply[10] = 0x03
        let full = NommoProtocol.reply(from: reply)
        suite.expect(full?.arguments[1] == 3 && full?.answers(.readSubwoofer) == true,
                     "a 91-byte reply is read with its report ID")
        let body = NommoProtocol.reply(from: Array(reply.dropFirst()))
        suite.expect(body == full, "a 90-byte reply without the report ID reads the same")
        suite.expect(NommoProtocol.reply(from: [0x07, 0x02]) == nil, "a short reply is no reply")
        reply[1] = 0x01
        suite.expect(NommoProtocol.reply(from: reply)?.isPending == true, "status 01 means the reply isn't ready")
        suite.expect(full?.answers(.readEQMode) == false, "a reply to another command doesn't answer this one")

        // MARK: Commands

        suite.expect(NommoCommand.writeSubwoofer(0).arguments == [0x00, 0x01],
                     "subwoofer 0 is never sent, since the speaker turns it into its default of 4")
        suite.expect(NommoCommand.writeSubwoofer(9).arguments == [0x00, 0x07], "the subwoofer tops out at 7")
        suite.expect(NommoCommand.selectBuiltIn(.music).arguments == [0x01, 0x02], "Music is built-in mode 2")
        let every: [NommoCommand] = [
            .readFirmware, .readSubwoofer, .writeSubwoofer(1), .readEQMode, .selectBuiltIn(.game), .readEQCurve,
            .writeEQCurve(.flat), .readAutoStandby, .writeAutoStandby(true), .readStandbyDelay,
            .writeStandbyDelay(.fifteen), .enterFrameMode, .frame([]), .resumeAnimation,
            .readBrightness, .writeBrightness(128),
        ]
        let known: Set<[UInt8]> = [[0x00, 0x87], [0x08, 0x87], [0x08, 0x07], [0x08, 0x82], [0x08, 0x02],
                                   [0x08, 0x84], [0x08, 0x04], [0x07, 0x88], [0x07, 0x08], [0x07, 0x83], [0x07, 0x03],
                                   [0x0F, 0x02], [0x0F, 0x03], [0x0F, 0x84], [0x0F, 0x04]]
        suite.expect(Set(every.map { [$0.commandClass, $0.commandID] }) == known,
                     "Neptater sends only commands confirmed on the speaker")
        suite.expect(!every.contains { $0.commandClass == 0x08 && $0.commandID == 0x0A },
                     "nothing sends 08:0A, which drops the speaker to Bluetooth")

        // MARK: EQ curves

        let curve = NommoEQCurve([-12, -5, 0, 3, 12, 0, 0, 0, 0, 0])
        suite.expect(curve.bytes.prefix(5) == [0x00, 0x07, 0x0C, 0x0F, 0x18], "a band byte is its level plus 0x0C")
        suite.expect(NommoEQCurve(bytes: curve.bytes) == curve, "band bytes read back into the same curve")
        suite.expect(NommoEQCurve(bytes: [0x19] + Array(repeating: 0x0C, count: 9)) == nil,
                     "a band byte past 0x18 is not a curve")
        suite.expect(NommoEQCurve([40, -40]).bands == [12, -12, 0, 0, 0, 0, 0, 0, 0, 0],
                     "a curve always has ten bands within ±12")
        suite.expect(NommoCommand.writeEQCurve(curve).arguments == [0x00] + curve.bytes,
                     "a curve write leads with a zero byte")
        for preset in NommoEQPreset.allCases {
            suite.expect(preset.razerCurve == NommoEQCurve(preset.razerCurve.bands),
                         "the \(preset.rawValue) Razer curve is a valid curve")
        }
        suite.expect(NommoEQPreset.music.razerCurve.bands == [3, 3, 2, -3, 0, 3, 2, 0, 2, 0]
                        && NommoBuiltInMode.allCases.map(\.preset) == [.game, .music, .movie],
                     "each built-in mode has the preset of the same name, holding the curve Synapse shows")

        // MARK: What the speaker reports

        suite.expect(NommoEQState(modeByte: 0x02, curve: nil) == .builtIn(.music), "mode 02 is Music")
        suite.expect(NommoEQState(modeByte: 0x10, curve: curve) == .custom(curve), "mode 10 is the custom curve")
        suite.expect(NommoEQState(modeByte: 0x00, curve: nil) == .other(0x00), "an unknown mode stays unknown")

        let presets = NommoEQPresetStore.razerCurves
        suite.expect(NommoEQSelection(state: .custom(NommoEQPreset.game.razerCurve), presets: presets)
                        == .preset(.game), "a curve matching a preset shows as that preset")
        suite.expect(NommoEQSelection(state: .custom(.flat), presets: presets) == .preset(.flat),
                     "a flat curve shows as Flat")
        suite.expect(NommoEQSelection(state: .custom(curve), presets: presets) == .otherCustom,
                     "a curve set elsewhere shows as other custom")
        suite.expect(NommoEQSelection(state: .builtIn(.movie), presets: presets) == .builtIn(.movie),
                     "a built-in mode shows as itself")
        suite.expect(NommoEQSelection(state: nil, presets: presets) == .unknown, "no reading is unknown")
        var twins = presets
        twins[.movie] = twins[.game]
        suite.expect(NommoEQSelection(state: .custom(presets[.game]!), presets: twins, preferring: .movie)
                        == .preset(.movie)
                        && NommoEQSelection(state: .custom(presets[.game]!), presets: twins) == .preset(.game)
                        && NommoEQSelection(state: .custom(curve), presets: twins, preferring: .movie) == .otherCustom,
                     "when two presets share a curve, the one in use stays selected")

        // MARK: The chart

        suite.expect(NommoEQSelection.builtIn(.movie).curve(presets: withEditedGame(presets), state: .builtIn(.movie))
                        == NommoEQPreset.movie.razerCurve,
                     "a built-in mode shows Razer's curve, not the edited copy")
        suite.expect(NommoEQSelection.preset(.game).curve(presets: withEditedGame(presets), state: nil) == editedGame
                        && NommoEQSelection.otherCustom.curve(presets: presets, state: .custom(curve)) == curve
                        && NommoEQSelection.unknown.curve(presets: presets, state: nil) == nil,
                     "a preset shows its saved curve, another custom curve shows as read, unknown shows nothing")
        suite.expect(NommoEQSelection.builtIn(.music).editablePreset == .music
                        && NommoEQSelection.preset(.movie).editablePreset == .movie,
                     "dragging a built-in mode's curve copies it into the preset of the same name")
        suite.expect(NommoEQSelection.preset(.flat).editablePreset == nil
                        && NommoEQSelection.otherCustom.editablePreset == nil
                        && NommoEQSelection.unknown.editablePreset == nil,
                     "flat and curves set elsewhere can't be dragged")

        // MARK: Presets on this Mac

        suite.expect(NommoEQPresetStore.decode(nil) == presets, "with nothing saved, every preset is its suggestion")
        suite.expect(NommoEQPresetStore.decode("not json") == presets, "damaged storage falls back to suggestions")
        var edited = presets
        edited[.game] = curve
        suite.expect(NommoEQPresetStore.decode(NommoEQPresetStore.encode(edited)) == edited,
                     "an edited preset survives saving")
        suite.expect(NommoEQPresetStore.decode(#"{"flat":[5,5,5,5,5,5,5,5,5,5]}"#)[.flat] == .flat,
                     "flat stays flat whatever is saved")
        suite.expect(NommoEQPresetStore.decode(#"{"music":[99]}"#)[.music]
                        == NommoEQCurve([12, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
                     "a saved curve is clamped to ten bands within ±12")
        suite.expect(!NommoEQPresetStore.encode(presets).contains("flat"), "flat is never saved")
        suite.expect(NommoEQPresetStore.decode(NommoEQPresetStore.defaultStorage) == presets,
                     "the registered default holds the suggestions")

        // MARK: Lighting

        let off = NommoProtocol.request(.frame([]))
        suite.expect(off[6] == 0x29 && Array(off[9..<14]) == [0x00, 0x00, 0x00, 0x00, 0x0B]
                        && off[14..<50].allSatisfy { $0 == 0 },
                     "an empty frame is twelve black LEDs after the frame header")
        let mixed = NommoCommand.frame([RGBColor(red: 0xFF, green: 0x10, blue: 0), RGBColor(red: 0, green: 0, blue: 0xEE)]
                                       + Array(repeating: .black, count: 20)).arguments
        suite.expect(mixed.count == 5 + 36 && Array(mixed[5..<8]) == [0xFF, 0x10, 0x00]
                        && Array(mixed[8..<11]) == [0x00, 0x00, 0xEE] && mixed[11...].allSatisfy { $0 == 0 },
                     "a frame carries one color per LED, twelve at most")
        suite.expect(NommoCommand.resumeAnimation.arguments == [0x00, 0x00, 0x00]
                        && NommoCommand.enterFrameMode.arguments == [0x00, 0x00, 0x08, 0x00, 0x01],
                     "frame mode and the animation use the arguments confirmed on the speaker")
        suite.expect(NommoBuiltInMode.allCases.allSatisfy { $0.indicatorColor.hue != nil },
                     "each built-in mode's color is a hue, as the speakers show it")
        suite.expect(NommoLighting.eqColorHold == 3, "the strings promise a built-in mode's color shows for 3 seconds")
        suite.expect(NommoCommand.writeBrightness(300).arguments == [0x01, 0x00, 0xFF]
                        && NommoCommand.readBrightness.arguments == [0x01, 0x00],
                     "brightness writes stay within 0 to 255")
        let grid = (0...100).map { Double($0) / 100 }
        let fadeOut = grid.map { NommoLighting.fadeLevel(from: 255, to: 0, progress: $0) }
        let fadeIn = grid.map { NommoLighting.fadeLevel(from: 0, to: 180, progress: $0) }
        suite.expect(fadeOut.first == 255 && fadeOut.last == 0 && fadeIn.first == 0 && fadeIn.last == 180,
                     "a fade starts and ends exactly on its levels")
        suite.expect(zip(fadeOut, fadeOut.dropFirst()).allSatisfy { $0 >= $1 }
                        && zip(fadeIn, fadeIn.dropFirst()).allSatisfy { $0 <= $1 },
                     "a fade only moves one way")
        suite.expect(fadeOut[50] < 255 / 2, "halfway through a fade out the level is under half, so it looks even")
        suite.expect(fadeOut.filter { $0 > 0 && $0 <= 3 }.count <= 6,
                     "a fade passes the coarse bottom levels quickly instead of lingering on them")
        suite.expect(NommoLighting.fadeLevel(from: 255, to: 0, progress: 2) == 0, "progress past the end holds the target")

        // MARK: Standby and firmware

        suite.expect(NommoStandbyDelay.fifteen.bytes == [0x03, 0x84], "15 minutes is 900 s, big-endian")
        suite.expect(NommoStandbyDelay(bytes: [0x07, 0x08]) == .thirty, "0708 reads back as 30 minutes")
        suite.expect(NommoStandbyDelay(bytes: [0x00, 0x3C]) == nil, "the speaker accepts only 15, 30 and 45 minutes")
        suite.expect(NommoProtocol.firmwareVersion(from: [1, 6, 1]) == "1.6.1", "firmware reads as major.minor.patch")
        suite.expect(NommoProtocol.firmwareVersion(from: [0, 0, 0]) == nil, "a zero firmware is no answer")
    }
}
