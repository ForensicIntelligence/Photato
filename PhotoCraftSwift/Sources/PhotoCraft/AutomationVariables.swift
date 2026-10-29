import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum VariablesAPI {
  static let commands: Set<String> = ["variables.preview", "variables.define", "variables.configure", "variables.rename", "variables.dataSets", "variables.image", "variables.image.remove", "variables.import", "variables.apply", "variables.clear", "variables.export", "variables.export.cancel"]
  static var uuid: [String: Any] { ["type": "string", "format": "uuid"] }
  static var nullableUUID: [String: Any] { ["type": ["string", "null"], "format": "uuid"] }
  static var text: [String: Any] { ["type": "string", "maxLength": 100_000] }
  static var pixelOptions: [String: Any] {
    BrushAPI.object(["method": BrushAPI.enumeration(VariablePixelMethod.allCases.map(\.rawValue)),
      "alignment": BrushAPI.enumeration(CanvasAnchor.allCases.map(\.rawValue)), "clipToBounds": BrushAPI.flag])
  }
  static var definition: [String: Any] {
    BrushAPI.object(["id": uuid, "name": ["type": "string", "minLength": 1, "maxLength": 128],
      "layerID": uuid, "kind": BrushAPI.enumeration(VariableKind.allCases.map(\.rawValue)),
      "pixelOptions": pixelOptions], required: ["name", "layerID", "kind"])
  }
  static var value: [String: Any] {
    ["oneOf": [
      BrushAPI.object(["variable": text, "kind": BrushAPI.enumeration(["visibility"]), "visible": BrushAPI.flag], required: ["variable", "kind", "visible"]),
      BrushAPI.object(["variable": text, "kind": BrushAPI.enumeration(["textReplacement"]), "text": text], required: ["variable", "kind", "text"]),
      BrushAPI.object(["variable": text, "kind": BrushAPI.enumeration(["pixelReplacement"]), "imageID": nullableUUID], required: ["variable", "kind", "imageID"])
    ]]
  }
  static var row: [String: Any] {
    BrushAPI.object(["id": uuid, "name": ["type": "string", "minLength": 1, "maxLength": 256],
      "values": ["type": "array", "maxItems": DataDrivenGraphics.maximumDefinitions, "items": value]], required: ["name", "values"])
  }
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "definitions": ["type": "array", "maxItems": DataDrivenGraphics.maximumDefinitions, "items": definition]
    case "dataSets": ["type": "array", "maxItems": DataDrivenGraphics.maximumDataSets, "items": row]
    case "dataSetID", "imageID", "operationID": uuid
    case "dataSetIDs": ["type": "array", "maxItems": DataDrivenGraphics.maximumDataSets, "uniqueItems": true, "items": uuid]
    case "append", "firstColumnNames", "replaceExisting": BrushAPI.flag
    case "delimiter": BrushAPI.enumeration(VariableDataDelimiter.allCases.map(\.rawValue))
    case "text": ["type": "string", "maxLength": 3_000_000]
    case "data": ["type": "string", "contentEncoding": "base64", "maxLength": 3_000_000]
    case "format": BrushAPI.enumeration([DocumentIO.Format.native, .psd, .psb, .png, .tiff, .jpeg].map(\.rawValue))
    case "prefix": ["type": "string", "minLength": 1, "maxLength": 64]
    case "imageReferences": ["type": "array", "maxItems": 256, "items": BrushAPI.object(["reference": ["type": "string", "minLength": 1, "maxLength": 1024], "imageID": uuid], required: ["reference", "imageID"])]
    default: ["type": "string", "minLength": 1, "maxLength": key == "name" ? 1024 : 128]
    }
  }
  static let definitions: [AutomationCommand.Definition] = [
    .init(name: "variables.preview", parameters: ["definitions": "Draft bindings", "dataSets": "Draft rows", "dataSetID": "Optional draft row to apply"], description: "Render a draft template to a PNG preview without changing document, history or revision. References existing embedded images; source/share changes revoke the result.", optionalParameters: ["dataSetID"]),
    .init(name: "variables.define", parameters: ["definitions": "Replacement binding list; same name links same-kind layers."], description: "Define template variables, retaining original image frames for existing binding IDs. One Undo transaction."),
    .init(name: "variables.configure", parameters: ["definitions": "Complete bindings", "dataSets": "Complete rows", "dataSetID": "Optional row to apply with the configuration"], description: "Commit a Variables dialog configuration and optional application atomically. Referenced images must already exist in the template.", optionalParameters: ["dataSetID"]),
    .init(name: "variables.rename", parameters: ["oldName": "Existing name", "newName": "Unused valid name"], description: "Rename all linked bindings and their data values in one transaction."),
    .init(name: "variables.dataSets", parameters: ["dataSets": "Typed rows", "append": "Append instead of replacing (default false)"], description: "Create, replace, rename, reorder or delete data sets by supplying the complete row list.", optionalParameters: ["append"]),
    .init(name: "variables.image", parameters: ["name": "Image display name", "data": "Base64 still-image bytes", "imageID": "Existing ID to replace; omitted creates a new asset"], description: "Decode and color-convert a replacement image into the native template. One Undo transaction; no server-side path or URL is read.", optionalParameters: ["imageID"]),
    .init(name: "variables.image.remove", parameters: ["imageID": "Unused image ID"], description: "Remove an unreferenced replacement image."),
    .init(name: "variables.import", parameters: ["text": "Decoded CSV/TSV text", "delimiter": "comma or tab", "firstColumnNames": "Use the first column to name rows", "replaceExisting": "Replace existing rows (default true)", "imageReferences": "CSV references mapped to template image IDs"], description: "Import data sets atomically. Every variable must occur once in the header. CSV references never grant filesystem access.", optionalParameters: ["delimiter", "firstColumnNames", "replaceExisting", "imageReferences"]),
    .init(name: "variables.apply", parameters: ["dataSetID": "Data set ID"], description: "Apply all linked variables through one cancellable native transaction with Undo."),
    .init(name: "variables.clear", parameters: [:], description: "Remove template definitions, rows and replacement assets, leaving the current artwork intact. Undo restores them."),
    .init(name: "variables.export", parameters: ["format": "photato, psd, psb, png, tiff or jpeg", "prefix": "Safe filename prefix", "dataSetIDs": "Selected rows, omitted/empty means all"], description: "Render independent variations into a ZIP download. Requires document transfers; template/history are unchanged.", optionalParameters: ["prefix", "dataSetIDs"]),
    .init(name: "variables.export.cancel", parameters: ["operationID": "Current data-set export ID"], description: "Cancel the matching export operation.")
  ]
  static func values(_ values: [String: VariableValue]) -> [[String: Any]] {
    values.keys.sorted().map { name in
      var result: [String: Any] = ["variable": name, "kind": values[name]!.kind.rawValue]
      switch values[name]! {
      case .visibility(let value): result["visible"] = value
      case .text(let value): result["text"] = value
      case .pixels(let value): result["imageID"] = value?.uuidString as Any? ?? NSNull()
      }
      return result
    }
  }
  static func state(_ document: CraftDocument, exportID: UUID? = nil) -> [String: Any] {
    let variables = document.variables ?? DataDrivenGraphics()
    return ["definitions": variables.definitions.map { definition -> [String: Any] in
      var item: [String: Any] = ["id": definition.id.uuidString, "name": definition.name, "kind": definition.kind.rawValue, "layerID": definition.layerID.uuidString]
      if let options = definition.pixelOptions { item["pixelOptions"] = BrushAPI.json(options) }
      if let frame = definition.pixelFrame { item["pixelFrame"] = BrushAPI.json(frame) }
      return item
    }, "dataSets": variables.dataSets.map { ["id": $0.id.uuidString, "name": $0.name, "values": values($0.values)] as [String: Any] },
    "images": variables.images.map { ["id": $0.id.uuidString, "name": $0.name, "width": $0.pixels.width, "height": $0.pixels.height, "depth": $0.pixels.depth.rawValue] as [String: Any] },
    "activeDataSetID": variables.activeDataSetID?.uuidString as Any? ?? NSNull(),
    "exportOperationID": exportID?.uuidString as Any? ?? NSNull()]
  }
  static func parseUUID(_ value: String) throws -> UUID {
    guard let id = UUID(uuidString: value) else { throw AutomationFailure(status: 400, message: "Invalid variable identifier.") }
    return id
  }
  static var stateSchema: [String: Any] {
    var binding = definition
    var fields = binding["properties"] as! [String: Any]
    fields["pixelFrame"] = BrushAPI.object(["width": BrushAPI.number(1, 1_000_000, integer: true), "height": BrushAPI.number(1, 1_000_000, integer: true),
      "transform": BrushAPI.object(Dictionary(uniqueKeysWithValues: ["a", "b", "c", "d", "tx", "ty"].map { ($0, ["type": "number"]) }), required: ["a", "b", "c", "d", "tx", "ty"])], required: ["width", "height", "transform"])
    binding["properties"] = fields; binding["required"] = ["id", "name", "layerID", "kind"]
    var rowState = row; rowState["required"] = ["id", "name", "values"]
    let asset = BrushAPI.object(["id": uuid, "name": schema("name"), "width": BrushAPI.number(1, 1_000_000, integer: true), "height": BrushAPI.number(1, 1_000_000, integer: true), "depth": BrushAPI.enumeration(PixelDepth.allCases.map(\.rawValue))], required: ["id", "name", "width", "height", "depth"])
    let fieldsOut: [String: Any] = ["definitions": ["type": "array", "maxItems": DataDrivenGraphics.maximumDefinitions, "items": binding],
      "dataSets": ["type": "array", "maxItems": DataDrivenGraphics.maximumDataSets, "items": rowState],
      "images": ["type": "array", "maxItems": DataDrivenGraphics.maximumImages, "items": asset], "activeDataSetID": nullableUUID, "exportOperationID": nullableUUID]
    return BrushAPI.object(fieldsOut, required: Array(fieldsOut.keys).sorted())
  }
  static var capabilities: [String: Any] {
    ["commands": commands.sorted(), "stateSchema": stateSchema, "nativeArchiveVersion": 61,
     "maximumDefinitions": DataDrivenGraphics.maximumDefinitions, "maximumDataSets": DataDrivenGraphics.maximumDataSets,
     "maximumImages": DataDrivenGraphics.maximumImages, "maximumOutputBytes": VariableDataExport.maximumBytes,
     "input": "Linked visibility, text and pixel bindings; typed rows; inline still images converted into the template profile. CSV references explicitly map to uploaded image IDs; no local paths or remote URLs are read by the API.",
     "transactions": "Desktop and API use the same prepared Undo transaction. Apply is atomic. Each exported variation starts from the original template. Export/cancel leave document and history unchanged; transfers and sharing must remain enabled.",
     "persistence": "Native61 retains bindings, original frames, rows and image assets. Non-native rendered variations omit template definitions; direct PSD template save rejects to prevent metadata loss.",
     "limits": "Template assets512MiB, metadata16MiB; API image/text payload3,000,000 characters within the4MiB command limit. Pixel Replacement requires ordinary RGB raster layers. RGB profile assignment/conversion updates embedded replacement assets atomically. Broader mode/depth lifecycle, full PSD variable interchange, Actions descriptors and exact Photoshop pixel/UI/platform parity remain open.",
     "adobe": "No dedicated Variables/Data Sets route exists in the pinned Photoshop v2 contract. No Adobe endpoint is invented; corresponding execute-actions descriptors remain unqualified."]
  }
}

