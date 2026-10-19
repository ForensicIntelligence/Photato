import Foundation
import PhotoCraftCore

/// The curv layer block has a one-byte map/points flag, a version and a
/// 32-bit channel bitmap. ACV has a separate, shorter header.
enum PSDCurves {
  static func read(_ data: Data) throws -> CurvesAdjustment {
    guard data.count <= 32768 else {
      throw CraftError.invalid("Curves data exceeds its size limit.")
    }
    var r = PSDReader(data: data)
    guard try r.u8() == 0 else {
      throw CraftError.unsupported("Freehand PSD curves are not supported yet.")
    }
    let version = try r.u16()
    guard version == 1 || version == 4 else {
      throw CraftError.unsupported("Unsupported PSD Curves version.")
    }
    let bitmap = try r.u32()
    let indices = (0..<32).filter { bitmap & (1 << $0) != 0 }
    return try records(&r, indices: indices, extensionAllowed: version == 1)
  }
  static func curve(_ r: inout PSDReader) throws -> CurveChannel {
    let count = try r.u16()
    guard (2...19).contains(count) else { throw CraftError.invalid("Invalid Curves point count.") }
    var points: [CurvePoint] = []
    for _ in 0..<count {
      let output = try r.u16()
      let input = try r.u16()
      points.append(.init(input, output))
    }
    let result = CurveChannel(points)
    try result.validate()
    return result
  }
  static func records(_ r: inout PSDReader, indices: [Int], extensionAllowed: Bool) throws
    -> CurvesAdjustment
  {
    var channels: [Int: CurveChannel] = [:]
    for index in indices { channels[index] = try curve(&r) }
    if r.remaining != 0 {
      guard extensionAllowed, try r.string(4) == "Crv ", try r.u16() == 4 else {
        throw CraftError.invalid("Invalid Curves extension.")
      }
      let count = try r.u32()
      guard count <= 256 else { throw CraftError.invalid("Excessive Curves extension count.") }
      var seen = Set<Int>()
      for _ in 0..<count {
        let index = try r.u16()
        guard index < 256, seen.insert(index).inserted else {
          throw CraftError.invalid("Duplicate or invalid Curves channel index.")
        }
        let value = try curve(&r)
        // Do not guess which contradictory legacy/extension record is authoritative.
        guard channels[index] == nil || channels[index] == value else {
          throw CraftError.unsupported("Conflicting legacy and extended Curves records.")
        }
        channels[index] = value
      }
    }
    guard r.remaining == 0 else { throw CraftError.invalid("Trailing Curves data.") }
    guard channels.allSatisfy({ $0.key < 4 || $0.value.isIdentity }) else {
      throw CraftError.unsupported("Curves on additional channels is not supported yet.")
    }
    return .init(
      rgb: channels[0] ?? .init(), red: channels[1] ?? .init(),
      green: channels[2] ?? .init(), blue: channels[3] ?? .init())
  }
  static func writeCurve(_ curve: CurveChannel, to w: inout PSDWriter) {
    w.n(curve.points.count, 2)
    for point in curve.points {
      w.n(point.output, 2)
      w.n(point.input, 2)
    }
  }
  static func write(_ curves: CurvesAdjustment, original: Data? = nil) throws -> Data {
    try curves.validate()
    if let original, try read(original) == curves { return original }
    var w = PSDWriter()
    w.n(0, 1)
    w.n(1, 2)
    w.n(15, 4)
    for channel in CurvesAdjustment.Channel.allCases { writeCurve(curves[channel], to: &w) }
    return w.data
  }
}

public enum CurvesPresetCodec {
  public static func read(_ data: Data) throws -> CurvesAdjustment {
    guard data.count <= 32768 else {
      throw CraftError.invalid("Curves preset exceeds its size limit.")
    }
    var r = PSDReader(data: data)
    let version = try r.u16()
    let value = try r.u16()
    let indices: [Int]
    switch version {
    case 1: indices = (0..<16).filter { value & (1 << $0) != 0 }
    case 4:
      guard (1...256).contains(value) else {
        throw CraftError.invalid("Invalid Curves preset channel count.")
      }
      indices = Array(0..<value)
    default: throw CraftError.unsupported("Unsupported Curves preset version.")
    }
    return try PSDCurves.records(&r, indices: indices, extensionAllowed: version == 1)
  }
  public static func write(_ curves: CurvesAdjustment, original: Data? = nil) throws -> Data {
    try curves.validate()
    if let original, try read(original) == curves { return original }
    var w = PSDWriter()
    w.n(4, 2)
    w.n(4, 2)
    for channel in CurvesAdjustment.Channel.allCases {
      PSDCurves.writeCurve(curves[channel], to: &w)
    }
    return w.data
  }
}

/// Numerical definitions observed in installed Photoshop 2026 presets.
/// No Adobe files, code or artwork are bundled.
public enum BuiltInCurvesPreset: String, CaseIterable, Sendable {
  case standard = "Default"
  case colorNegative = "Color Negative (RGB)"
  case crossProcess = "Cross Process (RGB)"
  case darker = "Darker (RGB)"
  case contrast = "Increase Contrast (RGB)"
  case lighter = "Lighter (RGB)"
  case linear = "Linear Contrast (RGB)"
  case medium = "Medium Contrast (RGB)"
  case negative = "Negative (RGB)"
  case strong = "Strong Contrast (RGB)"
  public var curves: CurvesAdjustment {
    switch self {
    case .standard: .init()
    case .colorNegative:
      .init(
        red: .init([.init(33, 255), .init(119, 127), .init(185, 0)]),
        green: .init([.init(28, 255), .init(77, 127), .init(132, 0)]),
        blue: .init([.init(25, 255), .init(60, 127), .init(108, 0)]))
    case .crossProcess:
      .init(
        red: .init([.init(0, 0), .init(64, 40), .init(128, 125), .init(175, 190), .init(255, 255)]),
        green: .init([.init(0, 0), .init(64, 48), .init(97, 128), .init(190, 208), .init(255, 208)]
        ),
        blue: .init([.init(0, 0), .init(59, 24), .init(181, 223), .init(255, 255)]))
    case .darker: .init(rgb: .init([.init(0, 0), .init(130, 101), .init(255, 255)]))
    case .contrast:
      .init(
        rgb: .init([.init(0, 0), .init(38, 17), .init(212, 231), .init(231, 250), .init(255, 255)]))
    case .lighter: .init(rgb: .init([.init(0, 0), .init(103, 125), .init(255, 255)]))
    case .linear: .init(rgb: .init([.init(0, 0), .init(78, 73), .init(177, 182), .init(255, 255)]))
    case .medium: .init(rgb: .init([.init(0, 0), .init(73, 56), .init(163, 164), .init(255, 255)]))
    case .negative: .init(rgb: .init([.init(0, 255), .init(255, 0)]))
    case .strong:
      .init(
        rgb: .init([.init(0, 0), .init(77, 50), .init(151, 153), .init(175, 188), .init(255, 255)]))
    }
  }
}
