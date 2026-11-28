import Foundation
import PhotoCraftCore

/// Packs bounded RGB regions through the native TIFF encoder to retain the same
/// associated integer alpha and straight Float32 samples as ordinary exports.
final class TIFFRGBRows {
  private let document: CraftDocument
  private let prepared: CraftDocument
  private let video: VideoTransitionRenderContext?
  private let facts: CompositionFacts?
  private let options: RasterEncodingOptions
  private let channels: Int
  private let bytesPerSample: Int
  private let requiresOpaque: Bool
  private let useRGB16WhiteMatte: Bool
  let associated: Bool
  private var start = -1
  private var height = 0
  private var packedRows: [[UInt8]] = []

  static func supportsWhiteMatte(_ document: CraftDocument) -> Bool {
    document.depth == .u16 && document.artboardOrigin == nil && Renderer.usesIntegerNormalRasterComposite(document)
      && document.layers.contains { $0.visible && $0.opacity > 0 }
  }

  init(_ document: CraftDocument, transparency: Bool, requiresOpaque: Bool = false) throws {
    self.document = document
    self.requiresOpaque = requiresOpaque
    useRGB16WhiteMatte = !transparency && !requiresOpaque && Self.supportsWhiteMatte(document)
    (prepared, video) = try Renderer.preparedSources(document)
    facts = document.width > Surface.maximumDensePixels / document.height ? CompositionFacts(prepared) : nil
    bytesPerSample = document.depth == .u8 ? 1 : document.depth == .u16 ? 2 : 4
    channels = transparency ? 4 : 3
    associated = transparency && document.depth != .f32
    options = RasterEncodingOptions(tiffCompression: RasterEncodingOptions.TIFFCompression.none,
      tiffByteOrder: .bigEndian, tiffTransparency: transparency)
  }

  func row(_ y: Int, components: Range<Int>, order: TIFFContainer.Order) throws -> [UInt8] {
    if y < start || y >= start + height { try prepare(y) }
    let source = packedRows[y - start]
    if components.count == channels && order == .big { return source }
    var result: [UInt8] = []
    result.reserveCapacity(document.width * components.count * bytesPerSample)
    for x in 0..<document.width {
      let base = x * channels * bytesPerSample
      for channel in components {
        let offset = base + channel * bytesPerSample
        for byte in 0..<bytesPerSample {
          result.append(source[offset + (order == .big ? byte : bytesPerSample - 1 - byte)])
        }
      }
    }
    return result
  }

  private func prepare(_ firstRow: Int) throws {
    start = firstRow
    height = min(document.height - firstRow, max(1, min(64, PSDCompositeRows.preferredBandPixels / document.width)))
    packedRows = [[UInt8]](repeating: [], count: height)
    let bandRowBytes = document.width * channels * bytesPerSample
    for y in packedRows.indices { packedRows[y].reserveCapacity(bandRowBytes) }
    for left in stride(from: 0, to: document.width, by: 2048) {
      try Task.checkCancellation()
      let bounds = IntRect(x: left, y: firstRow, width: min(2048, document.width - left), height: height)
      if useRGB16WhiteMatte, let patch = try LayerMerge.integerModeComposite(prepared,
        region: bounds, promoteRGB16Opacity: true) {
        for y in 0..<height {
          try Task.checkCancellation()
          for x in 0..<bounds.width {
            let rgb = NormalLayerComposite.whiteMattedRGB16(patch.pixel(x: x, y: y))
            for channel in 0..<3 {
              packedRows[y].append(UInt8(rgb[channel] >> 8))
              packedRows[y].append(UInt8(truncatingIfNeeded: rgb[channel]))
            }
          }
        }
        continue
      }
      let rendered = try Renderer.compositePrepared(prepared, region: bounds, video: video, facts: facts)
      let patch = try rendered.cropped(to: bounds)
      if requiresOpaque, try !patch.isOpaque() {
        throw CraftError.unsupported("JPEG-compressed TIFF requires an opaque composite. Turn off Save Transparency to use white.")
      }
      let bytes = try RasterIO.encoded(patch, type: .tiff, resolution: document.pixelsPerInch,
        outputDepth: document.depth, workingDocument: document, options: options)
      let file = try TIFFContainer(bytes, metadata: false)
      guard file.order == .big, let g = try TIFFStorage.Geometry(file, allowAssociatedAlpha: true),
        g.width == bounds.width, g.height == bounds.height, g.channels == channels, g.bits == bytesPerSample * 8,
        g.compression == 1, !g.planar, g.predictor == 1, g.associated == associated else {
        throw CraftError.invalid("The packed RGB TIFF region has an unexpected sample layout.")
      }
      let rowBytes = g.width * channels * bytesPerSample
      for row in 0..<height {
        let strip = row / g.rows
        let offset = g.offsets[strip] + row % g.rows * rowBytes
        packedRows[row].append(contentsOf: try file.bytes(at: offset, count: rowBytes))
      }
    }
  }
}
