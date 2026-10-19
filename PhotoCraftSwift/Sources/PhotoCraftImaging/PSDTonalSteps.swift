import Foundation
import PhotoCraftCore

/// Threshold (thrs) and Posterize (post): one unsigned short and two pad bytes.
enum PSDTonalSteps {
  static func key(_ kind: TonalStepsAdjustment.Kind) -> String {
    kind == .threshold ? "thrs" : "post"
  }
  static func read(_ data: Data, kind: TonalStepsAdjustment.Kind) throws -> TonalStepsAdjustment {
    guard data.count == 4 else { throw CraftError.invalid("Invalid \(kind.rawValue) record size.") }
    var r = PSDReader(data: data)
    let result = try TonalStepsAdjustment(kind: kind, level: r.u16())
    try result.validate()
    return result
  }
  static func write(_ value: TonalStepsAdjustment, original: Data? = nil) throws -> Data {
    try value.validate()
    if let original, try read(original, kind: value.kind) == value { return original }
    var w = PSDWriter()
    w.n(value.level, 2)
    w.n(0, 2)
    return w.data
  }
}
