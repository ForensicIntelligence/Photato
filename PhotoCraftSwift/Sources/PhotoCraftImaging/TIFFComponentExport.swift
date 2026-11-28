import Foundation
import CoreGraphics
import ImageIO
import PhotoCraftCore
import zlib

/// TIFF and BigTIFF component output. Only strips and IFD tables remain
/// in memory when writing to a file. The same encoder can target bounded API Data.
enum TIFFComponentExport {
  fileprivate final class Output {
    private var buffer = Data()
    private let file: AtomicFileWriter?
    let maximumBytes: Int
    let layout: TIFFContainer.Layout
    var count: Int { file?.count ?? buffer.count }
    var isFileBacked: Bool { file != nil }
    var data: Data { buffer }
    init(file: AtomicFileWriter?, layout: TIFFContainer.Layout) {
      self.file = file
      self.layout = layout
      maximumBytes = file == nil ? TIFFContainer.byteLimit : layout.maximumFileBytes
    }
    func align() throws {
      let padding = layout.padding(at: count)
      if padding > 0 { try append(Data(repeating: 0, count: padding)) }
    }
    func append(_ bytes: Data) throws {
      guard bytes.count <= maximumBytes - count else {
        throw CraftError.invalid("TIFF output exceeds its file size limit.")
      }
      if let file { try file.append(bytes) } else { buffer.append(bytes) }
    }
    func patch(_ bytes: Data, at offset: Int) throws {
      if let file { try file.patch(bytes, at: offset) }
      else { buffer.replaceSubrange(offset..<offset + bytes.count, with: bytes) }
    }
  }

  static func encoded(_ document: CraftDocument, options: RasterEncodingOptions) throws -> Data {
    let output = Output(file: nil, layout: .init(bigTIFF: options.tiffBigTIFF == true))
    try write(document, options: options, output: output)
    return output.data
  }

  static func write(_ document: CraftDocument, to url: URL, options: RasterEncodingOptions) throws {
    let layout = TIFFContainer.Layout(bigTIFF: options.tiffBigTIFF == true)
    let file = try AtomicFileWriter(to: url, maximumBytes: layout.maximumFileBytes)
    defer { file.discard() }
    try write(document, options: options, output: Output(file: file, layout: layout))
    try file.commit()
  }

  static func encodedComposite(_ source: Data, document: CraftDocument?, resolution: Double,
    options: RasterEncodingOptions) throws -> Data {
    let output = Output(file: nil, layout: .init(bigTIFF: options.tiffBigTIFF == true))
    try completeComposite(source, document: document, resolution: resolution, options: options, output: output)
    return output.data
  }

  static func writeComposite(_ source: Data, document: CraftDocument, to url: URL,
    options: RasterEncodingOptions) throws {
    let layout = TIFFContainer.Layout(bigTIFF: options.tiffBigTIFF == true)
    let file = try AtomicFileWriter(to: url, maximumBytes: layout.maximumFileBytes)
    try completeComposite(source, document: document, resolution: document.pixelsPerInch,
      options: options, output: Output(file: file, layout: layout))
    try file.commit()
  }

