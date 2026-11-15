// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import SwiftUI

/// An EQ curve laid out the way Razer Synapse lays one out: the ten bands on a
/// fixed ±12 dB scale with the dB marks on the right, and the frequencies and
/// the ranges they fall in underneath. With `onChange`, dragging in a band's
/// column moves that band in whole steps, showing its level while it moves.
struct NommoEQChart: View {
    let curve: NommoEQCurve
    /// Sub-bass, bass, low mids, mids, high mids and treble.
    let ranges: [String]
    var plotHeight: CGFloat = 96
    var onChange: ((NommoEQCurve) -> Void)?

    @State private var dragging: Int?

    private static let gutter: CGFloat = 34
    private static let inset: CGFloat = 6
    private static let marks = [12, 6, 0, -6, -12]
    /// Where each range starts and ends, in band columns (band i is centered
    /// on i + 0.5), close to where Synapse draws them.
    private static let rangeBounds: [CGFloat] = [0, 1.25, 3.4, 4.85, 6.9, 8.25, 10]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                GeometryReader { geometry in
                    plot(in: geometry.size)
                }
                marks
            }
            .frame(height: plotHeight)
            HStack(spacing: 0) {
                ForEach(NommoEQCurve.frequencyLabels, id: \.self) { label in
                    Text(label)
                        .frame(maxWidth: .infinity)
                }
                Text("Hz")
                    .padding(.leading, 6)
                    .frame(width: Self.gutter, alignment: .leading)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            HStack(spacing: 0) {
                GeometryReader { geometry in
                    rangeRow(width: geometry.size.width)
                }
                Spacer().frame(width: Self.gutter)
            }
            .frame(height: 16)
        }
    }

    private func plot(in size: CGSize) -> some View {
        let column = size.width / CGFloat(NommoEQCurve.bandCount)
        let points = curve.bands.enumerated().map { band, level in
            CGPoint(x: (CGFloat(band) + 0.5) * column, y: Self.y(for: level, height: size.height))
        }
        let dot = min(10, max(7, column * 0.34))
        return ZStack {
            ForEach(points.indices, id: \.self) { band in
                Path { path in
                    path.move(to: CGPoint(x: points[band].x, y: Self.y(for: 12, height: size.height)))
                    path.addLine(to: CGPoint(x: points[band].x, y: Self.y(for: -12, height: size.height)))
                }
                .stroke(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                Circle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 3, height: 3)
                    .position(x: points[band].x, y: Self.y(for: 0, height: size.height))
            }
            Path { path in path.addLines(points) }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            ForEach(points.indices, id: \.self) { band in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: dragging == band ? dot + 3 : dot, height: dragging == band ? dot + 3 : dot)
                    .position(points[band])
            }
            if let band = dragging {
                Text(Self.signed(curve.bands[band]))
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.regularMaterial))
                    .position(x: points[band].x,
                              y: points[band].y + (curve.bands[band] > 6 ? 14 : -14))
            }
        }
        .contentShape(Rectangle())
        .gesture(onChange == nil ? nil : drag(column: column, height: size.height))
        .overlay { if onChange != nil { adjustableBands } }
        .accessibilityHidden(onChange == nil)
    }

    private var marks: some View {
        GeometryReader { geometry in
            ForEach(Self.marks, id: \.self) { level in
                Text(level == 0 ? "0" : "\(level > 0 ? "+" : "")\(level)dB")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: Self.gutter - 6, alignment: .leading)
                    .position(x: 6 + (Self.gutter - 6) / 2, y: Self.y(for: level, height: geometry.size.height))
            }
        }
        .frame(width: Self.gutter)
        .accessibilityHidden(true)
    }

    private func rangeRow(width: CGFloat) -> some View {
        let column = width / CGFloat(NommoEQCurve.bandCount)
        return ZStack(alignment: .topLeading) {
            ForEach(ranges.indices, id: \.self) { index in
                let start = Self.rangeBounds[index] * column + 1
                let end = Self.rangeBounds[min(index + 1, Self.rangeBounds.count - 1)] * column - 1
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        Text(ranges[index])
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 2)
                    )
                    .frame(width: max(end - start, 0), height: 16)
                    .offset(x: start)
            }
        }
        .accessibilityHidden(true)
    }

    private func drag(column: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let band = dragging ?? min(max(Int(drag.startLocation.x / column), 0), NommoEQCurve.bandCount - 1)
                dragging = band
                let share = (drag.location.y - Self.inset) / max(height - 2 * Self.inset, 1)
                let level = min(max(Int((12 - share * 24).rounded()), NommoEQCurve.levels.lowerBound),
                                NommoEQCurve.levels.upperBound)
                if level != curve.bands[band] { onChange?(curve.setting(band: band, to: level)) }
            }
            .onEnded { _ in dragging = nil }
    }

    /// One adjustable element per band, for VoiceOver.
    private var adjustableBands: some View {
        HStack(spacing: 0) {
            ForEach(0..<NommoEQCurve.bandCount, id: \.self) { band in
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel("\(NommoEQCurve.frequencyLabels[band]) Hz")
                    .accessibilityValue(Self.signed(curve.bands[band]))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: onChange?(curve.setting(band: band, to: curve.bands[band] + 1))
                        case .decrement: onChange?(curve.setting(band: band, to: curve.bands[band] - 1))
                        @unknown default: break
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }

    static func signed(_ level: Int) -> String {
        level > 0 ? "+\(level)" : "\(level)"
    }

    private static func y(for level: Int, height: CGFloat) -> CGFloat {
        inset + CGFloat(12 - level) / 24 * (height - 2 * inset)
    }
}
