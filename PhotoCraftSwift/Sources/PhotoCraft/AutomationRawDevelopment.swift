import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension RawDevelopment {
  static var apiSchema: [String:Any] {
    let nullableNumber: (Double,Double) -> [String:Any] = { a,b in ["anyOf":[["type":"null"],["type":"number","minimum":a,"maximum":b]]] }
    return ["type":"object","additionalProperties":false,"properties":[
      "decoderVersion":["type":["string","null"],"maxLength":64],
      "temperature":nullableNumber(2000,50000),"tint":nullableNumber(-150,150),
      "exposure":["type":"number","minimum":-5,"maximum":5],"boost":["type":"number","minimum":0,"maximum":1],
      "shadowBoost":["type":"number","minimum":0,"maximum":2],"extendedRange":["type":"number","minimum":0,"maximum":2],
      "lensCorrection":["type":["boolean","null"]],"highlightRecovery":["type":["boolean","null"]],"adjustments":CameraRawSettings.apiSchema]]
  }
  static var apiCapabilities: [String:Any] {
    ["commands":["raw.inspect","raw.develop","raw.saveSourceSettings",CameraRawXMPAPI.name],"schema":apiSchema,"sourceMediaTypes":RawSourceIO.mediaTypes,
     "maximumSourceBytes":DocumentIO.maximumUploadBytes,"maximumLocalSourceBytes":SmartObject.maximumCameraRawSourceBytes,
     "maximumSensorPixels":RawSourceIO.maximumPixels,"maximumSensorSide":RawSourceIO.maximumDimension,
     "maximumSpatialAdjustmentPixels":Surface.maximumDensePixels,
     "limitedLargeAdjustments":["highlights","shadows","texture","clarity","dehaze"],
     "pagedDetail":["sharpening","luminanceNoiseReduction","colorNoiseReduction"],
     "pagedEffects":["vignette", "grain"],"nativeArchiveVersion":22,
     "inspectOptionalFields":["iso":["type":"number","exclusiveMinimum":0,"description":"EXIF ISO when recorded."]],
     "import":"POST /v1/documents/import; optional X-Photato-Open-Format: raw. Upload retains existing4MP/64MiB API limits. File Open and Place Embedded accept supported camera RAW types and read their matching XMP sidecar or embedded settings. For HTTP import, X-Photato-Raw-XMP accepts up to 8 KiB of base64-decoded XMP with the sensor bytes. X-Photato-Raw-Open-Mode supports image, object (default), or copy.",
     "history":"raw.develop uses the desktop source-redevelopment transaction. Partial settings or XMP retain existing values where fields are omitted. Explicit null or XMP As Shot resets the applicable values to decoder defaults. allInstances defaults true.",
     "sourceDownload":"Existing smart-objects/{layerID}/source route returns original bytes. Raw settings and decoder are exposed in Smart Object state; revision includes settings.",
     "developedDNGDownload":["method":"GET","path":"/v1/documents/{id}/smart-objects/{layerID}/source.dng",
       "contentType":"image/x-adobe-dng", "optionalRevisionHeader":"X-Photato-Revision",
       "behavior":"Returns a DNG copy with supported embedded Camera Raw settings. Retains sensor bytes and the original document. Requires native document transfers and an existing share."],
     "sourceSettingsSave":["command":"raw.saveSourceSettings","parameters":["layerID":"UUID"],
       "behavior":"Writes committed settings to the explicitly opened DNG. Requires local document saving, a shared document and current revision. A matching sidecar is retired after its settings are embedded, with a local backup if Trash is unavailable. The editor's state and history are preserved."],
     "availability":"Apple native camera/decoder support is checked per source. Highlight recovery requires supported macOS26+ hardware/decoder; no preview fallback, download or cloud call.",
     "limitations":"Default imports are RGB16. Sensor redevelop uses current document depth/profile. Save native Photato for editable source; PSD RAW descriptor interchange, general RAW-to-DNG encoding, Adobe white-balance preset rendering and all-camera parity remain unqualified. Camera Raw XMP settings convert through cameraRaw.settings.convert."]
  }
}
extension AutomationCommand {
  func rawTarget(_ document: CraftDocument) throws -> (UUID,SmartObject) {
    guard let id = UUID(uuidString:try string("layerID")),let object = document.layers.first(where: { $0.id == id })?.smartObject,object.rawDevelopment != nil else { throw AutomationFailure(status:422,message:"Select a RAW Smart Object.") }
    return (id,object)
  }
  func rawCommand(_ document: CraftDocument) throws -> Command {
    let (id,object) = try rawTarget(document)
    let json = parameters["settings"]
    let xmp = parameters["xmp"]
    guard (json == nil) != (xmp == nil) else {
      throw AutomationFailure(status: 400, message: "Supply either RAW settings or XMP text.")
    }
    let base = object.rawDevelopment!
    let settings: RawDevelopment
    do {
      if let json {
        settings = try RawDevelopment.decodeJSON(JSONSerialization.data(withJSONObject: json.jsonValue, options: .fragmentsAllowed), base: base)
      } else {
        settings = try CameraRawXMP.read(CameraRawXMPAPI.packet(xmp), into: base)
      }
    } catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    let all: Bool
    if let value = parameters["allInstances"] { guard case .bool(let flag) = value else { throw AutomationFailure(status:400,message:"allInstances must be boolean.") }; all = flag } else { all = true }
    return try RawSourceIO.command(in:document,layerID:id,settings:settings,allInstances:all)
  }
}
extension AutomationService {
  func downloadDevelopedDNG(_ source: SmartObject, request: AutomationRequest,
    document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else {
      throw AutomationFailure(status: 403, message: "Enable document downloads in the native API window.")
    }
    guard !documentTransferBusy else {
      throw AutomationFailure(status: 429, message: "A document transfer is already in progress.")
    }
    let expected = revision(document.store)
    if let requested = request.headers["x-photato-revision"], requested != expected {
      throw AutomationFailure(status: 409, message: "Stale document revision.")
    }
    guard source.mediaType == "image/x-adobe-dng", let settings = source.rawDevelopment,
      !source.data.isEmpty else {
      throw AutomationFailure(status: 422, message: "Select a Smart Object with a retained DNG source.")
    }
    let generation = documentTransferGeneration
    let authorization = token
    documentTransferBusy = true
    defer { documentTransferBusy = false }
    let worker = Task.detached(priority: .utility) {
      try RawSourceIO.dngWithSettings(source.data, settings: settings)
    }
    let output: Data
    do {
      output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    } catch is CancellationError {
      throw AutomationFailure(status: 409, message: "DNG download was cancelled.")
    } catch {
      throw AutomationFailure(status: 422, message: error.localizedDescription)
    }
    guard !Task.isCancelled, isRunning, token == authorization, documentTransfersEnabled,
      documentTransferGeneration == generation, revision(document.store) == expected,
      shares.contains(where: { $0.id == shareID && $0.document === document }) else {
      throw AutomationFailure(status: 409, message: "The document changed or sharing ended.")
    }
    return .init(status: 200, contentType: "image/x-adobe-dng", body: output,
      headers: ["X-Photato-Revision": expected])
  }

