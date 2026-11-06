import CoreGraphics
import Foundation
import PhotoCraftCore

public enum VectorRasterizer {
  public static func outline(_ path:VectorPath)throws->CGPath {try VectorPathGeometry.outline(path)}
  public static func filledPath(_ path:VectorPath)throws->CGPath {try VectorPathGeometry.filledPath(path)}
  public static func coverage(
    _ path: VectorPath, width: Int, height: Int,
    origin: PathPoint = PathPoint(0, 0), antiAlias: Bool = true,
    emptyRevealsAll: Bool = false
  ) throws -> SelectionMask {
    _ = try Surface(width: width, height: height)
    try path.validate()
    if width > Surface.maximumDensePixels/height {
      return try SelectionMask(coverage:pagedCoverage(path,width:width,height:height,
        origin:origin,antiAlias:antiAlias,emptyRevealsAll:emptyRevealsAll))
    }
    if path.isEmpty {
      let value: UInt8 = (emptyRevealsAll != path.inverted) ? 255 : 0
      return try SelectionMask(
        width: width, height: height,
        bytes: [UInt8](repeating: value, count: width * height))
    }
    guard
      let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = context.data
    else {
      throw CraftError.invalid("Could not rasterize the path.")
    }
    context.setShouldAntialias(antiAlias)
    context.setAllowsAntialiasing(antiAlias)
    context.translateBy(x: 0, y: Double(height))
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: -origin.x, y: -origin.y)
    context.setFillColor(gray: 1, alpha: 1)
    context.addPath(try filledPath(path))
    context.fillPath()
    var bytes = Array(
      UnsafeBufferPointer(
        start: data.assumingMemoryBound(to: UInt8.self),
        count: width * height))
    if path.inverted { for i in bytes.indices { bytes[i] = 255 - bytes[i] } }
    return try SelectionMask(width: width, height: height, bytes: bytes)
  }
}

/// Pixel and vector masks retain independent density/feather controls and multiply coverage.
public struct LayerMaskSampler: Sendable {
  private var pixel: MaskSampler?
  private var vector: MaskSampler?
  /// Available only for aligned, unfeathered paged vector coverage.
  var vectorTileSource: Surface?
  /// `pixelRegion` permits identity elision only for integer pixel-center renders.
  /// General callers (hit testing, for example) retain continuous edge coverage.
  public static func make(layer: Layer, document: CraftDocument, pixelRegion: IntRect? = nil) throws
    -> Self?
  {
    guard layer.mask != nil || layer.vectorMask != nil else { return nil }
    let sampler = try Self(layer: layer, document: document)
    if let region = pixelRegion,
      (sampler.pixel?.isIdentity(over: region) ?? true)
        && (sampler.vector?.isIdentity(over: region) ?? true)
    {
      return nil
    }
    return sampler
  }
  public init(layer: Layer, document: CraftDocument) throws {
    pixel = try layer.mask.map { _ in
      try MaskSampler(layer: layer, canvasSize: (document.width, document.height))
    }
    guard let mask = layer.vectorMask, mask.enabled else { return }
    try mask.validate()
    if document.width > Surface.maximumDensePixels/document.height {
      guard mask.feather==0 else {throw CraftError.unsupported("Large feathered vector masks still require bounded kernel preparation.")}
      let surface=try VectorRasterizer.pagedCoverage(mask.path,width:document.width,
        height:document.height,emptyRevealsAll:true)
      var prepared=Layer(name:"Paged vector coverage",content:.fill(.clear));prepared.mask=surface
      var properties=MaskProperties();properties.density=mask.density
      properties.outside=mask.path.isEmpty ? (mask.path.inverted ? 0:1):(mask.path.inverted ? 1:0)
      prepared.maskProperties=properties;vectorTileSource=surface
      vector=try MaskSampler(layer:prepared);return
    }
    let pad = Int(ceil(mask.feather * 3))
    let width = document.width + 2 * pad
    let height = document.height + 2 * pad
    let coverage = try VectorRasterizer.coverage(
      mask.path, width: width, height: height,
      origin: PathPoint(-Double(pad), -Double(pad)), emptyRevealsAll: true)
    let outside: Float =
      mask.path.isEmpty ? (mask.path.inverted ? 0 : 1) : (mask.path.inverted ? 1 : 0)
    var surface = try Surface(
      width: width, height: height, depth: .u8,
      fill: Pixel(outside, outside, outside))
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let value = coverage.coverage(x: x, y: y)
        if value != outside { surface.setPixel(x: x, y: y, Pixel(value, value, value)) }
      }
    }
    var prepared = Layer(name: "Vector coverage", content: .fill(.clear))
    prepared.x = -pad
    prepared.y = -pad
    prepared.mask = surface
    var properties = MaskProperties()
    properties.density = mask.density
    properties.feather = mask.feather
    properties.outside = outside
    prepared.maskProperties = properties
    vector = try MaskSampler(layer: prepared)
  }
  public func coverage(x: Double, y: Double) -> Float {
    (pixel?.coverage(x: x, y: y) ?? 1) * (vector?.coverage(x: x, y: y) ?? 1)
  }
}
