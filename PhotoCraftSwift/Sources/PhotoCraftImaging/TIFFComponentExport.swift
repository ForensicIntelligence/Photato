import Foundation
import CoreGraphics
import ImageIO
import PhotoCraftCore
import zlib

/// Classic TIFF component output. Only a strip and the small IFD tables remain
/// in memory when writing to a file. The same encoder can target bounded API Data.
enum TIFFComponentExport {
  private final class Output {
    private var buffer = Data()
    private let file: AtomicFileWriter?
    let maximumBytes: Int
    var count: Int { file?.count ?? buffer.count }
    var data: Data { buffer }
    init(file: AtomicFileWriter?) {
      self.file = file
      maximumBytes = file == nil ? TIFFContainer.byteLimit : TIFFContainer.classicFileMaximumBytes
    }
    func append(_ bytes: Data) throws {
      guard bytes.count <= maximumBytes - count else {
        throw CraftError.invalid("TIFF output exceeds its file size limit.")
      }
      if let file { try file.append(bytes) } else { buffer.append(bytes) }
    }
    func finish(_ headerOffset: Data) throws {
      if let file { try file.patch(headerOffset, at: 4) }
      else { buffer.replaceSubrange(4..<8, with: headerOffset) }
    }
  }

  static func encoded(_ document: CraftDocument, options: RasterEncodingOptions) throws -> Data {
    let output = Output(file: nil)
    try write(document, options: options, output: output)
    return output.data
  }

  static func write(_ document: CraftDocument, to url: URL, options: RasterEncodingOptions) throws {
    let file = try AtomicFileWriter(to: url, maximumBytes: TIFFContainer.classicFileMaximumBytes)
    defer { file.discard() }
    try write(document, options: options, output: Output(file: file))
    try file.commit()
  }

  private static func write(_ document: CraftDocument, options: RasterEncodingOptions, output: Output) throws {
    try options.validate(for: .tiff)
    try document.validate()
    guard let descriptor = document.modeDescriptor else {
      throw CraftError.invalid("Native TIFF output requires a component color mode.")
    }
    let width = document.width, height = document.height, depth = document.depth
    let bytesPerSample = depth == .u8 ? 1 : depth == .u16 ? 2 : 4
    let bits = bytesPerSample * 8, colors = descriptor.mode.componentCount
    let photometric = TIFFModeStorage.photometric(descriptor.mode)
    let preserveAlpha = options.tiffTransparency != false
    let channels = colors + (preserveAlpha ? 1 : 0)
    let planar = options.tiffPixelOrder == .perChannel
    let samplesPerRowPixel = planar ? 1 : channels
    let rowBytes = width * samplesPerRowPixel * bytesPerSample
    let compression = options.tiffCompression ?? .none, predictor = options.tiffPredictor == true
    guard !predictor || depth == .f32 else {
      throw CraftError.invalid("TIFF floating-point predictor requires a 32-bit document.")
    }
    let matted = preserveAlpha ? nil : try GrayscaleNormalComposite(document, descriptor: descriptor)
    let retained = RasterIO.retainedFlatRaster(in: document, width: width, height: height)
    let renderer = matted == nil && retained == nil ? try PSDModeCompositeRows(document) : nil
    let container = try directoryTemplate(document, options: options, descriptor: descriptor,
      bits: bits, colors: colors, channels: channels, photometric: photometric)
    let order: TIFFContainer.Order
    switch options.tiffByteOrder {
    case .bigEndian: order = .big
    case .littleEndian: order = .little
    case nil: order = options.tiffLayers == true ? .big : container.order
    }
    let rowsPerStrip = min(height, max(1, 65_536 / rowBytes))
    try output.append(Data(order == .big ? [77, 77, 0, 42, 0, 0, 0, 0] : [73, 73, 42, 0, 0, 0, 0, 0]))
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
    func makeRow(y: Int, first: Int, end: Int) throws -> [UInt8] {
      try Task.checkCancellation()
      var row: [UInt8] = []
      row.reserveCapacity(rowBytes)
      func appendPixel(_ raster: NativeModeRaster, _ index: Int) {
        let alpha = preserveAlpha ? 0 : Int(raster.rawWord(component: colors, index: index))
        for component in first..<end {
          let word = sample(raster, index, component)
          let color = preserveAlpha ? word : TIFFStorage.whiteMatteSample(word, alpha: alpha, bits: bits,
            associated: false, white: photometric != 5 && (photometric != 8 || component == 0),
            signedChroma: photometric == 8 && component > 0)
          append(color, to: &row)
        }
      }
      if let matted {
        for x in 0..<width { append(Int(matted.whiteMattedSample(at: y * width + x)), to: &row) }
      } else if let retained {
        for x in 0..<width { appendPixel(retained, y * width + x) }
      } else if let renderer {
        try renderer.forEachSample(inRow: y, appendPixel)
      }
      return predictor ? TIFFStorage.predict(row, components: samplesPerRowPixel, order: order) : row
    }
    for plane in 0..<(planar ? channels : 1) {
      for y in stride(from: 0, to: height, by: rowsPerStrip) {
        if output.count % 2 != 0 { try output.append(Data([0])) }
        let start = output.count
        let end = min(height, y + rowsPerStrip)
        let first = planar ? plane : 0, last = planar ? plane + 1 : channels
        var strip: [UInt8] = []
        strip.reserveCapacity(rowBytes * (end - y))
        for row in y..<end { strip += try makeRow(y: row, first: first, end: last) }
        try output.append(encodeStrip(strip, compression: compression))
        offsets.append(start)
        counts.append(output.count - start)
      }
    }
    container.set(259, [compression.tag]); container.set(273, offsets, type: 4)
    container.set(278, [rowsPerStrip], type: 4); container.set(279, counts, type: 4)
    container.set(284, [planar ? 2 : 1]); container.set(317, [predictor ? 3 : 1])
    if options.tiffLayers == true {
      try TIFFLayers.attach(document, to: container, order: order, compression: options.tiffLayerCompression ?? .zip)
    }
    let directory = try container.detachedDirectories(start: output.count, order: order, maximumOutput: output.maximumBytes)
    try output.append(directory.payload)
    try output.finish(directory.offset)
  }

