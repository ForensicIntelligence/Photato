import Foundation
import CoreGraphics
import PhotoCraftCore
import UniformTypeIdentifiers
import zlib

/// Native sample layout, prediction and strip compression over ImageIO's
/// uncompressed export. Metadata directories are serialized in the chosen order.
enum TIFFStorage {
  struct Geometry {
    let width: Int, height: Int, bits: Int, channels: Int, rows: Int
    let planar: Bool, associated: Bool, compression: Int, predictor: Int
    let offsets: [Int], counts: [Int]
    init?(_ file: TIFFContainer, allowAssociatedAlpha: Bool = false,
      colorComponents: Int = 3, photometric: Int = 2) throws {
      // Tile decoding remains with ImageIO; the strip path must not reject it.
      guard file.root.fields[324] == nil, file.root.fields[325] == nil else { return nil }
      guard try file.scalar(262) == photometric else { return nil }
      width = try file.scalar(256); height = try file.scalar(257)
      channels = try file.scalar(277)
      let depths = try file.numbers(258), formats = try file.numbers(339, default: [1])
      guard [colorComponents, colorComponents + 1].contains(channels), [1, channels].contains(depths.count),
        Set(depths).count == 1, [8, 16, 32].contains(depths[0]),
        [1, channels].contains(formats.count), Set(formats).count == 1,
        formats[0] == (depths[0] == 32 ? 3 : 1) else { return nil }
      bits = depths[0]
      if channels == colorComponents + 1 {
        let alpha = try file.numbers(338, default: [0])
        guard alpha == [2] || (allowAssociatedAlpha && alpha == [1]) else { return nil }
        associated = alpha == [1]
      } else { associated = false }
      let layout = try file.scalar(284, default: 1)
      guard [1, 2].contains(layout) else { return nil }
      planar = layout == 2
      rows = try file.scalar(278, default: height)
      compression = try file.scalar(259, default: 1)
      predictor = try file.scalar(317, default: 1)
      guard [1, 5, 8, 32946].contains(compression), [1, 2, 3].contains(predictor),
        predictor != 3 || bits == 32, predictor != 2 || bits != 32 else { return nil }
      guard width > 0, height > 0, width <= Surface.maxDimension,
        height <= Surface.maxDimension, width <= Surface.maxPixels / height, rows > 0 else {
        throw CraftError.invalid("Invalid TIFF sample geometry.")
      }
      offsets = try file.numbers(273); counts = try file.numbers(279)
      let stripCount = ((height - 1) / rows + 1) * (planar ? channels : 1)
      guard offsets.count == stripCount, counts.count == stripCount else {
        throw CraftError.invalid("Invalid TIFF strip table.")
      }
      for (offset, count) in zip(offsets, counts) {
        guard offset >= 8, offset <= file.data.count, count <= file.data.count - offset else {
          throw CraftError.invalid("Invalid TIFF strip extent.")
        }
      }
    }
  }
  static func surface(_ data: Data, depth: PixelDepth,
    encoding: SurfaceColorEncoding, space: CGColorSpace? = nil) throws -> Surface? {
    guard TIFFContainer.isClassic(data) else { return nil }
    let file = try TIFFContainer(data, metadata: false)
    guard let g = try Geometry(file, allowAssociatedAlpha: true),
      g.bits == (depth == .u8 ? 8 : depth == .u16 ? 16 : 32) else { return nil }
    // Retain the established ImageIO associated-alpha path for interleaved files.
    // Its planar path replaces integer alpha with full opacity (and Float32 with
    // NaN), so assemble those samples before the same CoreGraphics conversion.
    if g.associated && !g.planar { return nil }
    var output = try Surface(width: g.width, height: g.height, depth: depth,
      fill: Pixel(0, 0, 0, g.channels == 3 ? 1 : 0), colorEncoding: encoding)
    let planes = g.planar ? g.channels : 1, components = g.planar ? 1 : g.channels
    let stripsPerPlane = (g.height - 1) / g.rows + 1, bps = g.bits / 8
    for plane in 0..<planes {
      for strip in 0..<stripsPerPlane {
        try Task.checkCancellation()
        let y0 = strip * g.rows, rows = min(g.rows, g.height - y0)
        let index = plane * stripsPerPlane + strip
        let packed = Data(file.data[g.offsets[index]..<g.offsets[index] + g.counts[index]])
        let rowBytes = g.width * components * bps, expected = rows * rowBytes
        guard expected <= TIFFContainer.byteLimit else {
          throw CraftError.invalid("TIFF strip exceeds the sample budget.")
        }
        var samples: [UInt8]
        switch g.compression {
        case 1:
          guard packed.count == expected else { throw CraftError.invalid("Truncated TIFF strip.") }
          samples = [UInt8](packed)
        case 5: samples = try TIFFLZW.decode(packed, expected: expected)
        default: samples = try PSDChannelCodec.inflate(packed, expected: expected)
        }
        if g.predictor != 1 {
          for row in 0..<rows {
            try Task.checkCancellation()
            let start = row * rowBytes
            let decoded = restore(Array(samples[start..<start + rowBytes]), bits: g.bits,
              components: components, order: file.order, predictor: g.predictor)
            samples.replaceSubrange(start..<start + rowBytes, with: decoded)
          }
        }
        func sample(_ at: Int) throws -> Float {
          var bits: UInt32 = 0
          for byte in 0..<bps {
            bits = (bits << 8) | UInt32(samples[at + (file.order == .big ? byte : bps - 1 - byte)])
          }
          let value = g.bits == 32 ? Float(bitPattern: bits) : Float(bits) / (g.bits == 8 ? 255 : 65535)
          guard value.isFinite else { throw CraftError.invalid("Non-finite TIFF sample.") }
          return value
        }
        for y in 0..<rows {
          try Task.checkCancellation()
          for x in 0..<g.width {
            let at = y * rowBytes + x * components * bps
            var p = encoding == .linearRGB
              ? output.linearPixel(x: x, y: y0 + y) : output.pixel(x: x, y: y0 + y)
            if g.planar {
              let value = try sample(at)
              switch plane { case 0: p.r = value; case 1: p.g = value; case 2: p.b = value; default: p.a = value }
            } else {
              p = try Pixel(sample(at), sample(at + bps), sample(at + 2 * bps),
                g.channels == 4 ? sample(at + 3 * bps) : 1)
            }
            if encoding == .linearRGB { output.setLinearPixel(x: x, y: y0 + y, p) }
            else { output.setPixel(x: x, y: y0 + y, p) }
          }
        }
      }
    }
    if g.associated {
      let bytes = try output.rgbaData(depth: depth, colorEncoding: encoding)
      var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
      if depth == .u16 { info.insert(.byteOrder16Little) }
      if depth == .f32 { info.formUnion([.floatComponents, .byteOrder32Little]) }
      let colorSpace = try space ?? RasterIO.colorSpace()
      guard let provider = CGDataProvider(data: bytes as CFData),
        let image = CGImage(width: g.width, height: g.height, bitsPerComponent: g.bits,
          bitsPerPixel: g.bits * 4, bytesPerRow: g.width * bps * 4, space: colorSpace,
          bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false,
          intent: .defaultIntent) else { throw CraftError.invalid("Invalid TIFF associated-alpha image.") }
      return try RasterIO.surface(image, depth: depth, space: colorSpace, colorEncoding: encoding)
    }
    return output
  }
  static func rewrite(_ data: Data, options: RasterEncodingOptions,
    colorComponents: Int = 3, photometric: Int = 2) throws -> Data {
    try options.validate(for: .tiff)
    let file = try TIFFContainer(data, metadata: true)
    guard let g = try Geometry(file, allowAssociatedAlpha: true,
      colorComponents: colorComponents, photometric: photometric),
      !g.planar, g.compression == 1, g.predictor == 1 else {
      throw CraftError.invalid("Expected uncompressed interleaved TIFF intermediate.")
    }
    let predictor = options.tiffPredictor == true
    guard !predictor || g.bits == 32 else {
      throw CraftError.invalid("TIFF floating-point predictor requires a 32-bit document.")
    }
    let order: TIFFContainer.Order
    switch options.tiffByteOrder {
    case .bigEndian: order = .big
    case .littleEndian: order = .little
    case nil: order = file.order
    }
    let planar = options.tiffPixelOrder == .perChannel
    let compression = options.tiffCompression ?? .none
    let components = planar ? 1 : g.channels, bps = g.bits / 8
    let rowBytes = g.width * components * bps
    let rowsPerStrip = compression == .none ? g.height : max(1, min(g.height, 65536 / rowBytes))
    var output = Data(order == .little ? [73, 73, 42, 0, 0, 0, 0, 0] : [77, 77, 0, 42, 0, 0, 0, 0])
    var offsets: [Int] = [], counts: [Int] = []
    func append(_ data: Data) throws {
      guard data.count <= TIFFContainer.byteLimit - output.count else {
        throw CraftError.invalid("TIFF output exceeds the memory budget.")
      }
      output.append(data)
    }
    for plane in 0..<(planar ? g.channels : 1) {
      for startRow in stride(from: 0, to: g.height, by: rowsPerStrip) {
        try Task.checkCancellation()
        let endRow = min(g.height, startRow + rowsPerStrip)
        if output.count % 2 != 0 { output.append(0) }
        let start = output.count
        var strip: [UInt8] = []
        for y in startRow..<endRow {
          try Task.checkCancellation()
          let inputRowBytes = g.width * g.channels * bps, sourceStrip = y / g.rows
          let sourceRow = g.offsets[sourceStrip] + (y % g.rows) * inputRowBytes
          guard (y % g.rows + 1) * inputRowBytes <= g.counts[sourceStrip] else {
            throw CraftError.invalid("Incomplete uncompressed TIFF row.")
          }
          var row: [UInt8] = []; row.reserveCapacity(rowBytes)
          for x in 0..<g.width {
            for channel in 0..<components {
              let at = sourceRow + (x * g.channels + (planar ? plane : channel)) * bps
              for byte in 0..<bps {
                row.append(file.data[at + (order == file.order ? byte : bps - 1 - byte)])
              }
            }
          }
          if predictor { row = predict(row, components: components, order: order) }
          if compression == .none { try append(Data(row)) }
          else { strip.append(contentsOf: row) }
        }
        switch compression {
        case .none: break
        case .lzw: try append(TIFFLZW.encode(strip))
        case .zip:
          var size = compressBound(uLong(strip.count)), packed = [UInt8](repeating: 0, count: Int(compressBound(uLong(strip.count))))
          let status = packed.withUnsafeMutableBufferPointer { destination in
            strip.withUnsafeBufferPointer { source in
              compress2(destination.baseAddress!, &size, source.baseAddress!, uLong(strip.count), Z_DEFAULT_COMPRESSION)
            }
          }
          guard status == Z_OK else { throw CraftError.invalid("TIFF ZIP compression failed.") }
          try append(Data(packed.prefix(Int(size))))
        }
        offsets.append(start); counts.append(output.count - start)
      }
    }
    file.set(259, [compression.tag])
    file.set(273, offsets, type: 4); file.set(279, counts, type: 4)
    file.set(278, [rowsPerStrip], type: 4)
    file.set(284, [planar ? 2 : 1]); file.set(317, [predictor ? 3 : 1])
    try file.appendDirectories(to: &output, order: order)
    try Task.checkCancellation()
    return output
  }
  /// TIFF floating prediction puts each row's most-significant bytes first,
  /// then differences by samples-per-pixel across the entire shuffled row.
  static func predict(_ row: [UInt8], components: Int, order: TIFFContainer.Order) -> [UInt8] {
    let samples = row.count / 4
    var output = [UInt8](repeating: 0, count: row.count)
    for byte in 0..<4 {
      for sample in 0..<samples {
        output[byte * samples + sample] = row[sample * 4 + (order == .big ? byte : 3 - byte)]
      }
    }
    if output.count > components {
      for i in stride(from: output.count - 1, through: components, by: -1) {
        output[i] = output[i] &- output[i - components]
      }
    }
    return output
  }
  static func restore(_ row: [UInt8], bits: Int, components: Int,
    order: TIFFContainer.Order, predictor: Int) -> [UInt8] {
    var bytes = row
    if predictor == 3 {
      for i in components..<bytes.count { bytes[i] = bytes[i] &+ bytes[i - components] }
      let samples = bytes.count / 4
      var output = [UInt8](repeating: 0, count: bytes.count)
      for sample in 0..<samples {
        for byte in 0..<4 {
          output[sample * 4 + (order == .big ? byte : 3 - byte)] = bytes[byte * samples + sample]
        }
      }
      return output
    }
    let bps = bits / 8, stride = components * bps
    if bps == 1 {
      for i in stride..<bytes.count { bytes[i] = bytes[i] &+ bytes[i - stride] }
    } else {
      for i in Swift.stride(from: stride, to: bytes.count, by: 2) {
        let hi = order == .big ? 0 : 1, lo = 1 - hi
        let a = UInt16(bytes[i + hi]) << 8 | UInt16(bytes[i + lo])
        let b = UInt16(bytes[i - stride + hi]) << 8 | UInt16(bytes[i - stride + lo])
        let value = a &+ b
        bytes[i + hi] = UInt8(value >> 8); bytes[i + lo] = UInt8(truncatingIfNeeded: value)
      }
    }
    return bytes
  }
}
