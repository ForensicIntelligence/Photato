import Foundation

/// Removes empty editable storage, never layers merely invisible in the composite.
public enum EmptyLayerDeletion {
  public static let title = "Delete All Empty Layers"

  public static func unavailableReason(_ document: CraftDocument) -> String? {
    if document.animation != nil || document.videoTimeline != nil {
      return "Empty-layer deletion in Timeline documents is not qualified."
    }
    if document.isChannelOnly || document.inkMode != nil || document.restrictedMode != nil {
      return "Empty-layer deletion requires a layered image document."
    }
    return nil
  }

  public static func layerIDs(in document: CraftDocument) throws -> Set<UUID> {
    if let reason = unavailableReason(document) { throw CraftError.unsupported(reason) }
    let index = LayerHierarchyIndex(document)
    let children = Dictionary(grouping: document.layers, by: \.parentID)
    var clippingBases = Set<UUID>()
    for siblings in children.values {
      var base: UUID?
      for layer in siblings {
        if layer.isClipped {
          if let base { clippingBases.insert(base) }
        } else { base = layer.id }
      }
    }
    var removed = Set<UUID>()
    // Valid native hierarchy orders children before their group, so one pass
    // also removes groups made empty by removal of their empty descendants.
    for layer in document.layers {
      try Task.checkCancellation()
      guard !layer.isBackground, !clippingBases.contains(layer.id),
        !index.effectiveProtection(layer.id).fullyLocks,
        layer.nativeMode == nil, layer.smartObject == nil, layer.video == nil,
        layer.videoTiming == nil, layer.videoKeyframes == nil,
        layer.mask == nil, layer.vectorMask == nil, layer.style == nil,
        layer.smartFilters == nil, layer.sourceTags?.isEmpty != false
      else { continue }
      switch layer.content {
      case .raster(let pixels):
        if try pixels.contentBounds() == nil { removed.insert(layer.id) }
      case .group(let group):
        if group.artboard == nil, group.frame == nil, group.videoStartTime == nil,
          (children[layer.id] ?? []).allSatisfy({ removed.contains($0.id) }) {
          removed.insert(layer.id)
        }
      default: break // Editable type, shapes, adjustments and fills are content.
      }
    }
    // Keep an editable layer and the parents required by its hierarchy.
    if !document.layers.isEmpty, removed.count == document.layers.count {
      let survivor = document.layers[0]
      removed.remove(survivor.id)
      for parent in index.ancestors(of: survivor.id) { removed.remove(parent.id) }
    }
    return removed
  }

  public static func prepare(_ document: CraftDocument) throws -> Command {
    let ids = try layerIDs(in: document)
    var result = document
    if !ids.isEmpty {
      try Command.deleteLayers(ids).apply(to: &result)
      if let active = document.activeLayerID, !ids.contains(active) {
        result.activeLayerID = active
      }
    }
    let targets = document.layers.filter { ids.contains($0.id) }.map {
      ActionLayerTarget($0.id, in: document)
    }
    return .preparedAction(.init(source: document, result: result, title: title,
      recording: targets.isEmpty ? nil : .delete(targets)))
  }
}
