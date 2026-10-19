import Foundation
import PhotoCraftCore

/// The binary grdm record retains controls rather than baking them to dense stops.
/// Unknown interpolation/color models fail explicitly instead of changing the image.
enum PSDGradientMap {
  static func read(_ data: Data) throws -> GradientMapAdjustment {
    guard data.count <= 262_144 else {
      throw CraftError.invalid("Gradient Map record is too large.")
    }
    var r = PSDReader(data: data)
    let version = try r.u16()
    guard version == 1 || version == 3 else {
      throw CraftError.unsupported("Unsupported Gradient Map version.")
    }
    let reverse = try r.u8()
    let dither = try r.u8()
    guard reverse <= 1, dither <= 1 else { throw CraftError.invalid("Invalid Gradient Map flags.") }
    let method: GradientMethod
    if version == 3 {
      let code = try r.string(4)
      switch code {
      case "Gcls": method = .classic
      case "Lnr ": method = .linear
      case "Perc": method = .perceptual
      case "GIMs": method = .stripes
      default: throw CraftError.unsupported("Gradient Map method \(code) is not yet represented.")
      }
    } else {
      method = .classic
    }
    let count = try r.u32()
    guard count <= 65_536, count * 2 <= r.remaining else {
      throw CraftError.invalid("Invalid Gradient Map name.")
    }
    var units: [UInt16] = []
    for _ in 0..<count { units.append(UInt16(try r.u16())) }
    if units.last == 0 { units.removeLast() }
    let name = String(decoding: units, as: UTF16.self)
    func location(_ value: Int) throws -> Float {
      guard value <= 4096 else { throw CraftError.invalid("Invalid Gradient Map stop location.") }
      return Float(value) / 4096
    }
    func midpoint(_ value: Int) throws -> Float {
      guard value <= 100 else { throw CraftError.invalid("Invalid Gradient Map midpoint.") }
      return Float(value) / 100
    }
    let n = try r.u16()
    guard (1...GradientDefinition.maxStops).contains(n) else {
      throw CraftError.unsupported("Noise or excessive Gradient Map stops are not represented.")
    }
    var colors: [GradientColorStop] = []
    for _ in 0..<n {
      let position = try location(r.u32())
      let mid = try midpoint(r.u32())
      let space = try r.u16()
      let c = try (0..<4).map { _ in try r.u16() }
      _ = try r.u16()  // reserved, retained in the original record
      let color: GradientColor
      switch space {
      case 0: color = .rgb(Pixel(Float(c[0]) / 65535, Float(c[1]) / 65535, Float(c[2]) / 65535))
      case 1:
        color = .hsb(
          hue: Float(c[0]) / 65535 * 360, saturation: Float(c[1]) / 65535,
          brightness: Float(c[2]) / 65535)
      case 8:
        guard c[0] <= 10000 else { throw CraftError.invalid("Invalid gray Gradient Map stop.") }
        color = .gray(ink: Float(c[0]) / 10000)
      default: throw CraftError.unsupported("Gradient Map color space \(space) is not represented.")
      }
      colors.append(.init(position, color, midpoint: mid))
    }
    let nt = try r.u16()
    guard nt <= GradientDefinition.maxStops else {
      throw CraftError.invalid("Too many Gradient Map opacity stops.")
    }
    var opacity: [GradientOpacityStop] = []
    for _ in 0..<nt {
      let position = try location(r.u32())
      let mid = try midpoint(r.u32())
      let alpha = try r.u16()
      guard alpha <= 255 else { throw CraftError.invalid("Invalid Gradient Map opacity.") }
      opacity.append(.init(position, Float(alpha) / 255, midpoint: mid))
    }
    guard try r.u16() == 2 else {
      throw CraftError.unsupported("Unsupported Gradient Map expansion.")
    }
    let smoothness = try location(r.u16())
    guard try r.u16() == 32, try r.u16() == 0 else {
      throw CraftError.unsupported("Noise Gradient Maps are not yet represented.")
    }
    // Noise controls have no effect on solid gradients; the original bytes are retained.
    _ = try r.bytes(32)
    guard r.remaining <= 3, try r.bytes(r.remaining).allSatisfy({ $0 == 0 }) else {
      throw CraftError.unsupported("Unrepresented Gradient Map extension.")
    }
    let value = GradientMapAdjustment(
      gradient: .init(
        name: name.isEmpty ? "Custom" : name, colors: colors, opacity: opacity,
        smoothness: smoothness, method: method), reverse: reverse == 1, dither: dither == 1)
    try value.validate()
    return value
  }
  static func write(_ value: GradientMapAdjustment, original: Data? = nil) throws -> Data {
    try value.validate()
    // Photoshop 2026 removes stops beyond 100 on import. Check before reusing
    // an original record as well, so preserved bytes cannot bypass this limit.
    guard value.gradient.colors.count <= 100 else {
      throw CraftError.unsupported(
        "Photoshop Gradient Maps support up to 100 color stops. Reduce the color stops or save a Photato document."
      )
    }
    guard value.gradient.opacity.count <= 100 else {
      throw CraftError.unsupported(
        "Photoshop Gradient Maps support up to 100 opacity stops. Reduce the opacity stops or save a Photato document."
      )
    }
    if let original, try read(original) == value { return original }
    var w = PSDWriter()
    w.n(3, 2)
    w.n(value.reverse ? 1 : 0, 1)
    w.n(value.dither ? 1 : 0, 1)
    w.text(
      value.gradient.method == .classic
        ? "Gcls"
        : value.gradient.method == .linear
          ? "Lnr " : value.gradient.method == .stripes ? "GIMs" : "Perc")
    let name = Array(value.gradient.name.utf16) + [0]
    w.n(name.count, 4)
    for c in name { w.n(Int(c), 2) }
    w.n(value.gradient.colors.count, 2)
    for stop in value.gradient.colors {
      w.n(Int((stop.position * 4096).rounded()), 4)
      w.n(Int((stop.midpoint * 100).rounded()), 4)
      let values: [Int]
      switch stop.color {
      case .rgb(let p):
        values = [
          0, Int((p.r * 65535).rounded()), Int((p.g * 65535).rounded()),
          Int((p.b * 65535).rounded()), 0,
        ]
      case .hsb(let h, let s, let b):
        let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(
          dividingBy: 360)
        values = [
          1, Int((hue / 360 * 65535).rounded()), Int((s * 65535).rounded()),
          Int((b * 65535).rounded()), 0,
        ]
      case .gray(let ink): values = [8, Int((ink * 10000).rounded()), 0, 0, 0]
      case .foreground, .background:
        throw CraftError.invalid("Capture Gradient Map colors before export.")
      }
      for v in values { w.n(v, 2) }
      w.n(0, 2)
    }
    w.n(value.gradient.opacity.count, 2)
    for stop in value.gradient.opacity {
      w.n(Int((stop.position * 4096).rounded()), 4)
      w.n(Int((stop.midpoint * 100).rounded()), 4)
      w.n(Int((stop.opacity * 255).rounded()), 2)
    }
    w.n(2, 2)
    w.n(Int((value.gradient.smoothness * 4096).rounded()), 2)
    w.n(32, 2)
    w.n(0, 2)
    w.n(0, 4)
    w.n(0, 2)
    w.n(1, 2)
    w.n(2048, 4)
    w.n(3, 2)
    for v in [0, 0, 0, 0, 32768, 32768, 32768, 32768] { w.n(v, 2) }
    w.n(0, 2)
    while w.data.count % 4 != 0 { w.n(0, 1) }
    return w.data
  }
}
