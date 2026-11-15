// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation

/// The lighting controller in MSI's monitors (USB 1462:3FA4), as OpenRGB's
/// "MSI Monitor (Gaming Controller)" driver drives it (GPL-2.0-or-later, by
/// Andy Herbert and Ken Sanislo), checked on Jater's MPG 274URDFW E16M.
///
/// One 168-byte feature report, 0x72, sets the lighting: two identical
/// control blocks (mode, color, speed, brightness 0–100, a second color, and
/// 0x80 to paint from the per-LED colors), two arrays of 24 colors, and a
/// last byte that also writes it all to flash. Neptater never sets that byte:
/// what it draws lasts until the monitor powers off, and whatever the monitor
/// keeps in flash comes back after.
///
/// Many models share the USB ID; they tell their layout by answering 0xB0 on
/// report 0x01. Only layout 42 is known here: 22 rows down the back, top
/// first, each row lighting the left and the right side alike. Only the
/// second color array paints them; the first changes nothing (tried with
/// white and with red).
///
/// The monitor drives its LEDs straight from the values, so a little green
/// in a red shows as pink; colors go out through a 2.8 gamma, which Jater
/// matched by eye against the speakers' orange and pink.
enum MSIMonitorProtocol {
    static let vendorID = 0x1462
    static let productID = 0x3FA4
    static let frameReportID: UInt8 = 0x72
    static let frameLength = 168
    static let queryReportID: UInt8 = 0x01
    static let queryLength = 64
    static let supportedLayout = 42
    static let ledCount = 22

    private static let controlBlocks = [1, 12]
    private static let colorsStart = 95
    private static let staticMode: UInt8 = 0x01
    private static let paletteFlag: UInt8 = 0x80
    private static let storeIndex = 167
    static let gamma = 2.8

    private static let corrected: [UInt8] = (0...255).map {
        UInt8((pow(Double($0) / 255, gamma) * 255).rounded())
    }

    /// Asks which layout the monitor speaks; the answer comes as input report 0x01.
    static let layoutQuery: [UInt8] = {
        var bytes = [UInt8](repeating: 0, count: queryLength)
        bytes[0] = queryReportID
        bytes[1] = 0xB0
        return bytes
    }()

    /// The layout in an answer to `layoutQuery`: [0x01][0x5A][..][layout].
    static func layout(fromReply reply: [UInt8]) -> Int? {
        guard reply.count > 3, reply[0] == queryReportID, reply[1] == 0x5A else { return nil }
        return Int(reply[3])
    }

    /// A static frame painted LED by LED, gamma corrected, at full brightness
    /// (Neptater scales the colors itself), never written to flash.
    static func frame(_ colors: [RGBColor]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: frameLength)
        bytes[0] = frameReportID
        for block in controlBlocks {
            bytes[block] = staticMode
            bytes[block + 4] = 0x01
            bytes[block + 5] = 100
            bytes[block + 9] = paletteFlag
        }
        for index in 0..<ledCount {
            let color = index < colors.count ? colors[index] : .black
            bytes[colorsStart + index * 3] = corrected[Int(color.red)]
            bytes[colorsStart + index * 3 + 1] = corrected[Int(color.green)]
            bytes[colorsStart + index * 3 + 2] = corrected[Int(color.blue)]
        }
        return bytes
    }

    /// The monitor's own Rainbow Wave, as Jater's came set (mode 0x1A at speed
    /// 1, read from it on 2026-11-15), at `percent` brightness: what Neptater
    /// hands back, the way the speakers get their own spectrum back.
    static func rainbowWave(brightness percent: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: frameLength)
        bytes[0] = frameReportID
        let brightness = UInt8(min(max(percent, 1), 100))
        bytes.replaceSubrange(1...11, with: [0x1A, 0xFF, 0xFF, 0xFF, 0x01, brightness, 0x00, 0xFF, 0x00, 0x00, 0x00])
        bytes.replaceSubrange(12...22, with: [0x1A, 0x00, 0x00, 0x00, 0x01, brightness, 0x00, 0x00, 0x00, 0x00, 0x00])
        return bytes
    }

    /// The brightness field for a level factor on the colors, so the handed
    /// back effect looks as bright as the drawn lighting through the gamma.
    static func brightness(forLevel level: Double) -> Int {
        Int((pow(min(max(level, 0), 1), gamma) * 100).rounded())
    }

    /// Whether `report`, read back from the monitor, is a frame Neptater drew,
    /// rather than the monitor's own effect.
    static func isDrawnFrame(_ report: [UInt8]) -> Bool {
        report.count == frameLength && report[0] == frameReportID
            && report[controlBlocks[0]] == staticMode && report[controlBlocks[0] + 9] == paletteFlag
    }

    /// The colors in a drawn frame, undoing the gamma, to fade on from.
    static func colors(in report: [UInt8]) -> [RGBColor]? {
        guard isDrawnFrame(report) else { return nil }
        func plain(_ value: UInt8) -> UInt8 { UInt8((pow(Double(value) / 255, 1 / gamma) * 255).rounded()) }
        return (0..<ledCount).map {
            RGBColor(red: plain(report[colorsStart + $0 * 3]), green: plain(report[colorsStart + $0 * 3 + 1]),
                     blue: plain(report[colorsStart + $0 * 3 + 2]))
        }
    }
}
