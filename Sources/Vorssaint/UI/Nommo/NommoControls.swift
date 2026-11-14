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

/// A curve drawn the way EQ apps draw one: the ten bands joined smoothly
/// around the zero line, with a soft fill. The scale follows the curve, down to
/// ±4, so a gentle curve keeps its shape without small steps looking huge.
struct NommoCurvePreview: View {
    let curve: NommoEQCurve
    var height: CGFloat = 44

    private static let minimumScale = 4

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(for: curve, in: geometry.size)
            let line = Self.smoothPath(through: points)
            let middle = geometry.size.height / 2
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: middle))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: middle))
                }
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                Path { path in
                    path.addPath(Path(line))
                    if let last = points.last, let first = points.first {
                        path.addLine(to: CGPoint(x: last.x, y: middle))
                        path.addLine(to: CGPoint(x: first.x, y: middle))
                        path.closeSubpath()
                    }
                }
                .fill(LinearGradient(stops: [.init(color: Color.accentColor.opacity(0.45), location: 0),
                                             .init(color: Color.accentColor.opacity(0.08), location: 0.5),
                                             .init(color: Color.accentColor.opacity(0.45), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                Path(line)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: 4)
                        .position(point)
                }
            }
        }
        .frame(height: height)
        .padding(.horizontal, 3)
        .accessibilityHidden(true)
    }

    private static func points(for curve: NommoEQCurve, in size: CGSize) -> [CGPoint] {
        let scale = CGFloat(max(minimumScale, curve.bands.map(abs).max() ?? 0))
        let step = size.width / CGFloat(NommoEQCurve.bandCount - 1)
        let reach = size.height / 2 - 4
        return curve.bands.enumerated().map { index, level in
            CGPoint(x: CGFloat(index) * step, y: size.height / 2 - CGFloat(level) / scale * reach)
        }
    }

    /// Catmull-Rom through every band, as cubic Béziers.
    private static func smoothPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 0..<(points.count - 1) {
            let before = points[max(index - 1, 0)], start = points[index]
            let end = points[index + 1], after = points[min(index + 2, points.count - 1)]
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + (end.x - before.x) / 6, y: start.y + (end.y - before.y) / 6),
                          control2: CGPoint(x: end.x - (after.x - start.x) / 6, y: end.y - (after.y - start.y) / 6))
        }
        return path
    }
}

/// Ten bands, each dragged in whole steps from −12 to +12.
struct NommoCurveEditor: View {
    let curve: NommoEQCurve
    var sliderHeight: CGFloat = 120
    let onChange: (NommoEQCurve) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<NommoEQCurve.bandCount, id: \.self) { band in
                VStack(spacing: 5) {
                    Text(Self.signed(curve.bands[band]))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    NommoBandSlider(value: curve.bands[band], height: sliderHeight,
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
    let height: CGFloat
    let label: String
    let onChange: (Int) -> Void

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
        .frame(width: 28, height: height)
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

/// The presets kept on this Mac, edited in place: dragging a band saves the
/// curve and plays it on the speakers. Opens on the preset in use, if any.
struct NommoPresetEditor: View {
    var compact = false
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NommoService.shared
    @State private var editing: NommoEQPreset = .game

    private var strings: NommoFeatureStrings { FeatureStrings.nommo(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Picker(strings.editCurve, selection: $editing) {
                ForEach(NommoEQPreset.allCases.filter(\.isEditable), id: \.self) { preset in
                    Text(strings.presetName(preset)).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            NommoCurveEditor(curve: service.presets[editing] ?? editing.suggestedCurve,
                             sliderHeight: compact ? 90 : 120) {
                service.update(editing, curve: $0)
            }
            HStack(alignment: .top) {
                Text(strings.editCaption)
                    .font(compact ? .system(size: 9.5) : .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(strings.restoreSuggestion) {
                    service.restoreSuggestion(for: editing)
                }
                .controlSize(compact ? .small : .regular)
                .disabled(service.presets[editing] == editing.suggestedCurve)
            }
        }
        .onAppear {
            if case let .preset(preset) = service.selection, preset.isEditable { editing = preset }
        }
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
