// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import SwiftUI

/// Settings card for RGB lighting: the same controls as the panel.
struct RGBLightingSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = RGBLightingService.shared
    @AppStorage(DefaultsKey.panelShowRGBLighting) private var showInPanel = true

    private var strings: RGBLightingFeatureStrings { FeatureStrings.rgbLighting(l10n.language) }

    var body: some View {
        SettingsCard(title: strings.title) {
            SettingsRow(symbol: "rainbow", title: strings.showInPanel) {
                Toggle(strings.showInPanel, isOn: $showInPanel).labelsHidden()
            }
            Divider()
            SettingsRow(symbol: nil, title: strings.lighting, caption: strings.caption) {
                HStack(spacing: 10) {
                    RGBLightingModePicker()
                        .disabled(!service.settings.isOn)
                    RGBLightingSwitch()
                }
            }
            Group {
                if service.settings.mode.usesDirection {
                    SettingsRow(symbol: nil, title: strings.direction) {
                        RGBLightingDirectionPicker()
                            .frame(width: 200)
                    }
                }
                if service.settings.mode.usesColor {
                    SettingsRow(symbol: nil, title: strings.color,
                                caption: service.settings.mode == .lightning ? strings.lightningHint : nil) {
                        RGBLightingColorRow(size: 20)
                    }
                }
                SettingsRow(symbol: nil, title: strings.brightness) {
                    RGBLightingLevelSlider()
                        .frame(width: 240)
                }
                if service.settings.mode.moves {
                    SettingsRow(symbol: nil, title: strings.speed) {
                        RGBLightingSpeedSlider()
                            .frame(width: 280)
                    }
                }
            }
            .disabled(!service.settings.isOn)
            Divider()
            SettingsRow(symbol: nil, title: strings.devices) {
                RGBLightingDeviceList()
                    .frame(width: 320)
            }
        }
    }
}
