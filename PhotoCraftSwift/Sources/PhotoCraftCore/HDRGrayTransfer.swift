import Foundation

/// The 32-bit RGB mode conversion to the default linear grayscale space.
/// The ICC matrix already expresses the source primaries in the PCS.
struct HDRGrayTransfer {
  private let red: Float
  private let green: Float
  private let blue: Float

  init?(_ profile: Data) {
    guard Data(profile.dropFirst(20).prefix(4)) == Data("XYZ ".utf8),
      let tags = try? ICCProfile.tags(profile), (try? ICCProfile.isLinear(profile)) == true
    else { return nil }
    let otherTransforms = ["A2B", "B2A", "D2B", "B2D", "pre", "gam"]
    guard !tags.keys.contains(where: { key in otherTransforms.contains(where: { key.hasPrefix($0) }) })
    else { return nil }
    func words(_ key: String) -> [Int32]? {
      guard let tag = tags[key], tag.count >= 20,
        profile[tag.lowerBound..<(tag.lowerBound + 4)].elementsEqual("XYZ ".utf8)
      else { return nil }
      return [8, 12, 16].map { offset in
        let start = tag.lowerBound + offset
        let bits = profile[start..<(start + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Int32(bitPattern: bits)
      }
    }
    if tags["bkpt"] != nil {
      guard words("bkpt")?.allSatisfy({ $0 == 0 }) == true else { return nil }
    }
    guard let r = words("rXYZ"), let g = words("gXYZ"), let b = words("bXYZ") else { return nil }
    let colors = r + g + b
    let y = [r[1], g[1], b[1]]
    let total = y.reduce(Int64(0)) { $0 + Int64($1) }
    guard y.allSatisfy({ $0 >= 0 }), total > 0 else { return nil }
    if let standard = Self.standardPrimaries.first(where: { $0.matches(colors) }) {
      (red, green, blue) = standard.luminance
    } else {
      // Custom profiles with a different white luminance may require PCS
      // normalization. Leave those to the existing profile transform.
      guard total == 65_536 else { return nil }
      (red, green, blue) = (Float(y[0]) / 65_536, Float(y[1]) / 65_536, Float(y[2]) / 65_536)
    }
  }

  func sample(_ r: Float, _ g: Float, _ b: Float) -> Float {
    let rg = r * red + g * green
    return rg + b * blue
  }

  private struct Primaries {
    var xyz: [Int32]
    var luminance: (Float, Float, Float)
    func matches(_ other: [Int32]) -> Bool {
      // The observed standard-space recognition admits the small rounding
      // differences between ICC encoders for a single set of RGB primaries.
      zip(xyz, other).allSatisfy { abs(Int64($0) - Int64($1)) <= 65 }
    }
  }

  // Recognize the numerical primaries independently of the ICC description.
  // The standard-space coefficients retain more precision than ICC XYZ words.
  private static let standardPrimaries: [Primaries] = [
    // sRGB
    .init(xyz: [28576, 14581, 912, 25239, 46983, 6362, 9375, 3972, 46787],
      luminance: (0.222484529, 0.716905117, 0.060610354)),
    // Adobe RGB (1998)
    .init(xyz: [39960, 20389, 1276, 13453, 41004, 3989, 9777, 4143, 48796],
      luminance: (0.311112523, 0.625675142, 0.063212335)),
    // Display P3
    .init(xyz: [33759, 15807, -70, 19136, 45368, 2745, 10295, 4361, 51386],
      luminance: (0.241189182, 0.692244053, 0.066566765)),
    // Rec. 2020
    .init(xyz: [44137, 18287, -127, 10857, 44259, 1965, 8195, 2989, 52222],
      luminance: (0.279042602, 0.675344467, 0.045612931)),
  ]
}

