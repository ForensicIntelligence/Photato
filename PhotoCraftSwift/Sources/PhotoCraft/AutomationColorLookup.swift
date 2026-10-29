import Foundation
import PhotoCraftCore

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
  static var colorLookupCapabilities: [String:Any] {
    ["commands":["adjustment.create","adjustment.set","adjustment.apply"],"schema":ColorLookupAdjustment.apiSchema,
     "upload":["method":"POST","path":"/v1/luts","contentType":"application/octet-stream",
       "nameHeader":"X-Photato-LUT-Name: percent-encoded basename ending in cube, 3dl or look",
       "bodySchema":["type":"string","format":"binary","maxLength":ColorLUT.maximumFileBytes],
       "successStatus":201,"result":"lutID plus lut metadata"],
     "list":["method":"GET","path":"/v1/luts","result":"luts array with lutID and lut metadata"],
     "clear":["method":"POST","path":"/v1/luts/clear","body":"empty","result":"cleared count; layer data is retained"],
     "download":["method":"GET","path":"/v1/documents/{id}/layers/{layerID}/lut",
       "revisionHeader":"Optional X-Photato-Revision","result":"original LUT bytes or generated Cube; filename in layer colorLookup.lut.sourceFile"],
     "permission":"documentTransfersEnabled; disabling clears the session LUT cache",
     "limits":["maximumCachedTables":16,"maximumCacheBytes":64*1024*1024,"maximumTableEdge":ColorLUT.maximumSize],
     "presets":ColorLUTPreset.allCases.map { ["id":$0.rawValue,"title":$0.title] },
     "persistence":"Native18; upload then use lutID, or use preset. Omit both for identity. Set replaces all settings; upload the layer download to reuse its LUT.",
     "limitations":"RGB composite; bounded Cube/3DL/LOOK tables only. ICC/CSP and Photoshop exact interpolation/dither remain unqualified."]
  }
  func resolveColorLookup(_ command: AutomationCommand) throws -> ColorLookupAdjustment? {
    guard command.name.hasPrefix("adjustment."), let value = command.parameters["adjustment"]?.jsonValue as? [String:Any], value["kind"] as? String == "colorLookup" else { return nil }
    struct Parameters: Decodable { let kind: String; var lutID: UUID?; var preset: ColorLUTPresetValue?; var interpolation: ColorLUT.Interpolation?; var dither: Bool? }
    // Decode the strict public shape first; null settings are not defaults.
    guard Set(value.keys).isSubset(of:["kind","lutID","preset","interpolation","dither"]),
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
    guard collection || clear || download else { return nil }
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
