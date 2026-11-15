// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import SwiftUI

/// Panel section for the lighting of every RGB device at once: the switch, the mode, its
/// direction and color where it takes one, the brightness, the speed of the
/// moving modes, and which devices are there to show it.
struct RGBLightingSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = RGBLightingService.shared
    var collapsible = true

    private var strings: RGBLightingFeatureStrings { FeatureStrings.rgbLighting(l10n.language) }

    var body: some View {
        PanelSection(.rgbLighting, title: strings.title, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(strings.lighting)
                        .font(.system(size: 11.5, weight: .medium))
                    RGBLightingSwitch()
                        .controlSize(.mini)
                    Spacer(minLength: 8)
                    RGBLightingModePicker()
                        .controlSize(.small)
                        .disabled(!service.settings.isOn)
                }
                .help(strings.caption)
                VStack(alignment: .leading, spacing: 9) {
                    if service.settings.mode.usesDirection {
                        HStack {
                            Text(strings.direction)
                                .font(.system(size: 11.5, weight: .medium))
                            Spacer(minLength: 8)
                            RGBLightingDirectionPicker()
                                .controlSize(.small)
                                .frame(width: 150)
                        }
                    }
                    if service.settings.mode == .screen {
                        RGBScreenModeNote()
                    }
                    if service.settings.mode.listens {
                        Text(strings.musicHint)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if service.settings.mode.usesColor {
                        RGBLightingColorRow()
                        if service.settings.mode == .lightning {
                            Text(strings.lightningHint)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    RGBLightingLevelSlider()
                        .controlSize(.small)
                        .font(.system(size: 10.5))
                    if service.settings.mode.moves {
                        RGBLightingSpeedSlider()
                            .controlSize(.small)
                            .font(.system(size: 10.5))
                    }
                }
                .disabled(!service.settings.isOn)
                Divider()
                RGBLightingDeviceList()
                    .font(.system(size: 10.5))
            }
            .panelCard()
        }
    }
}
