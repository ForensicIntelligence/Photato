import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Published create-composite per-output layer selection; separate from edit-layer operations.
struct AdobeLayerOutput: Hashable, Sendable {
  enum Reference: Hashable, Sendable { case id(Int), name(String) }
  let layers: [Reference]?
  let crop: ImageAssetSelection.Crop
  init(_ fields: [String: Any], createComposite: Bool, mediaType: AdobeActionsRequest.MediaType) throws {
    if let raw = fields["layers"] {
      guard createComposite, mediaType != .json, let values = raw as? [Any], (1...100).contains(values.count) else { throw AdobeAPIError.invalid("Output layers require create-composite and one through100 layer references.") }
      layers = try values.enumerated().map { index, raw in
        let object = try AdobeActionsRequest.Object(raw, at: "outputs.layers[\(index)]", allowed: ["id", "name"])
        guard object.fields.count == 1 else { throw AdobeAPIError.invalid("Each layer reference must contain exactly one of id or name (not both).") }
        if object.fields["id"] != nil { return .id(try object.integer("id", range: 0...Int(Int32.max))) }
        let name = try object.string("name"); guard !name.isEmpty, name.utf8.count <= 4096 else { throw AdobeAPIError.invalid("Invalid output layer name.") }; return .name(name)
      }
      guard Set(layers!).count == layers!.count else { throw AdobeAPIError.invalid("Duplicate output layer reference.") }
      if layers!.count > 1, mediaType == .psd { throw AdobeAPIError.invalid("PSD output supports a single layer, group or artboard; use a raster format for multiple layers.") }
    } else { layers = nil }
    let value = fields["cropMode"] as? String ?? (layers?.count == 1 ? "layer_bounds" : "document_bounds")
    guard let mode = ImageAssetSelection.Crop(rawValue: value) else { throw AdobeAPIError.invalid("Invalid output cropMode.") }
    guard mode != .layerBounds || layers?.count == 1 else { throw AdobeAPIError.invalid("layer_bounds requires exactly one output layer.") }
    guard createComposite || mode == .documentBounds else { throw AdobeAPIError.unsupported("Only document_bounds is qualified for execute-actions output.") }
    crop = mode
  }
  func document(_ source: CraftDocument) throws -> CraftDocument {
    let ids = try layers.map { references in try references.map { reference -> UUID in
      switch reference {
      case .id(let id):
        if id==0,source.layers.count==1,source.layers[0].isBackground{return source.layers[0].id}
        guard id>0,id <= source.layers.count else { throw AdobeAPIError.invalid("Output layer id does not exist.") }; return source.layers[id-1].id
      case .name(let name):
        let found = source.layers.filter { $0.name == name }; guard found.count == 1 else { throw AdobeAPIError.invalid("Output layer name is missing or ambiguous.") }; return found[0].id
      }
    } }
    do { return try ImageAssetSelection.document(source, ids: ids, crop: crop, includingAncestors: true) }
    catch let error as AdobeAPIError { throw error }
    catch { throw AdobeAPIError.unsupported(error.localizedDescription) }
  }
}
