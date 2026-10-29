import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RestrictedModeAPI {
  static let commands = ["document.convertIndexed", "document.convertBitmap", "indexed.colorTable.read", "indexed.colorTable.write", "indexed.indices.read", "indexed.indices.write"]
  static let edits = ["document.convertIndexed", "document.convertBitmap", "indexed.colorTable.write", "indexed.indices.write"]
  static var color: [String: Any] { BrushAPI.object(["red": byte, "green": byte, "blue": byte], required: ["red", "green", "blue"]) }
  static var byte: [String: Any] { ["type": "integer", "minimum": 0, "maximum": 255] }
  static var colors: [String: Any] { ["type": "array", "minItems": 1, "maxItems": 256, "items": color] }
  static var optionalColors: [String: Any] { var schema = colors; schema["minItems"] = 0; return schema }
  static var indexed: [String: Any] { BrushAPI.object([
    "palette": BrushAPI.enumeration(IndexedPaletteKind.allCases.map(\.rawValue)), "colors": ["type": "integer", "minimum": 2, "maximum": 256],
    "forced": BrushAPI.enumeration(IndexedForcedColors.allCases.map(\.rawValue)), "forcedColors": optionalColors, "customPalette": optionalColors,
    "transparency": BrushAPI.flag, "matte": color, "dither": BrushAPI.enumeration(IndexedDither.allCases.map(\.rawValue)),
    "amount": ["type": "number", "minimum": 0, "maximum": 1], "preserveExact": BrushAPI.flag], required: []) }
  static var bitmap: [String: Any] { BrushAPI.object([
    "method": BrushAPI.enumeration(BitmapConversionMethod.allCases.map(\.rawValue)),
    "outputResolution": ["type": "number", "minimum": 1, "maximum": 9600],
    "frequency": ["type": "number", "minimum": 1, "maximum": 999.999],
    "angle": ["type": "number", "minimum": -180, "maximum": 180], "shape": BrushAPI.enumeration(BitmapHalftoneShape.allCases.map(\.rawValue)),
    "pattern": BrushAPI.object(["width": ["type": "integer", "minimum": 1, "maximum": 1024], "height": ["type": "integer", "minimum": 1, "maximum": 1024], "samples": ["type": "string", "contentEncoding": "base64", "maxLength": 1_398_104]], required: ["width", "height", "samples"])], required: []) }
  static func schema(_ key: String, command: String) -> [String: Any] {
    switch key {
    case "settings": return command == "document.convertIndexed" ? indexed : bitmap
    case "mergeVisible": return BrushAPI.flag
    case "colors", "previousPalette": return colors
    case "transparentIndex": return ["type": "integer", "minimum": -1, "maximum": 255, "description": "-1 removes transparency; omission retains existing transparency for color table edits."]
    case "actBase64": return ["type": "string", "contentEncoding": "base64", "maxLength": 1032]
    case "offset": return ["type": "integer", "minimum": 0, "maximum": PaletteQuantization.maximumPixels - 1]
    case "count": return ["type": "integer", "minimum": 1, "maximum": 4096]
    case "values": return ["type": "array", "minItems": 1, "maxItems": 4096, "items": byte]
    case "sources": return ["type": "array", "minItems": 1, "maxItems": 7, "items": BrushAPI.object(["id": ["type": "string", "format": "uuid"], "revision": ["type": "string", "minLength": 1, "maxLength": 256]], required: ["id", "revision"])]
    default: return [:]
    }
  }
  static var capabilities: [String: Any] { [
    "commands": commands, "nativeArchive": 47, "maximumPixels": PaletteQuantization.maximumPixels, "maximumIndexPage": 4096,
    "indexedSettings": indexed, "bitmapSettings": bitmap,
    "behavior": "Indexed conversion requires RGB/Grayscale8; Bitmap requires Grayscale8. Layer flattening/discarding auxiliary channels requires mergeVisible. Palette changes retain pixel indices, including duplicate colors. Index writes bypass selection and reject missing palette entries. Each edit is one atomic Undo with revision, busy and revocation checks.",
    "masterPalettes": "Provide additional shared sources with revisions; target is included automatically. All sources are immutable snapshots, combined up to 8,388,608 pixels. Only master palette modes accept sources. Previous palettes are explicit arrays; clients never depend on desktop history.",
    "colorTableResultSchema": BrushAPI.object(["colors": colors, "transparentIndex": schema("transparentIndex", command: ""), "actBase64": schema("actBase64", command: ""), "revision": ["type": "string"]], required: ["colors", "transparentIndex", "actBase64", "revision"]),
    "indexResultSchema": BrushAPI.object(["values": schema("values", command: ""), "offset": schema("offset", command: ""), "width": ["type": "integer", "minimum": 1], "height": ["type": "integer", "minimum": 1], "revision": ["type": "string"]], required: ["values", "offset", "width", "height", "revision"]),
    "colorTable": "Read returns colors, transparentIndex (-1 if absent), ACT base64 and revision; write accepts exactly one of colors or actBase64. Omitted transparentIndex preserves the current value for colors, or uses the ACT file value. ACT bytes are native 768/772-byte tables.",
    "indexResult": "Read returns row-major values, offset, width, height and revision. No history mutation. Values refer to palette entries, not their RGB values.",
    "limits": "Quantization/halftone settings are implemented natively from licensed PhotoCraft and public documentation. Exact Photoshop output, full tool/mode semantics and Adobe restricted conversion action descriptors remain unqualified; no new Adobe route is invented."] }
  static func decode<T: Codable>(_ value: AutomationValue?, schema: [String: Any], base: T) throws -> T {
    guard let value else { return base }
    do { return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: BrushAPI.merge(value, schema: schema, base: BrushAPI.json(base)))) }
    catch let error as AutomationFailure { throw error }
    catch { throw AutomationFailure(status: 400, message: "Invalid restricted-mode settings: \(error.localizedDescription)") }
  }
  static func palette(_ value: AutomationValue) throws -> [PaletteColor] {
    let raw = try BrushAPI.merge(value, schema: colors, base: [])
    return try JSONDecoder().decode([PaletteColor].self, from: JSONSerialization.data(withJSONObject: raw))
  }
}

