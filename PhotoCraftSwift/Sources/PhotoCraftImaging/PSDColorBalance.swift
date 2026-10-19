import Foundation
import PhotoCraftCore

/// blnc: nine signed big-endian shorts, one luminosity byte, optional padding.
/// Both 19-byte and padded 20-byte records occur in the source format readers.
enum PSDColorBalance {
  static func read(_ data: Data) throws -> ColorBalanceAdjustment {
    guard data.count == 19 || data.count == 20 else {
      throw CraftError.invalid("Color Balance data must contain 19 or 20 bytes.")
    }
    var r = PSDReader(data: data)
    func values(_ r: inout PSDReader) throws -> ColorBalanceValues {
      try .init(cyanRed: r.i16(), magentaGreen: r.i16(), yellowBlue: r.i16())
    }
    let shadows = try values(&r)
    let midtones = try values(&r)
    let highlights = try values(&r)
    let flag = try r.u8()
    guard flag <= 1 else { throw CraftError.invalid("Invalid Preserve Luminosity flag.") }
    let adjustment = ColorBalanceAdjustment(
      shadows: shadows, midtones: midtones,
      highlights: highlights, preserveLuminosity: flag != 0)
    try adjustment.validate()
    return adjustment
  }
  static func write(_ adjustment: ColorBalanceAdjustment, original: Data? = nil) throws -> Data {
    try adjustment.validate()
    if let original, try read(original) == adjustment { return original }
    var w = PSDWriter()
    for tone in ColorBalanceAdjustment.Tone.allCases {
      let values = adjustment[tone]
      for value in [values.cyanRed, values.magentaGreen, values.yellowBlue] { w.n(value, 2) }
    }
    w.n(adjustment.preserveLuminosity ? 1 : 0, 1)
    w.n(0, 1)
    return w.data
  }
}
