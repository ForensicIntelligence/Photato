import Foundation
import PhotoCraftCore

enum PSDSolidColor {
  static func read(_ data: Data) throws -> Pixel {
    let d = try PSDDescriptor.read(data, padding: true)
    guard ["null", "solidColorLayer"].contains(d.classID.text), d.items.count == 1,
      case .object(let color) = d["Clr "], color.classID.text == "RGBC"
    else { throw CraftError.unsupported("Unrepresented PSD solid-color descriptor.") }
    let floating = color["redFloat"] != nil
    let keys = floating ? ["redFloat", "greenFloat", "blueFloat"] : ["Rd  ", "Grn ", "Bl  "]
    guard color.items.count == 3 else {
      throw CraftError.unsupported("Unrepresented PSD solid-color components.")
    }
    let values = try keys.map { key -> Float in
      guard let value = color[key]?.number, value.isFinite,
        (0...(floating ? 1.0 : 255.0)).contains(value)
      else {
        throw CraftError.invalid("Invalid PSD RGB fill color.")
      }
      return Float(value / (floating ? 1 : 255))
    }
    return Pixel(values[0], values[1], values[2])
  }

  static func write(_ pixel: Pixel, original: Data? = nil) throws -> Data {
    guard [pixel.r, pixel.g, pixel.b].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
      pixel.a == 1
    else {
      throw CraftError.unsupported(
        "PSD solid-color export requires opaque SDR RGB. Use layer opacity for transparency.")
    }
    // Preserve the exact descriptor, including double precision and ID encoding,
    // when its decoded color is unchanged. Profile-converted colors regenerate it.
    if let original, (try? read(original)) == pixel { return original }
    let color = PSDDescriptor(
      "RGBC",
      items: [
        .init("Rd  ", .number(Double(pixel.r) * 255)),
        .init("Grn ", .number(Double(pixel.g) * 255)),
        .init("Bl  ", .number(Double(pixel.b) * 255)),
      ])
    return try PSDDescriptor("null", items: [.init("Clr ", .object(color))]).encoded()
  }
}
