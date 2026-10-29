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
  var pdfPlacementState: [String:Any] {
    ["stage":pdfPlacementWorkspace != nil ? "choosing":embeddedPlacement != nil ? (geometryBusy ? "committing":"transform"):pdfPlacementOperationID != nil ? "preparing":"idle",
     "content":pdfPlacementWorkspace?.content.rawValue as Any? ?? NSNull(),
     "selected":pdfPlacementWorkspace?.selected.sorted() ?? [],
     "layerID":embeddedPlacement?.layer.id.uuidString as Any? ?? NSNull(),
     "sourceName":pdfPlacementWorkspace?.source.name as Any? ?? embeddedPlacement?.layer.smartObject?.fileName as Any? ?? NSNull()]
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
    embeddedPlacement = nil
  }
  func commitEmbeddedPlacement(_ transform: TransformDraft) {
    guard let draft = embeddedPlacement,!geometryBusy else {return}
    guard draft.layer.id == transform.layerID, draft.original == document,
      draft.lifecycle == layerPanelGeneration,draft.session == sessionGeneration else {
      cancelTransform();error = "The document changed during placement. Place the source again.";return
    }
    let operation = UUID()
    geometryBusy = true;pdfPlacementOperationID = operation;error = nil
    geometryTask = Task { [weak self] in
      guard let self else {return}
      defer {
        if self.pdfPlacementOperationID == operation {
          self.pdfPlacementOperationID = nil;self.geometryBusy = false;self.geometryTask = nil;self.render()
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
        guard self.pdfPlacementOperationID == operation,self.embeddedPlacement?.layer.id == draft.layer.id,
          self.transformDraft == transform,self.document == draft.original,
          self.layerPanelGeneration == draft.lifecycle,self.sessionGeneration == draft.session else {
          throw CraftError.invalid("The document or placement changed before commit.")
        }
        try self.executeCompositePreparedEdit(prepared)
        self.transformDraft = nil;self.discardEmbeddedPlacement(restoreSelection:false)
        self.selectedLayerIDs = [draft.layer.id];self.onChange?(.changeDone);self.status = "PDF artwork placed"
      } catch is CancellationError {
        if self.pdfPlacementOperationID == operation {self.status = "Placement preparation cancelled"}
      } catch {
        if self.pdfPlacementOperationID == operation {self.error = error.localizedDescription}
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
    guard clipboardTargetAvailable else {return}
    let original = document,lifecycle = layerPanelGeneration,sessionID = sessionGeneration,operation = UUID()
    geometryBusy = true;pdfPlacementOperationID = operation;status = "Reading PDF…"
    geometryTask = Task { [weak self] in
      guard let self else {return}
      defer {
        if self.pdfPlacementOperationID == operation {
          self.pdfPlacementOperationID = nil;self.geometryBusy = false;self.geometryTask = nil;self.render()
        }
      }
      do {
        let reader = Task.detached(priority:.userInitiated) {
          let access = url.startAccessingSecurityScopedResource()
          defer {if access {url.stopAccessingSecurityScopedResource()}}
          return try PreparedPDFSource.read(url)
        }
        let source = try await withTaskCancellationHandler {try await reader.value} onCancel:{reader.cancel()}
        var options = try await self.choosePDFPlacement(source);options.layerID = layerID
        let selection = options,name = url.lastPathComponent
        let worker = Task.detached(priority:.userInitiated) {
          let command: Command
          if let frameID {
            command = try .frame(.replace(frameID,PDFSmartObjectIO.placed(source.data,fileName:name,in:original,
              settings:selection.settings,image:selection.image),fit:.fill))
          } else {command = try PDFSmartObjectAPI.prepare(source.data,name,original,selection)}
          return command
        }
        let command = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard self.pdfPlacementOperationID == operation,self.layerPanelGeneration == lifecycle,
          self.sessionGeneration == sessionID,self.document == original else {
          throw CraftError.invalid("The document changed while choosing PDF artwork.")
        }
        if case .addLayer(let layer) = command {
          self.geometryBusy = false;try self.beginEmbeddedPlacement(layer)
        } else {
          let prepare = Task.detached(priority:.userInitiated) {try PreparedEdit(command:command,document:original)}
          let edit = try await withTaskCancellationHandler {try await prepare.value} onCancel:{prepare.cancel()}
          try Task.checkCancellation()
          guard self.pdfPlacementOperationID == operation,self.layerPanelGeneration == lifecycle,
            self.sessionGeneration == sessionID,self.document == original else {throw CraftError.invalid("The document changed before PDF placement completed.")}
          try self.executeCompositePreparedEdit(edit)
          self.selectedLayerIDs = Set(self.document.activeLayerID.map{[$0]} ?? [])
          if self.document != original {self.onChange?(.changeDone)}
          self.status = "PDF artwork placed"
        }
      } catch is CancellationError {
        if self.pdfPlacementOperationID == operation {self.status = "PDF placement cancelled"}
      } catch {
        if self.pdfPlacementOperationID == operation {self.error = error.localizedDescription}
      }
    }
  }
  func cancelPDFPlacement() {
    if pdfPlacementOperationID != nil {geometryTask?.cancel();pdfPlacementOperationID = nil;geometryBusy = false}
    pdfPlacementWorkspace?.cancel();pdfPlacementWindow?.close();pdfPlacementWindow = nil;pdfPlacementWorkspace = nil
    discardEmbeddedPlacement(restoreSelection:false)
  }
}
