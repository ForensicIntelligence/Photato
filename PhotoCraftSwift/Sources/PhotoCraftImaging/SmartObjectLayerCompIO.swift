import Foundation
import PhotoCraftCore

struct SmartObjectCompPreparationCache {
  struct Entry {
    let object: SmartObject
    let document: CraftDocument
    let choices: SmartObjectLayerComps?
    var pixels: [String: Surface] = [:]
  }
  var entries: [UUID: Entry] = [:]
  var decodedSources = 0
  var renderedVariations = 0
}
public enum SmartObjectLayerCompIO {
  public static func catalog(in source: CraftDocument) throws -> SmartObjectLayerComps? {
    guard let comps = source.layerComps?.comps, !comps.isEmpty else { return nil }
    return try .init(entries: comps.map { .init(id: $0.id, name: $0.name) })
  }
  public static func presentation(_ source: CraftDocument, compID: UUID?) throws -> CraftDocument {
    guard let compID else { return source }
    guard let comp = source.layerComps?.comps.first(where: { $0.id == compID }), comp.missingLayers(in: source).isEmpty else {
      throw CraftError.invalid("The chosen source Layer Comp is missing or refers to deleted layers. Edit Contents to repair it, or choose Last Document State.")
    }
    return try LayerCompIO.document(source, applying: compID)
  }
  public static func pixels(_ source: CraftDocument, compID: UUID?, stackMode: ImageStackMode?, in parent: CraftDocument) throws -> Surface {
    try Task.checkCancellation()
    let variation = try presentation(source, compID: compID)
    if let stackMode { return try ImageStack.render(variation, mode: stackMode, in: parent) }
    return try ColorManagement.converted(SmartObjectIO.sourceComposite(variation), from: variation, to: parent)
  }
  public static func selection(in document: CraftDocument, layerID: UUID, compID: UUID?, sourceData: Data? = nil) throws -> Command {
    var cache = SmartObjectCompPreparationCache()
    return try selection(in: document, layerID: layerID, compID: compID, sourceData: sourceData, cache: &cache)
  }
  static func selection(in document: CraftDocument, layerID: UUID, compID: UUID?, sourceData: Data?, cache: inout SmartObjectCompPreparationCache) throws -> Command {
    try Task.checkCancellation(); try document.validate()
    guard let i = document.layers.firstIndex(where: { $0.id == layerID }),
      var object = document.layers[i].smartObject, !document.isImageLocked(layerID),
      object.rawDevelopment == nil, object.pdfSource == nil else { throw CraftError.invalid("Select an unlocked layered Smart Object.") }
    guard try document.layers[i].linkedSmartObjectPreview() == nil else { throw CraftError.unsupported("Update the linked source preview before choosing its Layer Comp.") }
    let mode = object.stackMode
    var entry: SmartObjectCompPreparationCache.Entry
    if let existing = cache.entries[object.sourceID], existing.object.sharesSource(with: object) {
      entry = existing
      if object.data.isEmpty { object = existing.object; object.stackMode = mode }
    } else {
      if object.data.isEmpty {
        guard let sourceData else { throw CraftError.invalid("Locate and authorize the linked original before choosing a Layer Comp.") }
        object = try object.hydrating(sourceData)
      }
      let source = try SmartObjectIO.sourceDocument(object)
      entry = .init(object: object, document: source, choices: try catalog(in: source)); cache.decodedSources += 1
    }
    guard var choices = entry.choices else { throw CraftError.invalid("The source document has no Layer Comps. Use Edit Contents to create one.") }
    choices.selectedID = compID; try choices.validate()
    let key = (compID?.uuidString ?? "last") + ":" + (mode?.rawValue ?? "none")
    let pixels: Surface
    if let existing = entry.pixels[key] { pixels = existing }
    else {
      pixels = try self.pixels(entry.document, compID: compID, stackMode: mode, in: document)
      entry.pixels[key] = pixels; cache.renderedVariations += 1
    }
    cache.entries[object.sourceID] = entry
    object.layerComps = choices; try object.validate()
    var result = document
    result.layers[i].smartObject = object; result.layers[i].content = .raster(pixels)
    for key in ["SoLd", "SoLE", "PlLd"] { result.layers[i].sourceTags?.removeValue(forKey: key) }
    return .linkedSmartObject(try .init(source: document, result: result, title: "Set Smart Object Layer Comp"))
  }
}
