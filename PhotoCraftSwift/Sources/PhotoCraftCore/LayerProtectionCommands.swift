import Foundation

extension Command {
  /// Validate the operation's target before any transaction mutates it. Whole-
  /// document resizing and explicit selection removal are distinct from painting.
  func validateProtection(in document: CraftDocument) throws {
    var pixels: UUID?
    var geometry: UUID?
    switch self {
    case .modeComponents(let edit):pixels=edit.layerID
    case .proceduralRender(let request):if !request.newLayer {pixels=request.layerID ?? document.activeLayerID}
    case .stroke(let id, _, _), .clear(let id), .fill(let id, _),
      .applyFilter(let id, _), .fillComponents(let id, _), .applyAdjustment(let id, _), .desaturate(let id),
      .autoCorrection(let id, _), .applyMask(let id): pixels = id
    case .cut(let ids, _) where document.selection != nil || document.restrictedMode != nil: pixels = ids.first
    case .layerVia(let id, .cut): pixels = id
    case .paintBucket(let id, let fill): if !fill.mask { pixels = id }
    case .paintGradient(let id, let stroke): if !stroke.mask { pixels = id }
    case .cloneStamp(let id, let stroke): if !stroke.mask { pixels = id }
    case .healingBrush(let id, let healing): if !healing.stroke.mask { pixels = id }
    case .spotHealing(let id, let stroke): if !stroke.mask { pixels = id }
    case .focus(let id, let stroke): if !stroke.mask { pixels = id }
    case .toning(let id, let stroke): if !stroke.mask { pixels = id }
    case .createMask(let id, .fromTransparency): pixels = id
    case .replaceContent(let id, _), .rasterize(let id, _):
      if case .raster = document.layers.first(where: { $0.id == id })?.content { pixels = id }
    case .move(let id, _, _), .transform(let id, _, _), .flip(let id, _): geometry = id
    default: break
    }
    if let pixels, document.isImageLocked(pixels) {
      throw CraftError.invalid("Unlock image pixels on the layer and its groups before editing them.")
    }
    if let pixels, document.layers.first(where: { $0.id == pixels })?.smartObject != nil {
      if case .rasterize = self {} else if case .applyFilter = self {} else {
        throw CraftError.invalid("Rasterize the Smart Object or use Edit Contents before editing its pixels.")
      }
    }
    if let geometry {
      let members = document.subtreeIDs(geometry)
      guard members.allSatisfy({ !document.isPositionLocked($0) }) else {
        throw CraftError.invalid("Unlock layer positions before moving or transforming them.")
      }
    }
  }
}
