// This product includes DNG technology under license by Adobe.
import Foundation
import PhotoCraftCore

/// A scene-referred linear DNG for an opaque, linear-sRGB HDR merge.
package enum RawLinearDNG {
  private static let layout = TIFFContainer.Layout(bigTIFF: false)
  private static let order = TIFFContainer.Order.little
  private static let previewMaximumSide = 160

  package static func write(_ document: CraftDocument, to url: URL, settings: CameraRawSettings? = nil) throws {
    try Task.checkCancellation()
    guard document.colorMode == .rgb, document.depth == .f32, document.modeDescriptor == nil,
      document.workingICC == nil, document.profileIsUntagged != true,
      document.width > 0, document.height > 0,
      document.width <= RawSourceIO.maximumDimension, document.height <= RawSourceIO.maximumDimension,
      document.width <= HDRMerge.maximumPixels / document.height else {
      throw CraftError.invalid("Linear DNG requires an HDR merge in linear sRGB or an equivalent opaque RGB32 document.")
    }
    try document.validate()
    let surface = try Renderer.composite(document)
    let previewRequest = try RasterPreviewRequest.overview(width: surface.width, height: surface.height,
      maximumSide: previewMaximumSide)
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
    for startRow in stride(from: 0, to: height, by: rowsPerStrip) {
      let endRow = min(startRow + rowsPerStrip, height)
      var samples = Data()
      samples.reserveCapacity((endRow - startRow) * bytesPerRow)
      for y in startRow..<endRow {
        try Task.checkCancellation()
        for x in 0..<width {
          let pixel = surface.linearPixel(x: x, y: y)
          guard pixel.isFinite, pixel.a == 1, min(pixel.r, pixel.g, pixel.b) >= 0,
            max(pixel.r, pixel.g, pixel.b) <= 65_504 else {
            throw CraftError.unsupported("Linear DNG requires opaque, nonnegative HDR samples within the 16-bit floating-point range.")
          }
          peak = max(peak, pixel.r, pixel.g, pixel.b)
          try appendHalf(pixel.r, to: &samples)
          try appendHalf(pixel.g, to: &samples)
          try appendHalf(pixel.b, to: &samples)
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
    thumbnail.root.fields[330] = .init(tag: 330, type: 4, count: 1, data: Data(), children: [raw.root])
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
    if let settings {
      let packet = try CameraRawXMP.write(settings)
      thumbnail.root.fields[700] = .init(tag: 700, type: 1, count: packet.count, data: packet)
    }
    let pointer = try thumbnail.writeDirectories(order: order, maximumOutput: SmartObject.maximumCameraRawSourceBytes,
      extent: { file.count }, emit: file.append, patch: { try file.patch($0, at: $1) })
    try file.patch(pointer, at: layout.headerPointerOffset)
    try file.commit()
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

  private static func appendHalf(_ value: Float, to samples: inout Data) throws {
    let bits = try OpenEXR.halfBits(value)
    samples.append(UInt8(truncatingIfNeeded: bits))
    samples.append(UInt8(bits >> 8))
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
