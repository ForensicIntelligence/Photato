import Foundation
import PhotoCraftCore

/// Render current source choices before exposing one complete parent transaction.
public enum LayerCompIO {
  public static func states(for operation: LayerCompCommand, in document: CraftDocument) throws -> [LayerCompLayerState] {
    switch operation {
    case .apply(let id):
      guard let comp = document.layerComps?.comps.first(where: { $0.id == id }) else { throw CraftError.invalid("Layer Comp no longer exists.") }
      return comp.layers
    case .restoreLast:
      guard let states = document.layerComps?.lastDocumentState else { throw CraftError.invalid("No saved document state.") }; return states
    default: return []
    }
  }
  public static func requiredSmartObjectLayers(for operation: LayerCompCommand, in document: CraftDocument) throws -> [UUID] {
    try document.validate()
    return try states(for: operation, in: document).compactMap { state in
      guard let choice = state.smartObjectSelection, let layer = document.layers.first(where: { $0.id == state.layerID }) else { return nil }
      guard let object = layer.smartObject, object.sourceID == choice.sourceID else { throw CraftError.invalid("A recorded Smart Object source was replaced or converted. Review and recapture the parent comp.") }
      return choice.matches(object) ? nil : layer.id
    }
  }
  public static func command(_ operation: LayerCompCommand, in document: CraftDocument, sourceData: [UUID: Data] = [:]) throws -> Command {
    try SmartObjectIO.withNesting {
      let required = try requiredSmartObjectLayers(for: operation, in: document)
      guard !required.isEmpty else { return .layerComp(operation) }
      let states = Dictionary(uniqueKeysWithValues: try states(for: operation, in: document).map { ($0.layerID, $0) })
      var candidate = document, cache = SmartObjectCompPreparationCache()
      for id in required {
        try Task.checkCancellation()
        let choice = states[id]!.smartObjectSelection!
        try SmartObjectLayerCompIO.selection(in: candidate, layerID: id, compID: choice.compID, sourceData: sourceData[choice.sourceID], cache: &cache).apply(to: &candidate)
      }
      try operation.apply(to: &candidate, recordingBefore: document)
      return .linkedSmartObject(try .init(source: document, result: candidate, title: operation.label))
    }
  }
  public static func document(_ document: CraftDocument, applying id: UUID, sourceData: [UUID: Data] = [:]) throws -> CraftDocument {
    var result = document; try command(.apply(id), in: document, sourceData: sourceData).apply(to: &result); return result
  }
}