extension AutomationCommand {
  func restrictedModeRequest(in document: CraftDocument) throws -> RestrictedModeRequest {
    var request = RestrictedModeRequest(name == "document.convertIndexed" ? .indexed : name == "document.convertBitmap" ? .bitmap : .colorTable)
    request.mergeVisible = try pathFlag("mergeVisible", false)
    switch request.kind {
    case .indexed:
      request.indexed = try RestrictedModeAPI.decode(parameters["settings"], schema: RestrictedModeAPI.indexed, base: IndexedColorSettings())
      if let previous = parameters["previousPalette"] { request.previousPalette = try RestrictedModeAPI.palette(previous) }
      try request.indexed.validate()
    case .bitmap:
      var settings = BitmapConversionSettings(); settings.outputResolution = document.pixelsPerInch
      request.bitmap = try RestrictedModeAPI.decode(parameters["settings"], schema: RestrictedModeAPI.bitmap, base: settings)
      try request.bitmap.validate()
    case .colorTable:
      guard case .indexed(let raster) = document.restrictedMode else { throw AutomationFailure(status: 422, message: "Color Table requires Indexed Color.") }
      guard (parameters["colors"] == nil) != (parameters["actBase64"] == nil) else { throw AutomationFailure(status: 400, message: "Provide exactly one of colors or actBase64.") }
      if let colors = parameters["colors"] { request.colors = try RestrictedModeAPI.palette(colors); request.transparentIndex = raster.transparentIndex }
      else {
        guard case .string(let encoded) = parameters["actBase64"], encoded.count <= 1032, let bytes = Data(base64Encoded: encoded) else { throw AutomationFailure(status: 400, message: "Invalid ACT encoding.") }
        let table = try ColorTableFile(data: bytes); request.colors = table.colors; request.transparentIndex = table.transparentIndex
      }
      if parameters["transparentIndex"] != nil { let index = try integer("transparentIndex", range: -1...255); request.transparentIndex = index == -1 ? nil : index }
    }
    return request
  }
  func indexedPage(in document: CraftDocument) throws -> (IndexedRaster, Int) {
    guard case .indexed(let raster) = document.restrictedMode else { throw AutomationFailure(status: 422, message: "This operation requires Indexed Color.") }
    let offset = try parameters["offset"].map { _ in try integer("offset", range: 0...Double(raster.indices.count - 1)) } ?? 0
    return (raster, offset)
  }
  func indexedWrite(in document: CraftDocument) throws -> Command {
    let (raster, offset) = try indexedPage(in: document)
    guard let id = document.activeLayerID, !document.isImageLocked(id) else { throw AutomationFailure(status: 422, message: "Unlock the indexed layer before writing pixels.") }
    guard let value = parameters["values"] else { throw AutomationFailure(status: 400, message: "Missing indices.") }
    let array = try BrushAPI.merge(value, schema: RestrictedModeAPI.schema("values", command: name), base: [])
    let values = try JSONDecoder().decode([UInt8].self, from: JSONSerialization.data(withJSONObject: array))
    guard values.count <= raster.indices.count - offset, values.allSatisfy({ Int($0) < raster.palette.count }) else { throw AutomationFailure(status: 400, message: "Indices exceed the pixel range or color table.") }
    var bytes = raster.indices; bytes.replaceSubrange(offset..<offset + values.count, with: values)
    let changed = try raster.replacingIndices(bytes); var result = document
    result.restrictedMode = .indexed(changed); result.layers[0].content = .raster(try changed.surface())
    return .preparedDocumentMode(.init(source: document, result: result, title: "Edit Color Indices"))
  }
}

