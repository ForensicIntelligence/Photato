import Foundation
import PhotoCraftCore

extension Artboard {
  var apiState: Any { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) ?? NSNull() }
  static var apiCapabilities: [String: Any] {
    ["edit": "artboard.edit", "export": "artboard.export", "nativeArchiveVersion": 27,
     "coordinates": "Bounds use logical document pixels; artboardOrigin maps physical canvas pixel0 to logical coordinates. Guides are local artboard offsets. Negative bounds expand and rebase the canvas without resampling layer pixels.",
     "behavior": "Top-level groups clip children and paint their background. Create, convert, configure, duplicate, clear guides and remove artboard metadata share native one-step Undo/Redo. Native files retain editable layers. Raster exports and multipage PDF use identical clipped rendering.",
     "limits": "Shared documents:300,000 pixels per side and8,000 layers within128MiB owned heap; exports128MiB. JSON/PNG/JPEG/TIFF Adobe create-artboard jobs are a bounded local subset. PSD/PSB artboards use whole-pixel RGB boards, admitted backgrounds and 1/32-pixel guides; broader format/precision contexts remain unqualified.",
     "operations": ["create", "convert", "configure", "duplicate", "guides.clear", "ungroup", "adjacent"], "adjacent": ["sides": ArtboardSide.allCases.map(\.rawValue), "defaultSpacing": 100, "spacingUnit": "logical pixels", "duplicate": "Option-click copies contents; API duplicate is explicit. New boards inherit size/background and start empty. Exact Photoshop defaults remain unqualified."], "exportFormats": ArtboardExport.formats,
     "interchange":"Shared PSD/PSB file transfers and native saves retain admitted editable RGB artboards, logical origin and scoped guides. The dedicated artboard.export command retains its existing output-format list; no Adobe route or output type is added."]
  }
}
extension AutomationCommand {
  static func artboardSchema(_ key: String) -> [String: Any] {
    switch key {
    case "operation": return ["type": "string", "enum": ["create", "convert", "configure", "duplicate", "guides.clear", "ungroup", "adjacent"]]
    case "side": return ["type": "string", "enum": ArtboardSide.allCases.map(\.rawValue)]
    case "duplicate": return ["type": "boolean", "default": false]
    case "spacing": return ["type": "integer", "minimum": 0, "maximum": 32768, "default": 100]
    case "layerID": return ["type": "string", "format": "uuid"]
    case "layerIDs": return ["type": "array", "maxItems": LayerLimits.maximumLayers, "uniqueItems": true, "items": ["type": "string", "format": "uuid"]]
    case "name": return ["type": "string", "minLength": 1, "maxLength": 256]
    case "format": return ["type": "string", "enum": ArtboardExport.formats]
    case "moveContents": return ["type": "boolean", "default": true]
    case "bounds": return ["type": "object", "additionalProperties": false, "required": ["x", "y", "width", "height"], "properties": ["x": ["type": "integer", "minimum": -1_000_000, "maximum": 1_000_000], "y": ["type": "integer", "minimum": -1_000_000, "maximum": 1_000_000], "width": ["type": "integer", "minimum": 1, "maximum": 300000], "height": ["type": "integer", "minimum": 1, "maximum": 300000]]]
    case "background": return ["type": "object", "additionalProperties": false, "required": ["r", "g", "b", "a"], "properties": Dictionary(uniqueKeysWithValues: ["r", "g", "b", "a"].map { ($0, ["type": "number", "minimum": 0, "maximum": 1]) })]
    case "guides": return ["type": "array", "maxItems": 512, "items": ["type": "object", "additionalProperties": false, "required": ["axis", "position"], "properties": ["axis": ["type": "string", "enum": ["horizontal", "vertical"]], "position": ["type": "number", "minimum": -1_000_000, "maximum": 1_000_000]]]]
    default: return [:]
    }
  }
  func artboardIDs() throws -> [UUID] {
    guard case .array(let values) = parameters["layerIDs"], values.count <= LayerLimits.maximumLayers else { throw AutomationFailure(status: 400, message: "layerIDs must be an array of up to8,000 distinct UUIDs.") }
    let ids = try values.map { value -> UUID in guard case .string(let string) = value, let id = UUID(uuidString: string) else { throw AutomationFailure(status: 400, message: "Invalid artboard layer UUID.") }; return id }
    guard Set(ids).count == ids.count else { throw AutomationFailure(status: 400, message: "Duplicate layer IDs.") }; return ids
  }
  func artboardCommand(_ document: CraftDocument) throws -> Command {
    func fail(_ text: String) -> AutomationFailure { .init(status: 400, message: text) }
    let operation = try string("operation")
    let required: Set<String>, optional: Set<String>
    switch operation {
    case "create": required = ["name", "bounds"]; optional = ["background", "layerIDs"]
    case "convert": required = ["layerID", "bounds"]; optional = ["background"]
    case "configure": required = ["layerID", "bounds"]; optional = ["name", "background", "guides", "moveContents"]
    case "duplicate": required = ["layerID", "bounds"]; optional = ["name"]
    case "adjacent": required = ["layerID", "side"]; optional = ["duplicate", "spacing", "name"]
    case "guides.clear", "ungroup": required = ["layerID"]; optional = []
    default: throw fail("Unknown artboard operation.")
    }
    let keys = Set(parameters.keys).subtracting(["operation"])
    guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else { throw fail("Missing or irrelevant artboard parameters.") }
    let id = try parameters["layerID"].map { _ in try actionUUID("layerID") }
    let layer = id.flatMap { id in document.layers.first { $0.id == id } }
    if id != nil && layer == nil { throw AutomationFailure(status: 404, message: "Layer not found.") }
    if operation == "adjacent" {
      guard let side = ArtboardSide(rawValue: try string("side")) else { throw fail("Invalid artboard side.") }
      var duplicate = false, spacing = 100
      if let value = parameters["duplicate"] { guard case .bool(let b) = value else { throw fail("duplicate must be boolean.") }; duplicate = b }
      if let value = parameters["spacing"] { guard case .number(let n) = value, n.isFinite, n.rounded() == n, (0...32768).contains(n) else { throw fail("Invalid artboard spacing.") }; spacing = Int(n) }
      return try ArtboardNeighborRequest(layerID: id!, side: side, duplicate: duplicate, spacing: spacing, name: try parameters["name"].map { _ in try string("name") }).command(in: document)
    }
    if operation == "guides.clear" { return .artboard(.clearGuides(id!)) }
    if operation == "ungroup" { return .artboard(.removeMetadata(id!)) }
    guard case .object(let rawBounds) = parameters["bounds"], Set(rawBounds.keys) == ["x", "y", "width", "height"] else { throw fail("bounds requires x,y,width,height.") }
    func integer(_ key: String, _ range: ClosedRange<Double>) throws -> Int {
      guard case .number(let n) = rawBounds[key], n.isFinite, n.rounded() == n, range.contains(n) else { throw fail("Invalid artboard \(key).") }; return Int(n)
    }
    let bounds = try IntRect(x: integer("x", -1_000_000...1_000_000), y: integer("y", -1_000_000...1_000_000), width: integer("width", 1...300000), height: integer("height", 1...300000))
    var background = layer?.artboard?.background ?? .white
    if let raw = parameters["background"] {
      guard case .object(let fields) = raw, Set(fields.keys) == ["r", "g", "b", "a"] else { throw fail("Background requires RGBA components.") }
      let components = try ["r", "g", "b", "a"].map { key -> Float in guard case .number(let n) = fields[key], n.isFinite, (0...1).contains(n) else { throw fail("Invalid background component.") }; return Float(n) }
      background = Pixel(components[0], components[1], components[2], components[3])
    }
    if operation == "create" { return .artboard(.create(name: try string("name"), bounds: bounds, background: background, children: try parameters["layerIDs"] == nil ? [] : artboardIDs())) }
    if operation == "convert" { return .artboard(.convert(id!, bounds: bounds, background: background)) }
    if operation == "duplicate" {
      guard let board = layer?.artboard, bounds.width == board.width, bounds.height == board.height else { throw fail("Duplicate bounds must retain the source artboard size.") }
      return .artboard(.duplicate(id!, x: bounds.x, y: bounds.y, name: try parameters["name"].map { _ in try string("name") }))
    }
    var guides = layer?.artboard?.guides ?? []
    if let raw = parameters["guides"] {
      guard case .array(let values) = raw, values.count <= 512 else { throw fail("Too many artboard guides.") }
      guides = try values.map { raw in
        guard case .object(let g) = raw, Set(g.keys) == ["axis", "position"], case .string(let axis) = g["axis"], let axis = ArtboardGuide.Axis(rawValue: axis), case .number(let p) = g["position"], p.isFinite, abs(p) <= 1_000_000 else { throw fail("Invalid artboard guide.") }
        return ArtboardGuide(axis: axis, position: p)
      }
    }
    var move = true
    if let raw = parameters["moveContents"] { guard case .bool(let b) = raw else { throw fail("moveContents must be boolean.") }; move = b }
    let board = Artboard(width: bounds.width, height: bounds.height, background: background, preset: layer?.artboard?.preset ?? "", guides: guides)
    return .artboard(.configure(id!, name: try parameters["name"] == nil ? layer!.name : string("name"), bounds: bounds, appearance: board, moveContents: move))
  }
}
extension AutomationService {
  func exportArtboard(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers before exporting artboards.") }
    let ids = try command.artboardIDs(), format = try command.string("format")
    let snapshot = document.store.document, expectedToken = token
    let worker = Task.detached(priority: .utility) { try ArtboardExport.encode(snapshot, ids: ids, format: format) }
    let bytes = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    prune()
    guard isRunning, token == expectedToken, shares.contains(where: { $0.id == shareID }), revision(document.store) == command.revision else { throw AutomationFailure(status: 409, message: "Document sharing changed during artboard export.") }
    return .init(status: 200, contentType: format == "pdf" ? "application/pdf" : DocumentIO.Format(rawValue: format)!.mediaType, body: bytes)
  }
}