  private static func completeComposite(_ source: Data, document: CraftDocument?, resolution: Double,
    options: RasterEncodingOptions, output: Output) throws {
    let container = try TIFFContainer(source, metadata: true)
    let order = container.order
    if output.layout.bigTIFF {
      try output.append(output.layout.header(order: order))
    } else { try output.append(source) }
    if options.tiffImagePyramid == true {
      let photometric = try container.scalar(262)
      guard let mode = TIFFModeStorage.mode(photometric),
        let geometry = try TIFFStorage.Geometry(container, allowAssociatedAlpha: true,
          colorComponents: mode.componentCount, photometric: photometric, allowSavedAlpha: true) else {
        throw CraftError.unsupported("Save Image Pyramid requires a supported component TIFF.")
      }
      let compression: RasterEncodingOptions.TIFFCompression =
        geometry.compression == 1 ? .none : geometry.compression == 5 ? .lzw : .zip
      let pyramid = TIFFImagePyramid(width: geometry.width, height: geometry.height,
        bits: geometry.bits, colors: mode.componentCount, opacity: geometry.opacitySample != nil,
        sourceChannels: geometry.channels, planar: geometry.planar, order: order,
        compression: compression, predictor: geometry.predictor == 3, photometric: photometric, output: output)
      try TIFFComponentRows.packedRows(container, geometry, components: geometry.planar ? 1 : geometry.channels) {
        try pyramid.append(plane: $0, samples: $1)
      }
      let opacity = geometry.opacitySample == nil ? nil : geometry.associated ? 1 : 2
      try pyramid.attach(to: container, resolution: resolution, opacity: opacity)
    }
    if output.layout.bigTIFF {
      let offsets = try container.numbers(273), lengths = try container.numbers(279)
      guard offsets.count == lengths.count else { throw CraftError.invalid("Invalid TIFF strip table.") }
      var newOffsets: [Int] = []
      for (offset, length) in zip(offsets, lengths) {
        try Task.checkCancellation()
        try output.align()
        newOffsets.append(output.count)
        try output.append(container.bytes(at: offset, count: length))
      }
      container.set(273, newOffsets, type: output.layout.offsetFieldType)
      container.set(279, lengths, type: output.layout.offsetFieldType)
    }
    if options.tiffLayers == true {
      guard let document else { throw CraftError.invalid("Layered TIFF encoding requires a document.") }
      try TIFFLayers.attach(document, to: container, order: order,
        compression: options.tiffLayerCompression ?? .zip, fileBacked: output.isFileBacked)
    }
    try finish(container, order: order, output: output)
  }

  private static func finish(_ container: TIFFContainer, order: TIFFContainer.Order, output: Output) throws {
    let offset = try container.writeDirectories(order: order, maximumOutput: output.maximumBytes, layout: output.layout,
      extent: { output.count }, emit: output.append, patch: output.patch)
    try output.patch(offset, at: output.layout.headerPointerOffset)
  }

