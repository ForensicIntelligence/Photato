import AppKit
import CryptoKit
import Foundation
import Observation
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class ImageGenerationJob {
  enum Phase:String {case preparingReference,awaitingSystem,preparing,completed,cancelled,stale,failed}
  let id=UUID(),sourceDocumentID:UUID,sourceRevision:UUID,lifecycle:UUID
  let sourceWidth: Int, sourceHeight: Int
  let intent: ImageGenerationIntent
  let referenceUse: ImageReferenceUse
  let foregroundLayerID: UUID?
  var referenceImage: CGImage?
  var referenceWidth: Int?
  var referenceHeight: Int?
  let importedReferenceRecord: ImageGenerationReferenceRecord?
  let initialPrompt:String,startedAt=Date(),processing:GenerationRecord.Processing
  var original:CraftDocument?
  var phase:Phase = .awaitingSystem
  var resultLayerID:UUID?
  var retainedResultID:UUID?
  var failure:String?
  var pending:Bool {phase == .preparingReference || phase == .awaitingSystem || phase == .preparing}
  init(source:CraftDocument,revision:UUID,lifecycle:UUID,prompt:String,processing:GenerationRecord.Processing,
    intent: ImageGenerationIntent = .image, reference: ImageGenerationReference? = nil, referenceUse: ImageReferenceUse = .inspiration) {
    original=source;sourceDocumentID=source.id;sourceRevision=revision;self.lifecycle=lifecycle
    sourceWidth = source.width; sourceHeight = source.height
    self.intent = intent; foregroundLayerID = intent == .background ? source.activeLayerID : nil
    let imported = intent == .image ? reference : nil
    let use: ImageReferenceUse = intent == .image ? referenceUse : .inspiration
    self.referenceUse = use
    importedReferenceRecord = imported?.record.recording(use); referenceImage = imported?.image
    referenceWidth = imported?.image.width; referenceHeight = imported?.image.height
    initialPrompt=prompt;self.processing=processing
  }
}

