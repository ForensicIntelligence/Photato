import Darwin
import Foundation

/// Precision promotion in the same RGB or Gray color space. A profile conversion
/// between different colorants still uses the ordinary ICC transform.
struct SDRToHDRTransfer {
  private static let workingMaximum = 32_768
  private static let curveIntervals = 4_096

  private enum Curve {
    case linear
    case values([Float])
  }
  private let curves: [Curve]
  private let sourceMaximum: UInt32

  init?(profile: Data, mode: DocumentColorMode, depth: PixelDepth) {
    guard (mode == .rgb || mode == .grayscale), depth != .f32,
      Data(profile.dropFirst(20).prefix(4)) == Data("XYZ ".utf8),
      let tags = try? ICCProfile.tags(profile, colorSpace: mode.profileSignature)
    else { return nil }
    // Do not discard profile transforms that take precedence over matrix/TRC.
    let transformPrefixes = ["A2B", "B2A", "D2B", "B2D", "pre", "gam"]
    guard !tags.keys.contains(where: { key in transformPrefixes.contains(where: { key.hasPrefix($0) }) }) else {
      return nil
    }
    let colorants = mode == .rgb ? ["rXYZ", "gXYZ", "bXYZ", "wtpt"] : ["wtpt"]
    for key in colorants {
      guard let field = tags[key], field.count >= 20 else { return nil }
      let start = field.lowerBound
      guard profile[start..<start + 4].elementsEqual("XYZ ".utf8) else { return nil }
    }
    let keys = mode == .rgb ? ["rTRC", "gTRC", "bTRC"] : ["kTRC"]
    var byRange: [Range<Int>: Curve] = [:]
    var curves: [Curve] = []
    for key in keys {
      guard let field = tags[key],
        let curve = byRange[field] ?? Self.curve(from: profile, field: field)
      else { return nil }
      byRange[field] = curve
      curves.append(curve)
    }
    self.curves = curves
    sourceMaximum = depth == .u8 ? 255 : 65_535
  }

  func sample(_ code: UInt32, component: Int) -> Float {
    let working = Int((code * UInt32(Self.workingMaximum) + sourceMaximum / 2) / sourceMaximum)
    switch curves[component] {
    case .linear:
      // The linear RGB/Gray path promotes 8-bit values directly.
      return sourceMaximum == 255 ? Float(code) / 255 : Float(working) / Float(Self.workingMaximum)
    case .values(let table): return table[working]
    }
  }

  private static func curve(from profile: Data, field: Range<Int>) -> Curve? {
    guard field.count >= 12 else { return nil }
    let start = field.lowerBound
    let type = String(decoding: profile[start..<start + 4], as: UTF8.self)
    func word(_ offset: Int, _ width: Int) -> UInt32 {
      profile[(start + offset)..<(start + offset + width)].reduce(0) { ($0 << 8) | UInt32($1) }
    }
    if type == "curv" {
      let count = Int(word(8, 4))
      guard count <= (field.count - 12) / 2 else { return nil }
      if count == 0 { return .linear }
      if count == 1 {
        let gamma = word(12, 2)
        if gamma == 256 { return .linear }
        return powerCurve(gamma)
      }
      func evaluate(_ value: Double) -> Double {
        let address = value * Double(count - 1)
        let low = min(Int(address), count - 2)
        let left = Double(word(12 + low * 2, 2)), right = Double(word(14 + low * 2, 2))
        return (left + (right - left) * (address - Double(low))) / 65_535
      }
      return .values(interpolated(evaluate))
    }
    guard type == "para", field.count >= 32, word(8, 2) == 3 else { return nil }
    func fixed(_ offset: Int) -> Double { Double(Int32(bitPattern: word(offset, 4))) / 65_536 }
    let gamma = fixed(12), a = fixed(16), b = fixed(20), lowSlope = fixed(24), breakpoint = fixed(28)
    guard gamma > 0, a >= 0, lowSlope >= 0, (0...1).contains(breakpoint),
      a * breakpoint + b >= 0
    else { return nil }
    let values = (0...workingMaximum).map { code in
      let input = Double(code) / Double(workingMaximum)
      guard input >= breakpoint else { return Float(lowSlope * input) }
      // The saved Intel references round the product before the add. On Apple
      // Silicon the two operations round once before evaluating the power.
      #if arch(x86_64)
      let base = Float(a) * Float(input) + Float(b)
      #else
      let base = Float(a * input + b)
      #endif
      return powf(base, Float(gamma))
    }
    guard values.allSatisfy(\.isFinite) else { return nil }
    return .values(values)
  }

  private static func powerCurve(_ raw: UInt32) -> Curve? {
    // At and below this exponent Photoshop used a different conversion path.
    guard raw > 128 else { return nil }
    let gamma = Double(raw) / 256
    if raw > 640 {
      return .values((0...workingMaximum).map { powf(Float($0) / Float(workingMaximum), Float(gamma)) })
    }
    var values = interpolated { pow($0, gamma) }
    for code in 0..<128 {
      values[code] = powf(Float(code) / Float(workingMaximum), Float(gamma))
    }
    return .values(values)
  }

  // Photoshop's observed sampled-curve path builds 4,097 Float32 endpoints.
  // Retain the separate Float32 subtraction and multiplication when interpolating.
  private static func interpolated(_ evaluate: (Double) -> Double) -> [Float] {
    let grid = (0...curveIntervals).map { Float(evaluate(Double($0) / Double(curveIntervals))) }
    return (0...workingMaximum).map { code in
      let index = code / 8, offset = code % 8
      let left = grid[index]
      guard offset != 0 else { return left }
      return left + (grid[index + 1] - left) * (Float(offset) / 8)
    }
  }
}
