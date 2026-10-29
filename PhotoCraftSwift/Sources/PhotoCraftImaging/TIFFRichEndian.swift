import Foundation
import PhotoCraftCore

/// Endian transport for the supported binary adjustment and vector-mask records.
/// Shared PSD readers still validate versions, values and represented semantics.
enum TIFFRichEndian {
  static func convert(_ input: Data, tag: String, order: TIFFContainer.Order) throws -> Data {
    try Task.checkCancellation()
    guard input.count <= PSDDescriptor.maxBytes else { throw CraftError.invalid("TIFF layer record is too large.") }
    var c = TIFFLayerEndian.Cursor(input, order: order)
    func words(_ count: Int, _ size: Int, _ c: inout TIFFLayerEndian.Cursor) throws {
      guard count <= c.remaining / size else { throw CraftError.invalid("Truncated TIFF rich record.") }
      for _ in 0..<count { try c.n(size) }
    }
    switch tag {
    case "levl":
      guard try c.n(2) == 2 else { throw CraftError.unsupported("Unsupported TIFF Levels version.") }
      try words(29 * 5, 2, &c)
      if c.remaining > 0 {
        guard try c.word() == "Lvls", try c.n(2) == 3 else {
          throw CraftError.invalid("Invalid TIFF Levels extension.")
        }
        let count = try c.n(2)
        guard (29...256).contains(count) else { throw CraftError.invalid("Invalid TIFF Levels count.") }
        try words((count - 29) * 5, 2, &c)
      }
    case "curv":
      guard try c.n(1) == 0 else { throw CraftError.unsupported("Freehand TIFF Curves are not yet supported.") }
      let version = try c.n(2)
      guard [1, 4].contains(version) else { throw CraftError.unsupported("Unsupported TIFF Curves version.") }
      let bits = try c.n(4)
      func curve(_ c: inout TIFFLayerEndian.Cursor) throws {
        let count = try c.n(2)
        guard (2...19).contains(count) else { throw CraftError.invalid("Invalid TIFF Curves point count.") }
        try words(count * 2, 2, &c)
      }
      for i in 0..<32 where bits & (1 << i) != 0 { try curve(&c) }
      if c.remaining > 0 {
        guard version == 1, try c.word() == "Crv ", try c.n(2) == 4 else {
          throw CraftError.invalid("Invalid TIFF Curves extension.")
        }
        let count = try c.n(4)
        guard count <= 256 else { throw CraftError.invalid("Too many TIFF Curves records.") }
        for _ in 0..<count { try c.n(2); try curve(&c) }
      }
    case "hue2":
      guard [100, 136].contains(input.count) else { throw CraftError.invalid("Invalid TIFF Hue/Saturation size.") }
      try c.n(2); try c.skip(2); try words(c.remaining / 2, 2, &c)
    case "blnc":
      guard [19, 20].contains(input.count) else { throw CraftError.invalid("Invalid TIFF Color Balance size.") }
      try words(9, 2, &c); try c.skip(c.remaining)
    case "thrs", "post":
      guard input.count == 4 else { throw CraftError.invalid("Invalid TIFF tonal-step size.") }
      try c.n(2); try c.skip(2)
    case "grdm":
      let version = try c.n(2); try c.skip(2)
      guard [1, 3].contains(version) else { throw CraftError.unsupported("Unsupported TIFF Gradient Map version.") }
      if version == 3 { _ = try c.word() }
      let count = try c.n(4)
      guard count <= 65_536 else { throw CraftError.invalid("TIFF gradient name is too long.") }
      try words(count, 2, &c)
      let colors = try c.n(2)
      guard colors <= GradientDefinition.maxStops else { throw CraftError.invalid("Too many TIFF gradient stops.") }
      for _ in 0..<colors { try words(2, 4, &c); try words(6, 2, &c) }
      let opacity = try c.n(2)
      guard opacity <= GradientDefinition.maxStops else { throw CraftError.invalid("Too many TIFF opacity stops.") }
      for _ in 0..<opacity { try words(2, 4, &c); try c.n(2) }
      try words(4, 2, &c)
      // Inactive noise controls are structured too, and retain every bit.
      try c.n(4); try words(2, 2, &c); try c.n(4); try words(10, 2, &c)
      guard c.remaining <= 3 else { throw CraftError.unsupported("Unknown TIFF Gradient Map extension.") }
      try c.padding()
    case "vmsk", "vsms":
      guard try c.n(4) == 3 else { throw CraftError.unsupported("Unsupported TIFF vector mask version.") }
      try c.n(4)
      guard c.remaining / 26 <= VectorPath.maxKnots + 258, c.remaining % 26 <= 3 else {
        throw CraftError.invalid("Invalid TIFF vector record count.")
      }
      while c.remaining >= 26 {
        try Task.checkCancellation()
        switch try c.n(2) {
        case 0, 3: try words(3, 2, &c); try c.skip(18)
        case 1, 2, 4, 5: try words(6, 4, &c)
        case 6: try c.skip(24)
        case 7: try words(5, 4, &c); try c.skip(4)
        case 8: try c.n(2); try c.skip(22)
        default: throw CraftError.unsupported("Unknown TIFF vector path selector.")
        }
      }
      try c.padding()
    default: throw CraftError.unsupported("Unsupported TIFF rich record.")
    }
    guard c.remaining == 0 else { throw CraftError.invalid("Unexpected TIFF rich record tail.") }
    return c.output
  }
}