/// Reserved non-executable layer metadata. Original bytes and descriptive
/// records are retained independently of the edited raster's current pixels.
enum GeneratedImageStorage {
  static let recordKey="PtAI",originalKey="PtAO"
  static func record(_ layer:Layer)throws->GenerationRecord? {
    guard let data=layer.sourceTags?[recordKey] else{return nil}
    return try GenerationRecord.decode(data)
  }
  static func original(_ layer:Layer)throws->(GenerationRecord,Data) {
    guard let record=try record(layer),let bytes=layer.sourceTags?[originalKey],
      bytes.count==record.originalByteCount,bytes.count<=GenerationRecord.maximumOriginalBytes,
      SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined()==record.originalSHA256
    else{throw CraftError.invalid("The original generated image is missing or does not match its record.")}
    return(record,bytes)
  }
  static func mediaType(_ format:DocumentOpenFormat)->String? {
    guard [DocumentOpenFormat.png,.jpeg,.tiff,.heic,.exr].contains(format)else{return nil}
    return format.persistenceFormat?.mediaType ?? (format == .heic ? "image/heic":nil)
  }
  static func generationRecord(_ bytes:Data,requestID:UUID,sourceDocumentID:UUID,sourceRevision:UUID,
    initialPrompt:String,startedAt:Date,acceptedAt:Date,processing:GenerationRecord.Processing,resultStyle:String?)throws->GenerationRecord {
    guard !bytes.isEmpty,bytes.count<=GenerationRecord.maximumOriginalBytes,let format=DocumentOpenFormat.detect(bytes),let type=mediaType(format)else{throw CraftError.invalid("The system image result is not a supported bounded image.")}
    return try GenerationRecord(requestID:requestID,sourceDocumentID:sourceDocumentID,sourceRevision:sourceRevision,
      initialPrompt:initialPrompt,startedAt:startedAt,acceptedAt:acceptedAt,processing:processing,resultStyle:resultStyle,
      originalMediaType:type,originalSHA256:SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),originalByteCount:bytes.count)
  }
  static func recoveredDocument(_ record:GenerationRecord,original:Data)throws->CraftDocument {
    try record.validate();try Task.checkCancellation()
    guard original.count==record.originalByteCount,SHA256.hash(data:original).map({String(format:"%02x",$0)}).joined()==record.originalSHA256 else{throw CraftError.invalid("The saved generated original failed its integrity check.")}
    var model=try DocumentIO.decode(original,native:false,name:"Generated original",rasterByteLimit:128*1024*1024)
    guard model.layers.count==1,case .raster=model.layers[0].content,model.layers[0].smartObject==nil,model.animation==nil,model.videoTimeline==nil else{throw CraftError.invalid("The original must contain one still raster image.")}
    let index=0
    model.id=UUID();model.name="Generated · " + String(record.initialPrompt.prefix(32))
    if model.layers[index].sourceTags==nil {model.layers[index].sourceTags=[:]}
    model.layers[index].sourceTags?[recordKey]=try record.encoded();model.layers[index].sourceTags?[originalKey]=original
    try model.validate();try Task.checkCancellation();return model
  }
  static func readLocalResult(_ url:URL)throws->Data {
    guard url.isFileURL else{throw CraftError.invalid("The system image result must be a local file.")}
    let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
    var bytes=Data()
    while let part=try file.read(upToCount:min(1024*1024,GenerationRecord.maximumOriginalBytes-bytes.count+1)),!part.isEmpty {
      guard part.count<=GenerationRecord.maximumOriginalBytes-bytes.count else{throw CraftError.invalid("The generated image exceeds the32MiB original-image limit.")}
      bytes.append(part)
    }
    guard !bytes.isEmpty else{throw CraftError.invalid("The system image result is empty.")};return bytes
  }
  static func preparedLayer(_ bytes:Data,source:CraftDocument,requestID:UUID,sourceRevision:UUID,
    initialPrompt:String,startedAt:Date,acceptedAt:Date,processing:GenerationRecord.Processing,resultStyle:String?,
    coverCanvas: Bool = false)throws->Layer {
    try Task.checkCancellation()
    guard !bytes.isEmpty,bytes.count<=GenerationRecord.maximumOriginalBytes,
      let format=DocumentOpenFormat.detect(bytes),[DocumentOpenFormat.png,.jpeg,.tiff,.heic,.exr].contains(format),
      mediaType(format) != nil
    else{throw CraftError.invalid("The system image result is not a supported bounded image.")}
    let imported=try DocumentIO.decode(bytes,native:false,name:"Generated image",rasterByteLimit:128*1024*1024)
    guard imported.layers.count==1,case .raster(let pixels)=imported.layers[0].content,
      imported.layers[0].smartObject==nil,imported.videoTimeline==nil,imported.animation==nil else{throw CraftError.invalid("The system image result must contain one still image.")}
    var raster=try ColorManagement.converted(pixels,from:imported,to:source)
    if coverCanvas {
      let scale = max(Double(source.width) / Double(raster.width), Double(source.height) / Double(raster.height))
      let placement = Transform2D.translation((Double(source.width) - Double(raster.width) * scale) / 2,
        (Double(source.height) - Double(raster.height) * scale) / 2) * .scale(scale, scale)
      raster = try RasterGeometry.render(raster, transform: placement,
        bounds: .init(x: 0, y: 0, width: source.width, height: source.height), method: .bicubic, clampEdges: true)
    } else if raster.width>source.width || raster.height>source.height {
      let scale=min(Double(source.width)/Double(raster.width),Double(source.height)/Double(raster.height))
      raster=try Renderer.resize(raster,width:max(1,Int(Double(raster.width)*scale)),height:max(1,Int(Double(raster.height)*scale)))
    }
    let record=try generationRecord(bytes,requestID:requestID,sourceDocumentID:source.id,sourceRevision:sourceRevision,
      initialPrompt:initialPrompt,startedAt:startedAt,acceptedAt:acceptedAt,processing:processing,resultStyle:resultStyle)
    var layer=Layer(name:"Generated · \(initialPrompt.prefix(32))",content:.raster(raster))
    layer.x=(source.width-raster.width)/2;layer.y=(source.height-raster.height)/2
    layer.sourceTags=[recordKey:try record.encoded(),originalKey:bytes]
    try Task.checkCancellation();return layer
  }
}

