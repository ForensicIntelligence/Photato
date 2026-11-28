// This product includes DNG technology under license by Adobe.
import Foundation
import PhotoCraftCore

/// A scene-referred linear sRGB DNG with optional transparency.
package enum RawLinearDNG {
  private static let layout = TIFFContainer.Layout(bigTIFF: false)
  private static let order = TIFFContainer.Order.little
  private static let previewMaximumSide = 160

  package static func write(_ document: CraftDocument, to url: URL, settings: CameraRawSettings? = nil,
    preserveTransparency: Bool = false, crop: RawCropBounds? = nil) throws {
    try Task.checkCancellation()
    guard document.colorMode == .rgb, document.depth == .f32, document.modeDescriptor == nil,
      document.workingICC == nil, document.profileIsUntagged != true,
      document.width > 0, document.height > 0,
      document.width <= RawSourceIO.maximumDimension, document.height <= RawSourceIO.maximumDimension,
      document.width <= RawHDRMerge.maximumPixels / document.height else {
      throw CraftError.invalid("Linear DNG requires an HDR merge in linear sRGB or an equivalent opaque RGB32 document.")
    }
    try document.validate()
    let hasPagedSource = document.layers.contains { layer in
      if case .raster(let pixels) = layer.content { return pixels.mappedBytes > 0 }
      return false
    }
    let surface = try hasPagedSource ? Renderer.compositePaged(document) : Renderer.composite(document)
    let previewRegion = try crop.map { try $0.rectangle(width: surface.width, height: surface.height) }
      ?? IntRect(x: 0, y: 0, width: surface.width, height: surface.height)
    let size = try RasterPreviewRequest.overview(width: previewRegion.width, height: previewRegion.height,
      maximumSide: previewMaximumSide)
    let previewRequest = try RasterPreviewRequest(region: previewRegion, width: size.width, height: size.height)
    let preview = try previewRequest.reducing(surface)
    let file = try AtomicFileWriter(to: url, maximumBytes: SmartObject.maximumCameraRawSourceBytes)
    defer { file.discard() }
    try file.append(layout.header(order: order))

    let previewOffset = file.count
    let previewBytes = try rgbThumbnail(preview)
    try file.append(previewBytes)
    if file.count % 2 != 0 { try file.append(Data([0])) }

    let width = surface.width, height = surface.height
    let bytesPerRow = width * 6
    let rowsPerStrip = max(1, AtomicFileWriter.chunkBytes / bytesPerRow)
    var stripOffsets = [Int](), stripLengths = [Int]()
    var peak: Float = 1
    var hasTransparency = false
    for startRow in stride(from: 0, to: height, by: rowsPerStrip) {
      let endRow = min(startRow + rowsPerStrip, height)
      var samples = Data(count: (endRow - startRow) * bytesPerRow)
      try samples.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
        var offset = 0
        for y in startRow..<endRow {
          try Task.checkCancellation()
          for pixel in surface.linearRow(y) {
            guard pixel.isFinite, (preserveTransparency && (0...1).contains(pixel.a)) || pixel.a == 1,
              min(pixel.r, pixel.g, pixel.b) >= 0,
              max(pixel.r, pixel.g, pixel.b) <= 65_504 else {
              throw CraftError.unsupported("The panorama or HDR merge has unsupported transparency or samples outside the linear DNG range.")
            }
            hasTransparency = hasTransparency || pixel.a < 1
            peak = max(peak, pixel.r, pixel.g, pixel.b)
            try bytes.storeBytes(of: OpenEXR.halfBits(pixel.r).littleEndian, toByteOffset: offset, as: UInt16.self)
            try bytes.storeBytes(of: OpenEXR.halfBits(pixel.g).littleEndian, toByteOffset: offset + 2, as: UInt16.self)
            try bytes.storeBytes(of: OpenEXR.halfBits(pixel.b).littleEndian, toByteOffset: offset + 4, as: UInt16.self)
            offset += 6
          }
        }
      }
      stripOffsets.append(file.count)
      stripLengths.append(samples.count)
      try file.append(samples)
    }

    let raw = TIFFContainer(order: order)
    imageDirectory(raw, width: width, height: height, bits: 16, photometric: 34_892,
      offsets: stripOffsets, lengths: stripLengths, rowsPerStrip: rowsPerStrip)
    raw.set(254, [0], type: 4)
    raw.set(339, [3, 3, 3])
    raw.set(50_713, [1, 1])
    raw.set(50_714, [0, 0, 0])
    let stops = Int(ceil(log2(Double(peak))))
    let whiteLevel = 1 << stops
    raw.set(50_717, [whiteLevel, whiteLevel, whiteLevel], type: 4)
    setRationals([(1, 1), (1, 1)], tag: 50_718, in: raw)
    raw.set(50_719, [0, 0], type: 4)
    raw.set(50_720, [width, height], type: 4)
    raw.set(50_829, [0, 0, height, width], type: 4)

    let thumbnail = TIFFContainer(order: order)
    imageDirectory(thumbnail, width: preview.width, height: preview.height, bits: 8, photometric: 2,
      offsets: [previewOffset], lengths: [previewBytes.count], rowsPerStrip: preview.height)
    thumbnail.set(254, [1], type: 4)
    var directories = [raw.root]
    if hasTransparency { directories.append(try transparencyDirectory(surface, writingTo: file)) }
    thumbnail.root.fields[330] = .init(tag: 330, type: 4, count: directories.count, data: Data(), children: directories)
    setASCII("Photato", tag: 271, in: thumbnail)
    setASCII("Linear HDR", tag: 272, in: thumbnail)
    setASCII("Photato", tag: 305, in: thumbnail)
    setASCII("Photato Linear HDR", tag: 50_708, in: thumbnail)
    for tag in [50_706, 50_707] {
      thumbnail.root.fields[tag] = .init(tag: tag, type: 1, count: 4, data: Data([1, 4, 0, 0]))
    }
    // Scene-referred D65 XYZ to linear sRGB, in the direction required by ColorMatrix1.
    let coefficients = [3_240_454, -1_537_139, -498_531, -969_266, 1_876_011, 41_556,
      55_643, -204_026, 1_057_225]
    setRationals(coefficients.map { ($0, 1_000_000) }, tag: 50_721, in: thumbnail, signed: true)
    setRationals([(1, 1), (1, 1), (1, 1)], tag: 50_728, in: thumbnail)
    setRationals([(stops, 1)], tag: 50_730, in: thumbnail, signed: true)
    thumbnail.set(50_778, [21]) // D65.
    let packet: Data?
    if let crop {
      var development = RawDevelopment()
      development.crop = crop
      development.adjustments = settings ?? .init()
      packet = try CameraRawXMP.write(development)
    } else {
      packet = try settings.map { try CameraRawXMP.write($0) }
    }
    if let packet { thumbnail.root.fields[700] = .init(tag: 700, type: 1, count: packet.count, data: packet) }
    let pointer = try thumbnail.writeDirectories(order: order, maximumOutput: SmartObject.maximumCameraRawSourceBytes,
      extent: { file.count }, emit: file.append, patch: { try file.patch($0, at: $1) })
    try file.patch(pointer, at: layout.headerPointerOffset)
    try file.commit()
  }

  struct TransparencyMask {
    fileprivate let data: Data
    fileprivate let width: Int
    fileprivate let rowsPerStrip: Int
    fileprivate let offsets: [Int]

    func row(_ y: Int) -> Data {
      let start = offsets[y / rowsPerStrip] + y % rowsPerStrip * width
      let index = data.startIndex + start
      return data[index..<(index + width)]
    }
  }

  // Core Image does not expose the alpha of an uncompressed DNG mask IFD.
  // Recognize the single-channel 8-bit strip layout and borrow rows from the original.
  static func transparencyMask(in data: Data, width: Int, height: Int) throws -> TransparencyMask? {
    guard width > 0, height > 0, width <= RawPanorama.maximumOutputPixels / height, TIFFContainer.isClassic(data),
      let file = try? TIFFContainer(data, metadata: false, additionalTags: [254], inspectSubIFDs: true,
        maximumBytes: SmartObject.maximumCameraRawSourceBytes) else { return nil }
    func integers(_ field: TIFFContainer.Field?) -> [Int] {
      guard let field, field.type == 3 || field.type == 4 else { return [] }
      let bytes = field.type == 3 ? 2 : 4
      guard field.count <= field.data.count / bytes else { return [] }
      return (0..<field.count).map { file.order.number(field.data, $0 * bytes, bytes) }
    }
    guard let mask = file.root.fields[330]?.children.first(where: { integers($0.fields[254]) == [4] }),
      integers(mask.fields[256]) == [width], integers(mask.fields[257]) == [height],
      integers(mask.fields[258]) == [8], integers(mask.fields[259]) == [1],
      integers(mask.fields[262]) == [4], integers(mask.fields[277]) == [1],
      integers(mask.fields[274]) == [1], integers(file.root.fields[274]) == [1],
      let rows = integers(mask.fields[278]).first, rows > 0 else { return nil }
    let offsets = integers(mask.fields[273]), lengths = integers(mask.fields[279])
    let strips = (height - 1) / rows + 1
    guard offsets.count == strips, lengths.count == strips else { return nil }
    for strip in 0..<strips {
      try Task.checkCancellation()
      let count = width * min(rows, height - strip * rows)
      guard lengths[strip] == count, offsets[strip] >= 0, offsets[strip] <= data.count - count else { return nil }
    }
    return TransparencyMask(data: data, width: width, rowsPerStrip: rows, offsets: offsets)
  }

  private static func transparencyDirectory(_ surface: Surface, writingTo file: AtomicFileWriter) throws -> TIFFContainer.Directory {
    let width = surface.width, height = surface.height
    let rows = max(1, AtomicFileWriter.chunkBytes / width)
    var offsets = [Int](), lengths = [Int]()
    for top in stride(from: 0, to: height, by: rows) {
      var mask = Data()
      let bottom = min(height, top + rows)
      mask.reserveCapacity(width * (bottom - top))
      for y in top..<bottom {
        try Task.checkCancellation()
        for pixel in surface.linearRow(y) { mask.append(UInt8((255 * unit(pixel.a)).rounded())) }
      }
      offsets.append(file.count)
      lengths.append(mask.count)
      try file.append(mask)
    }
    let directory = TIFFContainer(order: order)
    imageDirectory(directory, width: width, height: height, bits: 8, photometric: 4,
      offsets: offsets, lengths: lengths, rowsPerStrip: rows)
    directory.set(254, [4], type: 4)
    directory.set(258, [8])
    directory.set(277, [1])
    return directory.root
  }

  private static func imageDirectory(_ directory: TIFFContainer, width: Int, height: Int, bits: Int, photometric: Int,
    offsets: [Int], lengths: [Int], rowsPerStrip: Int) {
    directory.set(256, [width], type: 4)
    directory.set(257, [height], type: 4)
    directory.set(258, [bits, bits, bits])
    directory.set(259, [1])
    directory.set(262, [photometric])
    directory.set(273, offsets, type: 4)
    directory.set(274, [1])
    directory.set(277, [3])
    directory.set(278, [rowsPerStrip], type: 4)
    directory.set(279, lengths, type: 4)
    directory.set(284, [1])
  }

  private static func rgbThumbnail(_ surface: Surface) throws -> Data {
    var data = Data()
    data.reserveCapacity(surface.width * surface.height * 3)
    for y in 0..<surface.height {
      try Task.checkCancellation()
      for x in 0..<surface.width {
        let pixel = surface.pixel(x: x, y: y)
        data.append(UInt8((unit(pixel.r) * 255).rounded()))
        data.append(UInt8((unit(pixel.g) * 255).rounded()))
        data.append(UInt8((unit(pixel.b) * 255).rounded()))
      }
    }
    return data
  }

  private static func setASCII(_ value: String, tag: Int, in directory: TIFFContainer) {
    let bytes = Data(value.utf8) + Data([0])
    directory.root.fields[tag] = .init(tag: tag, type: 2, count: bytes.count, data: bytes)
  }

  private static func setRationals(_ values: [(Int, Int)], tag: Int, in directory: TIFFContainer, signed: Bool = false) {
    let bytes = values.reduce(into: Data()) { bytes, value in
      bytes.append(order.bytes(value.0, 4))
      bytes.append(order.bytes(value.1, 4))
    }
    directory.root.fields[tag] = .init(tag: tag, type: signed ? 10 : 5, count: values.count, data: bytes)
  }
}
