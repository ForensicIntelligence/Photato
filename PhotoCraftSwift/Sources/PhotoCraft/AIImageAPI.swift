import AppKit
import Foundation
import PhotoCraftAI
import PhotoCraftCore

/// Interactive system generation, distinct from resource-based Adobe services.
enum AIImageAPI {
  static let operations=["prepare","cancel","openSaved","trashSaved"]
  static func hasReference(_ value: AutomationValue?) -> Bool {
    guard let value else { return false }
    if case .null = value { return false }
    return true
  }
  static var referenceRecordSchema: [String: Any] {
    BrushAPI.object(["version": ["const": 1], "sha256": ["type": "string", "pattern": "^[0-9a-f]{64}$"],
      "byteCount": BrushAPI.number(1, Double(ImageGenerationReference.maximumBytes), integer: true),
      "mediaType": ["type": "string", "enum": ["image/png", "image/jpeg", "image/tiff", "image/heic"]],
      "width": BrushAPI.number(1, 300000, integer: true), "height": BrushAPI.number(1, 300000, integer: true),
      "previewWidth": BrushAPI.number(1, 2048, integer: true), "previewHeight": BrushAPI.number(1, 2048, integer: true),
      "role": ["const": "visualInspiration"], "providerAttested": ["const": false]],
      required: ["version", "sha256", "byteCount", "mediaType", "width", "height", "previewWidth", "previewHeight", "role", "providerAttested"])
  }
  static func referenceRecord(_ r: ImageGenerationReferenceRecord) -> [String: Any] {
    ["version": r.version, "sha256": r.sha256, "byteCount": r.byteCount, "mediaType": r.mediaType,
      "width": r.width, "height": r.height, "previewWidth": r.previewWidth, "previewHeight": r.previewHeight,
      "role": "visualInspiration", "providerAttested": false]
  }
  static var recordSchema:[String:Any] {
    let uuid:[String:Any]=["type":"string","format":"uuid"]
    let properties:[String:Any]=["layerID":uuid,"requestID":uuid,"sourceDocumentID":uuid,"sourceRevision":uuid,
      "initialPrompt":["type":"string","minLength":1,"maxLength":1000],"provider":["const":"Apple Image Playground"],
      "documentedProcessing":["type":"string","enum":["onDevice","privateCloudCompute","unknown"]],
      "modelIdentifier":["type":"null"],"seed":["type":"null"],"finalPrompt":["type":"null"],"providerAttested":["const":false],
      "startedAt":["type":"string","format":"date-time"],"acceptedAt":["type":"string","format":"date-time"],
      "resultStyle":["anyOf":[["type":"string","maxLength":256],["type":"null"]]],
      "originalMediaType":["type":"string","enum":["image/png","image/jpeg","image/tiff","image/heic","image/x-exr"]],
      "originalByteCount":["type":"integer","minimum":1,"maximum":GenerationRecord.maximumOriginalBytes],
      "originalSHA256":["type":"string","pattern":"^[0-9a-f]{64}$"]]
    return ["type":"object","additionalProperties":false,"required":properties.keys.sorted(),"properties":properties]
  }
  static var savedRecordSchema:[String:Any] {
    var schema=recordSchema,fields=schema["properties"] as! [String:Any]
    fields["resultID"]=fields.removeValue(forKey:"layerID");schema["properties"]=fields;schema["required"]=fields.keys.sorted();return schema
  }
  static var jobSchema:[String:Any] {
    let uuid:[String:Any]=["type":"string","format":"uuid"]
    let fields:[String:Any]=["id":uuid,"phase":["type":"string","enum":["preparingReference","awaitingSystem","preparing","completed","cancelled","stale","failed"]],
      "intent":["type":"string","enum":["image","background"]],
      "foregroundLayerID":["anyOf":[uuid,["type":"null"]]],
      "importedReference":["anyOf":[referenceRecordSchema,["type":"null"]]],
      "referenceSize":["anyOf":[BrushAPI.object(["width":BrushAPI.number(1,2048,integer:true),"height":BrushAPI.number(1,2048,integer:true)],required:["width","height"]),["type":"null"]]],
      "initialPrompt":["type":"string","maxLength":1000],"sourceDocumentID":uuid,"sourceRevision":uuid,
      "sourceCanvasSize":BrushAPI.object(["width":BrushAPI.number(1,300000,integer:true),"height":BrushAPI.number(1,300000,integer:true)],required:["width","height"]),
      "documentedProcessing":["type":"string","enum":["onDevice","privateCloudCompute","unknown"]],
      "resultLayerID":["anyOf":[uuid,["type":"null"]]],"retainedResultID":["anyOf":[uuid,["type":"null"]]],"error":["anyOf":[["type":"string"],["type":"null"]]]]
    return ["type":"object","additionalProperties":false,"required":fields.keys.sorted(),"properties":fields]
  }
  static var controlSchema:[String:Any] {
    ["oneOf":[
      ["type":"object","additionalProperties":false,"required":["operation","revision","resultID"],"properties":["operation":["type":"string","enum":["openSaved","trashSaved"]],"revision":["type":"string"],"resultID":["type":"string","format":"uuid"]]],
      ["type":"object","additionalProperties":false,"required":["operation","revision","prompt"],"properties":["operation":["const":"prepare"],"revision":["type":"string"],"prompt":["type":"string","minLength":1,"maxLength":1000],"intent":["type":"string","enum":["image","background"],"default":"image"],
        "reference":["anyOf":[BrushAPI.object(["dataBase64":["type":"string","minLength":1,"maxLength":ImageGenerationReference.maximumBase64Characters]],required:["dataBase64"]),["type":"null"]]]]],
      ["type":"object","additionalProperties":false,"required":["operation","revision","requestID"],"properties":["operation":["const":"cancel"],"revision":["type":"string"],"requestID":["type":"string","format":"uuid"]]]]]
  }
  static var stateSchema:[String:Any] {
    ["type":"object","additionalProperties":false,"required":["available","message","requiresNativeApproval","canStart","busy","intent","reference","referenceImportRequestID","selectedReference","background","selectedBackground","promptRefinementRequestID","authorizedSavedResultIDs","resultLayerIDs","selectedResult","job"],
     "properties":["available":["type":"boolean"],"message":["type":"string"],"requiresNativeApproval":["const":true],"canStart":["type":"boolean"],"busy":["type":"boolean"],"promptRefinementRequestID":["anyOf":[["type":"string","format":"uuid"],["type":"null"]]],
       "intent":["type":"string","enum":["image","background"]],
       "reference":["anyOf":[referenceRecordSchema,["type":"null"]]],
       "selectedReference":["anyOf":[referenceRecordSchema,["type":"null"]]],
       "referenceImportRequestID":["anyOf":[["type":"string","format":"uuid"],["type":"null"]]],
       "background":BrushAPI.object(["eligibleForegroundLayerID":["anyOf":[["type":"string","format":"uuid"],["type":"null"]]],"canStart":["type":"boolean"]],required:["eligibleForegroundLayerID","canStart"]),
       "selectedBackground":["anyOf":[backgroundRecordSchema,["type":"null"]]],
       "authorizedSavedResultIDs":["type":"array","items":["type":"string","format":"uuid"]],
       "resultLayerIDs":["type":"array","items":["type":"string","format":"uuid"]],"selectedResult":["anyOf":[recordSchema,["type":"null"]]],
       "job":["anyOf":[jobSchema,["type":"null"]]],"revision":["type":"string"]]]
  }
  static var capabilities:[String:Any] {
    ["statePath":"GET /v1/documents/{id}/ai","controlPath":"POST /v1/documents/{id}/ai",
     "recordPath":"GET /v1/documents/{id}/ai/records/{layerID}","originalPath":"GET /v1/documents/{id}/ai/results/{layerID}",
     "savedRecordPath":"GET /v1/documents/{id}/ai/saved-records/{resultID}","savedOriginalPath":"GET /v1/documents/{id}/ai/saved-results/{resultID}",
     "savedResults":"Accepted originals are atomically retained before source validation/preparation in a private local inbox, including stale/failed/cancelled placement. Global native Generated Results opens originals as separate unsaved documents and moves items to Trash. HTTP only accesses IDs authorized by this actual document/lifecycle session, never a global library or imported document UUID. openSaved requires transfers and idle document/lifecycle/share capacity; trashSaved requires local-saving permission. No model runs on reopen.",
     "inboxLimits":["maximumBytes":512*1024*1024,"maximumEntries":256,"maximumItemBytes":GeneratedResultInbox.archiveLimit,"automaticPurge":false],
     "controlSchema":controlSchema,"stateSchema":stateSchema,"recordSchema":recordSchema,"savedRecordSchema":savedRecordSchema,
     "systemPresentation":presentationCapabilities,
     "reference":["prepareField":"reference={dataBase64:...}; omitted or null clears the draft reference. Only image intent accepts an imported reference. No file paths or remote URLs accepted.",
       "maximumBytes":ImageGenerationReference.maximumBytes,"maximumPixels":ImageGenerationReference.maximumPixels,"maximumPreparedDimension":2048,
       "maximumAPIRequestBytes":ImageGenerationReference.maximumAPIRequestBytes,
       "input":"One still PNG/JPEG/TIFF/HEIC. A detached, orientation-corrected thumbnail is passed as the native system source image. Native Choose/Replace/Remove controls use the same decoder.",
       "authorization":"HTTP reference bytes require document transfers in addition to workspace panel changes and a real document window. Token/session/share/revision/permissions are rechecked after preparation. Native import and API prepare do not run a model.",
       "metadata":"The immutable request and placed layer keep the original input hash/type/size/dimensions and prepared dimensions. No local path or file name is stored. Reference original bytes are not embedded or returned; the original generated result remains in Generated Results independently. Recovery of that result alone does not restore reference context.",
       "remaining":"Visual inspiration only; system UI can replace it. Final reference identity is not provider-attested. Multiple references, separate Style/Composition strength, identity guarantees, selection-directed editing, markup, variations and real output qualification remain open."],
     "background":["intent":"background","defaultIntent":"image","placement":"Aspect-cover at canvas size, centered crop, below the captured masked foreground; source layers/pixels/mask properties and selection unchanged. One history transaction.",
       "source":"Existing visible root pixel layer with an enabled mask, without Smart Object/projective/clipping context. Use native Remove Background first. The selected masked subject is sent as a visual reference only after the native Generate action.",
       "referencePreparation":"Cancellable detached rendering/color conversion; maximum2048 per side. Immutable job intent, source/foreground IDs and reference dimensions are observable.",
       "limits":["maximumCanvasPixels":8_388_608,"maximumCanvasDimension":6000,"referenceMaximumDimension":2048],
       "remaining":"Real provider/background quality, empty-prompt behavior, exact Photoshop fitting/defaults/lighting/shadows, groups/Smart Objects, large canvases, generative expand/masked outpainting and full supported-platform/performance qualification remain open."],
     "generation":"Prepare opens the existing native prompt sheet only; requires Allow workspace panel changes and a desktop document window. The user starts/approves generation in the native/system UI. No headless model or deprecated ImageCreator is invoked by HTTP.",
     "cancellation":"Current document revision and exact pending image requestID or promptRefinementRequestID are required. Cancelling invalidates callbacks/preparation without an edit. Native close/dismiss/Cancel use the same job identity.",
     "snapshot":"Initial prompt, document snapshot and canvas dimensions, session/lifecycle IDs and processing route are captured before the system sheet. A stale, duplicate, cancelled or closed request never commits a result.",
     "provenance":"The native layer stores descriptive initial prompt, source/request identity, times, selected style when returned and original file hash/type/size. The system delegate has no typed model identifier, seed or final edited prompt fields; these remain null here. Original file metadata is preserved, not interpreted or qualified. Documented processing route is not per-result provider attestation.",
     "originalStorageBytes":GenerationRecord.maximumOriginalBytes,"recordStorageBytes":GenerationRecord.maximumRecordBytes,
     "history":"One accepted result is one transaction with Undo/Redo: a new image layer, or a prepared background below the retained masked subject. Native archives keep original bytes/record, background placement context and edited pixels; reopening/inspection does not need a model. Ordinary non-native Save guards provenance loss; Copy/download emits derived output.",
     "originalDownload":"Requires document transfers. The bounded original is hash-verified off the main actor; source revision, session/token, transfer permission and sharing are rechecked before response.",
     "limits":"Selected image-placement lifecycle supports still RGB8/16/32 documents; background intent adds the disclosed source-kind/canvas limits. Generative fill/expand/variation editing, general model/seed control, headless generation, actual provider output and full Photoshop/live/platform/performance equivalence remain open.",
     "adobe":"No corresponding interactive desktop lifecycle route is defined in the pinned Firefly v2 contract. No Adobe route or proprietary model identity/output equivalence is invented."]
  }
  static var backgroundRecordSchema:[String:Any] {
    BrushAPI.object(["version":["const":1],"foregroundLayerID":["type":"string","format":"uuid"],
      "width":BrushAPI.number(1,6000,integer:true),"height":BrushAPI.number(1,6000,integer:true),
      "placement":["const":"coverBelowSubject"]],required:["version","foregroundLayerID","width","height","placement"])
  }
  static func backgroundRecord(_ record:GeneratedBackgroundRecord)->[String:Any] {
    ["version":record.version,"foregroundLayerID":record.foregroundLayerID.uuidString,
      "width":record.width,"height":record.height,"placement":"coverBelowSubject"]
  }
  static var presentationCapabilities:[String:Any] {
    let policy = ImageGenerationPresentation.current
    return ["minimumMacOS":"26.0","styleKeys":policy.styles.map(\.rawValue),
      "defaultStyleKey":policy.defaultStyle?.rawValue as Any? ?? NSNull(),
      "anyStyleMinimumMacOS":"27.0","canvasSizeHintMinimumMacOS":"27.0",
      "canvasSizeHintConfigured":policy.usesCanvasSizeHint,"externalProviderStylesEnabled":false,
      "sizePolicy":"macOS27+ requests the closest system-supported resolution/aspect ratio to immutable job.sourceCanvasSize. Exact dimensions are not guaranteed. macOS26 retains system size defaults.",
      "availability":"These are configuration choices; actual eligibility/model readiness is reported by AI state. The user selects/approves generation in the native system sheet. Style keys are descriptive choices, distinct from the native resultStyle identifier."]
  }
  static func record(_ r:GenerationRecord,layerID:UUID)->[String:Any] {
    ["layerID":layerID.uuidString,"requestID":r.requestID.uuidString,"sourceDocumentID":r.sourceDocumentID.uuidString,"sourceRevision":r.sourceRevision.uuidString,
     "initialPrompt":r.initialPrompt,"provider":r.provider,"documentedProcessing":r.processing.rawValue,
     "modelIdentifier":NSNull(),"seed":NSNull(),"finalPrompt":NSNull(),"providerAttested":false,
     "startedAt":ISO8601DateFormatter().string(from:r.startedAt),"acceptedAt":ISO8601DateFormatter().string(from:r.acceptedAt),
     "resultStyle":r.resultStyle as Any? ?? NSNull(),"originalMediaType":r.originalMediaType,"originalSHA256":r.originalSHA256,"originalByteCount":r.originalByteCount]
  }
  @MainActor static func state(_ store:EditorStore)->[String:Any] {
    let capability=LocalAI.imageCapability
    var result:[String:Any]=["available":capability.available,"message":capability.message,"requiresNativeApproval":true,"canStart":capability.available && store.canStartSelectedImageGeneration,"busy":store.aiBusy,"intent":store.imageGenerationIntent.rawValue,
      "reference":store.imageReference.map { referenceRecord($0.record) } as Any? ?? NSNull(),
      "referenceImportRequestID":store.imageReferenceImportID?.uuidString as Any? ?? NSNull(),"selectedReference":NSNull(),
      "background":["eligibleForegroundLayerID":GeneratedBackground.foreground(in:store.document)?.id.uuidString as Any? ?? NSNull(),"canStart":capability.available && store.canStartBackgroundGeneration],
      "selectedBackground":NSNull(),"promptRefinementRequestID":store.promptRefinementID?.uuidString as Any? ?? NSNull(),
      "authorizedSavedResultIDs":store.authorizedGeneratedResults.filter{$0.value.documentID==store.document.id && $0.value.lifecycle==store.layerPanelGeneration}.keys.map(\.uuidString).sorted(),
      "resultLayerIDs":store.document.layers.filter{$0.sourceTags?[GeneratedImageStorage.recordKey] != nil}.map{$0.id.uuidString},"selectedResult":NSNull(),"job":NSNull()]
    if let layer=store.activeLayer,let r=try? GeneratedImageStorage.record(layer){result["selectedResult"]=record(r,layerID:layer.id)}
    if let layer=store.activeLayer,let context=try? GeneratedBackground.record(layer){result["selectedBackground"]=backgroundRecord(context)}
    if let layer=store.activeLayer,let reference=try? ImageGenerationReference.record(in:layer){result["selectedReference"]=referenceRecord(reference)}
    if let job=store.imageGenerationJob {
      result["job"]=["id":job.id.uuidString,"phase":job.phase.rawValue,"initialPrompt":job.initialPrompt,"sourceDocumentID":job.sourceDocumentID.uuidString,
        "intent":job.intent.rawValue,"foregroundLayerID":job.foregroundLayerID?.uuidString as Any? ?? NSNull(),
        "importedReference":job.importedReferenceRecord.map { referenceRecord($0) } as Any? ?? NSNull(),
        "referenceSize":job.referenceWidth.flatMap { width in job.referenceHeight.map { ["width":width,"height":$0] } } as Any? ?? NSNull(),
        "sourceCanvasSize":["width":job.sourceWidth,"height":job.sourceHeight],
        "sourceRevision":job.sourceRevision.uuidString,"documentedProcessing":job.processing.rawValue,"resultLayerID":job.resultLayerID?.uuidString as Any? ?? NSNull(),"retainedResultID":job.retainedResultID?.uuidString as Any? ?? NSNull(),"error":job.failure as Any? ?? NSNull()]as[String:Any]
    }
    return result
  }
}