  private static func write(_ document: CraftDocument, options: RasterEncodingOptions, output: Output) throws {
    try options.validate(for: .tiff)
    try document.validate()
    let width = document.width, height = document.height, depth = document.depth
    let rgb = document.modeDescriptor == nil && document.colorMode == .rgb
    let descriptor: DocumentModeDescriptor
    if let retained = document.modeDescriptor { descriptor = retained }
    else if rgb {
      let profile = try document.workingICC ?? NativeModeProfile.standard(.rgb, depth: depth)
      descriptor = try .init(mode: .rgb, depth: depth, profile: profile)
    } else { throw CraftError.invalid("Native TIFF output requires a component color mode.") }
    let bytesPerSample = depth == .u8 ? 1 : depth == .u16 ? 2 : 4
    let bits = bytesPerSample * 8, colors = descriptor.mode.componentCount
    let photometric = TIFFModeStorage.photometric(descriptor.mode)
    let compression = options.tiffCompression ?? .none
    let jpeg = compression == .jpeg
    if jpeg && !RasterEncodingOptions.supportsTIFFJPEG(width: width, height: height, depth: depth, mode: descriptor.mode) {
      throw CraftError.unsupported("JPEG-compressed TIFF requires RGB or Grayscale at 8 bits per channel and at most 30,000 pixels per side.")
    }
    if jpeg, options.tiffLayers == true, document.hasAuxiliaryChannels {
      throw CraftError.unsupported("JPEG-compressed TIFF cannot store saved selection channels. Choose lossless TIFF compression to retain them.")
    }
    let requiresOpaque = jpeg && options.tiffTransparency == nil
    let preserveAlpha = !jpeg && options.tiffTransparency != false
    let imageChannels = colors + (preserveAlpha ? 1 : 0)
    let savedAlpha: [AlphaChannel]
    if options.tiffLayers == true, document.hasAuxiliaryChannels {
      guard RasterIO.supportsLayeredTIFFSavedAlpha(document) else {
        throw CraftError.unsupported("Layered TIFF can retain saved alpha and spot channels in component color modes. Save Quick Mask in Photato, PSD or PSB.")
      }
      savedAlpha = document.alphaChannels ?? []
    } else { savedAlpha = [] }
    let savedRows = savedAlpha.map(PSDAuxiliaryChannels.storedRows)
    let channels = imageChannels + savedAlpha.count
    let planar = options.tiffPixelOrder == .perChannel
    let samplesPerRowPixel = planar ? 1 : channels
    let rowBytes = width * samplesPerRowPixel * bytesPerSample
    let predictor = options.tiffPredictor == true
    guard !predictor || depth == .f32 else {
      throw CraftError.invalid("TIFF floating-point predictor requires a 32-bit document.")
    }
    let matted = preserveAlpha || requiresOpaque ? nil : try GrayscaleNormalComposite(document, descriptor: descriptor)
    let retained = RasterIO.retainedFlatRaster(in: document, width: width, height: height)
    let rgbRows = rgb ? try TIFFRGBRows(document, transparency: preserveAlpha, requiresOpaque: requiresOpaque) : nil
    let renderer = !rgb && matted == nil && retained == nil ? try PSDModeCompositeRows(document) : nil
    let transparencyExtras = preserveAlpha ? [rgbRows?.associated == true ? 1 : 2] : []
    let extras = transparencyExtras + Array(repeating: 0, count: savedAlpha.count)
    let container = try directoryTemplate(document, options: options, descriptor: descriptor,
      bits: bits, channels: channels, photometric: photometric, extras: extras)
    let order: TIFFContainer.Order
    switch options.tiffByteOrder {
    case .bigEndian: order = .big
    case .littleEndian: order = .little
    case nil: order = options.tiffLayers == true ? .big : container.order
    }
    let pyramid = options.tiffImagePyramid == true
      ? TIFFImagePyramid(width: width, height: height, bits: bits, colors: colors, opacity: preserveAlpha,
          sourceChannels: channels, planar: planar, order: order, compression: compression,
          predictor: predictor, photometric: photometric, output: output, jpegQuality: options.tiffJPEGQuality)
      : nil
    let jpegEncoder = jpeg ? TIFFJPEGOutput(components: samplesPerRowPixel, quality: options.tiffJPEGQuality) : nil
    let rowsPerStrip = jpeg ? TIFFJPEGOutput.rowsPerStrip(height: height, rowBytes: rowBytes)
      : min(height, max(1, 65_536 / rowBytes))
    try output.append(output.layout.header(order: order))
    var offsets: [Int] = [], counts: [Int] = []

    func append(_ word: Int, to row: inout [UInt8]) {
      for byte in 0..<bytesPerSample {
        let shift = 8 * (order == .little ? byte : bytesPerSample - 1 - byte)
        row.append(UInt8(truncatingIfNeeded: word >> shift))
      }
    }
    func sample(_ raster: NativeModeRaster, _ index: Int, _ component: Int) -> Int {
      if raster.mode == .lab, component == 1 || component == 2 {
        let value = (Double(raster.value(component: component, index: index)) * 255 - 128)
          * (bytesPerSample == 1 ? 1 : 256)
        return Int(value.rounded())
      }
      return Int(raster.rawWord(component: component, index: index))
    }
    func savedAlphaRow(_ channel: Int, y: Int) throws -> [UInt8] {
      var samples: [UInt8]
      if let rows = savedRows[channel] { samples = try rows.row(y, channel: 0, depth: bits) }
      else { samples = try PSDAuxiliaryChannels.row(savedAlpha[channel], y: y, depth: bits) }
      if order == .little, bytesPerSample > 1 {
        for offset in stride(from: 0, to: samples.count, by: bytesPerSample) {
          samples[offset..<offset + bytesPerSample].reverse()
        }
      }
      return samples
    }
    func imageRow(y: Int, first: Int, end: Int) throws -> [UInt8] {
      try Task.checkCancellation()
      var row: [UInt8] = []
      row.reserveCapacity(rowBytes)
      func appendPixel(_ raster: NativeModeRaster, _ index: Int) throws {
        let alpha = preserveAlpha ? 0 : Int(raster.rawWord(component: colors, index: index))
        if requiresOpaque, alpha != 255 {
          throw CraftError.unsupported("JPEG-compressed TIFF requires an opaque composite. Turn off Save Transparency to use white.")
        }
        for component in first..<end {
          let word = sample(raster, index, component)
          let color = preserveAlpha ? word : TIFFStorage.whiteMatteSample(word, alpha: alpha, bits: bits,
            associated: false, white: photometric != 5 && (photometric != 8 || component == 0),
            signedChroma: photometric == 8 && component > 0)
          append(color, to: &row)
        }
      }
      if let rgbRows {
        row = try rgbRows.row(y, components: first..<end, order: order)
      } else if let matted {
        for x in 0..<width { append(Int(matted.whiteMattedSample(at: y * width + x)), to: &row) }
      } else if let retained {
        for x in 0..<width { try appendPixel(retained, y * width + x) }
      } else if let renderer {
        try renderer.forEachSample(inRow: y, appendPixel)
      }
      return row
    }
    func makeRow(y: Int, first: Int, end: Int) throws -> [UInt8] {
      if first >= imageChannels { return try savedAlphaRow(first - imageChannels, y: y) }
      let image = try imageRow(y: y, first: first, end: min(end, imageChannels))
      if end <= imageChannels { return image }
      let alpha = try savedAlpha.indices.map { try savedAlphaRow($0, y: y) }
      let imagePixelBytes = imageChannels * bytesPerSample
      var row: [UInt8] = []
      row.reserveCapacity(rowBytes)
      for x in 0..<width {
        let offset = x * imagePixelBytes
        row.append(contentsOf: image[offset..<offset + imagePixelBytes])
        let sample = x * bytesPerSample
        for plane in alpha { row.append(contentsOf: plane[sample..<sample + bytesPerSample]) }
      }
      return row
    }
    for plane in 0..<(planar ? channels : 1) {
      for y in stride(from: 0, to: height, by: rowsPerStrip) {
        let end = min(height, y + rowsPerStrip)
        let first = planar ? plane : 0, last = planar ? plane + 1 : channels
        var strip: [UInt8] = []
        strip.reserveCapacity(rowBytes * (end - y))
        for row in y..<end {
          let samples = try makeRow(y: row, first: first, end: last)
          try pyramid?.append(plane: plane, samples: samples)
          strip += predictor ? TIFFStorage.predict(samples, components: samplesPerRowPixel, order: order) : samples
        }
        try output.align()
        let start = output.count
        if let jpegEncoder { try output.append(jpegEncoder.encode(strip, width: width)) }
        else { try output.append(encodeStrip(strip, compression: compression)) }
        offsets.append(start)
        counts.append(output.count - start)
      }
    }
    container.set(259, [compression.tag]); container.set(273, offsets, type: output.layout.offsetFieldType)
    container.set(278, [rowsPerStrip], type: 4); container.set(279, counts, type: output.layout.offsetFieldType)
    container.set(284, [planar ? 2 : 1]); container.set(317, [predictor ? 3 : 1])
    jpegEncoder?.setYCbCrFields(on: container.root, order: container.order)
    try pyramid?.attach(to: container, resolution: document.pixelsPerInch, opacity: transparencyExtras.first)
    if options.tiffLayers == true {
      try TIFFLayers.attach(document, to: container, order: order,
        compression: options.tiffLayerCompression ?? .zip, fileBacked: output.isFileBacked)
    }
    try finish(container, order: order, output: output)
  }

