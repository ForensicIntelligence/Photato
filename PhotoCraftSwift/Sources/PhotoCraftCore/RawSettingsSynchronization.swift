import Foundation

package enum RawSettingsGroup: String, CaseIterable, Sendable {
  case sensor = "Sensor"
  case light = "Light"
  case color = "Color"
  case effects = "Effects"
  case curve = "Curve"
  case mixer = "Color Mixer"
  case grading = "Color Grading"
  case detail = "Detail"
}

extension RawDevelopment {
  /// With no baseline this copies the chosen groups. With a baseline it applies
  /// only changed controls, keeping each destination's other adjustments.
  package func synchronizing(_ source: Self, groups: Set<RawSettingsGroup>,
    changesFrom before: Self? = nil) -> Self {
    func includes<Value: Equatable>(_ value: Value, _ original: (Self) -> Value) -> Bool {
      before.map { original($0) != value } ?? true
    }
    var result = self
    if groups.contains(.sensor) {
      func transfer<Value: Equatable>(_ key: WritableKeyPath<Self, Value>) {
        let value = source[keyPath: key]
        if includes(value, { $0[keyPath: key] }) { result[keyPath: key] = value }
      }
      transfer(\.temperature); transfer(\.tint); transfer(\.exposure)
      transfer(\.boost); transfer(\.shadowBoost); transfer(\.extendedRange)
      transfer(\.lensCorrection); transfer(\.highlightRecovery)
    }

    let rgb = source.adjustments
    var adjusted = result.adjustments
    for control in CameraRawSettings.controls {
      guard let group = RawSettingsGroup(rawValue: control.group), groups.contains(group),
        includes(rgb[control.key], { $0.adjustments[control.key] }) else { continue }
      adjusted[control.key] = rgb[control.key]
    }
    func copy<Value: Equatable>(_ key: WritableKeyPath<CameraRawSettings, Value>) {
      let value = rgb[keyPath: key]
      if includes(value, { $0.adjustments[keyPath: key] }) { adjusted[keyPath: key] = value }
    }
    if groups.contains(.effects) {
      copy(\.vignetteStyle); copy(\.seed)
    }
    if groups.contains(.curve) {
      copy(\.curveSplits); copy(\.pointCurve); copy(\.pointCurveRed); copy(\.pointCurveGreen); copy(\.pointCurveBlue)
    }
    if groups.contains(.mixer) {
      for index in 0..<8 {
        copy(\.hslHue[index]); copy(\.hslSat[index]); copy(\.hslLum[index])
      }
    }
    if groups.contains(.grading) {
      let wheels: [WritableKeyPath<CameraRawSettings, CameraRawSettings.Wheel>] = [
        \.gradeShadows, \.gradeMidtones, \.gradeHighlights, \.gradeGlobal,
      ]
      for wheel in wheels {
        copy(wheel.appending(path: \.hue))
        copy(wheel.appending(path: \.sat))
        copy(wheel.appending(path: \.lum))
      }
    }
    result.adjustments = adjusted
    return result
  }
}
