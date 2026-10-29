import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ImageSequenceAPI {
  static let commands: Set<String> = ["sequence.export","sequence.export.cancel"]
  static let definitions: [AutomationCommand.Definition] = [
    .init(name:"sequence.export",parameters:["format":"png","useWorkArea":"Use Timeline work area; excludes explicit frame range","prefix":"Filename prefix (default frame)","firstFrame":"First zero-based frame (default0)","lastFrame":"Last zero-based frame inclusive (default last)","startNumber":"Initial filename number (default0)","digits":"Minimum numeric digits1–9 (default4)"],description:"Render frame animation or video Timeline to numbered PNG files plus sequence.json in a ZIP download. Requires document transfers; source and history remain unchanged.",optionalParameters:["useWorkArea","prefix","firstFrame","lastFrame","startNumber","digits"]),
    .init(name:"sequence.export.cancel",parameters:["operationID":"Active sequence export UUID"],description:"Cancel the matching sequence render/archive worker.")
  ]
  static func schema(_ key: String) -> [String:Any] {
    switch key {
    case "useWorkArea":BrushAPI.flag
    case "format": BrushAPI.enumeration(["png"])
    case "prefix": ["type":"string","minLength":1,"maxLength":64]
    case "digits": ["type":"integer","minimum":1,"maximum":9]
    case "startNumber": ["type":"integer","minimum":0,"maximum":999999999]
    case "operationID": ["type":"string","format":"uuid"]
    default: ["type":"integer","minimum":0,"maximum":20736000]
    }
  }
  static var stateSchema: [String:Any] { BrushAPI.object(["operationID":["type":["string","null"],"format":"uuid"]],required:["operationID"]) }
  static var capabilities: [String:Any] {
    ["commands":commands.sorted(),"stateSchema":stateSchema,"maximumFrames":4096,"maximumBytes":ImageSequenceExport.maximumBytes,
     "output":"application/zip: deterministic ZIP32 stored entries with UTF-8 names and CRC32. Numbered PNG files plus sequence.json(version1) contain source frame indices, seconds/durations, source/output depth, color policy, dimensions and loop metadata. Frame ranges are zero-based inclusive. Number digits are minimum padding; numbering may grow. Prefix allows letters/numbers/spaces/underscore/hyphen, up to64 UTF-8 bytes.",
     "color":"RGB8/16 PNG uses the existing working-profile encoder with full alpha. HDR32 converts to SDR sRGB16; source is unchanged. No Photoshop byte equivalence claim.",
     "desktop":"Timeline Export Image Sequence renders the same frames, stages a new <prefix>-sequence folder and publishes with exclusive rename. Existing destinations are never replaced.",
     "cancellation":"sequenceExport.operationID enables sequence.export.cancel while busy; document closure, task cancellation and source/revision/share/transfer revocation prevent output.",
     "limits":"PNG at source dimensions/timing only. Alternate formats, export resampling/resize, alpha modes, full Render Video and Photoshop exact/live/platform parity remain open.",
     "adobe":"No dedicated sequence endpoint in the pinned public v2 contract; no invented Adobe route. Generic video action descriptors remain required."]
  }
}
extension AutomationCommand {
  func imageSequenceOptions() throws -> ImageSequenceOptions {
    guard try string("format") == "png" else { throw AutomationFailure(status:400,message:"Sequence export requires PNG format.") }
    let area=try pathFlag("useWorkArea",false)
    if area,parameters["firstFrame"] != nil || parameters["lastFrame"] != nil{throw AutomationFailure(status:400,message:"Work area and explicit frame range are mutually exclusive.")}
    return ImageSequenceOptions(prefix:try parameters["prefix"].map{_ in try string("prefix")} ?? "frame",firstFrame:try parameters["firstFrame"].map{_ in try integer("firstFrame",range:0...20736000)} ?? 0,lastFrame:try parameters["lastFrame"].map{_ in try integer("lastFrame",range:0...20736000)},startNumber:try parameters["startNumber"].map{_ in try integer("startNumber",range:0...999999999)} ?? 0,digits:try parameters["digits"].map{_ in try integer("digits",range:1...9)} ?? 4,useWorkArea:area)
  }
}
extension AutomationService {
  func exportImageSequence(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document transfers before sequence export.") }
    let options = try command.imageSequenceOptions(),snapshot = document.store.document,expectedToken = token,transferGeneration = documentTransferGeneration
    sequenceExportShares.insert(shareID)
    defer {sequenceExportShares.remove(shareID)}
    let output = try await document.store.encodedImageSequence(options,archive:true)
    prune()
    guard isRunning,token == expectedToken,documentTransfersEnabled,documentTransferGeneration == transferGeneration,
      shares.contains(where:{$0.id == shareID && $0.document === document}),document.store.document == snapshot,revision(document.store) == command.revision else { throw AutomationFailure(status:409,message:"Sequence export was revoked or its source changed.") }
    guard let bytes = output.archive else { throw CraftError.invalid("Sequence archive was not produced.") }
    document.store.status = "Exported PNG sequence";return .init(status:200,contentType:"application/zip",body:bytes)
  }
  func cancelSharedSequenceExport(_ share:Share) {
    guard sequenceExportShares.contains(share.id) else{return}
    share.document?.store.sequenceExportWorker?.cancel()
  }
}
