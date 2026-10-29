import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import zlib

/// PNG Third Edition: palette entries and packed samples stay authoritative.
/// All five scanline filters and all Adam7 passes are decoded without RGB remapping.
enum PNGRestrictedStorage {
  static let signature = Data([137,80,78,71,13,10,26,10])
  struct Chunk { let type: String; let data: Data }
  static func integer(_ data: Data, _ at: Int) -> Int { data[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
  static func number(_ value: Int) -> Data { Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
  static func checksum(_ data: Data) -> UInt32 {
    data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
  }
  static func chunk(_ type: String, _ payload: Data) -> Data {
    let body = Data(type.utf8) + payload
    return number(payload.count) + body + number(Int(checksum(body)))
  }
  static func chunks(_ input: Data) throws -> [Chunk] {
    let data = Data(input)
    guard data.starts(with: signature), data.count <= PSDCodec.maximumInputBytes else { throw CraftError.invalid("Invalid PNG header or input size.") }
    var offset = 8, result = [Chunk](), seenData = false, endedData = false
    while offset < data.count {
      try Task.checkCancellation()
      guard data.count - offset >= 12 else { throw CraftError.invalid("Truncated PNG chunk.") }
      let count = integer(data, offset)
      guard count <= data.count - offset - 12 else { throw CraftError.invalid("Invalid PNG chunk length.") }
      let end = offset + count + 12, code = data[offset + 4..<offset + 8]
      guard code.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
        code[code.startIndex + 2] & 32 == 0,
        checksum(Data(data[offset + 4..<end - 4])) == UInt32(integer(data, end - 4)) else {
        throw CraftError.invalid("Invalid PNG chunk type or checksum.")
      }
      let type = String(decoding: code, as: UTF8.self)
      if type == "IDAT" { guard !endedData else { throw CraftError.invalid("Noncontiguous PNG image data.") }; seenData = true }
      else if seenData { endedData = true }
      if code.first! & 32 == 0, !["IHDR", "PLTE", "IDAT", "IEND"].contains(type) {
        throw CraftError.unsupported("Unknown required PNG chunk.")
      }
      result.append(.init(type: type, data: Data(data[offset + 8..<end - 4])))
      offset = end; if type == "IEND" { break }
    }
    guard offset == data.count, result.first?.type == "IHDR", result.first?.data.count == 13,
      result.last?.type == "IEND", result.last?.data.isEmpty == true, seenData else {
      throw CraftError.invalid("Incomplete PNG container.")
    }
    for type in ["IHDR", "PLTE", "tRNS", "iCCP", "sRGB", "gAMA", "cHRM", "pHYs", "IEND"] {
      guard result.filter({ $0.type == type }).count <= 1 else { throw CraftError.invalid("Duplicate PNG \(type) chunk.") }
    }
    let firstData = result.firstIndex { $0.type == "IDAT" }!
    for i in result.indices where ["PLTE", "tRNS", "iCCP", "sRGB", "gAMA", "cHRM", "pHYs"].contains(result[i].type) {
      guard i < firstData else { throw CraftError.invalid("PNG metadata appears after image data.") }
    }
    return result
  }
  static func passes(_ interlaced: Bool) -> [(Int, Int, Int, Int)] {
    interlaced ? [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)] : [(0,0,1,1)]
  }
  static func paeth(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
    let p = Int(a) + Int(b) - Int(c), da = abs(p - Int(a)), db = abs(p - Int(b)), dc = abs(p - Int(c))
    return da <= db && da <= dc ? a : db <= dc ? b : c
  }
  static func read(_ input: Data, name: String) throws -> CraftDocument? {
    let input = Data(input)
    guard input.starts(with: signature), input.count >= 33 else { return nil }
    // Other PNG types retain the qualified ImageIO path.
    guard input[25] == 3 || (input[25] == 0 && input[24] == 1) else { return nil }
    let blocks = try chunks(input), header = blocks[0].data
    let width = integer(header, 0), height = integer(header, 4), bits = Int(header[8]), indexed = header[9] == 3
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= PaletteQuantization.maximumPixels / height,
      (indexed ? [1,2,4,8].contains(bits) : bits == 1), header[10] == 0, header[11] == 0, header[12] <= 1 else {
      throw CraftError.invalid("Invalid restricted PNG sample layout.")
    }
    guard !blocks.contains(where: { ["acTL", "fcTL", "fdAT"].contains($0.type) }) else {
      throw CraftError.unsupported("Animated restricted PNG import requires a frame workflow.")
    }
    func payload(_ type: String) -> Data? { blocks.first { $0.type == type }?.data }
    var palette = [PaletteColor](), transparent: Int?
    if indexed {
      guard let table = payload("PLTE"), !table.isEmpty, table.count % 3 == 0, table.count / 3 <= 1 << bits else {
        throw CraftError.invalid("Invalid PNG palette.")
      }
      palette = stride(from: 0, to: table.count, by: 3).map { .init(table[$0], table[$0 + 1], table[$0 + 2]) }
      if let alpha = payload("tRNS") {
        guard !alpha.isEmpty, alpha.count <= palette.count else { throw CraftError.invalid("Invalid PNG palette alpha table.") }
        guard alpha.allSatisfy({ $0 == 0 || $0 == 255 }), alpha.filter({ $0 == 0 }).count <= 1 else {
          throw CraftError.unsupported("This indexed PNG has multiple or partial palette alpha values; the current Color Table supports one transparent entry.")
        }
        transparent = alpha.firstIndex(of: 0)
      }
    } else if payload("tRNS") != nil {
      throw CraftError.unsupported("Transparent grayscale PNG needs an alpha-capable document mode.")
    }
    var profile: Data?
    if let compressed = payload("iCCP") {
      guard let zero = compressed.firstIndex(of: 0), (1...79).contains(zero), zero + 2 < compressed.count, compressed[zero + 1] == 0 else {
        throw CraftError.invalid("Invalid PNG ICC profile chunk.")
      }
      profile = try RestrictedRasterCompression.inflate(Data(compressed[(zero + 2)...]), limit: ICCProfile.maximumBytes)
      try NativeModeProfile.validate(profile!, mode: indexed ? .rgb : .grayscale, depth: .u8)
    }
    var expected = 0
    for (x, y, dx, dy) in passes(header[12] == 1) where width > x && height > y {
      let w = (width - x + dx - 1) / dx, h = (height - y + dy - 1) / dy
      expected += ((w * bits + 7) / 8 + 1) * h
    }
    let compressed = blocks.filter { $0.type == "IDAT" }.reduce(into: Data()) { $0.append($1.data) }
    let bytes = try RestrictedRasterCompression.inflate(compressed, limit: expected, expected: expected)
    var samples = Data(count: width * height), offset = 0
    for (x0, y0, dx, dy) in passes(header[12] == 1) where width > x0 && height > y0 {
      let w = (width - x0 + dx - 1) / dx, h = (height - y0 + dy - 1) / dy, stride = (w * bits + 7) / 8
      var previous = [UInt8](repeating: 0, count: stride)
      for row in 0..<h {
        try Task.checkCancellation(); let filter = bytes[offset]; offset += 1
        guard filter <= 4 else { throw CraftError.invalid("Unknown PNG row filter.") }
        var values = Array(bytes[offset..<offset + stride]); offset += stride
        for i in values.indices {
          let a: UInt8 = i == 0 ? 0 : values[i - 1], b = previous[i], c: UInt8 = i == 0 ? 0 : previous[i - 1]
          switch filter {
          case 1: values[i] &+= a
          case 2: values[i] &+= b
          case 3: values[i] &+= UInt8((Int(a) + Int(b)) / 2)
          case 4: values[i] &+= paeth(a, b, c)
          default: break
          }
        }
        for x in 0..<w { samples[(y0 + row * dy) * width + x0 + x * dx] = (values[x * bits / 8] >> (8 - bits - (x * bits % 8))) & UInt8((1 << bits) - 1) }
        previous = values
      }
    }
    var document = try CraftDocument(width: width, height: height, name: name)
    if indexed {
      if profile == nil, payload("gAMA") != nil || payload("cHRM") != nil,
        let source = CGImageSourceCreateWithData(input as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let space = image.colorSpace {
        let base = space.model == .indexed ? space.baseColorSpace : space
        if base?.model == .rgb { profile = base?.copyICCData() as Data? }
      }
      document = try document.replacingRestrictedMode(.indexed(IndexedRaster(width: width, height: height, palette: palette, indices: samples, transparentIndex: transparent, profile: profile)))
    } else {
      var packed = Data(count: ((width + 7) / 8) * height)
      for y in 0..<height { for x in 0..<width where samples[y * width + x] == 0 { packed[y * ((width + 7) / 8) + x / 8] |= 0x80 >> (x % 8) } }
      document = try document.replacingRestrictedMode(.bitmap(BitmapRaster(width: width, height: height, bits: packed)))
    }
    document.sourceICC = profile
    if let physical = payload("pHYs") {
      guard physical.count == 9, physical[8] <= 1 else { throw CraftError.invalid("Invalid PNG pixel dimensions.") }
      let x = integer(physical, 0), y = integer(physical, 4)
      guard x == y else { throw CraftError.unsupported("Non-square PNG pixels are not represented by this document.") }
      if physical[8] == 1 { let dpi = Double(x) * 0.0254; guard (1...100_000).contains(dpi) else { throw CraftError.invalid("PNG resolution is outside the document range.") }; document.resolution = dpi }
    }
    if let source = CGImageSourceCreateWithData(input as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
      document.sourceMetadata = try RasterMetadata.capture(source, properties: properties)
    }
    try document.validate(); return document
  }
  static func write(_ document: CraftDocument, options: RasterEncodingOptions) throws -> Data {
    try document.validate()
    guard let restricted = document.restrictedMode else { throw CraftError.invalid("A restricted-mode PNG requires native samples.") }
    let indexed = document.colorMode == .indexed, bits = indexed ? 8 : 1, interlaced = options.pngInterlaced ?? false
    let width = document.width, height = document.height
    var header = number(width) + number(height); header.append(contentsOf: [UInt8(bits), indexed ? 3 : 0, 0, 0, interlaced ? 1 : 0])
    var output = signature + chunk("IHDR", header)
    switch restricted {
    case .indexed(let raster):
      let compressed = try RestrictedRasterCompression.deflate(raster.profile)
      output += chunk("iCCP", Data("Photato RGB".utf8) + Data([0,0]) + compressed)
      output += chunk("PLTE", Data(raster.palette.flatMap { [$0.red, $0.green, $0.blue] }))
      if let t = raster.transparentIndex { var alpha = Data(repeating: 255, count: t + 1); alpha[t] = 0; output += chunk("tRNS", alpha) }
    case .bitmap: break
    }
    let ppm = Int((document.pixelsPerInch / 0.0254).rounded())
    output += chunk("pHYs", number(ppm) + number(ppm) + Data([1]))
    if let metadata = try RasterMetadata.metadata(document.sourceMetadata, width: width, height: height,
      resolution: document.pixelsPerInch, linear: false, profileName: document.colorMode.title,
      isSRGB: false, photoshopMode: indexed ? 2 : 0), let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data? {
      output += chunk("iTXt", Data("XML:com.adobe.xmp".utf8) + Data(repeating: 0, count: 5) + xmp)
    }
    var rows = Data()
    for (x0, y0, dx, dy) in passes(interlaced) where width > x0 && height > y0 {
      let w = (width - x0 + dx - 1) / dx, h = (height - y0 + dy - 1) / dy
      for row in 0..<h {
        try Task.checkCancellation(); rows.append(0)
        var packed = Data(count: (w * bits + 7) / 8)
        for x in 0..<w {
          let px = x0 + x * dx, py = y0 + row * dy
          switch restricted {
          case .indexed(let r): packed[x] = r.indices[py * width + px]
          case .bitmap(let r): if !r.isBlack(x: px, y: py) { packed[x / 8] |= 0x80 >> (x % 8) }
          }
        }; rows.append(packed)
      }
    }
    let compressed = try RestrictedRasterCompression.deflate(rows, level: options.pngCompression ?? 6)
    for start in stride(from: 0, to: compressed.count, by: 65536) { output += chunk("IDAT", Data(compressed[start..<min(compressed.count, start + 65536)])) }
    output += chunk("IEND", Data()); return output
  }
}
