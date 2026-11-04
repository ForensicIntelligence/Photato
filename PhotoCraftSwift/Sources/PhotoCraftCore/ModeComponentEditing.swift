import Foundation

/// Editing values are channel-view gray: black means full ink in CMYK.
/// Numerical mode.channel.read/write continues to expose the stored ink values.
public struct ModeComponentEdit: Sendable {
  public enum Operation: Sendable {
    case fill(Float, Float)
    case stroke([StrokePoint], Brush)
    case invert
    case filter(RasterFilter)
  }
  public var layerID: UUID
  public var components: Set<Int>
  public var operation: Operation
  public init(layerID: UUID, components: Set<Int>, operation: Operation) {
    self.layerID = layerID; self.components = components; self.operation = operation
  }
  public var label: String {
    switch operation {
    case .fill: "Fill Color Channels"
    case .stroke(_, let brush): brush.erase ? "Erase Color Channels" : "Paint Color Channels"
    case .invert: "Invert Color Channels"
    case .filter(let filter): filter.kind.title
    }
  }
  public static let filters: Set<RasterFilter.Kind> = [.gaussianBlur, .boxBlur, .motionBlur,
    .average, .unsharpMask, .highPass, .addNoise, .mosaic]
  public static func raster(_ layer: Layer, in document: CraftDocument) throws -> NativeModeRaster {
    guard case .raster(let pixels) = layer.content else { throw CraftError.invalid("Choose a pixel layer for color-component editing.") }
    if let native = layer.nativeMode { return native }
    guard document.colorMode == .rgb else { throw CraftError.invalid("Missing native component planes.") }
    return try NativeModeRaster.retainingRGBSamples(pixels, profile: document.workingICC)
  }
  public func apply(to document: inout CraftDocument) throws {
    guard !components.isEmpty, components.isSubset(of: Set(0..<document.colorMode.componentCount)),
      let index = document.layers.firstIndex(where: { $0.id == layerID }),
      !document.isImageLocked(layerID), document.layers[index].smartObject == nil,
      document.layers[index].smartFilters == nil else {
      throw CraftError.invalid("Choose valid color components on an unlocked ordinary pixel layer.")
    }
    guard case .raster(let target) = document.layers[index].content else { throw CraftError.invalid("Choose a pixel layer for color-component editing.") }
    if target.width > NativeModeRaster.maximumPixels / target.height {
      try applyPaged(to: &document); return
    }
    let layer = document.layers[index], before = document
    let native = try Self.raster(layer, in: document), transform = layer.coordinateTransform
    var result = native
    try transform.validated()
    switch operation {
    case .fill(let value, let opacity):
      guard value.isFinite, opacity.isFinite, (0...1).contains(value), (0...1).contains(opacity) else { throw CraftError.invalid("Invalid channel fill.") }
    case .stroke(let points, let brush): try BrushPainter.validate(brush, points: points)
    case .filter(let filter):
      guard Self.filters.contains(filter.kind) else { throw CraftError.unsupported("This filter has not been implemented for individual color components.") }
      try filter.validate()
    case .invert: break
    }
    for component in components.sorted() {
      try Task.checkCancellation()
      var plane = try Surface(width: native.width, height: native.height, depth: native.depth)
      for y in 0..<native.height { try Task.checkCancellation(); for x in 0..<native.width {
        let stored = native.value(component: component, index: y * native.width + x)
        let value = native.mode == .cmyk ? 1 - stored : stored
        plane.setPixel(x: x, y: y, Pixel(value, value, value))
      } }
      switch operation {
      case .fill(let value, let opacity):
        try plane.mapStoredPixels { x, y, p in
          let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
          let coverage = before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
          if native.depth == .u8 {
            // Keep the independently qualified RGB8 neutral Fill rounding.
            return RGBComponentFill(components: .all, value: value, opacity: opacity).applying(to: p, coverage: coverage)
          }
          let k = coverage * opacity, v = p.r * (1 - k) + value * k
          return Pixel(v, v, v)
        }
      case .invert:
        try plane.mapStoredPixels { x, y, p in
          let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
          let k = before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
          let value = p.r * (1 - k) + (1 - p.r) * k
          return Pixel(value, value, value)
        }
      case .stroke(let points, var brush):
        let ink = brush.erase ? brush.backgroundColor ?? .white : brush.color
        let value = unit(ink.r * 0.2126 + ink.g * 0.7152 + ink.b * 0.0722)
        brush.color = Pixel(value, value, value, ink.a); brush.erase = false
        try Painter.stroke(surface: &plane, points: points, brush: brush,
          selection: before.selection, selectionMask: before.selectionMask,
          offsetX: layer.x, offsetY: layer.y, transform: transform, grayscaleMask: true)
      case .filter(let filter):
        var proxy = try CraftDocument(width: before.width, height: before.height, depth: native.depth)
        if native.depth == .f32 {
          var linear = try Surface(width: plane.width, height: plane.height, depth: .f32, colorEncoding: .linearRGB)
          for y in 0..<plane.height { try Task.checkCancellation(); for x in 0..<plane.width { linear.setLinearPixel(x: x, y: y, plane.pixel(x: x, y: y)) } }
          plane = linear
        }
        var target = Layer(name: "Channel", content: .raster(plane))
        target.x = layer.x; target.y = layer.y; target.affine = layer.affine
        proxy.layers = [target]; proxy.activeLayerID = target.id
        proxy.selection = before.selection; proxy.selectionMask = before.selectionMask
        try RasterFilterEngine.apply(filter, to: target.id, in: &proxy)
        guard case .raster(let pixels) = proxy.layers[0].content else { throw CraftError.invalid("Invalid channel filter result.") }
        plane = pixels
      }
      for y in 0..<native.height { try Task.checkCancellation(); for x in 0..<native.width {
        let value = native.depth == .f32 && plane.colorEncoding == .linearRGB
          ? plane.linearPixel(x: x, y: y).r : plane.pixel(x: x, y: y).r
        try result.set(native.mode == .cmyk ? 1 - value : value, component: component, index: y * native.width + x)
      } }
    }
    if document.hasNativeModeStorage {
      document.layers[index].nativeMode = result
      document.layers[index].content = .raster(try result.surface())
    } else {
      guard case .raster(var pixels) = layer.content else { throw CraftError.invalid("Missing component target.") }
      for y in 0..<native.height { try Task.checkCancellation(); for x in 0..<native.width {
        let i = y * native.width + x
        var p = document.depth == .f32 ? pixels.linearPixel(x: x, y: y) : pixels.pixel(x: x, y: y)
        if components.contains(0) { p.r = result.value(component: 0, index: i) }
        if components.contains(1) { p.g = result.value(component: 1, index: i) }
        if components.contains(2) { p.b = result.value(component: 2, index: i) }
        if document.depth == .f32 { pixels.setLinearPixel(x: x, y: y, p) } else { pixels.setPixel(x: x, y: y, p) }
      } }
      document.layers[index].content = .raster(pixels)
    }
  }
}
