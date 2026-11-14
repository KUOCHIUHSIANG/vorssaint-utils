// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

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

/// A small bar chart of a curve, each band drawn up or down from the middle.
struct NommoCurvePreview: View {
    let curve: NommoEQCurve
    var height: CGFloat = 26

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(curve.bands.enumerated()), id: \.offset) { _, level in
                let share = CGFloat(abs(level)) / CGFloat(NommoEQCurve.levels.upperBound)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .frame(height: level >= 0 ? height / 2 * (1 - share) : height / 2)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(height: max(1.5, height / 2 * share))
                    Spacer(minLength: 0)
                }
                .frame(height: height)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1))
        .accessibilityHidden(true)
    }
}

/// Ten bands, each dragged in whole steps from −12 to +12.
struct NommoCurveEditor: View {
    let curve: NommoEQCurve
    let onChange: (NommoEQCurve) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<NommoEQCurve.bandCount, id: \.self) { band in
                VStack(spacing: 5) {
                    Text(Self.signed(curve.bands[band]))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    NommoBandSlider(value: curve.bands[band],
                                    label: NommoEQCurve.frequencyLabels[band]) {
                        onChange(curve.setting(band: band, to: $0))
                    }
                    Text(NommoEQCurve.frequencyLabels[band])
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static func signed(_ level: Int) -> String {
        level > 0 ? "+\(level)" : "\(level)"
    }
}

private struct NommoBandSlider: View {
    let value: Int
    let label: String
    let onChange: (Int) -> Void

    private static let height: CGFloat = 120
    private static let lower = NommoEQCurve.levels.lowerBound
    private static let span = CGFloat(NommoEQCurve.levels.upperBound - NommoEQCurve.levels.lowerBound)

    var body: some View {
        GeometryReader { geometry in
            let middle = geometry.size.width / 2
            let height = geometry.size.height
            let knob = height * (1 - CGFloat(value - Self.lower) / Self.span)
            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 4, height: height)
                    .position(x: middle, y: height / 2)
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 12, height: 1)
                    .position(x: middle, y: height / 2)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: abs(knob - height / 2))
                    .position(x: middle, y: (knob + height / 2) / 2)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .frame(width: 14, height: 14)
                    .position(x: middle, y: knob)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let share = 1 - min(max(drag.location.y / height, 0), 1)
                let level = Int((share * Self.span).rounded()) + Self.lower
                if level != value { onChange(level) }
            })
        }
        .frame(width: 28, height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(NommoCurveEditor.signed(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(value + 1)
            case .decrement: onChange(value - 1)
            @unknown default: break
            }
        }
    }
}