  private static func directoryTemplate(_ document: CraftDocument, options: RasterEncodingOptions,
    descriptor: DocumentModeDescriptor, bits: Int, colors: Int, channels: Int, photometric: Int) throws -> TIFFContainer {
    let resolution = document.pixelsPerInch, depth = document.depth
    guard resolution.isFinite, (1...100_000).contains(resolution) else {
      throw CraftError.invalid("Native TIFF export requires a valid resolution.")
    }
    let template = try RasterIO.encoded(Surface(width: 1, height: 1, depth: depth), type: .tiff,
      resolution: resolution, outputDepth: depth, sourceMetadata: document.sourceMetadata,
      options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none))
    let file = try TIFFContainer(template, metadata: true)
    for tag in [301, 318, 319, 320, 330, 332, 333, 334, 336, 338, 34377, 37724] { file.root.fields.removeValue(forKey: tag) }
    file.root.next = nil
    file.set(256, [document.width], type: 4); file.set(257, [document.height], type: 4)
    file.set(258, Array(repeating: bits, count: channels)); file.set(262, [photometric]); file.set(277, [channels])
    file.set(339, Array(repeating: depth == .f32 ? 3 : 1, count: channels))
    if channels > colors { file.set(338, [2]) }
    if descriptor.mode == .cmyk { file.set(332, [1]); file.set(334, [4]) }
    let embedsProfile = options.tiffEmbedProfile ?? (document.profileIsUntagged != true)
    if embedsProfile {
      let profile = descriptor.profile
      file.root.fields[34675] = .init(tag: 34675, type: 7, count: profile.count, data: profile)
    } else { UntaggedOutput.removeTIFFProfile(from: file) }
    if let exif = file.root.fields[34665]?.children.first {
      exif.fields[40961] = .init(tag: 40961, type: 3, count: 1, data: file.order.bytes(65535, 2))
      exif.fields[40962] = .init(tag: 40962, type: 4, count: 1, data: file.order.bytes(document.width, 4))
      exif.fields[40963] = .init(tag: 40963, type: 4, count: 1, data: file.order.bytes(document.height, 4))
    }
    if let metadata = try RasterMetadata.metadata(document.sourceMetadata, width: document.width, height: document.height,
      resolution: resolution, linear: depth == .f32, profileName: descriptor.mode.title,
      isSRGB: false, photoshopMode: PSDModeStorage.code(descriptor.mode), embedsProfile: embedsProfile),
      let bytes = CGImageMetadataCreateXMPData(metadata, nil) as Data? {
      file.root.fields[700] = .init(tag: 700, type: 1, count: bytes.count, data: bytes)
    }
    return file
  }

  private static func encodeStrip(_ strip: [UInt8], compression: RasterEncodingOptions.TIFFCompression) throws -> Data {
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
    }
  }
}
