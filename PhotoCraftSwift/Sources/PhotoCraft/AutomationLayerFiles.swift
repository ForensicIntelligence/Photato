import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LayerFilesAPI {
  static let commands: Set<String> = ["layers.export", "layers.export.cancel"]
  static let definitions: [AutomationCommand.Definition] = [
    .init(name:"layers.export",parameters:["settings":"Layer-file formats, prefix, visibility, trim, ICC and codec settings"],description:"Download one file per selected or all individual layers as a ZIP using native Layers to Files. Requires transfers; source/history unchanged.",optionalParameters:["settings"]),
    .init(name:"layers.export.cancel",parameters:["operationID":"Active layer-file export UUID"],description:"Cancel the matching layer-file export and discard its private staging files.")
  ]
  static var settingsSchema: [String:Any] {
    ["type":"object","additionalProperties":false,"properties":[
      "format":BrushAPI.enumeration(LayerFileExportSettings.Format.allCases.map(\.rawValue)),
      "prefix":["type":"string","maxLength":64],"visibleOnly":BrushAPI.flag,"trim":BrushAPI.flag,"includeICC":BrushAPI.flag,"transparency":BrushAPI.flag,
      "jpegQuality":["type":"integer","minimum":0.0,"maximum":12.0],
      "tiffCompression":BrushAPI.enumeration(RasterEncodingOptions.TIFFCompression.allCases.map(\.rawValue)),
      "pngInterlaced":BrushAPI.flag,"paletteColors":["type":"integer","minimum":2.0,"maximum":256.0],
      "paletteDither":BrushAPI.enumeration(IndexedDither.allCases.map(\.rawValue)),"paletteAmount":["type":"number","minimum":0.0,"maximum":1.0],
      "ids":["type":"array","maxItems":LayerLimits.maximumLayers,"uniqueItems":true,"items":VariablesAPI.uuid]
    ]]
  }
  static func schema(_ key:String) -> [String:Any] { key == "operationID" ? VariablesAPI.uuid : settingsSchema }
  @MainActor static func state(_ store: EditorStore) -> [String:Any] {
    ["workspaceOpen":store.layerFileDraft != nil,"operationID":store.layerFilesID?.uuidString as Any? ?? NSNull(),"completed":store.layerFilesProgress.completed,"total":store.layerFilesProgress.total,"currentLayer":store.layerFilesProgress.current]
  }
  static var stateSchema: [String:Any] { ["type":"object","required":["workspaceOpen","operationID","completed","total","currentLayer"],"properties":["workspaceOpen":BrushAPI.flag,"operationID":VariablesAPI.nullableUUID,"completed":["type":"integer","minimum":0],"total":["type":"integer","minimum":0],"currentLayer":["type":"string"]]] }
  static var capabilities: [String:Any] {
    ["commands":commands.sorted(),"settings":settingsSchema,"formats":LayerFileExportSettings.Format.allCases.map(\.rawValue),
     "ordering":"Top-to-bottom individual layers, recursively through groups; groups supply ancestor appearance, not duplicate files. Visible-only tests eye visibility through ancestors, including zero-opacity layers.",
     "names":"Optional prefix, zero-based four-digit ordinal, sanitized layer name and extension. Existing destinations are never replaced.",
     "persistence":"Private per-file staging; native PSD/PSB/Photato use streaming file serializers without the API aggregate Data cap. Other formats retain existing codec limits. Native publishes completed files into the selected folder; API returns ZIP plus photato-layer-files.json.",
     "maximumZIPBytes":ImageAssetExport.maximumBytes,"history":"Immutable snapshots and shared native engine; no source/history changes.",
     "limits":"BMP/Targa cannot embed ICC. PNG-8 uses the existing8,388,608-pixel indexed converter and single transparent palette entry. PDF is rasterized at physical document resolution. Full group/clipping/adjustment/reference/codec defaults, maximum capacity, Photoshop bytes/UI and supported-platform qualification remain open.",
     "adobe":"Existing published create-composite per-output layer selection/crop uses native ImageAssetSelection; no batch Layers-to-Files endpoint is invented. Native and Adobe selection share ancestor context; complete Photoshop contextual output fidelity remains unqualified."]
  }
}
extension AutomationCommand {
  func layerFileSettings() throws -> LayerFileExportSettings {
    guard let value = parameters["settings"] else { return .init() }
    guard let fields = try BrushAPI.merge(value,schema:LayerFilesAPI.settingsSchema,path:"settings") as? [String:Any] else { throw AutomationFailure(status:400,message:"Invalid layer-file settings.") }
    var base = BrushAPI.json(LayerFileExportSettings()) as! [String:Any]
    for (key,value) in fields { base[key] = value }
    let parsed: LayerFileExportSettings
    do { parsed = try JSONDecoder().decode(LayerFileExportSettings.self,from:JSONSerialization.data(withJSONObject:base)) }
    catch { throw AutomationFailure(status:400,message:"Malformed layer export settings or UUID.") }
    var result = parsed
    if !result.format.supportsICC, fields["includeICC"] == nil { result.includeICC = false }
    try result.validate(); return result
  }
}
@MainActor extension AutomationService {
  func exportLayerFiles(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document transfers before exporting layer files.") }
    let source = document.store.document, expected = token, transfer = documentTransferGeneration
    let options = try command.layerFileSettings()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("photato-layer-download-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    layerFileExportShares.insert(shareID); defer { layerFileExportShares.remove(shareID) }
    let result = try await document.store.exportedLayerFiles(options,directory:directory,publish:false)
    prune()
    guard isRunning, token == expected, documentTransfersEnabled, documentTransferGeneration == transfer,
      shares.contains(where: { $0.id == shareID && $0.document === document }), document.closeWorkflowID == nil,
      document.store.document == source, revision(document.store) == command.revision else { throw AutomationFailure(status:409,message:"Layer-file export was revoked or its source changed.") }
    return .init(status:200,contentType:"application/zip",body:result.archive!)
  }
  func cancelSharedLayerFiles(_ share:Share) { if layerFileExportShares.contains(share.id) { share.document?.store.layerFilesWorker?.cancel() } }
}
