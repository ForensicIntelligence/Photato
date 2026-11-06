import Foundation
import PhotoCraftCore

/// A presentation-only plan. Original parameters, stroke sampling and prepared
/// edits never use this projection. Identity content removes spatial damage expansion while normal blending
/// bypasses its color effect. Visibility stays intact for attached clipping layers.
public struct LightEditingPreview: Sendable {
  public let pausedLayerIDs: [UUID]
  private let sourceID: UUID
  private let layerOrder: [UUID]
  public init(document: CraftDocument, editingLayers: Set<UUID>) {
    sourceID = document.id; layerOrder = document.layers.map(\.id)
    let children = Dictionary(grouping: document.layers, by: \.parentID)
    var paused = Set<UUID>()
    func light(_ layer: Layer, inputEdited: Bool) {
      if inputEdited, case .adjustment(.modern(let value)) = layer.content,
        value.kind == .light, value.needsNeighborhood { paused.insert(layer.id) }
    }
    // Track structural input dependence through the same stack boundaries as
    // composition. Occlusion/zero masks are deliberately not a pixel analysis.
    func stack(_ layers: [Layer], inputEdited: Bool, depth: Int) -> Bool {
      guard depth <= 32 else { return inputEdited }
      var outputEdited = inputEdited, index = 0
      while index < layers.count {
        let base = layers[index]; index += 1
        if base.isClipped { continue }
        let start = index
        while index < layers.count, layers[index].isClipped { index += 1 }
        guard base.visible, base.opacity > 0 else { continue }
        let before = outputEdited
        var sourceEdited: Bool
        if let group = base.group {
          let pass = group.passThrough && group.artboard == nil && group.frame == nil && base.style == nil
          sourceEdited = stack(children[base.id] ?? [], inputEdited: pass && before, depth: depth+1)
            || editingLayers.contains(base.id)
        } else if case .adjustment = base.content {
          light(base, inputEdited: before)
          sourceEdited = before || editingLayers.contains(base.id)
        } else { sourceEdited = editingLayers.contains(base.id) }
        if !base.clipsBlendAsGroup { sourceEdited = sourceEdited || before }
        for clip in layers[start..<index] where clip.visible && clip.opacity > 0 {
          if case .adjustment = clip.content { light(clip, inputEdited: sourceEdited) }
          else if clip.isGroup {
            sourceEdited = stack(children[clip.id] ?? [], inputEdited: false, depth: depth+1) || sourceEdited
          }
          sourceEdited = sourceEdited || editingLayers.contains(clip.id)
        }
        outputEdited = before || sourceEdited
      }
      return outputEdited
    }
    _ = stack(children[nil] ?? [], inputEdited: false, depth: 0)
    pausedLayerIDs = document.layers.compactMap { paused.contains($0.id) ? $0.id : nil }
  }
  public func project(_ document: CraftDocument) -> CraftDocument {
    guard !pausedLayerIDs.isEmpty, document.id == sourceID, document.layers.map(\.id) == layerOrder else { return document }
    let ids = Set(pausedLayerIDs)
    guard document.layers.filter({ ids.contains($0.id) }).allSatisfy({ layer in
      if case .adjustment(.modern(let value)) = layer.content { return value.kind == .light && value.needsNeighborhood }
      return false
    }) else { return document }
    var result = document
    for i in result.layers.indices where ids.contains(result.layers[i].id) {
      result.layers[i].content = .adjustment(.modern(.init(.light)))
      result.layers[i].blendMode = .normal
    }
    return result
  }
}