  private static func directoryTemplate(_ document: CraftDocument, options: RasterEncodingOptions,
    descriptor: DocumentModeDescriptor, bits: Int, channels: Int, photometric: Int,
    extras: [Int]) throws -> TIFFContainer {
    let resolution = document.pixelsPerInch, depth = document.depth
    guard resolution.isFinite, (1...100_000).contains(resolution) else {
      throw CraftError.invalid("Native TIFF export requires a valid resolution.")
    }
    let template = try RasterIO.encoded(Surface(width: 1, height: 1, depth: depth), type: .tiff,
      resolution: resolution, outputDepth: depth, sourceMetadata: document.sourceMetadata,
      options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none))
    let file = try TIFFContainer(template, metadata: true)
    for tag in [301, 318, 319, 320, 322, 323, 324, 325, 330, 332, 333, 334, 336, 338, 347,
      529, 530, 531, 532, 34377, 37724] {
      file.root.fields.removeValue(forKey: tag)
    }
    file.root.next = nil
    file.set(256, [document.width], type: 4); file.set(257, [document.height], type: 4)
    file.set(258, Array(repeating: bits, count: channels)); file.set(262, [photometric]); file.set(277, [channels])
    file.set(339, Array(repeating: depth == .f32 ? 3 : 1, count: channels))
    if !extras.isEmpty { file.set(338, extras) }
    if descriptor.mode == .cmyk { file.set(332, [1]); file.set(334, [4]) }
    let embedsProfile = options.tiffEmbedProfile ?? (document.profileIsUntagged != true)
    if embedsProfile {
      let profile = descriptor.profile
      file.root.fields[34675] = .init(tag: 34675, type: 7, count: profile.count, data: profile)
    } else { UntaggedOutput.removeTIFFProfile(from: file) }
    let rgb = document.modeDescriptor == nil && descriptor.mode == .rgb
    let isSRGB = rgb ? try ColorManagement.space(for: document) == RasterIO.colorSpace() : false
    if let exif = file.root.fields[34665]?.children.first {
      exif.fields[40961] = .init(tag: 40961, type: 3, count: 1, data: file.order.bytes(isSRGB ? 1 : 65535, 2))
      exif.fields[40962] = .init(tag: 40962, type: 4, count: 1, data: file.order.bytes(document.width, 4))
      exif.fields[40963] = .init(tag: 40963, type: 4, count: 1, data: file.order.bytes(document.height, 4))
    }
    if let metadata = try RasterMetadata.metadata(document.sourceMetadata, width: document.width, height: document.height,
      resolution: resolution, linear: depth == .f32, profileName: rgb ? ColorManagement.name(document) : descriptor.mode.title,
      isSRGB: isSRGB, photoshopMode: PSDModeStorage.code(descriptor.mode), embedsProfile: embedsProfile),
      let bytes = CGImageMetadataCreateXMPData(metadata, nil) as Data? {
      file.root.fields[700] = .init(tag: 700, type: 1, count: bytes.count, data: bytes)
    }
    return file
  }

  fileprivate static func encodeStrip(_ strip: [UInt8], compression: RasterEncodingOptions.TIFFCompression) throws -> Data {
    switch compression {
    case .none: return Data(strip)
    case .lzw: return try TIFFLZW.encode(strip)
    case .zip:
      var length = compressBound(uLong(strip.count))
      var buffer = Data(count: Int(length))
      let status = buffer.withUnsafeMutableBytes { destination in
        strip.withUnsafeBufferPointer { source in
          compress2(destination.bindMemory(to: UInt8.self).baseAddress, &length, source.baseAddress,
            uLong(strip.count), Z_DEFAULT_COMPRESSION)
        }
      }
      guard status == Z_OK else { throw CraftError.invalid("TIFF ZIP compression failed.") }
      buffer.count = Int(length)
      return buffer
    case .jpeg: throw CraftError.invalid("JPEG TIFF requires an opaque strip with known geometry.")
    }
  }
}

