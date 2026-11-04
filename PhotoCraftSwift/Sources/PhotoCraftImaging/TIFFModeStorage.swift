import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore

/// TIFF6 and Adobe's 2002 TIFF Technical Notes. Color planes stay numerical;
/// ColorSync is used only to build the RGB display cache.
enum TIFFModeStorage {
  static func photometric(_ mode: DocumentColorMode) -> Int {
    switch mode { case .rgb: 2; case .grayscale: 1; case .cmyk: 5; case .lab: 8; case .indexed: 3; case .bitmap: 0; case .duotone, .multichannel: -1 }
  }
  static func mode(_ photometric: Int) -> DocumentColorMode? {
    switch photometric { case 0, 1: .grayscale; case 2: .rgb; case 5: .cmyk; case 8, 9: .lab; default: nil }
  }
  static func read(_ data: Data, name: String) throws -> CraftDocument? {
    guard TIFFContainer.isClassic(data) else { return nil }
    let file = try TIFFContainer(data, metadata: false, additionalTags: [332, 34675])
    let photo = try file.scalar(262)
    // Keep the qualified legacy RGB/tiled/ImageIO path unchanged.
    guard let mode = mode(photo), mode != .rgb else { return nil }
    if mode == .grayscale, try file.numbers(258).contains(where: { $0 < 8 }) { return nil }
    guard let g = try TIFFStorage.Geometry(file, allowAssociatedAlpha: true,
      colorComponents: mode.componentCount, photometric: photo) else {
      throw CraftError.unsupported("This TIFF color-mode storage variant is not supported yet; import cancelled to retain its components.")
    }
    if mode == .cmyk {
      guard try file.scalar(332, default: 1) == 1 else {
        throw CraftError.unsupported("TIFF spot-ink separations are not supported yet.")
      }
    }
    guard g.width <= NativeModeRaster.maximumPixels / g.height else { throw CraftError.unsupported("TIFF component decoding currently supports up to8,388,608pixels.") }
    let depth: PixelDepth = g.bits == 8 ? .u8 : g.bits == 16 ? .u16 : .f32
    guard mode.depths.contains(depth) else { throw CraftError.unsupported("Unsupported TIFF mode/depth combination.") }
    if let field = file.root.fields[34675], ![1, 7].contains(field.type) {
      throw CraftError.invalid("Invalid TIFF ICC profile field.")
    }
    let original = file.root.fields[34675]?.data
    let profile = try PSDModeStorage.profile(original, mode: mode, depth: depth)
    var native = try NativeModeRaster(width: g.width, height: g.height, mode: mode, depth: depth, profile: profile)
    let planes = g.planar ? g.channels : 1, components = g.planar ? 1 : g.channels
    let stripsPerPlane = (g.height - 1) / g.rows + 1, bps = g.bits / 8
    for plane in 0..<planes { for strip in 0..<stripsPerPlane {
      try Task.checkCancellation()
      let y0 = strip * g.rows, rows = min(g.rows, g.height - y0)
      let index = plane * stripsPerPlane + strip, rowBytes = g.width * components * bps
      let expected = rows * rowBytes
      guard expected <= TIFFContainer.byteLimit else { throw CraftError.invalid("TIFF strip exceeds sample budget.") }
      let packed = Data(file.data[g.offsets[index]..<g.offsets[index] + g.counts[index]])
      var bytes: [UInt8]
      switch g.compression {
      case 1:
        guard packed.count == expected else { throw CraftError.invalid("Truncated TIFF strip.") }
        bytes = Array(packed)
      case 5: bytes = try TIFFLZW.decode(packed, expected: expected)
      default: bytes = try PSDChannelCodec.inflate(packed, expected: expected)
      }
      for row in 0..<rows {
        try Task.checkCancellation()
        let start = row * rowBytes
        let samples = g.predictor == 1 ? Array(bytes[start..<start + rowBytes])
          : TIFFStorage.restore(Array(bytes[start..<start + rowBytes]), bits: g.bits,
            components: components, order: file.order, predictor: g.predictor)
        for x in 0..<g.width { for channel in 0..<components {
          let c = g.planar ? plane : channel, at = (x * components + channel) * bps
          var raw: UInt32 = 0
          for b in 0..<bps { raw = raw << 8 | UInt32(samples[at + (file.order == .big ? b : bps - 1 - b)]) }
          var value = depth == .f32 ? Float(bitPattern: raw) : Float(raw) / (g.bits == 8 ? 255 : 65535)
          if c < mode.componentCount {
            if photo == 0 { value = 1 - value }
            if photo == 8, c > 0 {
              let signed = g.bits == 8 ? Float(Int8(bitPattern: UInt8(raw))) : Float(Int16(bitPattern: UInt16(raw))) / 256
              value = (signed + 128) / 255
              guard value <= 1 else { throw CraftError.unsupported("TIFF Lab chroma exceeds the current native component range.") }
            } else if photo == 9, g.bits == 16 {
              value = Float(raw) / 65280
              guard value <= 1 else { throw CraftError.unsupported("TIFF ICCLab sample exceeds the current native component range.") }
            }
          }
          try native.set(value, component: c, index: (y0 + row) * g.width + x)
        } }
      }
    } }
    if g.channels == mode.componentCount {
      for i in 0..<g.width * g.height { try native.set(1, component: mode.componentCount, index: i) }
    } else if g.associated {
      for i in 0..<g.width * g.height {
        if i % 4096 == 0 { try Task.checkCancellation() }
        let alpha = native.value(component: mode.componentCount, index: i)
        for c in 0..<mode.componentCount {
          let value = native.value(component: c, index: i)
          // Lab's chroma origin is zero a*/b*, not the biased storage zero.
          let origin: Float = mode == .lab && c > 0 ? 128 / 255 : 0
          try native.set(alpha > 0 ? (value - origin) / alpha + origin : origin, component: c, index: i)
        }
      }
    }
    let orientation = try file.scalar(274, default: 1)
    guard (1...8).contains(orientation) else { throw CraftError.invalid("Invalid TIFF orientation.") }
    if orientation != 1 { native = try oriented(native, orientation: orientation) }
    var document = try CraftDocument(width: native.width, height: native.height, depth: depth, name: name)
    document.modeDescriptor = try .init(mode: mode, depth: depth, profile: profile)
    document.sourceICC = original
    document.profileIsUntagged = original == nil ? true : nil
    if let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
      document.sourceMetadata = try RasterMetadata.capture(source, properties: properties)
      if let dpi = properties[kCGImagePropertyDPIWidth] as? Double, dpi.isFinite, (1...100_000).contains(dpi) { document.resolution = dpi }
    }
    var layer = Layer(name: name, content: .raster(try native.surface())); layer.nativeMode = native
    document.layers = [layer]; document.activeLayerID = layer.id
    try document.validate()
    return try TIFFLayers.read(data, composite: document) ?? document
  }
  static func oriented(_ source: NativeModeRaster, orientation: Int) throws -> NativeModeRaster {
    let swapped = orientation >= 5
    var result = try NativeModeRaster(width: swapped ? source.height : source.width,
      height: swapped ? source.width : source.height, mode: source.mode, depth: source.depth,
      profile: source.profile, intent: source.intent)
    for y in 0..<result.height { try Task.checkCancellation(); for x in 0..<result.width {
      let sx: Int, sy: Int
      switch orientation {
      case 2: (sx, sy) = (source.width - 1 - x, y)
      case 3: (sx, sy) = (source.width - 1 - x, source.height - 1 - y)
      case 4: (sx, sy) = (x, source.height - 1 - y)
      case 5: (sx, sy) = (y, x)
      case 6: (sx, sy) = (y, source.height - 1 - x)
      case 7: (sx, sy) = (source.width - 1 - y, source.height - 1 - x)
      case 8: (sx, sy) = (source.width - 1 - y, x)
      default: (sx, sy) = (x, y)
      }
      for c in 0...source.mode.componentCount { try result.set(source.value(component: c, index: sy * source.width + sx), component: c, index: y * result.width + x) }
    } }; return result
  }
  static func write(_ surface: Surface, document: CraftDocument, resolution: Double,
    depth: PixelDepth, metadata: [String: Data]?, options: RasterEncodingOptions,
    preserveSingleLayer: Bool = false) throws -> Data {
    guard let descriptor = document.modeDescriptor, depth == document.depth,
      resolution.isFinite, (1...100_000).contains(resolution) else {
      throw CraftError.invalid("Native TIFF export requires the document depth and a valid resolution.")
    }
    guard document.width <= NativeModeRaster.maximumPixels / document.height else { throw CraftError.unsupported("TIFF component output currently supports up to8,388,608pixels; use native86 to retain this document.") }
    let native: NativeModeRaster
    if preserveSingleLayer, document.layers.count == 1, let layer = document.layers.first,
      let stored = layer.nativeMode, layer.visible, layer.opacity == 1,
      layer.x == 0, layer.y == 0, layer.mask == nil, layer.vectorMask == nil,
      layer.style == nil, layer.smartObject == nil, layer.smartFilters == nil,
      layer.affine == nil, layer.warp == nil, layer.parentID == nil, layer.clipped != true,
      layer.blendMode == .normal, document.artboardOrigin == nil,
      stored.width == surface.width, stored.height == surface.height {
      native = stored
    } else {
      // Existing merged previews still use RGB composition/reseparation; exact
      // native ink blending remains a separate, explicitly tracked requirement.
      native = try NativeModeRaster.converting(surface, to: descriptor.mode, depth: depth,
        profile: descriptor.profile, intent: descriptor.intent)
    }
    try native.validate()
    // ImageIO supplies established EXIF/IPTC metadata serialization. Its sample
    // payload and color-dependent fields are replaced with the native planes.
    let template = try RasterIO.encoded(surface, type: .tiff, resolution: resolution,
      outputDepth: depth, sourceMetadata: metadata, options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none))
    let file = try TIFFContainer(template, metadata: true), colors = native.mode.componentCount
    let channels = colors + 1, bits = native.bytesPerSample * 8, photo = photometric(native.mode)
    for tag in [301, 318, 319, 320, 330, 332, 333, 334, 336, 34377, 37724] { file.root.fields.removeValue(forKey: tag) }
    file.root.next = nil
    file.set(256, [native.width], type: 4); file.set(257, [native.height], type: 4)
    file.set(258, Array(repeating: bits, count: channels)); file.set(262, [photo])
    file.set(277, [channels]); file.set(278, [native.height], type: 4)
    file.set(259, [1]); file.set(284, [1]); file.set(317, [1]); file.set(338, [2])
    file.set(339, Array(repeating: depth == .f32 ? 3 : 1, count: channels))
    if native.mode == .cmyk { file.set(332, [1]); file.set(334, [4]) }
    file.root.fields[34675] = .init(tag: 34675, type: 7, count: native.profile.count, data: native.profile)
    if let exif = file.root.fields[34665]?.children.first {
      exif.fields[40961] = .init(tag: 40961, type: 3, count: 1, data: file.order.bytes(65535, 2))
    }
    if let xmp = try RasterMetadata.metadata(metadata, width: native.width, height: native.height,
      resolution: resolution, linear: depth == .f32, profileName: native.mode.title,
      isSRGB: false, photoshopMode: PSDModeStorage.code(native.mode)),
      let bytes = CGImageMetadataCreateXMPData(xmp, nil) as Data? {
      file.root.fields[700] = .init(tag: 700, type: 1, count: bytes.count, data: bytes)
    }
    var output = Data(template.prefix(8))
    for i in 0..<native.width * native.height {
      if i % 4096 == 0 { try Task.checkCancellation() }
      for c in 0..<channels {
        if native.mode == .lab, c == 1 || c == 2 {
          let value = (Double(native.value(component: c, index: i)) * 255 - 128) * (bits == 8 ? 1 : 256)
          output.append(file.order.bytes(Int(value.rounded()), native.bytesPerSample))
        } else {
          output.append(file.order.bytes(Int(native.rawWord(component: c, index: i)), native.bytesPerSample))
        }
      }
    }
    file.set(273, [8], type: 4); file.set(279, [output.count - 8], type: 4)
    try file.appendDirectories(to: &output, order: file.order)
    return try TIFFStorage.rewrite(output, options: options, colorComponents: colors, photometric: photo)
  }
}
