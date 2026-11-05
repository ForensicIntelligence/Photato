import Foundation
import PhotoCraftCore

/// The published create-composite MoveLayer contract, not an invented actionJSON event.
struct AdobeLayerMoveEdit: Sendable {
  struct Reference: Sendable {
    let name: String?
    let identifier: Int32?
    init(_ object: AdobeActionsRequest.Object) throws {
      name = try object.fields["name"].map { _ in try object.string("name") }
      identifier = try object.fields["id"].map { _ in Int32(try object.integer("id", range: Int(Int32.min)...Int(Int32.max))) }
      guard (name == nil) != (identifier == nil), name.map({ !$0.isEmpty && $0.utf16.count <= 65_535 }) ?? true else {
        throw AdobeAPIError.invalid("Provide exactly one nonempty layer name or signed32-bit id.")
      }
    }
    func resolve(in document: CraftDocument) throws -> Layer {
      let matches = document.layers.filter { layer in
        if let name { return layer.name == name }
        guard let identifier, let bytes = layer.sourceTags?["lyid"], bytes.count == 4 else { return false }
        return Int32(bitPattern: bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) == identifier
      }
      guard matches.count == 1, let layer = matches.first else {
        throw AdobeAPIError.invalid("The layer reference must match exactly one input layer.")
      }
      return layer
    }
  }
  let target: Reference
  let type: String?
  let placement: String
  let reference: Reference?
  let includeChildren: Bool

  init(_ raw: Any, path: String) throws {
    typealias Object = AdobeActionsRequest.Object
    let object = try Object(raw, at: path, allowed: ["id", "name", "type", "operation"])
    target = try Reference(object)
    type = try object.fields["type"].map { _ in try object.string("type") }
    if let type, !["layer", "group_layer", "background_layer", "solid_color_layer", "text_layer", "smart_object_layer", "adjustment_layer"].contains(type) {
      throw AdobeAPIError.invalid("Unknown moved layer type.")
    }
    let operation = try object.object("operation", allowed: ["type", "placement", "shouldIncludeChildren"])
    guard try operation.string("type") == "move" else { throw AdobeAPIError.invalid("Expected move operation.") }
    includeChildren = try operation.optionalBool("shouldIncludeChildren") ?? true
    let position = try operation.object("placement", allowed: ["type", "referenceLayer"])
    placement = try position.string("type")
    guard ["top", "bottom", "above", "below", "into"].contains(placement) else { throw AdobeAPIError.invalid("Unknown layer placement.") }
    reference = try position.fields["referenceLayer"].map { _ in try Reference(position.object("referenceLayer", allowed: ["id", "name"])) }
    if ["above", "below", "into"].contains(placement), reference == nil {
      throw AdobeAPIError.invalid("This placement requires referenceLayer.")
    }
    if ["top", "bottom"].contains(placement), reference != nil {
      throw AdobeAPIError.unsupported("Top/bottom movement uses the document stack; referenceLayer is only supported for above/below/into.")
    }
  }
  func apply(to session: inout EditorSession) throws {
    let document = session.document, layer = try target.resolve(in: document)
    if let type {
      let actual: String
      if layer.isBackground { actual = "background_layer" }
      else if layer.smartObject != nil { actual = "smart_object_layer" }
      else { switch layer.content {
        case .group: actual = "group_layer"
        case .text: actual = "text_layer"
        case .fill: actual = "solid_color_layer"
        case .adjustment: actual = "adjustment_layer"
        default: actual = "layer"
      } }
      guard type == actual else { throw AdobeAPIError.invalid("The moved layer type does not match the input.") }
    }
    guard !layer.isBackground else { throw AdobeAPIError.unsupported("Convert Background before moving it.") }
    guard includeChildren || !layer.isGroup else {
      throw AdobeAPIError.unsupported("Moving only a group container without its children is not implemented; complete group moves preserve every child.")
    }
    if placement == "top" || placement == "bottom" {
      if layer.parentID == nil {
        try session.execute(.stackLayers(.init(layerIDs: [layer.id], operation: placement == "top" ? .bringToFront : .sendToBack)))
      } else {
        let roots = document.children(of: nil)
        try session.execute(.relocate(layer.id, nil, placement == "top" ? roots.count : (roots.first?.isBackground == true ? 1 : 0)))
      }
      return
    }
    let anchor = try reference!.resolve(in: document)
    if anchor.id == layer.id {
      guard placement != "into" else { throw AdobeAPIError.invalid("A group cannot be moved into itself.") }
      return
    }
    let moving = document.subtreeIDs(layer.id)
    guard !moving.contains(anchor.id) else { throw AdobeAPIError.invalid("A group cannot be placed relative to its own child.") }
    let parent: UUID?, position: Int
    if placement == "into" {
      guard anchor.isGroup else { throw AdobeAPIError.invalid("Into placement requires a group.") }
      parent = anchor.id
      position = document.children(of: anchor.id).filter { $0.id != layer.id }.count
    } else {
      parent = anchor.parentID
      let siblings = document.children(of: parent).filter { $0.id != layer.id }
      guard let index = siblings.firstIndex(where: { $0.id == anchor.id }) else { throw AdobeAPIError.invalid("The placement reference is unavailable.") }
      position = index + (placement == "above" ? 1 : 0)
    }
    try session.execute(.relocate(layer.id, parent, position))
  }
}
