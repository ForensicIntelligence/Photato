import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  func layerPositionBinding(_ layer: Layer, horizontal: Bool) -> Binding<Double> {
    let owner = store
    let generation = owner.layerPanelGeneration
    let id = layer.id
    func currentLayer() -> Layer? {
      guard owner.layerPanelGeneration == generation, owner.document.activeLayerID == id else {
        return nil
      }
      return owner.document.layers.first { $0.id == id }
    }
    return Binding(
      get: {
        let current = currentLayer() ?? layer
        let bounds = try? owner.layerBounds(current)
        return Double(horizontal ? bounds?.x ?? current.x : bounds?.y ?? current.y)
      },
      set: { value in
        guard value.isFinite, let current = currentLayer() else { return }
        // A field can deliver several parsed values before SwiftUI refreshes its
        // parent. Resolve both the translation and visible bounds from that same
        // current layer; captured geometry would accumulate an incorrect delta.
        let bounds = try? owner.layerBounds(current)
        let coordinate = horizontal ? current.x : current.y
        let origin = horizontal ? bounds?.x ?? current.x : bounds?.y ?? current.y
        let requested = Int(min(1_000_000, max(-1_000_000, value)))
        let delta = requested.subtractingReportingOverflow(origin)
        let translated = coordinate.addingReportingOverflow(delta.partialValue)
        guard !delta.overflow, !translated.overflow else {
          owner.error = "Position is out of range."
          return
        }
        guard translated.partialValue != coordinate else { return }
        owner.perform(
          .move(
            id, horizontal ? translated.partialValue : current.x,
            horizontal ? current.y : translated.partialValue))
      })
  }
}
