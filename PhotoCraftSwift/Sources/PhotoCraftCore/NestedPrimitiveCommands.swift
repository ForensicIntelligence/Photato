import Foundation

extension Command {
  /// Composite operations can invoke another validated command. Keep them out
  /// of the broad primitive switch so worker threads never nest its large frame.
  @inline(never)
  func applyNestedPrimitive(to d:inout CraftDocument)throws {
    func index(_ id:UUID)throws->Int {
      guard let i=d.layers.firstIndex(where:{$0.id==id}) else{throw CraftError.invalid("Layer no longer exists.")}
      guard !d.isLocked(id) else{throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")}
      return i
    }
    func raster(_ i:Int)throws->Surface {
      guard case .raster(let surface)=d.layers[i].content else{throw CraftError.unsupported("Rasterize this layer before painting or applying pixel filters.")}
      return surface
    }
    switch self {
    case .mergeLayers(let ids,let operation):
      try LayerMerge.apply(operation,layerIDs:ids,to:&d)
    case .addGradientFill(var layer, let createMask):
      guard case .gradientFill(let fill) = layer.content else {
        throw CraftError.invalid("Expected a gradient fill layer.")
      }
      try fill.validate()
      if createMask {
        layer = try layer.creatingPixelMask(
          d.selection == nil ? .revealAll : .revealSelection, in: d)
      }
      try Command.addLayer(layer).apply(to: &d)
    case .addPatternFill(var layer, let pattern, let createMask):
      guard case .patternFill(var fill) = layer.content else {
        throw CraftError.invalid("Expected a pattern fill layer.")
      }
      fill.patternID = try d.installPattern(pattern)
      layer.content = .patternFill(fill)
      if createMask {
        layer = try layer.creatingPixelMask(
          d.selection == nil ? .revealAll : .revealSelection, in: d)
      }
      try Command.addLayer(layer).apply(to: &d)
    case .independentSmartObjectCopy(let id):
      let i = try index(id)
      guard d.layers[i].smartObject != nil else { throw CraftError.invalid("Select an embedded Smart Object.") }
      try Command.duplicateLayer(id).apply(to: &d)
      if let i = d.activeIndex { d.layers[i].smartObject?.sourceID = UUID() }
    case .autoCorrection(let id, let kind):
      let i = try index(id)
      _ = try raster(i)
      let histogram = try RGBHistogram.pixelLayer(id, in: d)
      guard histogram.samples > 0 else { break }
      let levels = try kind.levels(from: histogram)
      try Command.applyAdjustment(id, .levels(levels)).apply(to: &d)
    case .desaturate(let id):
      try Command.applyAdjustment(id, .hueSaturation(.init(master: .init(saturation: -100))))
        .apply(to: &d)
    default:throw CraftError.invalid("Unexpected nested command routing.")
    }
  }
}
