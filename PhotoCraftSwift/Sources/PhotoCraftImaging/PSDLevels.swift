import Foundation
import PhotoCraftCore

/// Adobe's `levl` / ALV version-2 records and optional CS version-3 extension.
/// Only the RGB composite/red/green/blue records have represented semantics here.
enum PSDLevels {
  static func read(_ data: Data) throws -> LevelsAdjustment {
    var r = PSDReader(data: data)
    guard try r.u16() == 2 else { throw CraftError.unsupported("Unsupported PSD Levels version.") }
    func record(_ r: inout PSDReader) throws -> LevelsChannel {
      let black = try r.u16()
      let white = try r.u16()
      let outBlack = try r.u16()
      let outWhite = try r.u16()
      let gamma = try r.u16()
      let result = LevelsChannel(
        inputBlack: black, inputWhite: white,
        gamma: Float(gamma) / 100, outputBlack: outBlack, outputWhite: outWhite)
      try result.validate()
      return result
    }
    var records: [LevelsChannel] = []
    for _ in 0..<29 { records.append(try record(&r)) }
    if r.remaining != 0 {
      guard try r.string(4) == "Lvls", try r.u16() == 3 else {
        throw CraftError.invalid("Invalid PSD Levels extension.")
      }
      let count = try r.u16()
      // Photoshop 2026's shipped ALV presets use 62 records. The PSD header's
      // 56-channel limit is not a bound on this legacy/extension record array.
      guard (29...256).contains(count), r.remaining == (count - 29) * 10 else {
        throw CraftError.invalid("Invalid PSD Levels record count.")
      }
      for _ in 29..<count { records.append(try record(&r)) }
    }
    guard records.dropFirst(4).allSatisfy({ $0 == LevelsChannel() }) else {
      throw CraftError.unsupported("PSD Levels on additional channels is not supported yet.")
    }
    return LevelsAdjustment(rgb: records[0], red: records[1], green: records[2], blue: records[3])
  }

  static func write(_ levels: LevelsAdjustment, original: Data? = nil) throws -> Data {
    try levels.validate()
    if let original, try read(original) == levels { return original }
    var w = PSDWriter()
    w.n(2, 2)
    let records =
      [levels.rgb, levels.red, levels.green, levels.blue]
      + Array(repeating: LevelsChannel(), count: 25)
    for r in records {
      let gamma = Int((r.gamma * 100).rounded())
      guard Float(gamma) / 100 == r.gamma else {
        throw CraftError.unsupported("PSD Levels gamma requires two decimal places.")
      }
      for v in [r.inputBlack, r.inputWhite, r.outputBlack, r.outputWhite, gamma] { w.n(v, 2) }
    }
    return w.data
  }
}
