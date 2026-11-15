// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import AppKit
import SwiftUI

/// The modes, in a menu: there are too many for a segmented control.
struct RGBLightingModePicker: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = RGBLightingService.shared

    private var strings: RGBLightingFeatureStrings { FeatureStrings.rgbLighting(l10n.language) }

    var body: some View {
        Picker(strings.lighting, selection: Binding(get: { service.settings.mode }, set: { service.setMode($0) })) {
            ForEach(RGBLightingMode.allCases, id: \.self) { mode in
                Text(strings.modeName(mode)).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

/// Which way a wave or a meteor goes, as arrows seen from the chair.
struct RGBLightingDirectionPicker: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = RGBLightingService.shared

    private var strings: RGBLightingFeatureStrings { FeatureStrings.rgbLighting(l10n.language) }

    var body: some View {
        Picker(strings.direction, selection: Binding(get: { service.settings.direction },
                                                     set: { service.setDirection($0) })) {
            ForEach(RGBWaveDirection.allCases, id: \.self) { direction in
                Image(systemName: Self.symbol(direction))
                    .accessibilityLabel(strings.directionName(direction))
                    .help(strings.directionName(direction))
                    .tag(direction)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private static func symbol(_ direction: RGBWaveDirection) -> String {
        switch direction {
        case .down: return "arrow.down"
        case .up: return "arrow.up"
        case .right: return "arrow.right"
        case .left: return "arrow.left"
        }
    }
}

/// The speakers and the monitor, each with whether it shows the lighting.
struct RGBLightingDeviceList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var nommo = NommoService.shared
    @ObservedObject private var monitor = MSIMonitorService.shared

    private var strings: RGBLightingFeatureStrings { FeatureStrings.rgbLighting(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(FeatureStrings.nommo(l10n.language).title, connected: nommo.isConnected,
                detail: nommo.isConnected ? strings.connected : strings.notConnected)
            row(monitor.name ?? strings.monitor, connected: monitor.status == .ready, detail: monitorDetail)
        }
    }

    private var monitorDetail: String {
        switch monitor.status {
        case .absent: return strings.notConnected
        case .checking, .ready: return strings.connected
        case let .unsupported(layout): return String(format: strings.unsupportedFormat, layout)
        case .noAnswer: return strings.noAnswer
        }
    }

    private func row(_ name: String, connected: Bool, detail: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Nine fixed colors, then the ones added with "+" (right-click deletes
/// those), for the modes that show a color. Wraps to a second row as colors are added.
struct RGBLightingColorRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = RGBLightingService.shared
    var size: CGFloat = 18

    private var strings: RGBLightingFeatureStrings { FeatureStrings.rgbLighting(l10n.language) }
    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(size), spacing: 7), count: 10) }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(RGBLighting.swatches, id: \.hex) { color in
                swatch(color)
            }
            ForEach(Array(service.customColors.enumerated()), id: \.offset) { index, color in
                swatch(color)
                    .help("\(color.hex) · \(strings.deleteHint)")
                    .contextMenu {
                        Button(strings.deleteColor, role: .destructive) {
                            RGBColorPanel.shared.endAdding()
                            service.removeCustomColor(at: index)
                        }
                    }
            }
            if service.customColors.count < RGBLighting.maxCustomColors {
                Button {
                    RGBColorPanel.shared.beginAdding()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: size, height: size)
                        .overlay(Circle().strokeBorder(Color.secondary,
                                                       style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(strings.addColor)
                .accessibilityLabel(strings.addColor)
            }
        }
        .frame(width: size * 10 + 7 * 9, alignment: .leading)
    }

    private func swatch(_ color: RGBColor) -> some View {
        let chosen = service.settings.mode.usesColor && service.settings.color == color
        return Button {
            RGBColorPanel.shared.endAdding()
            service.setColor(color)
        } label: {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                .padding(chosen ? 3 : 0)
                .overlay(Circle().strokeBorder(chosen ? Color.primary : .clear, lineWidth: 1.5))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.hex)
    }
}

/// The brightness of every mode, 5 % to 100 %.
struct RGBLightingLevelSlider: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = RGBLightingService.shared

    private var strings: RGBLightingFeatureStrings { FeatureStrings.rgbLighting(l10n.language) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min")
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(service.settings.level) },
                                  set: { service.setLevel(Int($0.rounded())) }),
                   in: Double(RGBLighting.levelRange.lowerBound)...Double(RGBLighting.levelRange.upperBound))
                .accessibilityLabel(strings.brightness)
            Text("\(service.settings.level)%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
    }
}

/// Adding a color: "+" puts a new color after the others and opens the system
/// color panel on it; the color and the lights follow the panel live, and
/// closing the panel keeps it, unless it repeats a color already there. Kept
/// apart from the views, so the lights follow even if the menu panel closes.
final class RGBColorPanel: NSObject {
    static let shared = RGBColorPanel()

    private var addingIndex: Int?
    private var closeObserver: NSObjectProtocol?

    func beginAdding() {
        endAdding()
        let service = RGBLightingService.shared
        let start = service.settings.color
        guard let index = service.addCustomColor(start) else { return }
        addingIndex = index
        service.setColor(start)
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.color = start.nsColor
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: panel, queue: .main) { [weak self] _ in
            self?.endAdding(closingPanel: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
    }

    /// Keeps the added color, dropping it if it only repeats another. Picking
    /// or deleting a swatch ends it too, and closes the panel, which would
    /// otherwise stay open doing nothing.
    func endAdding(closingPanel: Bool = true) {
        guard let index = addingIndex else { return }
        addingIndex = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        if closingPanel { panel.close() }
        let service = RGBLightingService.shared
        guard service.customColors.indices.contains(index) else { return }
        let added = service.customColors[index]
        let others = RGBLighting.swatches + service.customColors.enumerated()
            .filter { $0.offset != index }.map(\.element)
        if others.contains(added) { service.removeCustomColor(at: index) }
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let index = addingIndex, let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        func byte(_ component: CGFloat) -> UInt8 { UInt8((min(max(component, 0), 1) * 255).rounded()) }
        let color = RGBColor(red: byte(rgb.redComponent), green: byte(rgb.greenComponent),
                               blue: byte(rgb.blueComponent))
        RGBLightingService.shared.updateCustomColor(at: index, to: color)
        RGBLightingService.shared.setColor(color)
    }
}

extension RGBColor {
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
