import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class DocumentDuplicateDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let generation: UUID
  let session: UUID
  var name: String
  var merged = false
  var processing = false
  var error: String?
  init(store: EditorStore) {
    original = store.document; generation = store.layerPanelGeneration; session = store.sessionGeneration
    name = original.name + " copy"
  }
  var mergedUnavailableReason: String? { DocumentDuplication.mergedUnavailableReason(original) }
  var valid: Bool { (try? LayerDuplication.validateName(name)) != nil && (!merged || mergedUnavailableReason == nil) }
}

extension EditorStore {
  var canDuplicateDocument: Bool {
    canBeginLayerCreation && documentController?.documents.contains(where:{($0 as? CraftNSDocument)?.store === self}) == true
      && documentController?.documentClosing.isActive != true && documentController?.documentOpening.isActive != true
      && documentController?.documentOpening.hasPendingRequests != true && documentController?.recoveryIndex.isBusy != true
  }
  func beginDocumentDuplicate() {
    finishLayerName(); guard canDuplicateDocument else { return }
    documentDuplicateDraft = DocumentDuplicateDraft(store:self)
  }
  func cancelDocumentDuplicate() {
    if documentDuplicateDraft?.processing == true { geometryTask?.cancel() }
    documentDuplicateDraft = nil
  }
  func commitDocumentDuplicate(_ draft: DocumentDuplicateDraft) {
    guard documentDuplicateDraft === draft, draft.valid, !draft.processing, !geometryBusy,
      let controller = documentController else { return }
    guard document == draft.original, layerPanelGeneration == draft.generation, sessionGeneration == draft.session else {
      draft.error = "The source changed. Cancel and reopen Duplicate Image."; return
    }
    let source = draft.original, name = draft.name, merged = draft.merged, prepare = documentDuplicatePreparation
    let opening = controller.documentOpening.generation, closing = controller.documentClosing.state?.id
    let maintenance = controller.recoveryMaintenance.generation, discovery = controller.recoveryDiscovery.generation
    draft.error = nil; draft.processing = true; geometryBusy = true
    geometryTask = Task { [weak self, weak controller] in
      let worker = Task.detached(priority:.userInitiated) { try prepare(source,name,merged) }
      defer {
        draft.processing = false
        if self?.layerPanelGeneration == draft.generation { self?.geometryBusy = false; self?.geometryTask = nil }
      }
      do {
        let model = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, let controller, self.documentDuplicateDraft === draft, self.document == source,
          self.layerPanelGeneration == draft.generation, self.sessionGeneration == draft.session,
          controller.documents.contains(where:{($0 as? CraftNSDocument)?.store === self}),
          !controller.documentClosing.isActive, controller.documentClosing.state?.id == closing,
          !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, controller.documentOpening.generation == opening,
          !controller.recoveryIndex.isBusy, controller.recoveryMaintenance.generation == maintenance,
          controller.recoveryDiscovery.generation == discovery else { throw CraftError.invalid("The source closed or changed during duplication.") }
        let created = CraftNSDocument(model:model)
        controller.addDocument(created); created.updateChangeCount(.changeDone)
        self.documentDuplicateDraft = nil; self.geometryBusy = false
        controller.documentWindows.presentAfterCurrentSheet(created)
        created.store.status = "Duplicate Image"
        self.status = "Duplicate Image"
      } catch is CancellationError { self?.documentDuplicateDraft = nil; self?.status = "Duplicate Image cancelled" }
      catch { if self?.documentDuplicateDraft === draft { draft.error = error.localizedDescription } }
    }
  }
}
struct DocumentDuplicateSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: DocumentDuplicateDraft
  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Duplicate Image").font(.headline)
      Text("Duplicate: \(draft.original.name)").lineLimit(2)
      HStack { Text("As:"); TextField("Document name",text:$draft.name).textFieldStyle(.roundedBorder).disabled(draft.processing) }
      Toggle("Duplicate Merged Layers Only",isOn:$draft.merged).disabled(draft.processing || draft.mergedUnavailableReason != nil)
      if let reason = draft.mergedUnavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
      if let error = draft.error { Text(error).foregroundStyle(.red) }
      HStack {
        if draft.processing { ProgressView().controlSize(.small); Text("Duplicating…").font(.caption) }
        Spacer()
        Button("Cancel") { store.cancelDocumentDuplicate() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitDocumentDuplicate(draft) }.keyboardShortcut(.defaultAction).disabled(!draft.valid || draft.processing)
      }
    }.padding(20).frame(width:460)
  }
}
extension AppDelegate {
  @objc func duplicateDocument(_ sender: Any?) { store?.beginDocumentDuplicate() }
}
