import AppKit
import PhotoCraftCore

@MainActor extension CraftNSDocument {
  var persistenceFormat: DocumentIO.Format {
    fileType.flatMap(DocumentIO.Format.init(typeIdentifier:)) ?? .native
  }
  var saveFormats: [DocumentIO.Format] {
    DocumentIO.Format.allCases.filter {
      DocumentIO.persistenceIssue(store.document, format: $0) == nil
    }
  }

  /// AppKit retains coordinated safe writes, save ownership, file dates and change tokens.
  /// Encode the value snapshot away from the main actor, then validate immediately before
  /// handing immutable bytes to AppKit. Neither a failed nor stale encode touches the file.
  func persistDocument(
    to url: URL, format: DocumentIO.Format, operation: NSDocument.SaveOperationType,
    validate: () throws -> Void = {},
    encoder: @escaping @Sendable (CraftDocument, DocumentIO.Format) throws -> Data = DocumentIO
      .encodeForPersistence
  ) async throws {
    guard canRunFileCommand else {
      throw CraftError.invalid("Finish the current document operation.")
    }
    if operation == .saveOperation, sourceSaveNeedsReview {
      throw CraftError.unsupported(
        "The imported profile or 32-bit PSD pixels cannot yet be saved back unchanged. Use Save As to review the output format and conversion limits, or keep a Photato original."
      )
    }
    guard url.isFileURL else { throw CraftError.invalid("Choose a local file.") }
    if let other = ownerController?.document(for: url), other !== self {
      throw CraftError.invalid("This destination is already open in another document.")
    }
    store.finishNumericField()
    store.finishLayerName()
    let snapshot = store.document
    let generation = store.layerPanelGeneration
    let source = revertSourceURL
    fileOperationBusy = true
    defer {
      fileOperationBusy = false
      preparedSaveData = nil
    }
    let worker = Task.detached(priority: .userInitiated) { try encoder(snapshot, format) }
    let bytes = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard store.document == snapshot, store.layerPanelGeneration == generation,
      revertSourceURL == source
    else {
      throw DocumentSaveConflict.changed
    }
    try validate()
    preparedSaveData = (format.typeIdentifier, bytes)
    try await writePreparedDocument(to: url, type: format.typeIdentifier, operation: operation)
    if operation == .saveAsOperation { sourceSaveNeedsReview = false }
  }
}

enum DocumentSaveConflict: LocalizedError {
  case changed
  var errorDescription: String? { "The document changed while preparing the save. Save again." }
}