  func saveRawSourceThroughAPI(_ command: AutomationCommand, document: CraftNSDocument,
    shareID: UUID) async throws {
    guard documentSavesEnabled else {
      throw AutomationFailure(status: 403, message: "Allow local document saving in the native API window first.")
    }
    let (layerID, object) = try command.rawTarget(document.store.document)
    guard document.canSaveRawSourceSettings(layerID: layerID), let settings = object.rawDevelopment else {
      throw AutomationFailure(status: 422, message: "Select the original layer of a locally opened Camera Raw document.")
    }
    guard rawSourceSaveTasks[shareID] == nil else {
      throw AutomationFailure(status: 409, message: "A RAW settings save is already running.")
    }
    try Task.checkCancellation()
    let task = Task { try await document.saveRawSourceSettings(layerID: layerID, settings: settings) }
    rawSourceSaveTasks[shareID] = task
    defer { rawSourceSaveTasks.removeValue(forKey: shareID) }
    do {
      try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    } catch RawDNGSource.SaveError.sidecarAccessNeeded {
      throw AutomationFailure(status: 403, message: "Authorize the RAW file’s folder in Photato before saving its settings.")
    } catch RawDNGSource.SaveError.sourceChanged {
      throw AutomationFailure(status: 409, message: "The RAW file or its sidecar changed. Reopen it before saving.")
    } catch is CancellationError {
      throw AutomationFailure(status: 409, message: "The RAW settings save was cancelled or revoked.")
    } catch {
      throw AutomationFailure(status: 422, message: error.localizedDescription)
    }
    guard isRunning, shares.contains(where: { $0.id == shareID && $0.document === document }) else {
      throw AutomationFailure(status: 409, message: "Sharing ended during the RAW settings save.")
    }
  }

  func inspectRaw(_ command: AutomationCommand,document: CraftNSDocument,shareID: UUID) async throws -> [String:Any] {
    let expected = revision(document.store)
    guard command.revision == expected else { throw AutomationFailure(status:409,message:"Stale document revision.") }
    let (layerID,object) = try command.rawTarget(document.store.document)
    let worker = Task.detached { try RawSourceIO.inspect(object.data,decoderVersion:object.rawDevelopment?.decoderVersion) }
    let info = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    guard isRunning,shares.contains(where: { $0.id == shareID && $0.document === document }),revision(document.store) == expected else { throw AutomationFailure(status:409,message:"RAW source changed or sharing ended.") }
    var result = try JSONSerialization.jsonObject(with:JSONEncoder().encode(info)) as! [String:Any]
    result["settings"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(object.rawDevelopment!))
    result["revision"] = expected
    result["canSaveSourceSettings"] = documentSavesEnabled && document.canSaveRawSourceSettings(layerID: layerID)
    if document.canSaveRawSourceSettings(layerID: layerID), let source = document.localRawSource?.original {
      result["sourceSettingsStorage"] = source.savesInsideDNG ? "embeddedDNG" : "sidecar"
    }
    return result
  }
}
