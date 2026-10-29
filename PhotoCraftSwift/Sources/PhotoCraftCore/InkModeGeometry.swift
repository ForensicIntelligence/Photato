import Foundation

extension InkPlane {
  /// Transform numeric coverage; never run ink samples through color management.
  /// Grid mappings copy their original bytes, including all16-bit precision.
  public func transformed(by transform: Transform2D, width: Int, height: Int,
    method: Resampling = .nearest, fill: Float = 0, clampEdges: Bool = false) throws -> Self {
    try validate()
    var result = try Self(width: width, height: height, depth: depth, value: fill)
    let inverse = try transform.inverted()
    let grid = [transform.a, transform.b, transform.c, transform.d].allSatisfy { [-1.0, 0, 1].contains($0) }
      && abs(transform.a * transform.d - transform.b * transform.c) == 1
      && transform.tx.rounded() == transform.tx && transform.ty.rounded() == transform.ty
      && abs(transform.a) + abs(transform.c) == 1 && abs(transform.b) + abs(transform.d) == 1
    let direct = method == .nearest || grid
    let cache = direct ? nil : try surface()
    var output = result.bytes
    let stride = depth == .u8 ? 1 : 2
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      var p = inverse.point(Double(x) + 0.5, Double(y) + 0.5)
      if clampEdges { p.x = min(Double(self.width) - 0.5, max(0.5, p.x)); p.y = min(Double(self.height) - 0.5, max(0.5, p.y)) }
      guard p.x >= 0, p.y >= 0, p.x < Double(self.width), p.y < Double(self.height) else { continue }
      let destination = (y * width + x) * stride
      if direct {
        let source = (Int(floor(p.y)) * self.width + Int(floor(p.x))) * stride
        output[destination] = bytes[source]
        if stride == 2 { output[destination + 1] = bytes[source + 1] }
      } else {
        let p = RasterGeometry.sample(cache!, x: p.x, y: p.y, method: method, clampEdges: clampEdges)
        let value = unit(p.r * p.a + fill * (1 - p.a))
        if stride == 1 { output[destination] = UInt8((value * 255).rounded()) }
        else { let n = UInt16((value * 65535).rounded()); output[destination] = UInt8(n & 255); output[destination + 1] = UInt8(n >> 8) }
      }
    } }
    result = try Self(width: width, height: height, depth: depth, bytes: output)
    return result
  }
}

public enum InkModeGeometry {
  public static func document(_ original: CraftDocument, by transform: Transform2D,
    width: Int, height: Int, method: Resampling = .nearest, fill: Pixel? = nil,
    clampEdges: Bool = false, clearSelection: Bool = false) throws -> CraftDocument {
    try original.validate(); try InkPlane.dimensions(width, height, original.depth)
    guard let inkMode = original.inkMode, fill?.isFinite != false else { throw CraftError.invalid("Ink geometry requires ink storage and a finite background.") }
    var result = original
    switch inkMode {
    case .duotone(var raster):
      let color = fill ?? .white
      let gray = unit((color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722) * unit(color.a) + 1 - unit(color.a))
      raster.gray = try raster.gray.transformed(by: transform, width: width, height: height, method: method, fill: gray, clampEdges: clampEdges)
      result.inkMode = .duotone(raster); result.layers[0].content = .raster(try raster.gray.surface())
    case .multichannel(var raster):
      guard fill == nil || fill == .white || fill?.a == 0 else {
        throw CraftError.unsupported("Multichannel canvas extension uses unprinted paper. Fill individual ink plates after extending the canvas.")
      }
      for i in raster.plates.indices {
        raster.plates[i].samples = try raster.plates[i].samples.transformed(by: transform, width: width,
          height: height, method: method, clampEdges: clampEdges)
      }
      result.inkMode = .multichannel(raster)
    }
    result.width = width; result.height = height
    result.transformSavedPaths(by: transform)
    try result.transformChannels(from: original, by: transform, method: method)
    if clearSelection { result.setCoverageSelection(nil) } else { try result.mapSelection(from: original, by: transform) }
    try result.validate(); return result
  }
  static func apply(_ command: Command, to document: inout CraftDocument) throws -> Bool {
    switch command {
    case .crop(let rect):
      guard rect.width > 0, rect.height > 0, rect == rect.clipped(toWidth: document.width, height: document.height) else { throw CraftError.invalid("Crop must lie within the canvas.") }
      guard !document.layers.contains(where: \.locked) else { throw CraftError.invalid("Unlock all layers before cropping.") }
      document = try self.document(document, by: .translation(-Double(rect.x), -Double(rect.y)), width: rect.width, height: rect.height, clearSelection: true)
    case .canvasSize(let width, let height, let anchor, let fill):
      try InkPlane.dimensions(width, height, document.depth)
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
      document = try self.document(document, by: turn.transform(width: document.width, height: document.height),
        width: swapped ? document.height : document.width, height: swapped ? document.width : document.height)
    default: return false
    }
    return true
  }
}
