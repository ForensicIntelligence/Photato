import Foundation
import PhotoCraftCore

enum PcraftSamples {
  struct Placed {
    let surface: Surface
    let x: Int
    let y: Int
    let outside: Float
  }
  static func depth(_ sample: String) throws -> PixelDepth {
    switch sample {
    case "U8": .u8
    case "U16": .u16
    case "F32": .f32
    default: throw CraftError.unsupported("Unsupported PhotoCraft sample depth.")
    }
  }
  static func validateSchema(_ node: PcraftNode) throws {
    try node.keys("format default tiles")
    try node.field("format").keys("mode sample alpha")
    for tile in try node.field("tiles").array() { try tile.keys("tx ty hash") }
  }
  static func placed(_ source: PcraftProject.Surface, mask: Bool, budget: inout Int) throws -> Placed {
    guard source.mode == (mask ? "Grayscale" : "Rgb"), !mask || !source.alpha else {
      throw CraftError.unsupported("PhotoCraft import requires RGB layers and grayscale masks without alpha.")
    }
    let depth = try depth(source.sample)
    let defaultPixel = try source.defaultPixel.withUnsafeBytes {
      try pixel($0, at: 0, depth: depth, gray: mask, alpha: source.alpha)
    }
    if mask {
      guard (0...1).contains(defaultPixel.r) else { throw invalidSamples }
    } else if !defaultPixel.hasSameBits(as: .clear) {
      throw CraftError.unsupported("A PhotoCraft raster's unbounded nonzero default cannot be retained by this finite layer model.")
    }
    let xs = source.tiles.keys.map { Int($0.x) }, ys = source.tiles.keys.map { Int($0.y) }
    let x = (xs.min() ?? 0) * 256, y = (ys.min() ?? 0) * 256
    let width = source.tiles.isEmpty ? 1 : ((xs.max()! + 1) * 256 - x)
    let height = source.tiles.isEmpty ? 1 : ((ys.max()! + 1) * 256 - y)
    guard abs(Double(x)) <= 1_000_000, abs(Double(y)) <= 1_000_000 else {
      throw CraftError.unsupported("PhotoCraft tile origins exceed the native coordinate limits.")
    }
    // One original tile expands to sixteen native tiles of RGBA Float values.
    // Reserve before allocation, including separate masks and duplicate layers.
    let bytes = source.tiles.count * 256 * 256 * MemoryLayout<Pixel>.stride
    guard bytes <= budget else { throw CraftError.invalid("PhotoCraft import exceeds the raster budget.") }
    budget -= bytes
    var output = try Surface(width: width, height: height, depth: depth, fill: defaultPixel)
    if !mask && depth == .f32 { output = try output.interpretingSamples(as: .linearRGB) }
    for (coordinate, bytes) in source.tiles {
      try Task.checkCancellation()
      let left = Int(coordinate.x) * 256 - x, top = Int(coordinate.y) * 256 - y
      try bytes.withUnsafeBytes { buffer in
        for row in 0..<256 {
          try Task.checkCancellation()
          for column in 0..<256 {
            let value = try pixel(buffer, at: (row * 256 + column) * source.bytesPerPixel,
              depth: depth, gray: mask, alpha: source.alpha)
            if mask && !(0...1).contains(value.r) { throw invalidSamples }
            if !value.hasSameBits(as: defaultPixel) {
              if !mask && depth == .f32 { output.setLinearPixel(x: left + column, y: top + row, value) }
              else { output.setPixel(x: left + column, y: top + row, value) }
            }
          }
        }
      }
    }
    return Placed(surface: output, x: x, y: y, outside: defaultPixel.r)
  }
  static func selection(_ source: PcraftProject.Surface, width: Int, height: Int,
    budget: inout Int) throws -> SelectionMask {
    guard source.mode == "Grayscale", source.sample == "U8", !source.alpha,
      source.defaultPixel == Data([0]) else {
      throw CraftError.unsupported("PhotoCraft selections require GRAY8 coverage with a zero outside value.")
    }
    guard width * height <= budget else { throw CraftError.invalid("PhotoCraft selection exceeds the raster budget.") }
    budget -= width * height
    var values = [UInt8](repeating: 0, count: width * height)
    for (coordinate, bytes) in source.tiles {
      let left = Int(coordinate.x) * 256, top = Int(coordinate.y) * 256
      for row in 0..<256 {
        try Task.checkCancellation()
        for column in 0..<256 {
          let value = bytes[row * 256 + column], x = left + column, y = top + row
          if x >= 0 && y >= 0 && x < width && y < height { values[y * width + x] = value }
          else if value != 0 {
            throw CraftError.unsupported("Off-canvas PhotoCraft selection coverage cannot be retained.")
          }
        }
      }
    }
    return try SelectionMask(width: width, height: height, bytes: values)
  }
  private static var invalidSamples: CraftError { .invalid("Invalid or non-finite PhotoCraft samples.") }
  private static func pixel(_ data: UnsafeRawBufferPointer, at: Int, depth: PixelDepth,
    gray: Bool, alpha: Bool) throws -> Pixel {
    let stride = depth == .u8 ? 1 : depth == .u16 ? 2 : 4
    func sample(_ index: Int) -> Float {
      let offset = at + index * stride
      switch depth {
      case .u8: return Float(data[offset]) / 255
      case .u16: return Float(UInt16(littleEndian: data.loadUnaligned(fromByteOffset: offset, as: UInt16.self))) / 65535
      case .f32: return Float(bitPattern: UInt32(littleEndian: data.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
      }
    }
    let red = sample(0)
    let value = Pixel(red, gray ? red : sample(1), gray ? red : sample(2), alpha ? sample(gray ? 1 : 3) : 1)
    guard value.isFinite, (0...1).contains(value.a) else { throw invalidSamples }
    return value
  }
}
