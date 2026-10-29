import AppKit
import Darwin
import PhotoCraftCore
import PhotoCraftImaging

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
  /// handing immutable bytes or a private staged file to AppKit. Neither a failed nor stale encode touches the file.
  func persistDocument(
    to url: URL, format: DocumentIO.Format, operation: NSDocument.SaveOperationType,
    options requestedOptions: RasterEncodingOptions? = nil,
    validate: () throws -> Void = {},
    maximumPreparedBytes: Int? = nil, encoder: DocumentIO.Encoder? = nil
  ) async throws {
    guard canRunFileCommand else {
      throw CraftError.invalid("Finish the current document operation.")
    }
    if operation == .saveOperation, sourceSaveNeedsReview {
      if isRecoveredSource { throw RecoverySourceConflict.review }
      throw CraftError.unsupported(
        "Use Save As to review the output file and format before replacing this document's original."
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
    let options = requestedOptions ?? compatibleRememberedEncodingOptions[format] ?? .init()
    try options.validate(for: format.contentType)
    let effectiveOptions = effectiveEncodingOptions(options, format: format, persistence: true)
    fileOperationBusy = true
    defer {
      fileOperationBusy = false
      preparedSaveOutput = nil
    }
    let worker = Task.detached(priority: .userInitiated) {
      let output = try DocumentIO.prepareOutput(snapshot, format: format, persistence: true, options: effectiveOptions, encoder: encoder)
      return (output, try output.contentDigest())
    }
    let (output, digest) = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard store.document == snapshot, store.layerPanelGeneration == generation,
      revertSourceURL == source
    else {
      throw DocumentSaveConflict.changed
    }
    if let maximumPreparedBytes, output.count > maximumPreparedBytes {
      throw AutomationFailure(status: 413, message: "Saved output exceeds the 128 MiB API limit.")
    }
    if operation == .saveOperation { try await validateRecoveredSourceForSave(to: url) }
    guard store.document == snapshot, store.layerPanelGeneration == generation,
      revertSourceURL == source else { throw DocumentSaveConflict.changed }
    try validate()
    // AppKit may pass an unrelated, newly created staging URL to write(to:).
    // Capture the final destination's visibility before handing off the save.
    let hidden = try Self.destinationHiddenFlag(url)
    preparedSaveOutput = (format.typeIdentifier, output, hidden)
    try await writePreparedDocument(to: url, type: format.typeIdentifier, operation: operation)
    if operation == .saveOperation || operation == .saveAsOperation {
      rememberedEncodingOptions[format] = options
      resetRecoverySource()
      if operation == .saveAsOperation { sourceSaveNeedsReview = false }
      let capture = Task.detached(priority: .utility) { try? RecoverySourceReader.capture(url) }
      let fingerprint = await withTaskCancellationHandler(operation: { await capture.value },
        onCancel: { capture.cancel() })
      if let fingerprint, fingerprint.sha256 == digest, fileURL == url {
        recoverySourceRecord = .make(url: url, format: format,
          needsReview: sourceSaveNeedsReview, fingerprint: fingerprint)
      }
      // Failure to capture provenance does not turn an already successful Save into
      // a failure. A subsequent recovery without a record requires explicit review.
      ownerController?.recoveryPreferences.remember(url)
    }
  }

  private static func destinationHiddenFlag(_ url: URL) throws -> Bool {
    var value = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
      path.map { fstatat(AT_FDCWD, $0, &value, 0) } ?? -1
    }
    if result != 0 {
      if errno == ENOENT { return false }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return value.st_flags & UInt32(UF_HIDDEN) != 0
  }
}

enum DocumentSaveConflict: LocalizedError {
  case changed
  var errorDescription: String? { "The document changed while preparing the save. Save again." }
}
