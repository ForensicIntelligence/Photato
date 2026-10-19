import Foundation
import PhotoCraftCore

public enum LevelsPresetCodec {
  public static func read(_ data: Data) throws -> LevelsAdjustment {
    guard data.count <= 4096 else {
      throw CraftError.invalid("Levels preset exceeds its size limit.")
    }
    return try PSDLevels.read(data)
  }
  public static func write(_ levels: LevelsAdjustment, original: Data? = nil) throws -> Data {
    try PSDLevels.write(levels, original: original)
  }
}

/// Mathematical settings observed in Photoshop 2026's installed Levels presets.
/// These definitions are native Swift; no Adobe preset files or artwork are bundled.
public enum BuiltInLevelsPreset: String, CaseIterable, Sendable {
  case standard = "Default"
  case darker = "Darker"
  case lighter = "Lighter"
  case contrast1 = "Increase Contrast 1"
  case contrast2 = "Increase Contrast 2"
  case contrast3 = "Increase Contrast 3"
  case shadows = "Lighten Shadows"
  case brighter = "Midtones Brighter"
  case dimmer = "Midtones Darker"
  public var levels: LevelsAdjustment {
    let channel: LevelsChannel
    switch self {
    case .standard: channel = .init()
    case .darker: channel = .init(inputBlack: 15)
    case .lighter: channel = .init(inputWhite: 230)
    case .contrast1: channel = .init(inputBlack: 10, inputWhite: 245)
    case .contrast2: channel = .init(inputBlack: 20, inputWhite: 235)
    case .contrast3: channel = .init(inputBlack: 30, inputWhite: 225)
    case .shadows: channel = .init(gamma: 1.6)
    case .brighter: channel = .init(gamma: 1.25)
    case .dimmer: channel = .init(gamma: 0.75)
    }
    return .init(rgb: channel)
  }
}