extension AutomationService {
  func executeRestrictedMode(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws {
    let request = try command.restrictedModeRequest(in: document.store.document)
    var inputs: [(UUID, String, CraftNSDocument)] = []
    if let raw = command.parameters["sources"] {
      guard request.kind == .indexed, [.masterPerceptual, .masterSelective, .masterAdaptive].contains(request.indexed.palette) else { throw AutomationFailure(status: 400, message: "Additional sources require a master palette.") }
      _ = try BrushAPI.merge(raw, schema: RestrictedModeAPI.schema("sources", command: command.name), base: [])
      guard case .array(let sources) = raw else { throw AutomationFailure(status: 400, message: "Invalid sources.") }
      for source in sources {
        guard case .object(let fields) = source, case .string(let text) = fields["id"], let id = UUID(uuidString: text), id != shareID,
          !inputs.contains(where: { $0.0 == id }), case .string(let expected) = fields["revision"],
          let input = shares.first(where: { $0.id == id })?.document else { throw AutomationFailure(status: 400, message: "Each additional source must be a distinct shared document.") }
        try preflight(input)
        guard revision(input.store) == expected else { throw AutomationFailure(status: 409, message: "A master source revision is stale.") }
        inputs.append((id, expected, input))
      }
    }
    let snapshots = inputs.map { $0.2.store.document }, captured = inputs
    try await executePreparedOperation(document: document, shareID: shareID, revision: command.revision, validateCommit: { [self] in
      for (index, entry) in captured.enumerated() {
        let (id, expected, input) = entry
        guard shares.contains(where: { $0.id == id && $0.document === input }), revision(input.store) == expected, input.store.document == snapshots[index] else { throw AutomationFailure(status: 409, message: "A master source changed or sharing ended.") }
        try preflight(input)
      }
    }) { source in try request.command(in: source, masters: snapshots) }
    if case .indexed(let raster) = document.store.document.restrictedMode { document.store.previousIndexedPalette = raster.palette }
  }
}
