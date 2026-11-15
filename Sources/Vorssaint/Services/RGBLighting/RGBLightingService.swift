// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation

/// The lighting chosen for every RGB device, kept on this Mac. Each device's
/// service draws it on its own queue from the same clock, so the speakers and
/// the monitor stay in step; this holds the choice and tells them when it
/// changes.
final class RGBLightingService: ObservableObject {
    static let shared = RGBLightingService()

    @Published private(set) var settings: RGBLightingChoice
    /// Colors added with "+", after the built-in swatches.
    @Published private(set) var customColors: [RGBColor]

    private init() {
        let defaults = UserDefaults.standard
        let level = defaults.integer(forKey: DefaultsKey.rgbLightingLevel)
        settings = RGBLightingChoice(
            mode: defaults.string(forKey: DefaultsKey.rgbLightingMode).flatMap(RGBLightingMode.init(rawValue:)) ?? .off,
            direction: defaults.string(forKey: DefaultsKey.rgbLightingDirection)
                .flatMap(RGBWaveDirection.init(rawValue:)) ?? .down,
            color: defaults.string(forKey: DefaultsKey.rgbLightingColor).flatMap(RGBColor.init(hex:))
                ?? RGBLighting.defaultColor,
            level: RGBLighting.levelRange.contains(level) ? level : RGBLighting.levelRange.upperBound,
            speed: RGBLighting.clampedSpeed(defaults.double(forKey: DefaultsKey.rgbLightingSpeed)))
        customColors = RGBLighting.decodeCustomColors(defaults.string(forKey: DefaultsKey.rgbLightingCustomColors))
        RGBLightingClock.shared.setSpeed(settings.speed, at: ProcessInfo.processInfo.systemUptime)
    }

    /// Whether the devices show this lighting; when off, they keep their own.
    var isActive: Bool { AppFeature.rgbLighting.isAvailable }

    func syncWithPreferences() {
        NommoService.shared.syncWithPreferences()
        MSIMonitorService.shared.syncWithPreferences()
    }

    func setMode(_ mode: RGBLightingMode) {
        settings.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.rgbLightingMode)
        lightingChanged()
    }

    func setDirection(_ direction: RGBWaveDirection) {
        settings.direction = direction
        UserDefaults.standard.set(direction.rawValue, forKey: DefaultsKey.rgbLightingDirection)
        lightingChanged()
    }

    /// Picking a color means showing it, so from a mode without one it also
    /// switches to a solid color.
    func setColor(_ color: RGBColor) {
        settings.color = color
        UserDefaults.standard.set(color.hex, forKey: DefaultsKey.rgbLightingColor)
        if !settings.mode.usesColor {
            settings.mode = .solid
            UserDefaults.standard.set(RGBLightingMode.solid.rawValue, forKey: DefaultsKey.rgbLightingMode)
        }
        lightingChanged()
    }

    /// Takes effect on the next frame, so a slider drag is followed live.
    func setLevel(_ percent: Int) {
        let percent = min(max(percent, RGBLighting.levelRange.lowerBound), RGBLighting.levelRange.upperBound)
        settings.level = percent
        UserDefaults.standard.set(percent, forKey: DefaultsKey.rgbLightingLevel)
        NommoService.shared.lightingLevelChanged()
        MSIMonitorService.shared.lightingLevelChanged()
    }

    /// The moving modes pick it up on their next frame, carrying on from where
    /// they are.
    func setSpeed(_ speed: Double) {
        let speed = RGBLighting.clampedSpeed(speed)
        settings.speed = speed
        UserDefaults.standard.set(speed, forKey: DefaultsKey.rgbLightingSpeed)
        RGBLightingClock.shared.setSpeed(speed, at: ProcessInfo.processInfo.systemUptime)
    }

    /// Adds a color after the others and returns its place, or nil when full.
    func addCustomColor(_ color: RGBColor) -> Int? {
        guard customColors.count < RGBLighting.maxCustomColors else { return nil }
        customColors.append(color)
        saveCustomColors()
        return customColors.count - 1
    }

    func updateCustomColor(at index: Int, to color: RGBColor) {
        guard customColors.indices.contains(index) else { return }
        customColors[index] = color
        saveCustomColors()
    }

    func removeCustomColor(at index: Int) {
        guard customColors.indices.contains(index) else { return }
        customColors.remove(at: index)
        saveCustomColors()
    }

    private func saveCustomColors() {
        UserDefaults.standard.set(RGBLighting.encodeCustomColors(customColors),
                                  forKey: DefaultsKey.rgbLightingCustomColors)
    }

    private func lightingChanged() {
        NommoService.shared.lightingChanged()
        MSIMonitorService.shared.lightingChanged()
    }
}