/// Builds the chained reduced-resolution directories from the serialized image
/// samples. Only one pending input row and one strip are retained at each level.
private final class TIFFImagePyramid {
  private final class Level {
    let width: Int
    let height: Int
    let rowsPerStrip: Int
    let rowBytes: Int
    var pending: [UInt8]?
    var strip: [UInt8] = []
    var offsets: [Int] = []
    var counts: [Int] = []
    let jpegEncoder: TIFFJPEGOutput?

    init(width: Int, height: Int, bytesPerPixel: Int, jpegEncoder: TIFFJPEGOutput?) {
      self.width = width
      self.height = height
      rowBytes = width * bytesPerPixel
      self.jpegEncoder = jpegEncoder
      rowsPerStrip = jpegEncoder == nil ? min(height, max(1, 65_536 / rowBytes))
        : TIFFJPEGOutput.rowsPerStrip(height: height, rowBytes: rowBytes)
    }
  }

  private let levels: [Level]
  private let bits: Int
  private let bytesPerSample: Int
  private let mainChannels: Int
  private let sourceChannels: Int
  private let physicalChannels: Int
  private let planar: Bool
  private let order: TIFFContainer.Order
  private let compression: RasterEncodingOptions.TIFFCompression
  private let predictor: Bool
  private let photometric: Int
  private let output: TIFFComponentExport.Output
  private var currentPlane: Int?