extension EditorStore {
  var canStartBackgroundGeneration: Bool {
    imageGenerationContextAvailable && GeneratedBackground.foreground(in: document) != nil
  }
  var canStartSelectedImageGeneration: Bool {
    imageGenerationIntent == .background ? canStartBackgroundGeneration : canStartImageGeneration
  }
  func prepareBackgroundGeneration() {
    guard canStartBackgroundGeneration else { return }
    imageGenerationIntent = .background; aiError = nil; showAI = true
  }
  var canStartImageGeneration:Bool {
    imageGenerationContextAvailable && !editingMask
      && (imageReferenceUse == .inspiration || (ImageReferenceUse.editingSupported && imageReference != nil))
  }
  private var imageGenerationContextAvailable:Bool {
    imageGenerationSourceAvailable() && !aiBusy && !geometryBusy && !hasToneDraft && !coalescingChanges && transformDraft==nil
      && historyOperation==nil && geometrySheet==nil && brushGesture==nil && pathGesture==nil
      && !editingComponent && !smartFilterMaskEditing && error==nil
      && document.colorMode == .rgb && document.restrictedMode==nil && document.inkMode==nil && !document.isChannelOnly
      && document.videoTimeline==nil && document.animation==nil
  }
  func startImageGeneration(capability:AICapability) throws {
    if imageGenerationIntent == .image { try imageReferenceUse.validate(hasReference:imageReference != nil) }
    guard canStartSelectedImageGeneration else{throw CraftError.invalid("Finish the current edit before generating an image. This image workflow currently requires a still RGB document and an eligible generation target.")}
    guard imageGenerationIntent != .background || canStartBackgroundGeneration else {
      throw CraftError.invalid("Select a visible, masked pixel layer outside a group. Remove its background first.")
    }
    let input=try LocalAI.validatePrompt(prompt)
    guard capability.available else{throw LocalAIError.unavailable(capability.message)}
    // Remove Background selects the new mask. Generating a separate layer must
    // leave mask-painting context before capturing the immutable image job.
    if imageGenerationIntent == .background, editingMask, let id=document.activeLayerID { select(id) }
    guard !editingMask else { throw CraftError.invalid("Select layer content before generating an image.") }
    let major=ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    let job=ImageGenerationJob(source:document,revision:sessionGeneration,lifecycle:layerPanelGeneration,prompt:input,
      processing:major>=27 ? .privateCloudCompute:major==26 ? .onDevice:.unknown,
      intent: imageGenerationIntent, reference: imageReference, referenceUse: imageReferenceUse)
    // Check record/space limits before invoking the system generation interface.
    let sizing=try GenerationRecord(requestID:job.id,sourceDocumentID:job.sourceDocumentID,sourceRevision:job.sourceRevision,
      initialPrompt:input,startedAt:job.startedAt,acceptedAt:job.startedAt,processing:job.processing,resultStyle:String(repeating:"x",count:256),
      originalMediaType:"image/png",originalSHA256:String(repeating:"0",count:64),originalByteCount:1)
    _ = try sizing.encoded();try generatedResultInbox.preflight()
    prompt=input;imageGenerationJob=job;aiError=nil;aiBusy=true
    if job.intent == .image { showImagePlayground=true; return }
    job.phase = .preparingReference; showImagePlayground=false
    let source=document,prepare=backgroundReferencePreparation
    aiTask=Task { [weak self,weak job] in
      guard !Task.isCancelled else { return }
      let worker=Task.detached(priority:.userInitiated) { try await prepare(source) }
      do {
        let image=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
        try Task.checkCancellation()
        guard let self,let job,self.imageGenerationJob === job,job.phase == .preparingReference else { return }
        guard self.imageSourceStillMatches(job) else {
          self.endImageGeneration(job,phase:.stale,message:"The document changed before background generation started.");return
        }
        job.referenceImage=image;job.referenceWidth=image.width;job.referenceHeight=image.height
        job.phase = .awaitingSystem;self.showImagePlayground=true;self.aiTask=nil
      } catch is CancellationError {
        if let self,let job,self.imageGenerationJob === job,job.pending { self.endImageGeneration(job,phase:.cancelled) }
      } catch {
        if let self,let job,self.imageGenerationJob === job,job.pending { self.endImageGeneration(job,phase:.failed,message:error.localizedDescription) }
      }
    }
  }
  func imageSourceStillMatches(_ job:ImageGenerationJob)->Bool {
    imageGenerationSourceAvailable() && imageGenerationJob === job && job.pending && sessionGeneration==job.sourceRevision
      && layerPanelGeneration==job.lifecycle && job.original==document
      && !geometryBusy && !hasToneDraft && !coalescingChanges && transformDraft==nil && historyOperation==nil
      && brushGesture==nil && pathGesture==nil && !editingComponent && !editingMask && !smartFilterMaskEditing
  }
  func endImageGeneration(_ job:ImageGenerationJob,phase:ImageGenerationJob.Phase,message:String?=nil) {
    guard imageGenerationJob === job else{return}
    job.phase=phase;job.failure=message;job.original=nil;job.referenceImage=nil;aiBusy=false;showImagePlayground=false
    if let message{aiError=message};aiTask=nil
  }
  func cancelImageGeneration(_ requestID:UUID) {
    guard let job=imageGenerationJob,job.id==requestID,job.pending else{return}
    aiTask?.cancel();endImageGeneration(job,phase:.cancelled);status="Image generation cancelled"
  }
  func cancelAIWork() {
    promptRefinementID=nil;imageReferenceImportID=nil;aiTask?.cancel();aiTask=nil
    if let job=imageGenerationJob,job.pending {cancelImageGeneration(job.id)}
    aiBusy=false
  }
  func imageSystemInterfaceDismissed(_ requestID:UUID) {
    guard let job=imageGenerationJob,job.id==requestID,job.phase == .awaitingSystem else{return}
    cancelImageGeneration(requestID)
  }
  func acceptGeneratedImage(_ url:URL,requestID:UUID,resultStyle:String?=nil) {
    guard let job=imageGenerationJob,job.id==requestID,job.phase == .awaitingSystem else{return}
    do {try acceptGeneratedImageData(GeneratedImageStorage.readLocalResult(url),requestID:requestID,resultStyle:resultStyle)}
    catch {job.failure=error.localizedDescription;aiError=error.localizedDescription}
  }
  func acceptGeneratedImageData(_ bytes:Data,requestID:UUID,resultStyle:String?=nil)throws {
    guard let job=imageGenerationJob,job.id==requestID,job.phase == .awaitingSystem else{throw CraftError.invalid("That image request is no longer awaiting a result.")}
    let acceptedAt=Date()
    let record=try GeneratedImageStorage.generationRecord(bytes,requestID:job.id,sourceDocumentID:job.sourceDocumentID,
      sourceRevision:job.sourceRevision,initialPrompt:job.initialPrompt,startedAt:job.startedAt,acceptedAt:acceptedAt,processing:job.processing,resultStyle:resultStyle)
    let retained=try generatedResultInbox.persist(record,original:bytes)
    job.retainedResultID=retained
    authorizedGeneratedResults[retained]=(job.sourceDocumentID,job.lifecycle)
    guard imageSourceStillMatches(job),let source=job.original else{endImageGeneration(job,phase:.stale,message:"The document changed. The original is saved in Generated Results; no image was added.");return}
    let initialPrompt=job.initialPrompt,revision=job.sourceRevision,id=job.id,start=job.startedAt,processing=job.processing
    job.phase = .preparing;showImagePlayground=false
    let prepare=imageGenerationPreparation,backgroundPrepare=backgroundGenerationPreparation
    let intent=job.intent,foregroundID=job.foregroundLayerID,referenceRecord=job.importedReferenceRecord
    aiTask=Task { [weak self,weak job] in
      guard !Task.isCancelled else{return}
      let worker=Task.detached(priority:.userInitiated) { () async throws -> (Layer,Command) in
        let layer:Layer
        if intent == .background {
          layer=try await backgroundPrepare(bytes,source,id,revision,initialPrompt,start,acceptedAt,processing,resultStyle)
          guard let foregroundID else { throw CraftError.invalid("The background request has no foreground.") }
          return (layer,try GeneratedBackground.command(layer,source:source,foregroundID:foregroundID))
        }
        layer=try ImageGenerationReference.attach(referenceRecord, to: await prepare(bytes,source,id,revision,initialPrompt,start,acceptedAt,processing,resultStyle))
        return (layer,.addLayer(layer))
      }
      do {
        let (layer,command)=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
        try Task.checkCancellation()
        guard let self,let job,self.imageGenerationJob === job,job.phase == .preparing else{return}
        guard self.imageSourceStillMatches(job) else{self.endImageGeneration(job,phase:.stale,message:"The document changed. The original is saved in Generated Results; no image was added.");return}
        try self.executeEditorCommand(command)
        job.resultLayerID=layer.id;self.endImageGeneration(job,phase:.completed)
        self.status=intent == .background ? "Background created with Image Playground"
          : job.referenceUse == .editExisting ? "Reference image edited with Image Playground" : "Created with Image Playground"
      }catch is CancellationError {
        if let self,let job,self.imageGenerationJob === job,job.pending {self.endImageGeneration(job,phase:.cancelled);self.status="Image generation cancelled"}
      }catch {
        if let self,let job,self.imageGenerationJob === job,job.pending {self.endImageGeneration(job,phase:.failed,message:error.localizedDescription+" The original is saved in Generated Results.")}
      }
    }
  }
  func refinePrompt() {
    guard !aiBusy else{return}
    let input=prompt,id=UUID();promptRefinementID=id;aiBusy=true;aiError=nil
    let refine=promptRefinement
    aiTask=Task { [weak self] in
      guard !Task.isCancelled,self?.promptRefinementID==id else{return}
      do {
        let raw=try await refine(input);try Task.checkCancellation()
        let result:String
        do {result=try LocalAI.validatePrompt(raw)}catch {throw CraftError.invalid("The local model returned an unsupported prompt. Your draft was kept.")}
        guard let self,self.promptRefinementID==id else{return}
        defer{self.promptRefinementID=nil;self.aiBusy=false;self.aiTask=nil}
        guard self.prompt==input else{self.status="Prompt changed; refinement was not applied";return}
        self.prompt=result
      }catch {
        guard let self,self.promptRefinementID==id else{return}
        self.promptRefinementID=nil;self.aiBusy=false;self.aiTask=nil
        if error is CancellationError {self.status="Prompt refinement cancelled"}else{self.aiError=error.localizedDescription}
      }
    }
  }
}
