import Foundation
import PhotoCraftCore

enum PSDColorMetadata {
  /// Photoshop 2026's neutral HDR conversion settings. Translated from the Rust
  /// port's crates/psd/src/hdr.rs (MIT OR Apache-2.0); required for 32-bit exports.
  static func defaultHDRToning() -> Data {
    var w = PSDWriter()
    func f(_ x: Float) { w.n(Int(x.bitPattern), 4) }
    w.text("hdrt")
    w.n(3, 4)
    f(0.23)
    w.n(2, 4)
    let name = Array("Linear\0".utf16)
    w.n(name.count, 4)
    for unit in name { w.n(Int(unit), 2) }
    w.n(2, 2)
    w.n(2, 2)
    for value in [0, 0, 255, 255] { w.n(value, 2) }
    w.n(1, 1)
    w.n(1, 1)
    w.n(0, 8)
    f(16)
    w.n(1, 4)
    w.n(0, 4)
    f(1)
    w.text("hdra")
    w.n(6, 4)
    w.n(0, 4)
    f(20)
    f(30)
    w.n(0, 4)
    w.n(0, 4)
    f(1)
    w.n(0, 6)
    return w.data
  }
  /// Read the leading kind entry in Photoshop's color-management descriptor.
  /// Unrecognized layouts fail explicitly until the general action-descriptor port is complete.
  static func usesICC(_ data: Data) throws -> Bool {
    var r = PSDReader(data: data)
    func text(_ r: inout PSDReader) throws -> String {
      let count = try r.u32()
      guard count <= 10_000 else { throw CraftError.invalid("PSD descriptor string is too long.") }
      var units: [UInt16] = []
      for _ in 0..<count { units.append(UInt16(try r.u16())) }
      return String(decoding: units.prefix(while: { $0 != 0 }), as: UTF16.self)
    }
    func key(_ r: inout PSDReader) throws -> String {
      let count = try r.u32()
      guard count <= 10_000 else { throw CraftError.invalid("PSD descriptor key is too long.") }
      return try r.string(count == 0 ? 4 : count)
    }
    guard try r.u32() == 16 else { return false }
    _ = try text(&r)
    guard try key(&r) == "documentColorManagementInfo", try r.u32() > 0,
      try key(&r) == "Knd ", try r.string(4) == "TEXT"
    else { return false }
    return try text(&r) == "icc"
  }
}