  init(width: Int, height: Int, bits: Int, colors: Int, opacity: Bool, sourceChannels: Int,
    planar: Bool, order: TIFFContainer.Order, compression: RasterEncodingOptions.TIFFCompression,
    predictor: Bool, photometric: Int, output: TIFFComponentExport.Output, jpegQuality: Int? = nil) {
    self.bits = bits
    self.bytesPerSample = bits / 8
    self.mainChannels = colors + (opacity ? 1 : 0)
    self.sourceChannels = sourceChannels
    self.physicalChannels = planar ? 1 : mainChannels
    self.planar = planar
    self.order = order
    self.compression = compression
    self.predictor = predictor
    self.photometric = photometric
    self.output = output
    var w = width, h = height, built: [Level] = []
    for _ in 0..<3 {
      w = (w + 1) / 2
      h = (h + 1) / 2
      let encoder = compression == .jpeg ? TIFFJPEGOutput(components: physicalChannels, quality: jpegQuality) : nil
      built.append(Level(width: w, height: h, bytesPerPixel: physicalChannels * bytesPerSample, jpegEncoder: encoder))
    }
    levels = built
  }

  func append(plane: Int, samples: [UInt8]) throws {
    if planar && plane >= mainChannels { return }
    if let currentPlane, currentPlane != plane { try finishPlane(currentPlane) }
    currentPlane = plane
    if !planar && mainChannels != sourceChannels {
      let stride = sourceChannels * bytesPerSample, count = mainChannels * bytesPerSample
      var image: [UInt8] = []
      image.reserveCapacity(samples.count / stride * count)
      for x in Swift.stride(from: 0, to: samples.count, by: stride) {
        image.append(contentsOf: samples[x..<x + count])
      }
      try push(image, level: 0, plane: plane)
    } else {
      try push(samples, level: 0, plane: plane)
    }
  }

  private func push(_ row: [UInt8], level index: Int, plane: Int) throws {
    guard levels.indices.contains(index) else { return }
    let level = levels[index]
    if let top = level.pending {
      level.pending = nil
      try emit(top, row, level: index, plane: plane)
    } else { level.pending = row }
  }

  private func emit(_ top: [UInt8], _ bottom: [UInt8], level index: Int, plane: Int) throws {
    try Task.checkCancellation()
    let level = levels[index]
    let pixelBytes = physicalChannels * bytesPerSample, sourceWidth = top.count / pixelBytes
    var reduced: [UInt8] = []
    reduced.reserveCapacity(level.rowBytes)

    func word(_ row: [UInt8], x: Int, channel: Int) -> UInt32 {
      let offset = x * pixelBytes + channel * bytesPerSample
      var value: UInt32 = 0
      for b in 0..<bytesPerSample {
        value = value << 8 | UInt32(row[offset + (order == .big ? b : bytesPerSample - 1 - b)])
      }
      return value
    }

    for x in 0..<level.width {
      let left = x * 2, right = min(left + 1, sourceWidth - 1)
      for channel in 0..<physicalChannels {
        let a = word(top, x: left, channel: channel), b = word(top, x: right, channel: channel)
        let c = word(bottom, x: left, channel: channel), d = word(bottom, x: right, channel: channel)
        let value: UInt32
        if bits == 32 {
          let sum = Double(Float(bitPattern: a)) + Double(Float(bitPattern: b))
            + Double(Float(bitPattern: c)) + Double(Float(bitPattern: d))
          value = Float(sum / 4).bitPattern
        } else {
          let sample = planar ? plane : channel
          if photometric == 8 && (sample == 1 || sample == 2) {
            let bias: UInt32 = bits == 8 ? 0x80 : 0x8000
            value = (((a ^ bias) + (b ^ bias) + (c ^ bias) + (d ^ bias) + 2) / 4) ^ bias
          } else {
            value = (a + b + c + d + 2) / 4
          }
        }
        for b in 0..<bytesPerSample {
          let shift = 8 * (order == .big ? bytesPerSample - 1 - b : b)
          reduced.append(UInt8(truncatingIfNeeded: value >> shift))
        }
      }
    }
    let stored = predictor ? TIFFStorage.predict(reduced, components: physicalChannels, order: order) : reduced
    level.strip.append(contentsOf: stored)
    if level.strip.count == level.rowsPerStrip * level.rowBytes { try flush(level) }
    try push(reduced, level: index + 1, plane: plane)
  }

