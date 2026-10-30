import CoreGraphics
import Foundation
import PhotoCraftCore

/// Immutable packed display buffer paired with its image. Regional updates only
/// convert/quantize changed pixels, then copy their rows into a COW byte buffer.
/// Keeping one full-size CGImage preserves Quartz filtering at every zoom level.
public struct CanvasRasterPreview: Sendable {
  public let base: CGImage
  public let documentRegion: IntRect
  let bytes: Data?
  public internal(set) var presentation: CanvasReducedPreview?
  public let repackedPixels: Int
  // Conservative admission: Data/CGDataProvider may share backing storage.
  public var allocatedBytes: Int { (bytes?.count ?? 0) + (presentation?.bytes.count ?? 0) }
  public init(base: CGImage, documentRegion: IntRect? = nil) {
    self.base = base
    self.documentRegion = documentRegion ?? IntRect(x: 0, y: 0, width: base.width, height: base.height)
    bytes = base.dataProvider?.data as Data?
    repackedPixels = base.width * base.height
  }
  private init(image: CGImage, bytes: Data, repackedPixels: Int) {
    base = image; documentRegion = IntRect(x: 0, y: 0, width: image.width, height: image.height); self.bytes = bytes; self.repackedPixels = repackedPixels
  }

  public func updating(_ snapshot: RenderSnapshot, scale: Double = 1) throws -> Self {
    var result = try updatingPixels(snapshot)
    result.presentation = try CanvasReducedPreview.make(image: result.base, bytes: result.bytes,
      scale: scale, damage: snapshot.update, previous: presentation)
    return result
  }
  public func scaled(to scale: Double) throws -> Self {
    var result = self
    result.presentation = try CanvasReducedPreview.make(image: base, bytes: bytes,
      scale: scale, damage: .full, previous: nil)
    return result
  }
  private func updatingPixels(_ snapshot: RenderSnapshot) throws -> Self {
    guard snapshot.surface.width == base.width, snapshot.surface.height == base.height,
      base.bitsPerComponent == 8, base.bitsPerPixel == 32, base.bytesPerRow == base.width * 4,
      base.alphaInfo == .last, let bytes, bytes.count == base.bytesPerRow * base.height
    else { return Self(base: try ColorManagement.displayImage(snapshot.surface, in: snapshot.document)) }
    switch snapshot.update {
    case .unchanged: return Self(image: base, bytes: bytes, repackedPixels: 0)
    case .full: return Self(base: try ColorManagement.displayImage(snapshot.surface, in: snapshot.document))
    case .region(let damage):
      let r = damage.clipped(toWidth: base.width, height: base.height)
      guard r.width > 0, r.height > 0 else { return Self(image: base, bytes: bytes, repackedPixels: 0) }
      let patch = try ColorManagement.displayImage(snapshot.surface.cropped(to: r), in: snapshot.document)
      guard let data = patch.dataProvider?.data, let source = CFDataGetBytePtr(data) else {
        throw CraftError.invalid("The display patch has no pixels.")
      }
      try Task.checkCancellation()
      var output = bytes
      output.withUnsafeMutableBytes { target in
        for row in 0..<r.height {
          target.baseAddress!.advanced(by: ((r.y + row) * base.width + r.x) * 4)
            .copyMemory(from: source.advanced(by: row * patch.bytesPerRow), byteCount: r.width * 4)
        }
      }
      try Task.checkCancellation()
      guard let provider = CGDataProvider(data: output as CFData),
        let image = CGImage(width: base.width, height: base.height, bitsPerComponent: 8,
          bitsPerPixel: 32, bytesPerRow: base.bytesPerRow, space: try RasterIO.colorSpace(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
          decode: nil, shouldInterpolate: true, intent: .relativeColorimetric)
      else { throw CraftError.invalid("Could not create the display preview.") }
      return Self(image: image, bytes: output, repackedPixels: r.width * r.height)
    }
  }
  /// The caller supplies top-left document coordinates, with its ordinary zoom filter.
  public func draw(in context: CGContext) {
    context.saveGState()
    context.translateBy(x: CGFloat(documentRegion.x), y: CGFloat(documentRegion.y + documentRegion.height))
    context.scaleBy(x: 1, y: -1)
    context.draw(presentation?.image ?? base, in: CGRect(x: 0, y: 0, width: documentRegion.width, height: documentRegion.height))
    context.restoreGState()
  }
}
