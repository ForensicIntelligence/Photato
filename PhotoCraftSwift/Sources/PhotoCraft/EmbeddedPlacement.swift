import AppKit
import CryptoKit
import PhotoCraftCore
import PhotoCraftImaging

struct PreparedEmbeddedSource: Sendable {
  let data: Data
  let fileName: String
  let document: CraftDocument?
  var isPDF: Bool {document == nil}
  static func read(_ url: URL) throws -> Self {
    let access = url.startAccessingSecurityScopedResource()
    defer {if access {url.stopAccessingSecurityScopedResource()}}
    return try RecoverySourceReader.withStableMetadata {
      let reader = try RecoverySourceReader(url)
      let file = try FileHandle(forReadingFrom:url);defer {try? file.close()}
      var data = Data()
      while true {
        try Task.checkCancellation()
        guard let chunk = try file.read(upToCount:min(65536,SmartObject.maximumSourceBytes+1-data.count)),!chunk.isEmpty else {break}
        data.append(chunk)
        guard data.count <= SmartObject.maximumSourceBytes else {throw CraftError.invalid("Choose artwork no larger than64MiB.")}
      }
      let fingerprint = try reader.finish()
      guard fingerprint.sha256 == SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() else {throw DocumentPersistenceConflict.changed}
      let model = PDFImport.recognizes(data) ? nil:try SmartObjectIO.decode(data,fileName:url.lastPathComponent)
      return Self(data:data,fileName:url.lastPathComponent,document:model)
    }
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
  func placeEmbeddedSource(_ url: URL,replacing layerID: UUID? = nil,frame frameID: UUID? = nil) {
    guard clipboardTargetAvailable else {return}
    let original = document,lifecycle = layerPanelGeneration,sessionID = sessionGeneration,operation = UUID()
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
        let reader = Task.detached(priority:.userInitiated) {try PreparedEmbeddedSource.read(url)}
        let source = try await withTaskCancellationHandler {try await reader.value} onCancel:{reader.cancel()}
        try Task.checkCancellation()
        guard self.embeddedPlacementOperationID == operation,self.layerPanelGeneration == lifecycle,
          self.sessionGeneration == sessionID,self.document == original else {throw CraftError.invalid("The document changed while reading artwork.")}
        self.embeddedPlacementIsPDF = source.isPDF
        var options = EmbeddedSourceOptions();options.layerID = layerID;options.frameID = frameID
        var pdf: PDFSmartObjectOptions?
        if source.isPDF {
          var selected = try await self.choosePDFPlacement(PreparedPDFSource(data:source.data,name:url.deletingPathExtension().lastPathComponent))
          selected.layerID = layerID;pdf = selected
        } else if let decoded = source.document,decoded.layers.first?.smartObject?.rawDevelopment != nil,
          RawSourceIO.recognizes(source.data) {
          options.rawDevelopment = try await self.chooseRawPlacement(decoded)
        }
        let selection = options,pdfSelection = pdf
        let worker = Task.detached(priority:.userInitiated) {
          try Task.checkCancellation()
          if let pdfSelection {
            if let frameID {
              return try Command.frame(.replace(frameID,PDFSmartObjectIO.placed(source.data,fileName:source.fileName,in:original,
                settings:pdfSelection.settings,image:pdfSelection.image),fit:.fill))
            }
            return try PDFSmartObjectAPI.prepare(source.data,source.fileName,original,pdfSelection)
          }
          return try EmbeddedSourceAPI.prepare(source.data,source.fileName,original,selection,decoded:source.document)
        }
        let command = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard self.embeddedPlacementOperationID == operation,self.layerPanelGeneration == lifecycle,
          self.sessionGeneration == sessionID,self.document == original else {throw CraftError.invalid("The document changed while preparing artwork.")}
        if case .addLayer(let layer) = command {
          self.geometryBusy = false;try self.beginEmbeddedPlacement(layer)
        } else {
          let prepare = Task.detached(priority:.userInitiated) {try PreparedEdit(command:command,document:original)}
          let edit = try await withTaskCancellationHandler {try await prepare.value} onCancel:{prepare.cancel()}
          try Task.checkCancellation()
          guard self.embeddedPlacementOperationID == operation,self.layerPanelGeneration == lifecycle,
            self.sessionGeneration == sessionID,self.document == original else {throw CraftError.invalid("The document changed before placement completed.")}
          try self.executeCompositePreparedEdit(edit)
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