  private func flush(_ level: Level) throws {
    guard !level.strip.isEmpty else { return }
    try output.align()
    let encoded: Data
    if let jpegEncoder = level.jpegEncoder { encoded = try jpegEncoder.encode(level.strip, width: level.width) }
    else { encoded = try TIFFComponentExport.encodeStrip(level.strip, compression: compression) }
    level.offsets.append(output.count)
    level.counts.append(encoded.count)
    try output.append(encoded)
    level.strip.removeAll(keepingCapacity: true)
  }

  private func finishPlane(_ plane: Int) throws {
    for index in levels.indices {
      let level = levels[index]
      if let row = level.pending {
        level.pending = nil
        try emit(row, row, level: index, plane: plane)
      }
      try flush(level)
    }
  }

  func attach(to container: TIFFContainer, resolution: Double, opacity: Int?) throws {
    if let currentPlane { try finishPlane(currentPlane) }
    guard !levels.isEmpty else { return }
    func set(_ tag: Int, _ values: [Int], type: Int = 3, in node: TIFFContainer.Directory) {
      let count = type == 3 ? 2 : type == 16 ? 8 : 4
      node.fields[tag] = TIFFContainer.Field(tag: tag, type: type, count: values.count,
        data: values.reduce(into: Data()) { $0.append(container.order.bytes($1, count)) })
    }
    container.set(254, [0], type: 4)
    var first: TIFFContainer.Directory?, last: TIFFContainer.Directory?
    for (index, level) in levels.enumerated() {
      let node = TIFFContainer.Directory()
      set(254, [1], type: 4, in: node)
      set(256, [level.width], type: 4, in: node)
      set(257, [level.height], type: 4, in: node)
      set(258, Array(repeating: bits, count: mainChannels), in: node)
      set(259, [compression.tag], in: node)
      set(262, [photometric], in: node)
      set(273, level.offsets, type: output.layout.offsetFieldType, in: node)
      set(274, [1], in: node)
      set(277, [mainChannels], in: node)
      set(278, [level.rowsPerStrip], type: 4, in: node)
      set(279, level.counts, type: output.layout.offsetFieldType, in: node)
      let scale = Double(1 << (index + 1))
      let numerator = Int((resolution * 10_000 / scale).rounded())
      let dpi = container.order.bytes(numerator, 4) + container.order.bytes(10_000, 4)
      for tag in [282, 283] { node.fields[tag] = .init(tag: tag, type: 5, count: 1, data: dpi) }
      set(284, [planar ? 2 : 1], in: node)
      set(296, [2], in: node)
      if predictor { set(317, [3], in: node) }
      if let opacity { set(338, [opacity], in: node) }
      if bits == 32 { set(339, Array(repeating: 3, count: mainChannels), in: node) }
      for tag in [332, 334, 34675] { node.fields[tag] = container.root.fields[tag] }
      level.jpegEncoder?.setYCbCrFields(on: node, order: container.order)
      if let last { last.next = node } else { first = node }
      last = node
    }
    if let first {
      container.root.fields[330] = .init(tag: 330, type: 4, count: 1, data: Data(), children: [first])
    }
  }
}
