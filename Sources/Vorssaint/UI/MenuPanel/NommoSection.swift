// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import SwiftUI

/// Panel section with every Nommo V2 control, so nothing needs Settings: the
/// subwoofer level and EQ up front, the curve editor behind a disclosure, and
/// standby. It reads the speaker each time it appears, so the panel shows what
/// the speaker actually has.
struct NommoSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared
    @State private var editorExpanded = false
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
                    if !editorExpanded, case let .preset(preset) = service.selection,
                       let curve = service.presets[preset] {
                        NommoCurvePreview(curve: curve)
                    }
                    editorDisclosure
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

    private var editorDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                editorExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(editorExpanded ? 90 : 0))
                    Text(strings.editCurve)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if editorExpanded {
                NommoPresetEditor(compact: true)
                    .controlSize(.small)
            }
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
