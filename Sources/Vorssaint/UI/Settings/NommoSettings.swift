// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import SwiftUI

/// Settings card for the Nommo V2: the panel controls, plus the editor for the
/// presets kept on this Mac and the speaker's standby.
struct NommoSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared
    @AppStorage(DefaultsKey.panelShowNommo) private var showInPanel = true

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }

    var body: some View {
        SettingsCard(title: strings.title) {
            SettingsRow(symbol: "hifispeaker.2.fill", title: strings.showInPanel, caption: status) {
                Toggle(strings.showInPanel, isOn: $showInPanel).labelsHidden()
            }
            if service.isConnected {
                Divider()
                SettingsRow(symbol: nil, title: strings.subwoofer) {
                    NommoSubwooferPicker()
                        .frame(width: 240)
                }
                Divider()
                SettingsRow(symbol: nil, title: strings.equalizer, caption: strings.builtInCaption) {
                    NommoEQMenu()
                }
                Divider()
                curveEditor
                Divider()
                SettingsRow(symbol: nil, title: strings.autoStandby, caption: strings.autoStandbyCaption) {
                    Toggle(strings.autoStandby, isOn: Binding(get: { service.state.autoStandby ?? false },
                                                               set: { service.setAutoStandby($0) }))
                        .labelsHidden()
                        .disabled(service.state.autoStandby == nil)
                }
                SettingsRow(symbol: nil, title: strings.standbyDelay) {
                    NommoStandbyDelayPicker()
                        .frame(width: 220)
                }
            }
            if service.failure != nil {
                Text(strings.noReply)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, settingsRowTextInset)
            }
        }
        .onAppear { service.refresh() }
    }

    private var status: String {
        guard service.isConnected else { return strings.notConnected }
        guard let firmware = service.state.firmware else { return strings.connected }
        return "\(strings.connected) · \(String(format: strings.firmwareFormat, firmware))"
    }

    private var curveEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(strings.editCurve)
                .font(.headline)
            NommoPresetEditor()
        }
        .padding(.vertical, 4)
    }
}
