import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

typealias UpscalePreparation = @Sendable (CraftDocument,Int,@escaping @Sendable(LearnedUpscale.Progress)->Void) async throws -> CraftDocument

@MainActor @Observable final class UpscaleDraft: Identifiable {
  let id=UUID(),original:CraftDocument,generation:UUID,session:UUID
  var scale=2
  var processing=false
  var error:String?
  init(store:EditorStore) {original=store.document;generation=store.layerPanelGeneration;session=store.sessionGeneration}
  var output: String {
    guard let size=try? LearnedUpscale.outputSize(width:original.width,height:original.height,scale:scale) else {return "Output exceeds the document dimensions."}
    return "\(size.width) × \(size.height) pixels in a new document"
  }
}
extension EditorStore {
  var canBeginUpscale:Bool {canDuplicateDocument && LearnedUpscaleDocument.unavailableReason(document) == nil}
  func beginUpscale() {
    finishLayerName();guard canBeginUpscale else{return}
    upscaleDraft=UpscaleDraft(store:self)
  }
  func cancelUpscale() {
    if upscaleOperationID != nil {geometryTask?.cancel()}
    upscaleDraft=nil
  }
  func updateUpscaleProgress(_ value:LearnedUpscale.Progress,operation:UUID) {
    guard upscaleOperationID == operation else{return};upscaleProgress=value
  }
  func commitUpscale(_ draft:UpscaleDraft) {
    guard upscaleDraft === draft,!draft.processing,!geometryBusy,upscaleUnavailableReason() == nil,
      (try? LearnedUpscale.outputSize(width:draft.original.width,height:draft.original.height,scale:draft.scale)) != nil,
      let controller=documentController else{return}
    guard document == draft.original,layerPanelGeneration == draft.generation,sessionGeneration == draft.session else {
      draft.error="The source changed. Cancel and reopen Generative Upscale.";return
    }
    let source=draft.original,scale=draft.scale,prepare=upscalePreparation,operation=UUID()
    let opening=controller.documentOpening.generation,closing=controller.documentClosing.state?.id
    let maintenance=controller.recoveryMaintenance.generation,discovery=controller.recoveryDiscovery.generation
    draft.error=nil;draft.processing=true;geometryBusy=true;upscaleOperationID=operation;upscaleProgress=nil
    let report:@Sendable(LearnedUpscale.Progress)->Void = { [weak self] value in
      Task { @MainActor [weak self] in self?.updateUpscaleProgress(value,operation:operation) }
    }
    geometryTask=Task { [weak self,weak controller] in
      let worker=Task.detached(priority:.userInitiated) {try await prepare(source,scale,report)}
      defer {
        draft.processing=false
        if self?.upscaleOperationID == operation {
          self?.upscaleOperationID=nil;self?.upscaleProgress=nil
          if self?.layerPanelGeneration == draft.generation {self?.geometryBusy=false;self?.geometryTask=nil}
        }
      }
      do {
        let model=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard let self,let controller,self.upscaleDraft === draft,self.upscaleOperationID == operation,
          self.document == source,self.layerPanelGeneration == draft.generation,self.sessionGeneration == draft.session,
          controller.documents.contains(where:{($0 as? CraftNSDocument)?.store === self}),
          !controller.documentClosing.isActive,controller.documentClosing.state?.id == closing,
          !controller.documentOpening.isActive,!controller.documentOpening.hasPendingRequests,controller.documentOpening.generation == opening,
          !controller.recoveryIndex.isBusy,controller.recoveryMaintenance.generation == maintenance,
          controller.recoveryDiscovery.generation == discovery else {throw CraftError.invalid("The source closed or changed while upscaling.")}
        try model.validate()
        let created=CraftNSDocument(model:model)
        controller.addDocument(created);created.updateChangeCount(.changeDone)
        self.upscaleDraft=nil;self.geometryBusy=false
        controller.documentWindows.presentAfterCurrentSheet(created)
        self.status="Upscaled to a new document";created.store.status="Local Real-ESRGAN super resolution"
      } catch is CancellationError {
        if self?.upscaleOperationID == operation {self?.upscaleDraft=nil;self?.status="Upscaling cancelled"}
      } catch {if self?.upscaleDraft === draft {draft.error=error.localizedDescription}}
    }
  }
}

struct UpscaleProgressControl:View {
  let progress:LearnedUpscale.Progress?
  var body:some View {
    if let progress,progress.completedTiles < progress.totalTiles {
      ProgressView("Upscaling tile \(progress.completedTiles + 1) of \(progress.totalTiles)",value:Double(progress.completedTiles),total:Double(progress.totalTiles))
        .accessibilityLabel("Super-resolution tiles")
    } else {
      HStack {ProgressView().controlSize(.small);Text(progress == nil ? "Preparing local model…":"Finishing output…")}
    }
  }
}
struct GenerativeUpscaleSheet:View {
  @Bindable var store:EditorStore
  @Bindable var draft:UpscaleDraft
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Generative Upscale").font(.headline)
      Text(draft.original.name).lineLimit(2)
      Form {
        LabeledContent("Model",value:"Real-ESRGAN · On device")
        Picker("Scale",selection:$draft.scale) {Text("2×").tag(2);Text("4×").tag(4)}
          .pickerStyle(.segmented).disabled(draft.processing)
        LabeledContent("Output",value:draft.output)
      }
      Text("Creates a merged copy with learned image detail. The source stays unchanged. Colour and transparency are retained; this model can invent detail.")
        .font(.caption).foregroundStyle(.secondary)
      if let reason=store.upscaleUnavailableReason() {Text(reason).font(.caption).foregroundStyle(.secondary)}
      if let error=draft.error {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      if draft.processing {UpscaleProgressControl(progress:store.upscaleProgress)}
      HStack {
        Spacer()
        Button("Cancel") {store.cancelUpscale()}.keyboardShortcut(.cancelAction)
        Button("Upscale") {store.commitUpscale(draft)}.keyboardShortcut(.defaultAction)
          .disabled(draft.processing || store.upscaleUnavailableReason() != nil || (try? LearnedUpscale.outputSize(width:draft.original.width,height:draft.original.height,scale:draft.scale)) == nil)
      }
    }.padding(20).frame(width:500)
  }
}
extension AppDelegate {
  @objc func generativeUpscale() {store?.beginUpscale()}
}
