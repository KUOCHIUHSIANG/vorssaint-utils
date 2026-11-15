// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import SwiftUI

/// Panel section with every Nommo V2 control, so nothing needs Settings: the
/// subwoofer level, the EQ with its curve to drag, lighting and standby. It
/// reads the speaker each time it appears, so the panel shows what the
/// speaker actually has.
struct NommoSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared
    var collapsible = true

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }

    var body: some View {
        PanelSection(.nommo, title: strings.title, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 9) {
                if service.isConnected {
                    HStack {
                        Text(strings.subwoofer)
                        Spacer(minLength: 8)
                        if let level = service.state.subwoofer {
                            Text("\(level) / \(NommoSubwoofer.range.upperBound)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    NommoSubwooferPicker()
                        .controlSize(.small)
                    Divider()
                    HStack {
                        Text(strings.equalizer)
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer(minLength: 8)
                        NommoEQMenu()
                            .controlSize(.small)
                    }
                    NommoEQEditor()
                        .controlSize(.small)
                    Divider()
                    HStack {
                        Text(strings.lighting)
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer(minLength: 8)
                        NommoLightingPicker()
                            .controlSize(.small)
                            .frame(width: 190)
                    }
                    .help(strings.lightingCaption)
                    if service.lighting == .solid {
                        NommoLightingColorRow()
                    }
                    if service.lighting != .off {
                        NommoLightingLevelSlider()
                            .controlSize(.small)
                            .font(.system(size: 10.5))
                    }
                    Divider()
                    standby
                    if service.failure != nil {
                        Text(strings.noReply)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(strings.notConnected)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .panelCard()
            .onAppear { service.refresh() }
        }
    }

    private var standby: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(strings.autoStandby, isOn: Binding(get: { service.state.autoStandby ?? false },
                                                      set: { service.setAutoStandby($0) }))
                .font(.system(size: 11.5, weight: .medium))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(service.state.autoStandby == nil)
                .help(strings.autoStandbyCaption)
            if service.state.autoStandby == true {
                NommoStandbyDelayPicker()
                    .controlSize(.small)
                Text(strings.autoStandbyCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
