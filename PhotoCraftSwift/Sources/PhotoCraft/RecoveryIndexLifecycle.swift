import AppKit
import PhotoCraftCore

@MainActor extension CraftNSDocument {
  func retireRecoveryRegistration() {
    do { try ownerController?.recoveryIndex.retire(recoveryGroupID) }
    catch { recoveryRegistrationError = "Recovery cleanup could not be recorded. Existing backups are preserved." }
  }
  var recoveryRegistrationState: [String: Any] {
    let entry = ownerController?.recoveryIndex.entries.filter { $0.recoveryID == recoveryGroupID }
      .max { $0.sequence < $1.sequence }
    return ["status": recoveryRegistrationError == nil ? (entry?.state.rawValue ?? "none") : "failed",
      "isPersistent": ownerController?.recoveryIndex.directoryURL != nil,
      "lastError": recoveryRegistrationError as Any? ?? NSNull()]
  }
}

/// Metadata-only screening is followed by the normal full native decoder and a
/// second token check before publishing a recovered document to the controller.
struct IndexedRecoveryCandidate: Sendable {
  enum Issue: String, Sendable { case missing, invalid, unavailable }
  let entry: RecoveryIndexEntry
  let context: RecoverySnapshotContext?
  let issue: Issue?
  var metadata: NativeArchive.RecoveryMetadata? = nil
  var capacityLimited = false
  static func inspect(_ entry: RecoveryIndexEntry,
    maximumMetadataBytes: Int = NativeArchive.maximumBytes) -> Self {
    do {
      try Task.checkCancellation()
      if (try? entry.backupURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
        return .init(entry: entry, context: nil, issue: .invalid)
      }
      let metadata = try NativeArchive.readRecoveryMetadata(entry.backupURL,
        maximumMetadataBytes: maximumMetadataBytes)
      let context = RecoverySnapshotContext.decode(metadata?.context)
      guard let metadata, !metadata.invalidContext, let context, context.snapshotID == entry.snapshotID,
        context.recoveryID == entry.recoveryID, context.documentID == entry.documentID,
        context.sourceURL == entry.sourceURL
      else { return .init(entry: entry, context: nil, issue: .invalid) }
      return .init(entry: entry, context: context, issue: nil, metadata: metadata)
    } catch is NativeArchiveMemoryLimit {
      return .init(entry: entry, context: nil, issue: .unavailable, capacityLimited: true)
    } catch {
      let error = error as NSError
      let missing = (error.domain == NSPOSIXErrorDomain && error.code == 2)
        || (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError)
      return .init(entry: entry, context: nil, issue: missing ? .missing : .unavailable)
    }
  }
}

@MainActor extension CraftDocumentController {
  func startIndexedRecovery() {
    guard initialRecoveryTask == nil, !initialRecoveryFinished else { return }
    initialRecoveryTask = Task { [weak self] in
      guard let self else { return }
      do { try await discoverIndexedRecovery(display: true) }
      catch { /* File Handling and API retain observable recovery failure state. */ }
      initialRecoveryTask = nil
      initialRecoveryFinished = true
      if pendingUntitledRequest, !Task.isCancelled {
        pendingUntitledRequest = false
        if documentOpening.hasPendingRequests { return }
        if let document = currentDocument ?? documents.first { document.showWindows() }
        else { newDocument(nil) }
      }
    }
  }
  func discoverIndexedRecovery(display: Bool, expectedRevision: UUID? = nil,
    validate: () throws -> Void = {}) async throws
  {
    try await discoverIndexedRecovery(display: display, expectedRevision: expectedRevision,
      started: { _ in }, validate: validate)
  }
  func discoverIndexedRecovery(display: Bool, expectedRevision: UUID? = nil,
    started: (UUID) -> Void, validate: () throws -> Void = {}) async throws
  {
    do {
      try await recoveryDiscovery.run(display: display, expectedRevision: expectedRevision,
        validate: validate, started: started)
    } catch {
      if !recoveryIndex.isDiscovering {
        recoveryIndex.discoveryError = error is CancellationError
          ? "Recovery cancelled. Existing backups remain available for retry."
          : (error as? RecoveryMemoryFailure)?.localizedDescription
            ?? (error as? RecoveryIndexFailure)?.localizedDescription
            ?? "Recovery discovery did not finish. Existing backups are preserved; retry when ready."
      }
      throw error
    }
  }
}
