import Foundation
import ImageIO
import PhotoCraftCore

/// TIFF6 palette indices and bilevel samples, independent of the RGB display
/// cache. Photoshop resources retain palette length/transparent-index identity.
enum TIFFRestrictedStorage {
  static func unpackBits(_ packed: Data, expected: Int, rowBytes: Int) throws -> Data {
    var result = Data(), offset = 0
    while offset < packed.count {
      try Task.checkCancellation()
      let control = Int(Int8(bitPattern: packed[offset])); offset += 1
      if control == -128 { continue }
      let count = control >= 0 ? control + 1 : 1 - control
      // Some interoperable encoders pack the entire strip/tile in one stream.
      // Accept runs across scanlines, but never beyond the declared segment.
      guard count <= expected - result.count else {
        throw CraftError.invalid("TIFF PackBits run exceeds its segment.")
      }
      if control >= 0 {
        guard count <= packed.count - offset else { throw CraftError.invalid("Truncated TIFF PackBits literal.") }
        result.append(packed[offset..<offset + count]); offset += count
      } else {
        guard offset < packed.count else { throw CraftError.invalid("Truncated TIFF PackBits repeat.") }
        result.append(Data(repeating: packed[offset], count: count)); offset += 1
      }
    }
    guard result.count == expected else { throw CraftError.invalid("Truncated TIFF PackBits strip.") }
    return result
  }
  static func read(_ data: Data, name: String) throws -> CraftDocument? {
    guard TIFFContainer.isClassic(data) else { return nil }
    let file = try TIFFContainer(data, metadata: false,
      additionalTags: [266, 282, 283, 296, 301, 318, 319, 320, 34377, 34675, 37724])
    let photo = try file.scalar(262), depths = try file.numbers(258, default: [1])
    let indexed = photo == 3
    guard indexed || ([0, 1].contains(photo) && depths == [1]) else { return nil }
    let width = try file.scalar(256), height = try file.scalar(257)
    let channels = try file.scalar(277, default: 1), bits = depths[0]
    let extra = try file.numbers(338, default: [])
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= PaletteQuantization.maximumPixels / height, [1, 2].contains(channels),
      (depths.count == channels || depths.count == 1), Set(depths).count == 1,
      indexed ? [1, 2, 4, 8].contains(bits) : (bits == 1 && channels == 1),
      channels == 1 ? extra.isEmpty : extra == [2],
      try file.numbers(339, default: [1]).allSatisfy({ $0 == 1 }) else {
      throw CraftError.unsupported("This TIFF requires unsupported indexed/bitmap samples or auxiliary channels.")
    }
    guard file.root.fields[37724] == nil else {
      throw CraftError.unsupported("Restricted-mode TIFF layer records are not supported yet.")
    }
    guard ![301, 318, 319].contains(where: { file.root.fields[$0] != nil }) else {
      throw CraftError.unsupported("TIFF palette transfer tables and chromaticity tags require additional color management.")
    }
    let layout = try file.scalar(284, default: 1), compression = try file.scalar(259, default: 1)
    let fill = try file.scalar(266, default: 1), predictor = try file.scalar(317, default: 1)
    guard [1, 2].contains(layout), [1, 5, 8, 32946, 32773].contains(compression),
      [1, 2].contains(fill), fill == 1 || (bits == 1 && compression == 1),
      predictor == 1 || (predictor == 2 && bits == 8 && [5, 8, 32946].contains(compression)) else {
      throw CraftError.unsupported("This TIFF bit order, compression or predictor is not supported yet.")
    }
    let planar = layout == 2, components = planar ? 1 : channels
    let tiled = file.root.fields[324] != nil || file.root.fields[325] != nil
    let segmentWidth = tiled ? try file.scalar(322) : width
    let segmentHeight = tiled ? try file.scalar(323) : min(height, try file.scalar(278, default: height))
    guard segmentWidth > 0, segmentHeight > 0, segmentWidth <= Surface.maxDimension,
      segmentHeight <= Surface.maxDimension else { throw CraftError.invalid("Invalid restricted TIFF segment geometry.") }
    if tiled, file.root.fields[273] != nil || file.root.fields[279] != nil {
      throw CraftError.invalid("TIFF contains both strip and tile tables.")
    }
    let across = (width - 1) / segmentWidth + 1, down = (height - 1) / segmentHeight + 1
    let offsets = try file.numbers(tiled ? 324 : 273), counts = try file.numbers(tiled ? 325 : 279)
    guard offsets.count == across * down * (planar ? channels : 1), counts.count == offsets.count else {
      throw CraftError.invalid("Invalid restricted TIFF segment table.")
    }
    var indices = Data(count: width * height), alpha = Data(repeating: UInt8((1 << bits) - 1), count: width * height)
    for plane in 0..<(planar ? channels : 1) { for segment in 0..<across * down {
      try Task.checkCancellation()
      let x0 = segment % across * segmentWidth, y0 = segment / across * segmentHeight
      let rows = tiled ? segmentHeight : min(segmentHeight, height - y0)
      let rowBytes = (segmentWidth * components * bits + 7) / 8, expected = rowBytes * rows
      let i = plane * across * down + segment, offset = offsets[i], count = counts[i]
      guard expected <= TIFFContainer.byteLimit, offset >= 8, offset <= file.data.count,
        count > 0, count <= file.data.count - offset else { throw CraftError.invalid("Invalid TIFF segment extent.") }
      let packed = Data(file.data[offset..<offset + count])
      var samples: Data
      switch compression {
      case 1: guard packed.count == expected else { throw CraftError.invalid("Truncated TIFF segment.") }; samples = packed
      case 5: samples = Data(try TIFFLZW.decode(packed, expected: expected))
      case 32773: samples = try unpackBits(packed, expected: expected, rowBytes: rowBytes)
      default: samples = try RestrictedRasterCompression.inflate(packed, limit: expected, expected: expected)
      }
      if fill == 2 { samples = Data(samples.map { byte in (0..<8).reduce(UInt8(0)) { ($0 << 1) | (byte >> $1 & 1) } }) }
      for y in 0..<rows {
        try Task.checkCancellation()
        let base = y * rowBytes
        if predictor == 2 {
          for i in components..<rowBytes { samples[base + i] &+= samples[base + i - components] }
        }
        guard y0 + y < height else { continue }
        for x in 0..<min(segmentWidth, width - x0) { for c in 0..<components {
          let bit = (x * components + c) * bits
          let value = samples[base + bit / 8] >> (8 - bits - bit % 8) & UInt8((1 << bits) - 1)
          let index = (y0 + y) * width + x0 + x
          if (planar ? plane : c) == 0 { indices[index] = value } else { alpha[index] = value }
        } }
      }
    } }
    let resources = file.root.fields[34377]?.data ?? Data(), blocks = try PSDImageResources.blocks(resources)
    for tag in [34377, 34675] {
      if let f = file.root.fields[tag], ![1, 7].contains(f.type) { throw CraftError.invalid("Invalid TIFF binary metadata field.") }
    }
    for id in [1039, 1046, 1047] {
      guard blocks.filter({ $0.id == id }).count <= 1 else { throw CraftError.invalid("Duplicate restricted TIFF resource.") }
    }
    let profile = file.root.fields[34675]?.data ?? blocks.first { $0.id == 1039 }?.data
    if let embedded = file.root.fields[34675]?.data, let secondary = blocks.first(where: { $0.id == 1039 })?.data,
      embedded != secondary { throw CraftError.invalid("TIFF and Photoshop resource profiles disagree.") }
    var palette = [PaletteColor](), transparent: Int?
    if indexed {
      let table = try file.numbers(320), entries = 1 << bits
      guard file.root.fields[320]?.type == 3, table.count == entries * 3 else { throw CraftError.invalid("Invalid TIFF ColorMap.") }
      var count = entries
      if let field = blocks.first(where: { $0.id == 1046 }) {
        var reader = PSDReader(data: field.data)
        guard field.data.count == 2 else { throw CraftError.invalid("Invalid TIFF palette count resource.") }
        count = try reader.u16(); guard (1...entries).contains(count) else { throw CraftError.invalid("Invalid TIFF palette count.") }
      }
      if let field = blocks.first(where: { $0.id == 1047 }) {
        var reader = PSDReader(data: field.data)
        guard field.data.count == 2 else { throw CraftError.invalid("Invalid TIFF transparent index resource.") }
        let value = try reader.u16()
        if value != 65535 { guard value < count else { throw CraftError.invalid("Invalid TIFF transparent index.") }; transparent = value }
      }
      guard indices.allSatisfy({ Int($0) < count }) else { throw CraftError.invalid("TIFF sample is outside its palette.") }
      for i in 0..<count {
        let values = [table[i], table[entries + i], table[2 * entries + i]]
        guard values.allSatisfy({ $0 % 257 == 0 }) else {
          throw CraftError.unsupported("TIFF palette precision exceeds the8-bit Color Table; import cancelled to preserve its colors.")
        }
        palette.append(.init(UInt8(values[0] / 257), UInt8(values[1] / 257), UInt8(values[2] / 257)))
      }
      if channels == 2 {
        let maximum = UInt8((1 << bits) - 1)
        for i in indices.indices where alpha[i] == 0 {
          if let transparent, transparent != Int(indices[i]) { throw CraftError.unsupported("TIFF alpha uses more than one transparent palette entry.") }
          transparent = Int(indices[i])
        }
        guard indices.indices.allSatisfy({ alpha[$0] == (Int(indices[$0]) == transparent ? 0 : maximum) }) else {
          throw CraftError.unsupported("TIFF per-pixel alpha is not represented by a single transparent Color Table entry.")
        }
      }
    } else if let profile { try NativeModeProfile.validate(profile, mode: .grayscale, depth: .u8) }
    let orientation = try file.scalar(274, default: 1)
    guard (1...8).contains(orientation) else { throw CraftError.invalid("Invalid TIFF orientation.") }
    let w = orientation >= 5 ? height : width, h = orientation >= 5 ? width : height
    var oriented = Data(count: w * h)
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let sx: Int, sy: Int
      switch orientation {
      case 2: (sx, sy) = (width - 1 - x, y)
      case 3: (sx, sy) = (width - 1 - x, height - 1 - y)
      case 4: (sx, sy) = (x, height - 1 - y)
      case 5: (sx, sy) = (y, x)
      case 6: (sx, sy) = (y, height - 1 - x)
      case 7: (sx, sy) = (width - 1 - y, height - 1 - x)
      case 8: (sx, sy) = (width - 1 - y, x)
      default: (sx, sy) = (x, y)
      }; oriented[y * w + x] = indices[sy * width + sx]
    } }
    var document = try CraftDocument(width: w, height: h, name: name)
    if indexed {
      document = try document.replacingRestrictedMode(.indexed(IndexedRaster(width: w, height: h,
        palette: palette, indices: oriented, transparentIndex: transparent, profile: profile)))
    } else {
      var packed = Data(count: ((w + 7) / 8) * h)
      for y in 0..<h { for x in 0..<w where oriented[y * w + x] == (photo == 0 ? 1 : 0) { packed[y * ((w + 7) / 8) + x / 8] |= 0x80 >> (x % 8) } }
      document = try document.replacingRestrictedMode(.bitmap(BitmapRaster(width: w, height: h, bits: packed)))
    }
    document.sourceICC = profile
    if let source = CGImageSourceCreateWithData(data as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
      document.sourceMetadata = try RasterMetadata.capture(source, properties: properties)
    }
    if !resources.isEmpty { document.sourceMetadata = (document.sourceMetadata ?? [:]).merging(["psdResources": resources]) { _, new in new } }
    let paths = try PSDRestrictedStorage.paths(blocks, width: width, height: height)
    guard paths.isEmpty || orientation == 1 else { throw CraftError.unsupported("Rotated TIFF saved paths require a matching path transform.") }
    document.paths = paths.isEmpty ? nil : paths
    if let x = file.root.fields[282], let y = file.root.fields[283] {
      func rational(_ field: TIFFContainer.Field) throws -> Double {
        guard field.type == 5, field.count == 1, file.order.number(field.data, 4, 4) > 0 else { throw CraftError.invalid("Invalid TIFF resolution.") }
        return Double(file.order.number(field.data, 0, 4)) / Double(file.order.number(field.data, 4, 4))
      }
      let dx = try rational(x), dy = try rational(y), unit = try file.scalar(296, default: 2)
      guard [1, 2, 3].contains(unit), abs(dx - dy) < 0.01 else { throw CraftError.unsupported("Non-square TIFF pixels are not represented by this document.") }
      if unit != 1 {
        let dpi = dx * (unit == 3 ? 2.54 : 1)
        guard (1...100_000).contains(dpi) else { throw CraftError.invalid("Invalid TIFF resolution range.") }; document.resolution = dpi
      }
    }
    try document.validate(); return document
  }
  static func write(_ document: CraftDocument, options: RasterEncodingOptions) throws -> Data {
    try document.validate(); try options.validate(for: .tiff)
    guard let raster = document.restrictedMode, options.tiffLayers != true, options.tiffPredictor != true else {
      throw CraftError.unsupported("Indexed/Bitmap TIFF output requires flat samples without the floating-point predictor.")
    }
    // ImageIO serializes descriptive EXIF/IPTC metadata; replace all color and
    // sample fields with the authoritative restricted raster below.
    let template = try RasterIO.encoded(raster.surface(), type: .tiff, resolution: document.pixelsPerInch,
      sourceMetadata: document.sourceMetadata, options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none))
    let file = try TIFFContainer(template, metadata: true)
    for tag in [301, 318, 319, 320, 330, 332, 333, 334, 336, 338, 34377, 34675, 37724] { file.root.fields.removeValue(forKey: tag) }
    file.root.next = nil
    let indexed = document.colorMode == .indexed, bits = indexed ? 8 : 1
    let channels: Int
    if case .indexed(let r) = raster, r.transparentIndex != nil { channels = 2 } else { channels = 1 }
    let planar = options.tiffPixelOrder == .perChannel, components = planar ? 1 : channels
    let order: TIFFContainer.Order = options.tiffByteOrder == .bigEndian ? .big : options.tiffByteOrder == .littleEndian ? .little : file.order
    let compression = options.tiffCompression ?? .none
    let width = document.width, height = document.height, rowBytes = (width * components * bits + 7) / 8
    let rows = compression == .none ? height : max(1, min(height, 65536 / rowBytes))
    var resources = try PSDRestrictedStorage.resources(document, includeResolution: document.pixelsPerInch < 65536)
    if case .indexed(let r) = raster {
      var table = [Int](repeating: 0, count: 768)
      for (i, color) in r.palette.enumerated() { table[i] = Int(color.red) * 257; table[256 + i] = Int(color.green) * 257; table[512 + i] = Int(color.blue) * 257 }
      file.set(320, table)
      file.root.fields[34675] = .init(tag: 34675, type: 7, count: r.profile.count, data: r.profile)
    }
    if !resources.isEmpty { file.root.fields[34377] = .init(tag: 34377, type: 7, count: resources.count, data: resources) }
    resources.removeAll()
    file.set(256, [width], type: 4); file.set(257, [height], type: 4); file.set(274, [1])
    file.set(258, Array(repeating: bits, count: channels)); file.set(262, [indexed ? 3 : 0]); file.set(266, [1])
    file.set(277, [channels]); file.set(278, [rows], type: 4); file.set(259, [compression.tag]); file.set(284, [planar ? 2 : 1]); file.set(317, [1])
    file.set(339, Array(repeating: 1, count: channels)); if channels == 2 { file.set(338, [2]) }
    if let exif = file.root.fields[34665]?.children.first {
      exif.fields[40961] = .init(tag: 40961, type: 3, count: 1, data: file.order.bytes(65535, 2))
    }
    if let metadata = try RasterMetadata.metadata(document.sourceMetadata, width: width, height: height,
      resolution: document.pixelsPerInch, profileName: document.colorMode.title, isSRGB: false, photoshopMode: indexed ? 2 : 0),
      let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data? { file.root.fields[700] = .init(tag: 700, type: 1, count: xmp.count, data: xmp) }
    var output = Data(order == .little ? [73,73,42,0,0,0,0,0] : [77,77,0,42,0,0,0,0]), offsets = [Int](), counts = [Int]()
    for plane in 0..<(planar ? channels : 1) { for y0 in stride(from: 0, to: height, by: rows) {
      var samples = Data()
      for y in y0..<min(y0 + rows, height) {
        try Task.checkCancellation()
        switch raster {
        case .bitmap(let r): samples.append(r.bits[y * rowBytes..<(y + 1) * rowBytes])
        case .indexed(let r):
          for x in 0..<width { for c in 0..<components {
            let index = r.indices[y * width + x]
            samples.append((planar ? plane : c) == 0 ? index : (Int(index) == r.transparentIndex ? 0 : 255))
          } }
        }
      }
      let packed: Data
      switch compression {
      case .none: packed = samples
      case .lzw: packed = try TIFFLZW.encode(Array(samples))
      case .zip: packed = try RestrictedRasterCompression.deflate(samples)
      }
      if output.count % 2 != 0 { output.append(0) }
      offsets.append(output.count); counts.append(packed.count); output.append(packed)
    } }
    file.set(273, offsets, type: 4); file.set(279, counts, type: 4)
    try file.appendDirectories(to: &output, order: order); try Task.checkCancellation(); return output
  }
}
