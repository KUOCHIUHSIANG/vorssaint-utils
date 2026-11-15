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
