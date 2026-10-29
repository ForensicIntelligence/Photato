import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct EmbeddedPlacementDraft: Sendable {
  let original: CraftDocument
  let layer: Layer
  let selected: Set<UUID>
  let lifecycle: UUID
  let session: UUID
  let preview: CraftDocument
}

extension EditorStore {
  var layerPanelDocument: CraftDocument { embeddedPlacement?.preview ?? document }
  var embeddedPlacementState: [String:Any] {
    ["stage":rawPlacementWorkspace != nil ? "developingRaw":pdfPlacementWorkspace != nil ? "choosingPDF":embeddedPlacement != nil ? (geometryBusy ? "committing":"transform"):embeddedPlacementOperationID != nil ? "preparing":"idle",
     "layerID":embeddedPlacement?.layer.id.uuidString as Any? ?? NSNull(),
     "sourceName":embeddedPlacement?.layer.smartObject?.fileName as Any? ?? embeddedPlacementSourceName as Any? ?? NSNull(),
     "mediaType":embeddedPlacement?.layer.smartObject?.mediaType as Any? ?? NSNull()]
  }
  var pdfPlacementState: [String:Any] {
    let active = embeddedPlacementIsPDF || embeddedPlacement?.layer.smartObject?.pdfSource != nil
    return ["stage": !active ? "idle":pdfPlacementWorkspace != nil ? "choosing":embeddedPlacement != nil ? (geometryBusy ? "committing":"transform"):embeddedPlacementOperationID != nil ? "preparing":"idle",
     "content":pdfPlacementWorkspace?.content.rawValue as Any? ?? NSNull(),
     "selected":pdfPlacementWorkspace?.selected.sorted() ?? [],
     "layerID":active ? (embeddedPlacement?.layer.id.uuidString as Any? ?? NSNull()):NSNull(),
     "sourceName":active ? (pdfPlacementWorkspace?.source.name as Any? ?? embeddedPlacement?.layer.smartObject?.fileName as Any? ?? NSNull()):NSNull()]
  }


  func beginEmbeddedPlacement(_ layer: Layer) throws {
    guard clipboardTargetAvailable else {throw CraftError.invalid("Finish the current edit before placing artwork.")}
    var preview = document
    try Command.addLayer(layer).apply(to:&preview)
    let inserted = preview.layers.first(where:{$0.id == layer.id})!
    let bounds = try layerBounds(inserted)
    embeddedPlacement = EmbeddedPlacementDraft(original:document,layer:inserted,selected:selectedLayerIDs,
      lifecycle:layerPanelGeneration,session:sessionGeneration,preview:preview)
    transformDraft = TransformDraft(layerID:layer.id,bounds:bounds)
    selectedLayerIDs = [layer.id];tool = .move
    status = "Place Embedded · Return to commit · Escape to cancel"
    render()
  }
  func discardEmbeddedPlacement(restoreSelection: Bool = true) {
    if let draft = embeddedPlacement,restoreSelection,draft.original.id == document.id {
      selectedLayerIDs = draft.selected.intersection(Set(document.layers.map(\.id)))
    }
    embeddedPlacement = nil;embeddedPlacementSourceName = nil;embeddedPlacementIsPDF = false
  }
  func commitEmbeddedPlacement(_ transform: TransformDraft) {
    guard let draft = embeddedPlacement,!geometryBusy else {return}
    guard draft.layer.id == transform.layerID, draft.original == document,
      draft.lifecycle == layerPanelGeneration,draft.session == sessionGeneration else {
      cancelTransform();error = "The document changed during placement. Place the source again.";return
    }
    let operation = UUID()
    geometryBusy = true;embeddedPlacementOperationID = operation;error = nil
    geometryTask = Task { [weak self] in
      guard let self else {return}
      defer {
        if self.embeddedPlacementOperationID == operation {
          self.embeddedPlacementOperationID = nil;self.geometryBusy = false;self.geometryTask = nil;self.render()
        }
      }
      do {
        let worker = Task.detached(priority:.userInitiated) {
          let layer = try DocumentGeometry.transformLayer(draft.layer,by:transform.delta,in:draft.original,method:transform.interpolation)
          _ = try PDFSmartObjectIO.renderedLayer(layer,in:draft.original)
          try Task.checkCancellation()
          return try PreparedEdit(command:.addLayer(layer),document:draft.original)
        }
        let prepared = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard self.embeddedPlacementOperationID == operation,self.embeddedPlacement?.layer.id == draft.layer.id,
          self.transformDraft == transform,self.document == draft.original,
          self.layerPanelGeneration == draft.lifecycle,self.sessionGeneration == draft.session else {
          throw CraftError.invalid("The document or placement changed before commit.")
        }
        try self.executeCompositePreparedEdit(prepared)
        self.transformDraft = nil;self.discardEmbeddedPlacement(restoreSelection:false)
        self.selectedLayerIDs = [draft.layer.id];self.onChange?(.changeDone);self.status = "Artwork placed"
      } catch is CancellationError {
        if self.embeddedPlacementOperationID == operation {self.status = "Placement preparation cancelled"}
      } catch {
        if self.embeddedPlacementOperationID == operation {self.error = error.localizedDescription}
      }
    }
  }

  func choosePDFPlacement(_ source: PreparedPDFSource) async throws -> PDFSmartObjectOptions {
    try Task.checkCancellation()
    let model = PDFImportWorkspace(source:source,placement:true)
    pdfPlacementWorkspace = model
    defer {if pdfPlacementWorkspace === model {pdfPlacementWindow?.close();pdfPlacementWindow = nil;pdfPlacementWorkspace = nil}}
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {continuation in
        guard !Task.isCancelled else {continuation.resume(throwing:CancellationError());return}
        model.placementCompletion = {continuation.resume(with:$0)}
        model.inspect()
        if let pdfPlacementPresenter {pdfPlacementPresenter(model)} else {
          let window = PDFImportWindow(model:model);pdfPlacementWindow = window;window.showWindow(nil)
        }
      }
    } onCancel:{Task {@MainActor in model.cancel()}}
  }
  func placePDF(_ url: URL,replacing layerID: UUID? = nil,frame frameID: UUID? = nil) {
    placeEmbeddedSource(url,replacing:layerID,frame:frameID)
  }
  func cancelEmbeddedPlacement() {
    if embeddedPlacementOperationID != nil {geometryTask?.cancel();embeddedPlacementOperationID = nil;geometryBusy = false}
    rawPlacementWorkspace?.cancel();rawPlacementWindow?.close();rawPlacementWindow = nil;rawPlacementWorkspace = nil
    embeddedPlacementSourceName = nil;embeddedPlacementIsPDF = false
    pdfPlacementWorkspace?.cancel();pdfPlacementWindow?.close();pdfPlacementWindow = nil;pdfPlacementWorkspace = nil
    discardEmbeddedPlacement(restoreSelection:false)
  }
}
