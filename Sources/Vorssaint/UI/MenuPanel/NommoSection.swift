// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import SwiftUI

/// Panel section for the everyday Nommo V2 controls: subwoofer level and EQ.
/// The curve editor and standby live in Settings. It reads the speaker each
/// time it appears, so the panel shows what the speaker actually has.
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
                    if case let .preset(preset) = service.selection, let curve = service.presets[preset] {
                        NommoCurvePreview(curve: curve)
                    }
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
}
