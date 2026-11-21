import Foundation
import PhotoCraftCore

extension PathTarget {
  var owningLayerID: UUID? {
    switch self {
    case .saved: nil
    case .shape(let id), .vectorMask(let id): id
    }
  }
}

@MainActor extension EditorStore {
  var canChangePathIsolation: Bool {
    canChangeLayerSelection && pathMarquee == nil && freeformGesture == nil
  }

  var canIsolateFocusedPath: Bool {
    canChangePathIsolation && pathTarget?.owningLayerID != nil && selectedVectorPath != nil
  }

  func setPathIsolation(_ enabled: Bool) throws {
    guard enabled || pathIsolationLayerID != nil else { return }
    guard canChangePathIsolation else {
      throw CraftError.invalid("Finish the current interaction before changing path isolation.")
    }
    if !enabled { endPathIsolation(); return }
    guard let target = pathTarget, let owner = target.owningLayerID, selectedVectorPath != nil else {
      throw CraftError.invalid("Select a shape path or vector mask to isolate its layer.")
    }
    guard pathIsolationLayerID != owner else { return }
    if document.activeLayerID != owner { session.setFilteredLayerSelection(owner) }
    selectedLayerIDs = [owner]
    var filter = layerPanelFilter
    filter.enabled = true
    filter.mode = .selected
    try setLayerFilter(filter)
    pathIsolationLayerID = owner
    companionPathChoices.removeAll { $0.target.owningLayerID != owner }
    if pathRangeAnchor?.owningLayerID != owner { pathRangeAnchor = target }
  }

  // Focus changes and layer removal can require cleanup during another command.
  func endPathIsolation() {
    guard pathIsolationLayerID != nil else { return }
    pathIsolationLayerID = nil
    var filter = layerPanelFilter
    filter.mode = .kind
    filter.kinds = []
    layerPanelFilter = filter
    layerFilterRevision = UUID()
  }

  func validatePathIsolation() {
    guard let owner = pathIsolationLayerID else { return }
    let layer = document.layers.first { $0.id == owner }
    switch pathTarget {
    case .shape(let id) where id == owner && layer?.shape != nil: return
    case .vectorMask(let id) where id == owner && layer?.vectorMask != nil: return
    default: endPathIsolation()
    }
  }

  func handlePathIsolationDoubleClick(at point: PathPoint, tolerance: Double) -> Bool {
    guard canChangePathIsolation else { return false }
    let hit = selectedVectorPath.map {
      pathContainsPointer($0, point: point, tolerance: tolerance, includeInterior: true)
    } ?? false
    if pathIsolationLayerID != nil {
      if !hit { endPathIsolation() }
      return true
    }
    guard hit, canIsolateFocusedPath else { return false }
    do { try setPathIsolation(true) } catch { self.error = error.localizedDescription }
    return true
  }
}