extension AutomationService {
  func controlAIImage(_ request:AutomationRequest,share:Share,document:CraftNSDocument) async throws->AutomationResponse {
    guard request.headers["content-type"]?.lowercased().split(separator:";").first=="application/json" else{throw AutomationFailure(status:415,message:"Content-Type must be application/json.")}
    guard let value=try? JSONDecoder().decode(AutomationValue.self,from:request.body),case .object(let fields)=value,
      case .string(let operation)=fields["operation"],AIImageAPI.operations.contains(operation),
      case .string(let expected)=fields["revision"] else{throw AutomationFailure(status:400,message:"Expected strict AI operation, revision and parameters as JSON.")}
    let store=document.store
    guard expected==revision(store)else{throw AutomationFailure(status:409,message:"Stale revision. Refresh the AI document state.")}
    if operation=="openSaved" || operation=="trashSaved" {
      guard Set(fields.keys)==["operation","revision","resultID"],case .string(let raw)=fields["resultID"],let resultID=UUID(uuidString:raw)else{throw AutomationFailure(status:400,message:"Saved-result operations require a resultID UUID.")}
      let inbox=try authorizedAIInbox(resultID,store:store)
      if operation=="trashSaved" {
        guard documentSavesEnabled else{throw AutomationFailure(status:403,message:"Allow local document saving before moving a saved result to Trash.")}
        try preflight(document);try inbox.moveToTrash(resultID);store.authorizedGeneratedResults.removeValue(forKey:resultID)
      }else{return try await openSavedAIResult(resultID,share:share,document:document,inbox:inbox)}
    }else if operation=="cancel" {
      guard Set(fields.keys)==["operation","revision","requestID"],case .string(let id)=fields["requestID"],let requestID=UUID(uuidString:id)else{throw AutomationFailure(status:400,message:"Cancel requires a requestID UUID.")}
      if store.promptRefinementID==requestID || store.imageReferenceImportID==requestID {store.cancelAIWork()}
      else {
        guard let job=store.imageGenerationJob,job.id==requestID,job.pending else{throw AutomationFailure(status:409,message:"That AI request is no longer pending.")}
        store.cancelImageGeneration(requestID)
      }
    }else{
      guard Set(fields.keys).isSubset(of:["operation","revision","prompt","intent","reference"]),case .string(let raw)=fields["prompt"]else{throw AutomationFailure(status:400,message:"Prepare requires a prompt, current revision and optional intent/reference.")}
      let intent:ImageGenerationIntent
      if let value=fields["intent"] {
        guard case .string(let rawIntent)=value,let parsed=ImageGenerationIntent(rawValue:rawIntent)else{throw AutomationFailure(status:400,message:"intent must be image or background.")}
        intent=parsed
      }else{intent = .image}
      guard workspacePanelChangesEnabled else{throw AutomationFailure(status:403,message:"Allow workspace panel changes in the native API window first.")}
      try preflight(document)
      guard document.windowForSheet != nil else{throw AutomationFailure(status:409,message:"Open this document in a desktop window before preparing interactive AI.")}
      guard intent != .background || store.canStartBackgroundGeneration else {
        throw AutomationFailure(status:409,message:"Select a visible masked pixel layer outside a group before preparing a generated background.")
      }
      let prompt: String
      do {prompt=try LocalAI.validatePrompt(raw)}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
      var reference: ImageGenerationReference?
      if let value=fields["reference"],AIImageAPI.hasReference(value) {
        guard intent == .image, case .object(let content)=value, Set(content.keys)==["dataBase64"],
          case .string(let encoded)=content["dataBase64"], !encoded.isEmpty,
          encoded.utf8.count<=ImageGenerationReference.maximumBase64Characters,
          let bytes=Data(base64Encoded:encoded),!bytes.isEmpty,bytes.count<=ImageGenerationReference.maximumBytes else {
          throw AutomationFailure(status:400,message:"reference must contain bounded image dataBase64 for image intent.")
        }
        guard documentTransfersEnabled else {throw AutomationFailure(status:403,message:"Allow document transfers before supplying a reference image.")}
        let token=token,generation=generation,prepare=store.imageReferencePreparation
        let worker=Task.detached(priority:.userInitiated){try await prepare(bytes)}
        do {reference=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})}
        catch is CancellationError {throw AutomationFailure(status:409,message:"Reference preparation cancelled.")}
        catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
        prune()
        guard !Task.isCancelled,isRunning,self.token==token,self.generation==generation,
          workspacePanelChangesEnabled,documentTransfersEnabled,
          shares.contains(where:{$0.id==share.id && $0.document===document}),revision(store)==expected,
          document.windowForSheet != nil else {throw AutomationFailure(status:409,message:"Reference preparation cancelled or document/share/permissions changed.")}
        try preflight(document)
      }
      store.prompt=prompt;store.imageReference=reference
      store.imageGenerationIntent=intent
      store.aiError=nil;store.showAI=true
    }
    var response=AIImageAPI.state(store);response["revision"]=revision(store);return .json(response)
  }
  func originalAIImage(_ layerID:UUID,share:Share,document:CraftNSDocument,requestedRevision:String?) async throws->AutomationResponse {
    guard documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Allow document transfers before downloading an original result.")}
    guard let layer=document.store.document.layers.first(where:{$0.id==layerID})else{throw AutomationFailure(status:404,message:"Generated layer not found.")}
    let expected=revision(document.store),expectedToken=token,expectedGeneration=generation
    guard requestedRevision==nil || requestedRevision==expected else{throw AutomationFailure(status:409,message:"Stale revision. Refresh the AI document state.")}
    let worker=Task.detached(priority:.userInitiated){try Task.checkCancellation();let value=try GeneratedImageStorage.original(layer);try Task.checkCancellation();return value}
    let value=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    prune()
    guard !Task.isCancelled,isRunning,token==expectedToken,generation==expectedGeneration,documentTransfersEnabled,
      shares.contains(where:{$0.id==share.id && $0.document===document}),revision(document.store)==expected else{throw AutomationFailure(status:409,message:"Original download was cancelled or the document/share changed.")}
    return .init(status:200,contentType:value.0.originalMediaType,body:value.1)
  }
}
