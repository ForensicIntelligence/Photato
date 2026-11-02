import Foundation

/// Geometry operates on palette indices and packed bits. Exact grid transforms
/// retain sample identity even when several palette entries have the same RGB.
public enum RestrictedModeGeometry {
  public static func transformed(_ raster: RestrictedModeRaster, by transform: Transform2D,
    width: Int, height: Int, method: Resampling = .nearest, fill: Pixel? = nil,
    clampEdges: Bool = false) throws -> RestrictedModeRaster {
    try raster.validate(); try IndexedRaster.validateDimensions(width, height)
    let inverse = try transform.inverted()
    guard fill?.isFinite != false else { throw CraftError.invalid("Invalid restricted-mode fill color.") }
    let grid = [transform.a, transform.b, transform.c, transform.d].allSatisfy { [-1.0, 0, 1].contains($0) }
      && abs(transform.a * transform.d - transform.b * transform.c) == 1
      && transform.tx.rounded() == transform.tx && transform.ty.rounded() == transform.ty
      && abs(transform.a) + abs(transform.c) == 1 && abs(transform.b) + abs(transform.d) == 1
    let direct = method == .nearest || grid
    let surface = direct ? nil : try raster.surface()
    var result = Data(count: raster.mode == .indexed ? width * height : ((width + 7) / 8) * height)
    func mappedColor(_ pixel: Pixel, _ indexed: IndexedRaster) -> UInt8 {
      if pixel.a < 0.5, let transparent = indexed.transparentIndex { return UInt8(transparent) }
      let rgb = indexed.transparentIndex == nil
        ? SIMD3(pixel.r * pixel.a + 1 - pixel.a, pixel.g * pixel.a + 1 - pixel.a, pixel.b * pixel.a + 1 - pixel.a)
        : SIMD3(pixel.r, pixel.g, pixel.b)
      return UInt8(PaletteQuantization.nearest(indexed.palette, rgb, excluding: indexed.transparentIndex))
    }
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      var point = inverse.point(Double(x) + 0.5, Double(y) + 0.5)
      if clampEdges { point.x = min(Double(raster.width) - 0.5, max(0.5, point.x)); point.y = min(Double(raster.height) - 0.5, max(0.5, point.y)) }
      let inside = point.x >= 0 && point.y >= 0 && point.x < Double(raster.width) && point.y < Double(raster.height)
      switch raster {
      case .indexed(let indexed):
        let index: UInt8
        if inside && direct { index = indexed.indices[Int(floor(point.y)) * raster.width + Int(floor(point.x))] }
        else {
          let pixel = inside ? RasterGeometry.sample(surface!, x: point.x, y: point.y, method: method, clampEdges: clampEdges) : fill ?? (indexed.transparentIndex == nil ? .white : .clear)
          guard indexed.palette.count > 1 || indexed.transparentIndex == nil || pixel.a < 0.5 else { throw CraftError.invalid("The color table has no opaque entry for this fill.") }
          index = mappedColor(pixel, indexed)
        }
        result[y * width + x] = index
      case .bitmap(let bitmap):
        let black: Bool
        if inside && direct { black = bitmap.isBlack(x: Int(floor(point.x)), y: Int(floor(point.y))) }
        else {
          let p = inside ? RasterGeometry.sample(surface!, x: point.x, y: point.y, method: method, clampEdges: clampEdges) : fill ?? .white
          black = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) * p.a + 1 - p.a < 0.5
        }
        if black { result[y * ((width + 7) / 8) + x / 8] |= 0x80 >> (x % 8) }
      }
    } }
    switch raster {
    case .indexed(let old): return .indexed(try IndexedRaster(width: width, height: height, palette: old.palette, indices: result, transparentIndex: old.transparentIndex, profile: old.profile))
    case .bitmap: return .bitmap(try BitmapRaster(width: width, height: height, bits: result))
    }
  }
  public static func document(_ original: CraftDocument, by transform: Transform2D,
    width: Int, height: Int, method: Resampling = .nearest, fill: Pixel? = nil,
    clampEdges: Bool = false, clearSelection: Bool = false) throws -> CraftDocument {
    try original.validate()
    guard let raster = original.restrictedMode else { throw CraftError.invalid("Restricted-mode geometry requires indexed or one-bit samples.") }
    let changed = try transformed(raster, by: transform, width: width, height: height, method: method, fill: fill, clampEdges: clampEdges)
    var result = original; result.width = width; result.height = height; result.restrictedMode = changed
    result.layers[0].content = .raster(try changed.surface())
    result.transformSavedPaths(by: transform)
    try result.mapGuides( transform)
    if clearSelection { result.setCoverageSelection(nil) } else { try result.mapSelection(from: original, by: transform) }
    try result.validate(); return result
  }
  /// Returns false for unrelated commands so the ordinary modular engine keeps
  /// its protection, layer and atomic-invariant checks.
  static func apply(_ command: Command, to document: inout CraftDocument) throws -> Bool {
    switch command {
    case .crop(let rect):
      guard rect.width > 0, rect.height > 0, rect == rect.clipped(toWidth: document.width, height: document.height) else { throw CraftError.invalid("Crop must lie within the canvas.") }
      guard !document.layers.contains(where: \.locked) else { throw CraftError.invalid("Unlock all layers before cropping.") }
      document = try self.document(document, by: .translation(-Double(rect.x), -Double(rect.y)), width: rect.width, height: rect.height, clearSelection: true)
    case .canvasSize(let width, let height, let anchor, let fill):
      try IndexedRaster.validateDimensions(width, height)
      let fractions = anchor.fractions
      let x = floor(Double(width - document.width) * fractions.0), y = floor(Double(height - document.height) * fractions.1)
      document = try self.document(document, by: .translation(x, y), width: width, height: height, fill: fill)
    case .imageSize(let width, let height, let resolution, let method):
      guard resolution.isFinite, (1...100_000).contains(resolution) else { throw CraftError.invalid("Invalid image resolution.") }
      let delta = Transform2D.scale(Double(width) / Double(document.width), Double(height) / Double(document.height))
      var result = try self.document(document, by: delta, width: width, height: height, method: method, clampEdges: true)
      result.resolution = resolution; document = result
    case .rotateCanvas(let turn):
      let swapped = turn == .clockwise || turn == .counterclockwise
      document = try self.document(document, by: turn.transform(width: document.width, height: document.height), width: swapped ? document.height : document.width, height: swapped ? document.width : document.height)
    default: return false
    }
    return true
  }
}
