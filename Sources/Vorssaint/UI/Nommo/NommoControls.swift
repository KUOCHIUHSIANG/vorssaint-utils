// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import AppKit
import SwiftUI

/// Subwoofer levels 1 to 7. The speaker has no 0: it reads an out-of-range
/// value as its default of 4.
struct NommoSubwooferPicker: View {
    @ObservedObject private var service = NommoService.shared

    var body: some View {
        Picker("", selection: Binding(get: { service.state.subwoofer ?? 0 },
                                      set: { service.setSubwoofer($0) })) {
            ForEach(Array(NommoSubwoofer.range), id: \.self) { level in
                Text("\(level)").tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(service.state.subwoofer == nil)
    }
}

/// Razer's built-in modes and the presets kept on this Mac, in one menu.
struct NommoEQMenu: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }

    var body: some View {
        Menu {
            Section(strings.builtInGroup) {
                ForEach(NommoBuiltInMode.allCases, id: \.self) { item(.builtIn($0)) }
            }
            Section(strings.myEQGroup) {
                ForEach(NommoEQPreset.allCases, id: \.self) { item(.preset($0)) }
            }
        } label: {
            Text(strings.selectionName(service.selection))
        }
        .fixedSize()
        .disabled(service.state.eq == nil)
    }

    private func item(_ choice: NommoEQSelection) -> some View {
        Toggle(strings.selectionName(choice), isOn: Binding(get: { service.selection == choice },
                                                            set: { if $0 { service.select(choice) } }))
    }
}

/// The curve of the EQ in use, on Razer's chart. Dragging a band saves and
/// plays it; a built-in mode's curve is first copied into the preset of the
/// same name, the way Synapse turns an edited preset into Custom. Once a
/// preset differs from Razer's curve, a button puts it back.
struct NommoEQEditor: View {
    var plotHeight: CGFloat = 84
    var compact = true
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }

    var body: some View {
        let selection = service.selection
        if let curve = selection.curve(presets: service.presets, state: service.state.eq) {
            let preset = selection.editablePreset
            VStack(alignment: .trailing, spacing: 6) {
                NommoEQChart(curve: curve, ranges: strings.ranges, plotHeight: plotHeight,
                             onChange: preset == nil ? nil : { service.editCurve($0) })
                    .help(preset.map { caption(for: selection, preset: $0) } ?? "")
                if case let .preset(edited) = selection, edited.isEditable, curve != edited.razerCurve {
                    Button(strings.restoreRazerCurve) {
                        service.restoreRazerCurve(for: edited)
                    }
                    .controlSize(compact ? .small : .regular)
                }
            }
        }
    }

    private func caption(for selection: NommoEQSelection, preset: NommoEQPreset) -> String {
        if case .builtIn = selection { return String(format: strings.copyCaption, strings.presetName(preset)) }
        return strings.editCaption
    }
}

/// 15, 30 or 45 minutes: the only delays the speaker accepts.
struct NommoStandbyDelayPicker: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }

    var body: some View {
        Picker(strings.standbyDelay, selection: Binding(get: { service.state.standbyDelay ?? .fifteen },
                                                        set: { service.setStandbyDelay($0) })) {
            ForEach(NommoStandbyDelay.allCases, id: \.self) { delay in
                Text(String(format: strings.minutesFormat, delay.minutes)).tag(delay)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(service.state.autoStandby != true)
    }
}

/// The lighting Neptater keeps the speakers on.
struct NommoLightingPicker: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }

    var body: some View {
        Picker(strings.lighting, selection: Binding(get: { service.lighting }, set: { service.setLighting($0) })) {
            ForEach(NommoLighting.allCases, id: \.self) { lighting in
                Text(strings.lightingName(lighting)).tag(lighting)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// Nine fixed colors, then the ones added with "+" (right-click deletes
/// those), for the solid lighting. Wraps to a second row as colors are added.
struct NommoLightingColorRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared
    var size: CGFloat = 18

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }
    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(size), spacing: 7), count: 10) }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(NommoLighting.swatches, id: \.hex) { color in
                swatch(color)
            }
            ForEach(Array(service.customColors.enumerated()), id: \.offset) { index, color in
                swatch(color)
                    .help("\(color.hex) · \(strings.deleteHint)")
                    .contextMenu {
                        Button(strings.deleteColor, role: .destructive) {
                            NommoColorPanel.shared.endAdding()
                            service.removeCustomColor(at: index)
                        }
                    }
            }
            if service.customColors.count < NommoLighting.maxCustomColors {
                Button {
                    NommoColorPanel.shared.beginAdding()
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

    private func swatch(_ color: NommoColor) -> some View {
        let chosen = service.lighting == .solid && service.lightingColor == color
        return Button {
            NommoColorPanel.shared.endAdding()
            service.setLightingColor(color)
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

/// The brightness of the rainbow and the solid color, 5 % to 100 %.
struct NommoLightingLevelSlider: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min")
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(service.lightingLevel) },
                                  set: { service.setLightingLevel(Int($0.rounded())) }),
                   in: Double(NommoLighting.levelRange.lowerBound)...Double(NommoLighting.levelRange.upperBound))
                .accessibilityLabel(strings.brightness)
            Text("\(service.lightingLevel)%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
    }
}

/// Adding a color: "+" puts a new color after the others and opens the system
/// color panel on it; the color and the speakers follow the panel live, and
/// closing the panel keeps it, unless it repeats a color already there. Kept
/// apart from the views, so the speakers follow even if the menu panel closes.
final class NommoColorPanel: NSObject {
    static let shared = NommoColorPanel()

    private var addingIndex: Int?
    private var closeObserver: NSObjectProtocol?

    func beginAdding() {
        endAdding()
        let service = NommoService.shared
        let start = service.lightingColor
        guard let index = service.addCustomColor(start) else { return }
        addingIndex = index
        service.setLightingColor(start)
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
        let service = NommoService.shared
        guard service.customColors.indices.contains(index) else { return }
        let added = service.customColors[index]
        let others = NommoLighting.swatches + service.customColors.enumerated()
            .filter { $0.offset != index }.map(\.element)
        if others.contains(added) { service.removeCustomColor(at: index) }
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let index = addingIndex, let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        func byte(_ component: CGFloat) -> UInt8 { UInt8((min(max(component, 0), 1) * 255).rounded()) }
        let color = NommoColor(red: byte(rgb.redComponent), green: byte(rgb.greenComponent),
                               blue: byte(rgb.blueComponent))
        NommoService.shared.updateCustomColor(at: index, to: color)
        NommoService.shared.setLightingColor(color)
    }
}

extension NommoColor {
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
