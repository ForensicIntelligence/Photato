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
    ["commands":["raw.inspect","raw.develop"],"schema":apiSchema,"sourceMediaTypes":RawSourceIO.mediaTypes,
     "maximumSourceBytes":SmartObject.maximumSourceBytes,"maximumSensorPixels":RawSourceIO.maximumPixels,"nativeArchiveVersion":22,
     "import":"POST /v1/documents/import; optional X-Photato-Open-Format: raw. Upload retains existing4MP/64MiB API limits. File Open and Place Embedded accept native supported camera RAW types.",
     "history":"raw.develop uses the desktop source-redevelopment transaction. Partial settings retain existing values; null resets optional values to decoder defaults. allInstances defaults true.",
     "sourceDownload":"Existing smart-objects/{layerID}/source route returns original bytes. Raw settings and decoder are exposed in Smart Object state; revision includes settings.",
     "availability":"Apple native camera/decoder support is checked per source. Highlight recovery requires supported macOS26+ hardware/decoder; no preview fallback, download or cloud call.",
     "limitations":"Default imports are RGB16. Sensor redevelop uses current document depth/profile. Save native Photato for editable source; PSD RAW descriptor interchange, DNG output, Adobe white-balance presets, XMP and all-camera parity remain unqualified."]
  }
}
extension AutomationCommand {
  func rawTarget(_ document: CraftDocument) throws -> (UUID,SmartObject) {
    guard let id = UUID(uuidString:try string("layerID")),let object = document.layers.first(where: { $0.id == id })?.smartObject,object.rawDevelopment != nil else { throw AutomationFailure(status:422,message:"Select a RAW Smart Object.") }
    return (id,object)
  }
  func rawCommand(_ document: CraftDocument) throws -> Command {
    let (id,object) = try rawTarget(document)
    guard let data = parameters["settings"] else { throw AutomationFailure(status:400,message:"Missing RAW settings.") }
    let settings: RawDevelopment
    do { settings = try RawDevelopment.decodeJSON(JSONSerialization.data(withJSONObject:data.jsonValue,options:.fragmentsAllowed),base:object.rawDevelopment!) }
    catch { throw AutomationFailure(status:400,message:error.localizedDescription) }
    let all: Bool
    if let value = parameters["allInstances"] { guard case .bool(let flag) = value else { throw AutomationFailure(status:400,message:"allInstances must be boolean.") }; all = flag } else { all = true }
    return try RawSourceIO.command(in:document,layerID:id,settings:settings,allInstances:all)
  }
}
extension AutomationService {
  func inspectRaw(_ command: AutomationCommand,document: CraftNSDocument,shareID: UUID) async throws -> [String:Any] {
    let expected = revision(document.store)
    guard command.revision == expected else { throw AutomationFailure(status:409,message:"Stale document revision.") }
    let (_,object) = try command.rawTarget(document.store.document)
    let worker = Task.detached { try RawSourceIO.inspect(object.data,decoderVersion:object.rawDevelopment?.decoderVersion) }
    let info = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    guard isRunning,shares.contains(where: { $0.id == shareID && $0.document === document }),revision(document.store) == expected else { throw AutomationFailure(status:409,message:"RAW source changed or sharing ended.") }
    var result = try JSONSerialization.jsonObject(with:JSONEncoder().encode(info)) as! [String:Any]
    result["settings"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(object.rawDevelopment!)); result["revision"] = expected
    return result
  }
}
