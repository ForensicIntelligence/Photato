import Foundation
import PhotoCraftCore

/// Sample global color adjustments with the normal native compositor. A LUT
/// cannot represent a spatial mask, neighborhood effect or position-based noise.
public enum ColorLookupExport {
  public static func adjustments(in document: CraftDocument) throws -> [Layer] {
    guard document.colorMode == .rgb, document.restrictedMode == nil,
      document.inkMode == nil, !document.isChannelOnly,
      document.animation == nil, document.videoTimeline == nil,
      document.layers.count > 1, document.layers.first?.isBackground == true
    else { throw CraftError.unsupported("Use an RGB document with a Background layer and global adjustment layers.") }
    var result: [Layer] = []
    for layer in document.layers.dropFirst() {
      guard case .adjustment(let adjustment) = layer.content, layer.parentID == nil else {
        throw CraftError.unsupported("Color Lookup export requires adjustment layers above Background; pixel layers and groups are not supported yet.")
      }
      guard layer.visible, layer.opacity > 0 else { continue }
      guard !layer.isClipped, layer.vectorMask == nil, layer.style == nil,
        layer.smartObject == nil, layer.smartFilters == nil, layer.warp == nil,
        layer.sourceProjection == nil, layer.nativeMode == nil,
        layer.blendMode != .dissolve, layer.x == 0, layer.y == 0, layer.affine == nil
      else { throw CraftError.unsupported("Spatial effects, clipping and Dissolve cannot be represented by a global color LUT.") }
      if let mask = layer.mask, layer.effectiveMaskProperties.enabled {
        let p = layer.effectiveMaskProperties
        guard mask.tileCount == 0, mask.defaultPixel.r == 1,
          mask.width >= document.width, mask.height >= document.height,
          p.transform == .identity, !p.inverted, p.feather == 0 else {
          throw CraftError.unsupported("Disable spatial masks or use an unmodified all-white mask before exporting a color LUT.")
        }
      }
      switch adjustment {
      case .modern(let value):
        guard !value.needsNeighborhood, !value.variesWithPosition else {
          throw CraftError.unsupported("Neighborhood adjustments and Grain cannot be represented by a global color LUT.")
        }
      case .colorLookup(let value):
        guard !value.dither else { throw CraftError.unsupported("Turn off Color Lookup dithering before exporting a global LUT.") }
      case .gradientMap(let value):
        guard !value.dither else { throw CraftError.unsupported("Turn off Gradient Map dithering before exporting a global LUT.") }
      case .source(let value):
        guard !value.isOpaque, value.options["dither"] != true else {
          throw CraftError.unsupported("Opaque adjustments and dithering cannot be represented by a global color LUT.")
        }
        _ = try SourceAdjustmentTransfer(value, depth: document.depth)
      default: break
      }
      var global = layer
      global.mask = nil; global.maskProperties = nil
      result.append(global)
    }
    return result
  }

  public static func bake(_ document: CraftDocument, size: Int = 32,
    title: String = "Color Lookup") throws -> ColorLUT {
    guard (2...ColorLUT.maximumSize).contains(size) else { throw CraftError.invalid("Grid points must be between 2 and 129.") }
    let layers = try adjustments(in: document)
    try document.validate(); try Task.checkCancellation()
    var input = try Surface(width: size * size, height: size, depth: document.depth)
    let divisor = Float(size - 1)
    try input.mapPixels(in: .init(x: 0, y: 0, width: size * size, height: size)) { x, y, _ in
      Pixel(Float(x % size) / divisor, Float(x / size) / divisor, Float(y) / divisor)
    }
    var grid = try CraftDocument(width: size * size, height: size, depth: document.depth)
    grid.colorSpace = document.colorSpace; grid.sourceICC = document.sourceICC
    grid.workingICC = document.workingICC; grid.profileIsUntagged = document.profileIsUntagged
    var background = Layer(name: "LUT Input", content: .raster(input)); background.background = true
    grid.layers = [background] + layers; grid.activeLayerID = background.id
    let output = try Renderer.composite(grid)
    var values = [Float](); values.reserveCapacity(size * size * size * 3)
    for b in 0..<size {
      try Task.checkCancellation()
      for g in 0..<size { for r in 0..<size {
        let p = output.pixel(x: g * size + r, y: b)
        values.append(contentsOf: [p.r, p.g, p.b])
      } }
    }
    let lut = ColorLUT(title: title, size: size, values: values)
    try lut.validate(); return lut
  }

  public static func cube(_ document: CraftDocument, size: Int = 32,
    title: String = "Color Lookup") throws -> Data {
    let data = try ColorLUTFile.export(bake(document, size: size, title: title)).data
    guard data.count <= ColorLUT.maximumFileBytes else { throw CraftError.unsupported("The exported LUT exceeds the current 64 MiB file limit. Choose fewer grid points.") }
    return data
  }
}
