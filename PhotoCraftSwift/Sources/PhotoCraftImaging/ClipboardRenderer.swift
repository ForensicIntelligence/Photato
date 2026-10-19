import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers

public enum ClipboardRenderer {
  public static func copy(_ document: CraftDocument, layerIDs: Set<UUID>, merged: Bool = false)
    throws -> ClipboardContent
  {
    try document.validate()
    if !merged && document.selection == nil {
      guard !layerIDs.isEmpty,
        layerIDs.allSatisfy({ id in document.layers.contains { $0.id == id } })
      else {
        throw CraftError.invalid("Select a layer to copy.")
      }
      let ids = layerIDs.reduce(into: Set<UUID>()) { $0.formUnion(document.subtreeIDs($1)) }
      var copied = document
      copied.layers = document.layers.filter { ids.contains($0.id) }
      copied.selection = nil
      copied.selectionMask = nil
      copied.paths = nil
      copied.sourceMetadata = nil
      copied.activeLayerID =
        ids.contains(document.activeLayerID ?? UUID())
        ? document.activeLayerID : copied.layers.last?.id
      var bounds: IntRect?
      for index in copied.layers.indices {
        if let parent = copied.layers[index].parentID, !ids.contains(parent) {
          copied.layers[index].parentID = nil
        }
        if case .text(var text) = copied.layers[index].content {
          text.layoutWidth = text.layoutWidth ?? document.width
          text.layoutHeight = text.layoutHeight ?? document.height
          copied.layers[index].content = .text(text)
        }
        let layer = copied.layers[index]
        if layer.isGroup { continue }
        let area: IntRect
        switch layer.content {
        case .fill, .patternFill, .gradientFill, .adjustment:
          area = IntRect(x: 0, y: 0, width: document.width, height: document.height)
        default:
          let pixels = try Renderer.layerSurface(layer, in: document)
          area = try layer.coordinateTransform.bounds(width: pixels.width, height: pixels.height)
        }
        if let old = bounds {
          let x = min(old.x, area.x)
          let y = min(old.y, area.y)
          bounds = IntRect(
            x: x, y: y,
            width: max(old.x + old.width, area.x + area.width) - x,
            height: max(old.y + old.height, area.y + area.height) - y)
        } else {
          bounds = area
        }
      }
      return try ClipboardContent(
        kind: .layers, document: copied,
        bounds: bounds ?? IntRect(x: 0, y: 0, width: document.width, height: document.height))
    }
    let pixels: Surface
    let inverse: Transform2D
    if merged {
      pixels = try Renderer.composite(document)
      inverse = .identity
    } else {
      guard layerIDs.count == 1, let id = layerIDs.first,
        let layer = document.layers.first(where: { $0.id == id })
      else {
        throw CraftError.unsupported("Copy a pixel selection from one layer, or use Copy Merged.")
      }
      pixels = try Renderer.layerSurface(layer, in: document)
      if layer.isGroup {
        inverse = .identity
      } else if layer.isCanvasFill {
        inverse = .identity
      } else {
        inverse = try layer.coordinateTransform.inverted()
      }
    }
    let area =
      document.selection ?? IntRect(x: 0, y: 0, width: document.width, height: document.height)
    var extracted = try Surface(width: area.width, height: area.height, depth: document.depth)
    var x0 = area.width
    var y0 = area.height
    var x1 = -1
    var y1 = -1
    for y in 0..<area.height {
      try Task.checkCancellation()
      for x in 0..<area.width {
        let px = x + area.x
        let py = y + area.y
        let local = inverse.point(Double(px) + 0.5, Double(py) + 0.5)
        // Copy aligned pixels directly: even a zero-weight premultiply/unpremultiply
        // interpolation round-trip can change Float bits and discard hidden colors.
        let alignedX = local.x - 0.5
        let alignedY = local.y - 0.5
        var value =
          abs(alignedX) < 10_000_000 && abs(alignedY) < 10_000_000
            && alignedX == alignedX.rounded() && alignedY == alignedY.rounded()
          ? pixels.pixel(x: Int(alignedX), y: Int(alignedY))
          : RasterGeometry.sample(pixels, x: local.x, y: local.y, method: .bilinear)
        value.a *= document.selectionCoverage(x: px, y: py)
        value = value.quantized(document.depth)
        if value.a > 0 {
          x0 = min(x0, x)
          x1 = max(x1, x)
          y0 = min(y0, y)
          y1 = max(y1, y)
        }
        if value != .clear { extracted.setPixel(x: x, y: y, value) }
      }
    }
    guard x1 >= x0, y1 >= y0 else {
      throw CraftError.invalid("Could not copy because the selected area is empty.")
    }
    var trimmed = try Surface(width: x1 - x0 + 1, height: y1 - y0 + 1, depth: document.depth)
    for y in 0..<trimmed.height {
      try Task.checkCancellation()
      for x in 0..<trimmed.width {
        let value = extracted.pixel(x: x + x0, y: y + y0)
        if value != .clear { trimmed.setPixel(x: x, y: y, value) }
      }
    }
    return try .pixels(
      trimmed, x: area.x + x0, y: area.y + y0,
      resolution: document.pixelsPerInch)
  }
  public static func preview(_ content: ClipboardContent) throws -> Surface {
    if content.kind == .pixels, case .raster(let pixels) = content.document.layers[0].content {
      return pixels
    }
    if content.document.layers.count == 1, let layer = content.document.layers.first,
      layer.visible, layer.opacity == 1, layer.blendMode == .normal, !layer.isClipped,
      layer.mask == nil, layer.vectorMask == nil, layer.affine == nil,
      case .raster(let pixels) = layer.content,
      pixels.width == content.bounds.width, pixels.height == content.bounds.height,
      layer.x == content.bounds.x, layer.y == content.bounds.y
    {
      return try pixels.converted(to: content.document.depth)
    }
    return try Renderer.composite(content.newDocument(name: "Clipboard"))
      .converted(to: content.document.depth)
  }
  public static func flattened(_ content: ClipboardContent) throws -> ClipboardContent {
    if content.kind == .pixels { return content }
    return try .pixels(
      preview(content), x: content.bounds.x, y: content.bounds.y,
      resolution: content.document.pixelsPerInch)
  }
  /// TIFF retains source component precision; PNG is an SDR fallback.
  /// The private native representation remains authoritative for lossless layer/sample transfer.
  public static func imageData(_ surface: Surface, type: UTType) throws -> Data {
    guard type == .tiff || type == .png else {
      throw CraftError.invalid("Unsupported clipboard format.")
    }
    let image = try type == .tiff ? tiffImage(surface) : RasterIO.displayImage(surface)
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
    else { throw CraftError.invalid("Clipboard image encoder unavailable.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw CraftError.invalid("Could not encode the clipboard image.")
    }
    return data as Data
  }
  private static func tiffImage(_ surface: Surface) throws -> CGImage {
    if surface.depth == .f32 { return try RasterIO.cgImage(surface) }
    if surface.depth == .u8 { return try RasterIO.displayImage(surface) }
    let data = try surface.rgbaData(depth: .u16)
    guard let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(
        width: surface.width, height: surface.height,
        bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: surface.width * 8,
        space: try RasterIO.colorSpace(),
        bitmapInfo: [.byteOrder16Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)],
        provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric)
    else { throw CraftError.invalid("Could not create the 16-bit clipboard image.") }
    return image
  }

  public static func readImage(_ data: Data) throws -> ClipboardContent {
    guard data.count <= 512 * 1024 * 1024,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
      throw CraftError.invalid("Clipboard does not contain a supported image.")
    }
    _ = try Surface(width: width, height: height)
    guard
      let image = CGImageSourceCreateImageAtIndex(
        source, 0,
        [kCGImageSourceShouldCache: false] as CFDictionary)
    else {
      throw CraftError.invalid("Could not decode the clipboard image.")
    }
    let depth: PixelDepth =
      image.bitsPerComponent > 16 ? .f32 : image.bitsPerComponent > 8 ? .u16 : .u8
    let pixels = try RasterIO.oriented(
      RasterIO.surface(image, depth: depth),
      orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1)
    return try .pixels(pixels)
  }
}
