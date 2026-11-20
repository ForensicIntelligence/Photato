import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct PreparedEmbeddedSource: Sendable {
  let original: EmbeddedSourceBytes
  var data: Data { original.data }
  let fileName: String
  let document: CraftDocument?
  var isPDF: Bool {document == nil}
  static func read(_ url: URL) throws -> Self {
    let access = url.startAccessingSecurityScopedResource()
    defer {if access {url.stopAccessingSecurityScopedResource()}}
    let original = try RecoverySourceReader.snapshot(url, maximumBytes: SmartObject.maximumLocalEmbeddedBytes(forHeader:),
      fileBackedAbove: SmartObject.maximumSourceBytes)
    let model = PDFImport.recognizes(original.data) ? nil : try SmartObjectIO.decode(original,fileName:url.lastPathComponent)
    return Self(original:original,fileName:url.lastPathComponent,document:model)
  }
}

extension EditorStore {
  func chooseRawPlacement(_ document: CraftDocument) async throws -> RawDevelopment {
    try Task.checkCancellation()
    let model = try RawPlacementWorkspace(document:document)
    rawPlacementWorkspace = model
    defer {if rawPlacementWorkspace === model {rawPlacementWindow?.close();rawPlacementWindow = nil;rawPlacementWorkspace = nil}}
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {continuation in
        guard !Task.isCancelled else {model.cancel();continuation.resume(throwing:CancellationError());return}
        model.completion = {continuation.resume(with:$0)}
        if let rawPlacementPresenter {rawPlacementPresenter(model)} else {
          let window = RawPlacementWindow(model:model);rawPlacementWindow = window;window.showWindow(nil)
        }
      }
    } onCancel:{Task {@MainActor in model.cancel()}}
  }
  func placeEmbeddedSource(_ url: URL,replacing layerID: UUID? = nil,frame frameID: UUID? = nil,linkedGrant: LinkedArtworkGrant? = nil) {
    guard clipboardTargetAvailable else {return}
    let original = document,lifecycle = layerPanelGeneration,sessionID = sessionGeneration,operation = UUID()
    let preferences = artworkPlacementPreferences.settings
    let newLayer = layerID == nil && frameID == nil
    let rasterize = newLayer && linkedGrant == nil && !preferences.alwaysCreateSmartObjectsWhenPlacing
    geometryBusy = true;embeddedPlacementOperationID = operation;embeddedPlacementSourceName = url.lastPathComponent
    embeddedPlacementIsPDF = false;status = "Reading artwork…";error = nil
    geometryTask = Task { [weak self] in
      guard let self else {return}
      defer {
        if self.embeddedPlacementOperationID == operation {
          self.embeddedPlacementOperationID = nil;self.geometryBusy = false;self.geometryTask = nil
          self.embeddedPlacementSourceName = nil;self.embeddedPlacementIsPDF = false;self.render()
        }
      }
      do {
        let reader = Task.detached(priority:.userInitiated) {()throws->(PreparedEmbeddedSource,LinkedArtworkRead?) in
          if let linkedGrant {
            let file=try LinkedArtworkRead.read(linkedGrant)
            let decoded=PDFImport.recognizes(file.data) ? nil:try SmartObjectIO.decode(file.original,fileName:file.fileName)
            return (.init(original:file.original,fileName:file.fileName,document:decoded),file)
          }
          return (try PreparedEmbeddedSource.read(url),nil)
        }
        let (source,linkedFile) = try await withTaskCancellationHandler {try await reader.value} onCancel:{reader.cancel()}
        try Task.checkCancellation()
        guard self.embeddedPlacementOperationID == operation,self.layerPanelGeneration == lifecycle,
          self.sessionGeneration == sessionID,self.document == original else {throw CraftError.invalid("The document changed while reading artwork.")}
        self.embeddedPlacementIsPDF = source.isPDF
        var options = EmbeddedSourceOptions();options.layerID = layerID;options.frameID = frameID
        if newLayer { options.fit = preferences.resizeImageDuringPlace }
        var pdf: PDFSmartObjectOptions?
        if source.isPDF {
          var selected = try await self.choosePDFPlacement(PreparedPDFSource(data:source.data,name:url.deletingPathExtension().lastPathComponent))
          selected.layerID = layerID
          if newLayer { selected.fit = options.fit }
          pdf = selected
        } else if let decoded = source.document,decoded.layers.first?.smartObject?.rawDevelopment != nil,
          RawSourceIO.recognizes(source.data) {
          options.rawDevelopment = try await self.chooseRawPlacement(decoded)
        }
        let selection = options,pdfSelection = pdf
        let worker = Task.detached(priority:.userInitiated) {
          try Task.checkCancellation()
          return try ArtworkPlacementPreparation.prepare(source.original,fileName:source.fileName,in:original,
            embedded:selection,pdf:pdfSelection,decoded:source.document)
        }
        var command = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard self.embeddedPlacementOperationID == operation,self.layerPanelGeneration == lifecycle,
          self.sessionGeneration == sessionID,self.document == original else {throw CraftError.invalid("The document changed while preparing artwork.")}
        if let file=linkedFile {
          guard self.linkedSourceRegistry.stillAuthorizes(file.grant) else{throw CraftError.invalid("Artwork authorization was revoked.")}
          let signature=Task.detached {try LinkedArtworkRead.signature(file.grant)}
          guard try await signature.value==file.signature else{throw DocumentPersistenceConflict.changed}
          try Task.checkCancellation()
          guard self.embeddedPlacementOperationID==operation,self.layerPanelGeneration==lifecycle,self.sessionGeneration==sessionID,self.document==original else{throw CraftError.invalid("The document changed before placement completed.")}
          command=try LinkedArtworkPreparation.linking(command,file:file,in:original)
        }
        if case .addLayer(let layer) = command, !preferences.skipTransformWhenPlacing {
          self.geometryBusy = false
          try self.beginEmbeddedPlacement(layer, rasterize: rasterize, linkedFile: linkedFile)
        } else {
          let preparedCommand = command
          let prepare = Task.detached(priority:.userInitiated) {
            if case .addLayer(let layer) = preparedCommand {
              let result = try ArtworkPlacementPreparation.finish(layer, in: original, rasterize: rasterize)
              return try PreparedEdit(command: .addLayer(result), document: original)
            }
            return try PreparedEdit(command: preparedCommand, document: original)
          }
          let edit = try await withTaskCancellationHandler {try await prepare.value} onCancel:{prepare.cancel()}
          try Task.checkCancellation()
          guard self.embeddedPlacementOperationID == operation,self.layerPanelGeneration == lifecycle,
            self.sessionGeneration == sessionID,self.document == original else {throw CraftError.invalid("The document changed before placement completed.")}
          if let linkedFile, !self.linkedSourceRegistry.stillAuthorizes(linkedFile.grant) {
            throw CraftError.invalid("Artwork authorization was revoked.")
          }
          try self.executeCompositePreparedEdit(edit, allowLinkedSmartObject: edit.linkedSmartObjectEdit != nil)
          self.selectedLayerIDs = Set(self.document.activeLayerID.map{[$0]} ?? [])
          if self.document != original {self.onChange?(.changeDone)}
          self.status = "Artwork placed"
        }
      } catch is CancellationError {
        if self.embeddedPlacementOperationID == operation {self.status = "Placement cancelled"}
      } catch {
        if self.embeddedPlacementOperationID == operation {self.error = error.localizedDescription}
      }
    }
  }
}
