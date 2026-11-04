import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ImageExportAPI {
  static let commands: Set<String> = ["image.export", "image.export.cancel", "export.preferences"]
  static let definitions: [AutomationCommand.Definition] = [
    .init(name: "image.export", parameters: ["settings": "Export target, assets, format, dimensions, scales, color and metadata options"], description: "Download PNG/JPEG/GIF assets plus a manifest as ZIP using native Export As. Requires transfers; source/history unchanged.", optionalParameters: ["settings"]),
    .init(name: "image.export.cancel", parameters: ["operationID": "Active image or color lookup export UUID"], description: "Cancel the matching asset or global color lookup export without revoking document access."),
    .init(name: "export.preferences", parameters: ["settings": "Quick Export format, quality, transparency, color and metadata preferences"], description: "Read or update native Quick Export preferences without changing document history.", optionalParameters: ["settings"])
  ]
  static let preferenceKeys: Set<String> = ["format", "quality", "transparency", "convertToSRGB", "embedProfile", "metadata"]
  static var settingsSchema: [String: Any] {
    ["type": "object", "additionalProperties": false, "properties": [
      "format": BrushAPI.enumeration(ImageExportSettings.Format.allCases.map(\.rawValue)),
      "target": BrushAPI.enumeration(ImageExportSettings.Target.allCases.map(\.rawValue)),
      "ids": ["type": "array", "maxItems": 256, "uniqueItems": true, "items": VariablesAPI.uuid],
      "scales": ["type": "array", "minItems": 1, "maxItems": 16, "items": ["type": "object", "additionalProperties": false, "required": ["factor", "suffix"], "properties": ["factor": ["type": "number", "minimum": 0.01, "maximum": 1000], "suffix": ["type": "string", "maxLength": 64]]]],
      "width": ["type": "integer", "minimum": 1, "maximum": Surface.maxDimension], "height": ["type": "integer", "minimum": 1, "maximum": Surface.maxDimension],
      "canvasWidth": ["type": "integer", "minimum": 1, "maximum": Surface.maxDimension], "canvasHeight": ["type": "integer", "minimum": 1, "maximum": Surface.maxDimension],
      "resampling": BrushAPI.enumeration(Resampling.allCases.map(\.rawValue)),
      "transparency": BrushAPI.flag, "quality": ["type": "integer", "minimum": 0, "maximum": 100],
      "convertToSRGB": BrushAPI.flag, "embedProfile": BrushAPI.flag,
      "metadata": BrushAPI.enumeration(ImageExportSettings.Metadata.allCases.map(\.rawValue)), "trim": BrushAPI.flag
    ]]
  }
  static func schema(_ key: String, preferences: Bool = false) -> [String: Any] {
    if key == "operationID" { return VariablesAPI.uuid }
    var result = settingsSchema
    if preferences, let properties = result["properties"] as? [String: Any] { result["properties"] = properties.filter { preferenceKeys.contains($0.key) } }
    return result
  }
  static var capabilities: [String: Any] {
    ["commands": commands.sorted(), "settings": settingsSchema, "formats": ["png", "jpeg", "gif"], "targets": ["document", "layers", "artboards"], "maximumEncodedBytes": ImageAssetExport.maximumBytes,
     "history": "Immutable source snapshot; exports and preference changes do not add Undo entries.",
     "ancestorContext": "Selected layer assets retain ancestor group appearance through the same isolation as Layers to Files and published Adobe outputs.",
     "preview": "Native asynchronous cancelable preview uses the same asset encoder; API returns files and dimensions in ZIP manifest.",
     "limits": "Shared options across selected assets, 16 scales/256 selected roots. GIF has one-bit alpha and native palette quantization. JPEG quality uses the existing 0..12 native mapping. Custom RGB32 web exports require sRGB conversion. Complete Photoshop encoder/resampling/defaults/metadata/physical/platform equivalence is unqualified.",
     "adobe": "Published create-composite output.layers and cropMode use shared source isolation. Adobe raster/PSD contracts remain separate; no image.export Adobe route is invented."]
  }
  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    ["workspaceOpen": store.imageExportDraft != nil, "operationID": store.imageExportID?.uuidString as Any? ?? NSNull(), "preferences": (BrushAPI.json(ImageExportPreferences.load()) as! [String: Any]).filter { preferenceKeys.contains($0.key) }]
  }
  static var stateSchema: [String: Any] { ["type": "object", "required": ["workspaceOpen", "operationID", "preferences"], "properties": ["workspaceOpen": BrushAPI.flag, "operationID": VariablesAPI.nullableUUID, "preferences": schema("settings", preferences: true)]] }
}
extension AutomationCommand {
  func imageExportSettings(defaults: ImageExportSettings = .init()) throws -> ImageExportSettings {
    guard let input = parameters["settings"] else { return defaults }
    let object = try BrushAPI.merge(input, schema: ImageExportAPI.schema("settings", preferences: name == "export.preferences"), path: "settings")
    var base = BrushAPI.json(defaults) as! [String: Any]
    for (key, value) in object as! [String: Any] { base[key] = value }
    let result: ImageExportSettings
    do { result = try JSONDecoder().decode(ImageExportSettings.self, from: JSONSerialization.data(withJSONObject: base)) }
    catch { throw AutomationFailure(status: 400, message: "Malformed export settings or layer UUID.") }
    try result.validate(); return result
  }
}
struct ImageExportOutput: Sendable {
  let files: [ImageExportFile]
  let zip: Data
}
enum ImageExportPreparation {
  static func render(_ document: CraftDocument, settings: ImageExportSettings) throws -> ImageExportOutput {
    let files = try ImageAssetExport.render(document, settings: settings)
    let manifest: [String: Any] = ["source": document.name, "format": settings.format.rawValue, "files": files.map { ["name": $0.name, "width": $0.width, "height": $0.height, "scale": $0.scale, "bytes": $0.data.count, "sourceID": $0.sourceID?.uuidString as Any? ?? NSNull()] as [String: Any] }]
    var entries = files.map { StoredZIP.File(name: $0.name, data: $0.data) }
    entries.append(.init(name: "photato-export-manifest.json", data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])))
    let zip = try StoredZIP.encode(entries, maximumBytes: ImageAssetExport.maximumBytes)
    return .init(files: files, zip: zip)
  }
}
@MainActor extension AutomationService {
  func exportImages(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers before exporting assets.") }
    let snapshot = document.store.document, expectedToken = token, transfer = documentTransferGeneration, options = try command.imageExportSettings()
    imageExportShares.insert(shareID); defer { imageExportShares.remove(shareID) }
    let output = try await document.store.encodedImageAssets(options)
    prune()
    guard isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transfer,
      shares.contains(where: { $0.id == shareID && $0.document === document }), document.closeWorkflowID == nil,
      document.store.document == snapshot, revision(document.store) == command.revision else { throw AutomationFailure(status: 409, message: "Asset export was revoked or its source changed.") }
    return .init(status: 200, contentType: "application/zip", body: output.zip)
  }
  func cancelSharedImageExport(_ share: Share) {
    if imageExportShares.contains(share.id) { share.document?.store.imageExportWorker?.cancel() }
    if colorLookupExportShares.contains(share.id) { share.document?.store.colorLookupExportWorker?.cancel() }
  }
}
