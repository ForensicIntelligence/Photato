import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension ColorLookupAdjustment {
  var apiObject: [String:Any] {
    ["kind":"colorLookup","interpolation":interpolation.rawValue,"dither":dither,
     "lut":lut.map { $0.apiMetadata } ?? NSNull()]
  }
  static var apiSchema: [String:Any] {
    ["type":"object","additionalProperties":false,"required":["kind"],
     "properties":["kind":["const":"colorLookup"],"lutID":["type":"string","format":"uuid"],
       "preset":["type":"string","enum":ColorLUTPreset.allCases.map(\.rawValue)],
       "interpolation":["type":"string","enum":ColorLUT.Interpolation.allCases.map(\.rawValue),"default":"trilinear"],
       "dither":["type":"boolean","default":true]],
     "not":["required":["lutID","preset"]]]
  }
}
extension ColorLUT {
  var apiMetadata: [String:Any] {
    ["title":title,"size":size,"domainMin":domainMin,"domainMax":domainMax,
     "hasInputGrid":inputGrid != nil,"curveLength":(curve?.values.count ?? 0)/3,
     "estimatedBytes":estimatedBytes,"sourceFile":sourceFile ?? (title+".cube")]
  }
}
extension AutomationService {
  static var colorLookupExportStateSchema: [String: Any] {
    BrushAPI.object(["available": BrushAPI.flag, "workspaceOpen": BrushAPI.flag,
      "operationID": ["type": ["string", "null"], "format": "uuid"],
      "formats": ["type":"array","items":BrushAPI.enumeration(ColorLookupFileFormat.allCases.map(\.rawValue))], "busy": BrushAPI.flag], required: ["available", "workspaceOpen", "operationID", "busy"])
  }
  func colorLookupExportState(_ store: EditorStore) -> [String: Any] {
    ["available": store.canExportColorLookup, "workspaceOpen": store.colorLookupExportDraft != nil,
      "operationID": store.colorLookupExportID?.uuidString as Any? ?? NSNull(),
      "formats": (store.colorLookupExportID != nil ? store.colorLookupExportActiveFormats : store.colorLookupExportDraft?.formats ?? []).map(\.rawValue), "busy": store.colorLookupExportID != nil]
  }
  static var colorLookupCapabilities: [String:Any] {
    ["interpolationReference":["nativeDefault":"tetrahedral", "legacyPhotatoOmittedDefault":"trilinear", "explicitPhotato":"Set interpolation:tetrahedral for Photoshop-matching Cube evaluation; explicit trilinear remains available and native archives retain their encoded choice.", "adobe":"Color Lookup actions use tetrahedral interpolation.", "PSD":"Editable Color Lookup uses tetrahedral interpolation. Editable export builds a deterministic ICC v4 float-CLUT cache from the original uniform unit-domain table, with native descriptor framing. Imported caches are accepted only when every sample matches that table; standalone ICC, shapers, nonuniform domains and extra transforms remain unsupported for this editable interchange.", "qualification":"Controlled Photoshop2026 Cube references cover edges2/3 at RGB8/16/32 with Dither off. Other formats, profiles, domains, shapers and stochastic dither remain unqualified."],
     "propertyPreparation":["native":"Color Lookup layer Properties prepares and validates replacement content on the existing detached transaction worker. Publication, history and dirty notifications remain on the main actor. Native callers await geometryTask before reading committed content.",
       "state":"Existing geometryBusy/status/error state applies. Properties disables competing controls and offers Cancel during preparation; source-session/lifecycle fences discard stale results.",
       "api":"Existing adjustment.set and adjustmentBrush.edit replace use prepared transactions and retain their request, response, revision, busy and history contracts. Adobe action execution retains its documented lookup subset; no new endpoint or descriptor.",
       "limits":"No rendering kernel, file format, Actions version or command change. Commit/history spilling/rendering can still occupy the main actor. Faster submission does not qualify physical input/display latency,60fps or all tools."],
     "commands":["adjustment.create","adjustment.set","adjustment.apply"],"schema":ColorLookupAdjustment.apiSchema,
     "upload":["method":"POST","path":"/v1/luts","contentType":"application/octet-stream",
       "nameHeader":"X-Photato-LUT-Name: percent-encoded basename ending in cube, 3dl or look",
       "bodySchema":["type":"string","format":"binary","maxLength":ColorLUT.maximumFileBytes],
       "successStatus":201,"result":"lutID plus lut metadata"],
     "list":["method":"GET","path":"/v1/luts","result":"luts array with lutID and lut metadata"],
     "clear":["method":"POST","path":"/v1/luts/clear","body":"empty","result":"cleared count; layer data is retained"],
     "download":["method":"GET","path":"/v1/documents/{id}/layers/{layerID}/lut",
       "revisionHeader":"Optional X-Photato-Revision","result":"original LUT bytes or generated Cube; filename in layer colorLookup.lut.sourceFile"],
     "stackExport":["method":"GET","path":"/v1/documents/{id}/color-lookup.cube",
       "paths":ColorLookupFileFormat.allCases.map{"/v1/documents/{id}/color-lookup."+$0.rawValue}+["/v1/documents/{id}/color-lookup.zip"],
       "formats":ColorLookupFileFormat.allCases.map(\.rawValue),
       "bundleHeaders":"ZIP: X-Photato-LUT-Formats optional comma-separated unique formats (default all); X-Photato-LUT-Filename optional percent-encoded safe base filename,120UTF8bytes. Single-file suffix selects one format; formats header is rejected there.",
       "metadataHeaders":"X-Photato-LUT-Copyright optional percent-encoded text,1024UTF8bytes/no controls; prefix © Copyright plus UTC creation year. X-Photato-LUT-Created optional ISO8601 timestamp, default request time; pins ICC creation metadata for reproducible exports.",
       "cancelCommand":"image.export.cancel with operationID from colorLookupExport state",
       "gridHeader":"X-Photato-LUT-Grid-Points: integer2–129, default32",
       "titleHeader":"X-Photato-LUT-Description: optional percent-encoded UTF-8, maximum1024bytes, no control characters; default Color Lookup",
       "revisionHeader":"Optional X-Photato-Revision", "contentType":"application/octet-stream",
       "stateSchema":colorLookupExportStateSchema,
       "behavior":"Bake the visible global RGB adjustment stack above Background through the shared native compositor. No document/history/dirty change. Native File > Export > Color Lookup Tables shares this preparation. Transfer/revision/busy/source/revocation/cancellation checks apply.",
       "limits":"CUBE/3DL/CSP/RGBdevice-link ICC;2–129grid points/64MiB per file,256MiB+8192bytes per ZIP. 3DL12-bit integer and ICC16-bit integer output require0–1samples; CUBE/CSP retain extended values. CSP/ICC native import/profile classes, full256grid/streaming and exact Photoshop files/defaults remain open. Some legacy3DL readers infer output scale for dark tables; declared Photato scale is retained by native3DL import.  Spatial masks, groups/pixel overlays, clipping, dither/Dissolve, Grain and neighborhood effects reject rather than silently change their meaning. Current working RGB sample space/depth is retained; no ICC profile is embedded in CUBE. Exact Photoshop tables/defaults, other formats/full Photoshop grid ranges, full export and platform qualification remain open. No published dedicated Adobe v2 LUT-export route or unqualified action descriptor is invented."],
     "permission":"documentTransfersEnabled; disabling clears the session LUT cache",
     "limits":["maximumCachedTables":16,"maximumCacheBytes":64*1024*1024,"maximumTableEdge":ColorLUT.maximumSize],
     "presets":ColorLUTPreset.allCases.map { ["id":$0.rawValue,"title":$0.title] },
     "persistence":"Native18; upload then use lutID, or use preset. Omit both for identity. Set replaces all settings; upload the layer download to reuse its LUT.",
     "limitations":"RGB composite; bounded Cube/3DL/LOOK tables only. ICC/CSP import remains unsupported. Exact output is qualified only for the captured unit-domain Cube edges2/3, RGB8/16/32 and Dither off; other interpolation/dither/profile/domain cases remain open."]
  }
  func resolveColorLookup(_ command: AutomationCommand) throws -> ColorLookupAdjustment? {
    guard command.name.hasPrefix("adjustment."), let value = command.parameters["adjustment"]?.jsonValue as? [String:Any], value["kind"] as? String == "colorLookup" else { return nil }
    return try resolveColorLookupParameters(value)
  }
  func resolveColorLookupParameters(_ value:[String:Any])throws->ColorLookupAdjustment {
    struct Parameters: Decodable { let kind: String; var lutID: UUID?; var preset: ColorLUTPresetValue?; var interpolation: ColorLUT.Interpolation?; var dither: Bool? }
    // Decode the strict public shape first; null settings are not defaults.
    guard value["kind"] as? String == "colorLookup",Set(value.keys).isSubset(of:["kind","lutID","preset","interpolation","dither"]),
      value["lutID"] == nil || value["preset"] == nil, !value.values.contains(where:{ $0 is NSNull }) else {
      throw AutomationFailure(status:400,message:"Invalid Color Lookup parameters.")
    }
    do {
      let p = try JSONDecoder().decode(Parameters.self,from:JSONSerialization.data(withJSONObject:value))
      let lut: ColorLUT?
      if let id = p.lutID {
        guard let cached = luts[id] else { throw AutomationFailure(status:404,message:"LUT not found in this API session.") }; lut = cached
      } else if let preset = p.preset { lut = try preset.value.makeLUT() }
      else { lut = nil }
      return .init(lut:lut,interpolation:p.interpolation ?? .trilinear,dither:p.dither ?? true)
    } catch let e as AutomationFailure { throw e }
    catch { throw AutomationFailure(status:400,message:"Invalid Color Lookup parameters: \(error.localizedDescription)") }
  }
  func handleLUTTransfer(_ request: AutomationRequest) async throws -> AutomationResponse? {
    let parts = request.path.split(separator:"/").map(String.init)
    let collection = request.path == "/v1/luts"
    let clear = request.method == "POST" && request.path == "/v1/luts/clear"
    let download = request.method == "GET" && parts.count == 6 && parts[0] == "v1" && parts[1] == "documents" && parts[3] == "layers" && parts[5] == "lut" && request.path == "/"+parts.joined(separator:"/")
    let stackExport = request.method == "GET" && parts.count == 4 && parts[0] == "v1" && parts[1] == "documents" && (["color-lookup.zip"]+ColorLookupFileFormat.allCases.map{"color-lookup."+$0.rawValue}).contains(parts[3]) && request.path == "/"+parts.joined(separator:"/")
    guard collection || clear || download || stackExport else { return nil }
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document uploads and downloads in the native API window.") }
    if collection && request.method == "GET" {
      return .json(["luts":luts.sorted { $0.key.uuidString < $1.key.uuidString }.map { ["lutID":$0.key.uuidString,"lut":$0.value.apiMetadata] as [String:Any] }])
    }
    if clear {
      guard request.body.isEmpty else { throw AutomationFailure(status:400,message:"Clear expects an empty body.") }
      let count = luts.count; luts.removeAll(); lutCacheGeneration = UUID()
      return .json(["cleared":count])
    }
    guard !documentTransferBusy else { throw AutomationFailure(status:429,message:"A document transfer is already in progress.") }
    let expectedToken = token, generation = documentTransferGeneration, cacheGeneration = lutCacheGeneration
    documentTransferBusy = true; defer { documentTransferBusy = false }
    func validate() throws {
      guard !Task.isCancelled, isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == generation, lutCacheGeneration == cacheGeneration else {
        throw AutomationFailure(status:409,message:"LUT transfer was cancelled or revoked.")
      }
    }
    if collection {
      guard request.method == "POST", request.headers["content-type"]?.lowercased().split(separator:";").first == "application/octet-stream" else { throw AutomationFailure(status:415,message:"Upload raw LUT bytes as application/octet-stream.") }
      guard request.body.count <= ColorLUT.maximumFileBytes else { throw AutomationFailure(status:413,message:"LUT file exceeds64MiB.") }
      guard let raw = request.headers["x-photato-lut-name"], let name = raw.removingPercentEncoding, !name.isEmpty, name.utf8.count <= 1024, URL(fileURLWithPath:name).lastPathComponent == name, !name.contains("\\"), !name.unicodeScalars.contains(where:{ $0.value < 32 }) else { throw AutomationFailure(status:400,message:"Supply X-Photato-LUT-Name as a percent-encoded basename.") }
      guard luts.count < 16 else { throw AutomationFailure(status:413,message:"Clear the session LUT cache before uploading more tables.") }
      let worker = Task.detached(priority:.utility) { try ColorLUTFile.read(request.body,name:name) }
      let lut = try await withTaskCancellationHandler { try await worker.value } onCancel:{ worker.cancel() }
      try validate()
      guard luts.values.reduce(lut.estimatedBytes,{ $0+$1.estimatedBytes }) <= 64*1024*1024 else { throw AutomationFailure(status:413,message:"Session LUT cache exceeds64MiB.") }
      let id = UUID(); luts[id] = lut
      return .json(["lutID":id.uuidString,"lut":lut.apiMetadata],status:201)
    }
    if stackExport {
      guard request.body.isEmpty else { throw AutomationFailure(status:400,message:"LUT export expects an empty body.") }
      guard let shareID = UUID(uuidString:parts[2]), let share = shares.first(where:{$0.id == shareID}),
        let document = share.document else { throw AutomationFailure(status:404,message:"Shared document not found.") }
      let size: Int
      if let raw = request.headers["x-photato-lut-grid-points"] {
        guard let value = Int(raw), (2...ColorLUT.maximumSize).contains(value) else { throw AutomationFailure(status:400,message:"Grid points must be an integer from2to129.") }
        size = value
      } else { size = 32 }
      let title: String
      if let raw = request.headers["x-photato-lut-description"] {
        guard let value = raw.removingPercentEncoding, value.utf8.count <= 1024,
          !value.unicodeScalars.contains(where:{$0.value < 32}) else { throw AutomationFailure(status:400,message:"Invalid LUT description.") }
        title = value
      } else { title = "Color Lookup" }
      let archive = parts[3] == "color-lookup.zip"
      let formats:[ColorLookupFileFormat]
      if archive {
        if let raw=request.headers["x-photato-lut-formats"] {
          let names=raw.split(separator:",",omittingEmptySubsequences:false).map{$0.trimmingCharacters(in:.whitespaces)}
          let parsed=names.compactMap(ColorLookupFileFormat.init(rawValue:))
          guard parsed.count==names.count,!parsed.isEmpty,Set(parsed).count==parsed.count else {throw AutomationFailure(status:400,message:"Choose unique LUT formats:3dl,cube,csp,icc.")}
          formats=parsed
        }else {formats=ColorLookupFileFormat.allCases}
      }else {
        guard request.headers["x-photato-lut-formats"]==nil,let format=ColorLookupFileFormat(rawValue:String(parts[3].dropFirst("color-lookup.".count))) else {throw AutomationFailure(status:400,message:"The single-file path selects its LUT format.")}
        formats=[format]
      }
      func textHeader(_ key:String,_ fallback:String)throws->String {
        guard let raw=request.headers[key] else{return fallback}
        guard let value=raw.removingPercentEncoding else{throw AutomationFailure(status:400,message:"Invalid percent-encoded LUT metadata.")};return value
      }
      let date:Date
      if let raw=request.headers["x-photato-lut-created"] {
        guard let value=ISO8601DateFormatter().date(from:raw)else {throw AutomationFailure(status:400,message:"Supply an ISO8601 ICC creation date.")};date=value
      }else {date=Date()}
      let options=ColorLookupExportRequest(size:size,title:title,copyright:try textHeader("x-photato-lut-copyright",""),formats:formats,baseName:try textHeader("x-photato-lut-filename","Color Lookup"),created:date)
      do{try options.validate()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
      let expectedRevision = revision(document.store)
      guard request.headers["x-photato-revision"] == nil || request.headers["x-photato-revision"] == expectedRevision else { throw AutomationFailure(status:409,message:"Stale document revision.") }
      guard document.canRunFileCommand, document.closeWorkflowID == nil, document.store.canExportImages else { throw AutomationFailure(status:409,message:"Finish the current edit or export first.") }
      _ = try ColorLookupExport.adjustments(in:document.store.document)
      let source = document.store.document
      colorLookupExportShares.insert(shareID); defer { colorLookupExportShares.remove(shareID) }
      let data = try await document.store.encodedColorLookupData(options,archive:archive)
      try validate(); prune()
      guard shares.contains(where:{$0.id == shareID && $0.document === document}), document.closeWorkflowID == nil,
        document.store.document == source, revision(document.store) == expectedRevision else { throw AutomationFailure(status:409,message:"Document changed during LUT export.") }
      return .init(status:200,contentType:archive ? "application/zip":"application/octet-stream",body:data)
    }
    guard let shareID = UUID(uuidString:parts[2]), let layerID = UUID(uuidString:parts[4]), let share = shares.first(where:{ $0.id == shareID }), let document = share.document,
      case .adjustment(.colorLookup(let value)) = document.store.document.layers.first(where:{ $0.id == layerID })?.content, let lut = value.lut else { throw AutomationFailure(status:404,message:"Shared Color Lookup layer not found.") }
    let expectedRevision = revision(document.store)
    guard request.headers["x-photato-revision"] == nil || request.headers["x-photato-revision"] == expectedRevision else { throw AutomationFailure(status:409,message:"Stale document revision.") }
    let worker = Task.detached(priority:.utility) { try ColorLUTFile.export(lut).data }
    let data = try await withTaskCancellationHandler { try await worker.value } onCancel:{ worker.cancel() }
    try validate()
    guard shares.contains(where:{ $0.id == shareID }), revision(document.store) == expectedRevision else { throw AutomationFailure(status:409,message:"Document changed during LUT export.") }
    return .init(status:200,contentType:"application/octet-stream",body:data)
  }
}
private struct ColorLUTPresetValue: Decodable {
  let value: ColorLUTPreset
  init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let value = ColorLUTPreset(rawValue:raw) else { throw CraftError.invalid("Unknown Photato LUT preset.") }; self.value = value
  }
}
