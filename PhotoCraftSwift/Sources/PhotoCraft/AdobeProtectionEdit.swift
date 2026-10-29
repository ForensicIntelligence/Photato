import CoreFoundation
import Foundation
import PhotoCraftCore

/// Supported create-composite edit subset. All other edits are explicit failures.
struct AdobeProtectionEdit: Sendable {
  enum Target: Sendable { case name(String), identifier(Int32) }
  let target: Target
  let type: String?
  let protection: LayerProtection?
  let effects: [LayerEffect]?

  init(_ raw: Any, path: String) throws {
    guard let object = raw as? [String: Any] else {
      throw AdobeAPIError.invalid("\(path) must be an object.")
    }
    guard Set(object.keys).isSubset(of: ["id", "name", "operation", "type", "protection", "layerEffects"]) else {
      throw AdobeAPIError.unsupported("Only layer protection and supported dropShadow edits are implemented by create-composite.")
    }
    guard let operation = object["operation"] as? [String: Any],
      Set(operation.keys) == ["type"], operation["type"] as? String == "edit" else {
      throw AdobeAPIError.unsupported("Only operation.type edit is implemented by create-composite.")
    }
    guard (object["id"] == nil) != (object["name"] == nil) else {
      throw AdobeAPIError.unsupported("Provide one layer reference: id or name.")
    }
    if let id = object["id"] {
      guard let value = id as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
        value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
        value.doubleValue >= Double(Int32.min), value.doubleValue <= Double(Int32.max) else {
        throw AdobeAPIError.invalid("Layer id must be a signed32-bit integer.")
      }
      target = .identifier(value.int32Value)
    } else {
      guard let name = object["name"] as? String, !name.isEmpty, name.utf16.count <= 65_535 else {
        throw AdobeAPIError.invalid("Layer name must be a nonempty string.")
      }
      target = .name(name)
    }
    if let raw = object["type"] {
      guard let value = raw as? String,
        ["layer", "group_layer", "solid_color_layer", "text_layer", "smart_object_layer",
          "adjustment_layer", "background_layer"].contains(value) else {
        throw AdobeAPIError.invalid("Unknown layer type.")
      }
      type = value
    } else { type = nil }
    effects = try AdobeLayerEffects.parse(object["layerEffects"])
    switch try AdobeLayerProtection.parse(object["protection"], addingLayer: false) {
    case .unchanged: protection = nil
    case .replace(let value): protection = value
    }
  }

  func apply(to session: inout EditorSession) throws {
    let matches = session.document.layers.filter { layer in
      switch target {
      case .name(let name): return layer.name == name
      case .identifier(let id):
        guard let raw = layer.sourceTags?["lyid"], raw.count == 4 else { return false }
        let value = raw.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Int32(bitPattern: value) == id
      }
    }
    guard matches.count == 1, let layer = matches.first else {
      throw AdobeAPIError.invalid("The layer reference must match exactly one input layer.")
    }
    if let type {
      let expected: String
      switch layer.content {
      case .group: expected = "group_layer"
      case .text: expected = "text_layer"
      case .fill: expected = "solid_color_layer"
      case .adjustment: expected = "adjustment_layer"
      default: expected = "layer"
      }
      guard type == (layer.smartObject == nil ? expected : "smart_object_layer") else {
        throw AdobeAPIError.unsupported("The requested layer type does not match the native input layer.")
      }
    }
    if let effects {
      guard !layer.isGroup else { throw AdobeAPIError.unsupported("Group layerEffects are not implemented by this adapter.") }
      var style = layer.style ?? LayerStyle()
      style.effects.removeAll { $0.kind == .dropShadow }; style.effects += effects
      try session.execute(.layerStyle([layer.id], style))
    }
    guard let protection else { return }
    // Adobe explicitly applies group protection to descendants, including their
    // stored flags. Native group inheritance alone is not this transport contract.
    let ids = session.document.subtreeIDs(layer.id)
    try session.execute(.protection(Dictionary(uniqueKeysWithValues: ids.map { ($0, protection) })))
  }
}

extension LayerProtection {
  var apiNames: [String] {
    if fullyLocks { return ["all"] }
    if isEmpty { return ["none"] }
    return [("transparency", Self.transparency), ("composite", Self.image),
      ("position", Self.position), ("artboard_autonest", Self.autoNest)]
      .filter { contains($0.1) }.map(\.0)
  }
}