extension AutomationCommand {
  func variableString(_ key: String) throws -> String {
    guard let value = parameters[key] else { throw AutomationFailure(status: 400, message: "Missing \(key).") }
    return try BrushAPI.merge(value, schema: VariablesAPI.schema(key), path: key) as! String
  }
  func variableRows() throws -> [VariableDataSet] {
    guard let value = parameters["dataSets"] else { throw AutomationFailure(status: 400, message: "Missing dataSets.") }
    let raw = try BrushAPI.merge(value, schema: VariablesAPI.schema("dataSets"), path: "dataSets") as! [[String: Any]]
    return try raw.map { item in
      var values: [String: VariableValue] = [:]
      for field in item["values"] as! [[String: Any]] {
        let name = field["variable"] as! String
        guard values[name] == nil else { throw AutomationFailure(status: 400, message: "A data set repeats a variable.") }
        switch field["kind"] as! String {
        case "visibility": values[name] = .visibility(field["visible"] as! Bool)
        case "textReplacement": values[name] = .text(field["text"] as! String)
        default: values[name] = .pixels(try (field["imageID"] as? String).map(VariablesAPI.parseUUID))
        }
      }
      return .init(id: try (item["id"] as? String).map(VariablesAPI.parseUUID) ?? UUID(), name: item["name"] as! String, values: values)
    }
  }
  func variableDefinitions(in document: CraftDocument) throws -> [VariableDefinition] {
    guard let value = parameters["definitions"] else { throw AutomationFailure(status: 400, message: "Missing definitions.") }
    let raw = try BrushAPI.merge(value, schema: VariablesAPI.schema("definitions"), path: "definitions") as! [[String: Any]]
    return try raw.map { item in
      let kind = VariableKind(rawValue: item["kind"] as! String)!, layer = try VariablesAPI.parseUUID(item["layerID"] as! String)
      let old = document.variables?.definitions.first { $0.layerID == layer && $0.kind == kind }
      let id = try (item["id"] as? String).map(VariablesAPI.parseUUID) ?? old?.id ?? UUID()
      var options: VariablePixelOptions?
      if let rawOptions = item["pixelOptions"] as? [String: Any] {
        guard kind == .pixelReplacement else { throw AutomationFailure(status: 400, message: "Only pixel variables accept placement options.") }
        var parsed = VariablePixelOptions()
        if let value = rawOptions["method"] as? String { parsed.method = VariablePixelMethod(rawValue: value)! }
        if let value = rawOptions["alignment"] as? String { parsed.alignment = CanvasAnchor(rawValue: value)! }
        if let value = rawOptions["clipToBounds"] as? Bool { parsed.clipToBounds = value }
        options = parsed
      }
      return .init(id: id, name: item["name"] as! String, layerID: layer, kind: kind, pixelOptions: options)
    }
  }
  func variableCommand(in document: CraftDocument) throws -> Command {
    switch name {
    case "variables.define": return .variables(.define(try variableDefinitions(in: document)))
    case "variables.configure", "variables.preview":
      var settings = document.variables ?? .init()
      settings.definitions = try variableDefinitions(in: document); settings.dataSets = try variableRows()
      return .variables(.configure(settings, apply: try parameters["dataSetID"].map { _ in try actionUUID("dataSetID") }))
    case "variables.rename": return .variables(.rename(try string("oldName"), try string("newName")))
    case "variables.dataSets": return .variables(.dataSets(try variableRows(), append: try pathFlag("append", false)))
    case "variables.apply": return .variables(.apply(try actionUUID("dataSetID")))
    case "variables.clear": return .variables(.clear)
    case "variables.image.remove": return .variables(.removeImage(try actionUUID("imageID")))
    case "variables.image":
      let text = try variableString("data")
      guard text.utf8.count <= 3_000_000, let bytes = Data(base64Encoded: text) else { throw AutomationFailure(status: 400, message: "Supply bounded base64 still-image data.") }
      let id = try parameters["imageID"].map { _ in try actionUUID("imageID") } ?? UUID()
      return .variables(.image(try VariableGraphicsInput.image(bytes, name: variableString("name"), id: id, for: document)))
    case "variables.import":
      var settings = document.variables ?? .init(), options = VariableDataImportOptions()
      options.firstColumnNames = try pathFlag("firstColumnNames", false); options.replaceExisting = try pathFlag("replaceExisting", true)
      if parameters["delimiter"] != nil {
        guard let delimiter = VariableDataDelimiter(rawValue: try string("delimiter")) else { throw AutomationFailure(status: 400, message: "Choose comma or tab.") }; options.delimiter = delimiter
      }
      var references: [String: UUID] = [:]
      if let value = parameters["imageReferences"] {
        let items = try BrushAPI.merge(value, schema: VariablesAPI.schema("imageReferences"), path: "imageReferences") as! [[String: Any]]
        for item in items {
          let key = item["reference"] as! String
          guard references[key] == nil else { throw AutomationFailure(status: 400, message: "Duplicate image reference.") }
          references[key] = try VariablesAPI.parseUUID(item["imageID"] as! String)
        }
      }
      let rows = try VariableDataImport.dataSets(variableString("text"), variables: settings, options: options) { reference in
        guard let id = references[reference], settings.images.contains(where: { $0.id == id }) else { throw CraftError.invalid("Map each CSV image reference to an uploaded template image.") }; return id
      }
      settings.dataSets = options.replaceExisting ? rows : settings.dataSets + rows
      return .variables(.configure(settings, apply: nil))
    default: throw AutomationFailure(status: 400, message: "Unknown variable operation.")
    }
  }
}

extension AutomationService {
  func previewVariableData(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard !previewBusy else { throw AutomationFailure(status: 429, message: "A preview is already rendering. Retry shortly.") }
    previewBusy = true; defer { previewBusy = false }
    let snapshot = document.store.document, expectedGeneration = generation
    let worker = Task.detached(priority: .userInitiated) {
      var candidate = snapshot
      try command.variableCommand(in: snapshot).apply(to: &candidate)
      try Self.checkLimits(candidate)
      return try Self.png(candidate)
    }
    let bytes = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    prune()
    guard !Task.isCancelled, generation == expectedGeneration, revision(document.store) == command.revision,
      document.store.document == snapshot, shares.contains(where: { $0.id == shareID && $0.document === document }) else {
      throw AutomationFailure(status: 409, message: "The preview source changed or sharing ended.")
    }
    return .init(status: 200, contentType: "image/png", body: bytes)
  }
}
