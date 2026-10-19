import Foundation
import PhotoCraftCore

/// Version-2 hue2 / AHU stores both inactive and active parameter sets.
/// Retain them independently, including non-rendering Colorize settings.
enum PSDHueSaturation {
  static func read(_ data: Data) throws -> HueSaturationAdjustment {
    guard data.count == 100 || data.count == 136 else {
      throw CraftError.invalid(
        "Hue/Saturation data must contain 100 bytes, or 136 with range colors.")
    }
    var r = PSDReader(data: data)
    guard try r.u16() == 2 else {
      throw CraftError.unsupported("Unsupported Hue/Saturation version.")
    }
    let colorize = try r.u8()
    guard colorize <= 1 else { throw CraftError.invalid("Invalid Hue/Saturation Colorize flag.") }
    _ = try r.u8()  // Padding is explicitly ignored by the public format specification.
    func values(_ r: inout PSDReader) throws -> HueSaturationValues {
      try .init(hue: r.i16(), saturation: r.i16(), lightness: r.i16())
    }
    let colorization = try values(&r)
    let master = try values(&r)
    var ranges: [HueRange] = []
    for _ in 0..<6 {
      let bounds = try (0..<4).map { _ in try r.u16() }
      ranges.append(try .init(values: values(&r), bounds: HueRange.fromWrapped(bounds)))
    }
    let result = HueSaturationAdjustment(
      master: master, colorization: colorization,
      colorize: colorize != 0, ranges: ranges)
    try result.validate()
    if data.count == 136 {
      guard try r.bytes(36) == rangeColors(result) else {
        throw CraftError.unsupported("Unrepresented Hue/Saturation range-color data.")
      }
    }
    return result
  }
  static func write(
    _ adjustment: HueSaturationAdjustment, original: Data? = nil,
    includeRangeColors: Bool = false
  ) throws -> Data {
    try adjustment.validate()
    if let original, try read(original) == adjustment { return original }
    var w = PSDWriter()
    w.n(2, 2)
    w.n(adjustment.colorize ? 1 : 0, 1)
    w.n(0, 1)
    func values(_ v: HueSaturationValues, _ w: inout PSDWriter) {
      for value in [v.hue, v.saturation, v.lightness] { w.n(value, 2) }
    }
    values(adjustment.colorization, &w)
    values(adjustment.master, &w)
    for range in adjustment.ranges {
      for bound in range.bounds { w.n((bound % 360 + 360) % 360, 2) }
      values(range.values, &w)
    }
    if includeRangeColors || original?.count == 136 {
      w.data.append(rangeColors(adjustment))
    }
    return w.data
  }
  /// Six H/S/L triples from pinned Photoshop records. Only this reconstructible
  /// form is currently represented; do not silently ignore arbitrary extensions.
  static func rangeColors(_ adjustment: HueSaturationAdjustment) -> Data {
    var w = PSDWriter()
    for range in adjustment.ranges {
      w.n(range.representativeHue, 2)
      w.n(100, 2)
      w.n(50, 2)
    }
    return w.data
  }
}

public enum HueSaturationPresetCodec {
  public static func read(_ data: Data) throws -> HueSaturationAdjustment {
    try PSDHueSaturation.read(data)
  }
  public static func write(_ adjustment: HueSaturationAdjustment, original: Data? = nil) throws
    -> Data
  {
    try PSDHueSaturation.write(adjustment, original: original)
  }
}

/// Numeric definitions observed in installed Photoshop 2026 AHU presets.
/// Inactive colorization values are part of the settings; no Adobe files are bundled.
public enum BuiltInHueSaturationPreset: String, CaseIterable, Sendable {
  case standard = "Default"
  case cyanotype = "Cyanotype"
  case saturation = "Increase Saturation"
  case more = "Increase Saturation More"
  case oldStyle = "Old Style"
  case red = "Red Boost"
  case sepia = "Sepia"
  case strong = "Strong Saturation"
  case yellow = "Yellow Boost"
  public var adjustment: HueSaturationAdjustment {
    switch self {
    case .standard: .init()
    case .cyanotype: .init(colorization: .init(hue: -145, saturation: 25), colorize: true)
    case .sepia: .init(colorization: .init(hue: 35, saturation: 25), colorize: true)
    case .saturation:
      .init(master: .init(saturation: 10), colorization: .init(hue: 66, saturation: 25))
    case .more: .init(master: .init(saturation: 30), colorization: .init(hue: 66, saturation: 25))
    case .oldStyle:
      .init(
        master: .init(saturation: -40, lightness: 5), colorization: .init(hue: 66, saturation: 25))
    case .red:
      .init(master: .init(hue: -5, saturation: 20), colorization: .init(hue: 18, saturation: 25))
    case .strong: .init(master: .init(saturation: 50), colorization: .init(hue: 66, saturation: 25))
    case .yellow:
      .init(master: .init(hue: 5, saturation: 20), colorization: .init(hue: 18, saturation: 25))
    }
  }
}
