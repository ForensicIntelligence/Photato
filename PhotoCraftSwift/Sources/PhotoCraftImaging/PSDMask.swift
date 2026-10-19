import Foundation
import PhotoCraftCore

/// User/real raster-mask records. Photoshop writes both documented parameter ordering and
/// real-mask-first ordering; lengths and parameter flags disambiguate them.
struct PSDMaskRecord {
  struct Bounds {
    var x: Int, y: Int, width: Int, height: Int
    var empty: Bool { width == 0 || height == 0 }
    static func read(_ r: inout PSDReader) throws -> Self {
      let top = try r.i32()
      let left = try r.i32()
      let bottom = try r.i32()
      let right = try r.i32()
      guard bottom >= top, right >= left,
        [top, left, bottom, right].allSatisfy({ abs(Double($0)) <= 1_000_000 })
      else {
        throw CraftError.invalid("Invalid PSD mask bounds.")
      }
      if right > left && bottom > top { _ = try Surface(width: right - left, height: bottom - top) }
      return Self(x: left, y: top, width: right - left, height: bottom - top)
    }
  }
  var bounds: Bounds
  var background: UInt8
  var flags: UInt8
  var real: (bounds: Bounds, background: UInt8, flags: UInt8)?
  var density: UInt8 = 255
  var feather: Double = 0
  var vectorDensity: UInt8 = 255
  var vectorFeather: Double = 0
  static func read(_ data: Data) throws -> Self? {
    if data.isEmpty { return nil }
    var r = PSDReader(data: data)
    var result = try Self(bounds: Bounds.read(&r), background: r.u8(), flags: r.u8())
    guard result.background == 0 || result.background == 255 else {
      throw CraftError.invalid("Invalid PSD mask outside color.")
    }
    let parameters = result.flags & 16 != 0
    func fits(_ offset: Int) -> Bool {
      guard parameters, offset < data.count else { return false }
      let flags = data[offset]
      guard flags & 0xf0 == 0 else { return false }
      let size =
        1 + (flags & 1 != 0 ? 1 : 0) + (flags & 2 != 0 ? 8 : 0)
        + (flags & 4 != 0 ? 1 : 0) + (flags & 8 != 0 ? 8 : 0)
      return (offset + size...offset + size + 3).contains(data.count)
    }
    func readReal(_ r: inout PSDReader) throws -> (bounds: Bounds, background: UInt8, flags: UInt8)
    {
      let f = try r.u8()
      let bg = try r.u8()
      guard bg == 0 || bg == 255 else {
        throw CraftError.invalid("Invalid real mask outside color.")
      }
      return (try Bounds.read(&r), bg, f)
    }
    let realFirst = parameters && !fits(18) && fits(36)
    if realFirst { result.real = try readReal(&r) }
    if parameters {
      let flags = try r.u8()
      guard flags & 0xf0 == 0 else { throw CraftError.invalid("Invalid PSD mask parameter flags.") }
      if flags & 1 != 0 { result.density = try r.u8() }
      if flags & 2 != 0 { result.feather = Double(bitPattern: try r.number(8)) }
      if flags & 4 != 0 { result.vectorDensity = try r.u8() }
      if flags & 8 != 0 { result.vectorFeather = Double(bitPattern: try r.number(8)) }
    }
    if !realFirst && r.remaining >= 18 { result.real = try readReal(&r) }
    guard r.remaining <= 3, try r.bytes(r.remaining).allSatisfy({ $0 == 0 }),
      result.feather.isFinite, result.feather >= 0,
      result.vectorFeather.isFinite, result.vectorFeather >= 0
    else {
      throw CraftError.invalid("Invalid PSD mask parameters or padding.")
    }
    return result
  }
  func selected(_ channel: Int) throws -> (Bounds, MaskProperties) {
    var p = MaskProperties()
    let b: Bounds
    let bg: UInt8
    let f: UInt8
    if channel == -3 {
      guard let real else { throw CraftError.invalid("Real PSD mask channel has no rectangle.") }
      (b, bg, f) = (real.bounds, real.background, real.flags)
    } else {
      (b, bg, f) = (bounds, background, flags)
    }
    p.outside = Float(bg) / 255
    p.enabled = f & 2 == 0
    p.linked = f & 1 == 0
    p.inverted = f & 4 != 0
    p.density = Float(density) / 255
    p.feather = feather
    try p.validate()
    return (b, p)
  }
}
