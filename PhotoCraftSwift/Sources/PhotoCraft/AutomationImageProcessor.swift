import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ImageProcessorAPI {
  static let commands: Set<String> = ["document.imageProcessor","document.imageProcessor.cancel"]
  static var settingsSchema: [String:Any] {
    let format: [String:Any] = ["type":"object","additionalProperties":false,"properties":["enabled":["type":"boolean"],"resize":["type":"boolean"],"width":["type":"integer","minimum":1,"maximum":30_000],"height":["type":"integer","minimum":1,"maximum":30_000]]]
    var fields: [String:[String:Any]] = ["jpeg":format,"psd":format,"tiff":format,"jpegQuality":["type":"integer","minimum":0,"maximum":12],"copyright":["type":"string","maxLength":4096],"actionID":["type":"string","format":"uuid"]]
    for key in ["convertJPEGToSRGB","includeICC","tiffLZW","maximizeCompatibility","dontEnlarge","useFirstImageProfile"] {fields[key] = ["type":"boolean"]}
    return ["type":"object","additionalProperties":false,"properties":fields]
  }
  static var sourcesSchema: [String:Any] {var s = ContactSheetSettings.sourcesSchema;s["maxItems"] = 8;return s}
  static func schema(_ key: String) -> [String:Any] {key == "settings" ? settingsSchema:key == "sources" ? sourcesSchema:["type":"string","format":"uuid"]}
  static var capabilities: [String:Any] {
    ["command":"document.imageProcessor","cancelCommand":"document.imageProcessor.cancel","settingsSchema":settingsSchema,"sourcesSchema":sourcesSchema,
     "result":"HTTP200 application/zip with JPEG/PSD/TIFF folders and image-processor.json records(source,file,width,height,format). Sources/history are unchanged. All files prepare before download; failure/revocation returns no archive.",
     "settings":"Optional per-format enable/resize/width/height; JPEG quality0–12 and sRGB conversion; TIFF LZW; embedded ICC; copyright; optional loaded Action UUID; first-image profile reuse; dontEnlarge. Native Save/Load uses the same JSON settings.",
     "limits":"Transfers enabled,1–8 explicitly shared current sources including target;8MP/512MiB each,128MiB total ZIP. Native file/folder workflow allows256 sources. Still images only; codec/Actions support limits apply. No arbitrary API filesystem access.",
     "open":"Maximize Compatibility must currently be true. Interactive first-image Camera Raw settings, clipboard/master-palette Actions, exact encoder/resampling/defaults and live/platform parity are unqualified.",
     "adobe":"No dedicated Image Processor endpoint in the pinned public v2 contract. Existing published actions/edit routes remain distinct; no route or descriptor is invented."]
  }
}
extension AutomationCommand {
  func imageProcessorSettings() throws -> ImageProcessorSettings {
    var settings = ImageProcessorSettings()
    if let value = parameters["settings"] {
      let base = try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings))
      let merged = try BrushAPI.merge(value,schema:ImageProcessorAPI.settingsSchema,base:base,path:"imageProcessor.settings")
      do {settings = try ImageProcessorSettings.decode(JSONSerialization.data(withJSONObject:merged))} catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
    }
    return settings
  }
}
extension AutomationService {
  func executeImageProcessor(_ command: AutomationCommand,anchorID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else {throw AutomationFailure(status:403,message:"Enable document transfers before exporting processed images.")}
    guard !documentTransferBusy,imageProcessorTask == nil else {throw AutomationFailure(status:409,message:"Finish the current document transfer or Image Processor operation.")}
    let settings = try command.imageProcessorSettings()
    guard case .array(let values) = command.parameters["sources"],(1...8).contains(values.count) else {throw AutomationFailure(status:400,message:"Choose1–8 shared images.")}
    let inputs = try values.map {value -> (UUID,String,CraftNSDocument) in
      guard case .object(let fields) = value,Set(fields.keys) == ["id","revision"],case .string(let raw) = fields["id"],let id = UUID(uuidString:raw),case .string(let revision) = fields["revision"],!revision.isEmpty,let document = shares.first(where:{$0.id == id})?.document else {throw AutomationFailure(status:400,message:"Each image requires its shared UUID and current revision.")}
      try preflight(document);guard self.revision(document.store) == revision else {throw AutomationFailure(status:409,message:"An image revision is stale.")};return (id,revision,document)
    }
    let ids = Set(inputs.map(\.0));guard ids.count == inputs.count,ids.contains(anchorID) else {throw AutomationFailure(status:400,message:"Include the target exactly once, without duplicate source images.")}
    let anchor = inputs.first{$0.0 == anchorID}!.2
    guard inputs.allSatisfy({$0.2.store.session.actionRecording == nil}) else {throw AutomationFailure(status:409,message:"Stop action recording before processing images.")}
    let action = try settings.actionID.map{try anchor.store.actions.action($0)}
    let snapshots = inputs.map{$0.2.store.document},token = token,generation = generation,transfer = documentTransferGeneration,id = UUID()
    imageProcessorOperationID = id;imageProcessorSourceIDs = ids;documentTransferBusy = true
    let worker = Task.detached(priority:.userInitiated) {try ImageProcessor.render(snapshots.map{ActionBatchSource(document:$0)},settings:settings,action:action).zip()}
    imageProcessorTask = worker
    defer {if imageProcessorOperationID == id {imageProcessorTask = nil;imageProcessorOperationID = nil;imageProcessorSourceIDs = []};documentTransferBusy = false}
    let bytes = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
    prune()
    guard !worker.isCancelled,isRunning,self.token == token,self.generation == generation,documentTransfersEnabled,documentTransferGeneration == transfer else {throw AutomationFailure(status:409,message:"Image Processor export was cancelled or revoked.")}
    for (index,input) in inputs.enumerated() {
      guard shares.contains(where:{$0.id == input.0 && $0.document === input.2}),revision(input.2.store) == input.1,input.2.store.document == snapshots[index],input.2.closeWorkflowID == nil else {throw AutomationFailure(status:409,message:"A source changed, closed or stopped sharing during Image Processor export.")}
    }
    return .init(status:200,contentType:"application/zip",body:bytes)
  }
}
