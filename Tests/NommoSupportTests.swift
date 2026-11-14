// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation

/// The Nommo V2 report format, the commands Neptater may send, and the EQ
/// presets kept on this Mac.
enum NommoSupportTests {
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
            .writeStandbyDelay(.fifteen),
        ]
        let known: Set<[UInt8]> = [[0x00, 0x87], [0x08, 0x87], [0x08, 0x07], [0x08, 0x82], [0x08, 0x02],
                                   [0x08, 0x84], [0x08, 0x04], [0x07, 0x88], [0x07, 0x08], [0x07, 0x83], [0x07, 0x03]]
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
            suite.expect(preset.suggestedCurve == NommoEQCurve(preset.suggestedCurve.bands),
                         "the \(preset.rawValue) suggestion is a valid curve")
        }

        // MARK: What the speaker reports

        suite.expect(NommoEQState(modeByte: 0x02, curve: nil) == .builtIn(.music), "mode 02 is Music")
        suite.expect(NommoEQState(modeByte: 0x10, curve: curve) == .custom(curve), "mode 10 is the custom curve")
        suite.expect(NommoEQState(modeByte: 0x00, curve: nil) == .other(0x00), "an unknown mode stays unknown")

        let presets = NommoEQPresetStore.suggestedCurves
        suite.expect(NommoEQSelection(state: .custom(NommoEQPreset.game.suggestedCurve), presets: presets)
                        == .preset(.game), "a curve matching a preset shows as that preset")
        suite.expect(NommoEQSelection(state: .custom(.flat), presets: presets) == .preset(.flat),
                     "a flat curve shows as Flat")
        suite.expect(NommoEQSelection(state: .custom(curve), presets: presets) == .otherCustom,
                     "a curve set elsewhere shows as other custom")
        suite.expect(NommoEQSelection(state: .builtIn(.movie), presets: presets) == .builtIn(.movie),
                     "a built-in mode shows as itself")
        suite.expect(NommoEQSelection(state: nil, presets: presets) == .unknown, "no reading is unknown")

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

        // MARK: Standby and firmware

        suite.expect(NommoStandbyDelay.fifteen.bytes == [0x03, 0x84], "15 minutes is 900 s, big-endian")
        suite.expect(NommoStandbyDelay(bytes: [0x07, 0x08]) == .thirty, "0708 reads back as 30 minutes")
        suite.expect(NommoStandbyDelay(bytes: [0x00, 0x3C]) == nil, "the speaker accepts only 15, 30 and 45 minutes")
        suite.expect(NommoProtocol.firmwareVersion(from: [1, 6, 1]) == "1.6.1", "firmware reads as major.minor.patch")
        suite.expect(NommoProtocol.firmwareVersion(from: [0, 0, 0]) == nil, "a zero firmware is no answer")
    }
}
