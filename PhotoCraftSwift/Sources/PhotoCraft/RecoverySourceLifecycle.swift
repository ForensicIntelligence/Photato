import AppKit
import CryptoKit
import PhotoCraftCore
import PhotoCraftImaging

@MainActor extension CraftNSDocument {
  static func formatNeedsReview(_ model: CraftDocument, format: DocumentIO.Format?) -> Bool {
    let sourceSpace = model.sourceICC.flatMap { CGColorSpace(iccData: $0 as CFData) }
    return ((format == .psd || format == .psb) && model.depth == .f32)
      || (sourceSpace != nil && sourceSpace != CGColorSpace(name: CGColorSpace.sRGB)
        && sourceSpace != CGColorSpace(name: CGColorSpace.linearSRGB))
  }
  func resetRecoverySource() {
    sourceVerificationGeneration = UUID()
    sourceVerificationTask?.cancel()
    sourceVerificationTask = nil
    recoverySourceRecord = nil
    pendingRecoveryContext = nil
    recoverySourceStatus = .none
    isRecoveredSource = false
    if let recoverySourceAccessURL { recoverySourceAccessURL.stopAccessingSecurityScopedResource() }
    recoverySourceAccessURL = nil
  }
  func restoreRecoverySource(registeredURL: URL) {
    sourceSaveNeedsReview = true
    isRecoveredSource = true
    recoverySourceStatus = .unverified
    guard let record = RecoverySourceRecord.decode(pendingRecoveryContext) else { return }
    pendingRecoveryContext = nil
    // Preserve the recorded type even if the current original now contains another format.
    guard RecoverySourceRecord.canonical(registeredURL) == RecoverySourceRecord.canonical(record.originalURL)
      || record.bookmark != nil
    else { return }
    recoverySourceStatus = .checking
    let generation = sourceVerificationGeneration
    sourceVerificationTask = Task { [weak self] in
      let worker = Task.detached(priority: .utility) { record.verify(registeredURL: registeredURL) }
      let result = await withTaskCancellationHandler(operation: { await worker.value },
        onCancel: { worker.cancel() })
      guard let self, !Task.isCancelled, sourceVerificationGeneration == generation,
        fileURL == registeredURL else { return }
      defer { sourceVerificationTask = nil }
      recoverySourceStatus = result.status
      guard result.status != .unverified else { return }
      fileType = DocumentIO.Format(rawValue: record.format)?.typeIdentifier
      recoverySourceRecord = record
      guard result.status.verified, let url = result.url, let fingerprint = result.fingerprint else {
        store.status = "Recovered document: original \(result.status.rawValue). Use Save As."
        return
      }
      if let other = ownerController?.document(for: url), other !== self {
        recoverySourceStatus = .unverified
        return
      }
      if url.startAccessingSecurityScopedResource() { recoverySourceAccessURL = url }
      fileURL = url
      // Match Foundation/AppKit's date representation, rather than reconstructing its rounding.
      fileModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      recoverySourceRecord = .make(url: url, format: DocumentIO.Format(rawValue: record.format)!,
        needsReview: record.needsFormatReview, fingerprint: fingerprint)
      sourceSaveNeedsReview = record.needsFormatReview
      store.status = result.status == .moved
        ? "Recovered document: moved original verified." : "Recovered document: original verified."
    }
  }
  /// Save rechecks a recovered association after preparing its output, immediately
  /// before AppKit's coordinated save. A bookmark cannot redirect this Save elsewhere.
  func validateRecoveredSourceForSave(to url: URL) async throws {
    guard isRecoveredSource else { return }
    guard let record = recoverySourceRecord else {
      recoverySourceStatus = .unverified
      sourceSaveNeedsReview = true
      throw RecoverySourceConflict.review
    }
    let generation = sourceVerificationGeneration
    let worker = Task.detached(priority: .userInitiated) {
      record.verify(registeredURL: url, resolveBookmark: false)
    }
    let result = await withTaskCancellationHandler(operation: { await worker.value },
      onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard sourceVerificationGeneration == generation else { throw DocumentSaveConflict.changed }
    guard result.status.verified else {
      recoverySourceStatus = result.status
      sourceSaveNeedsReview = true
      throw RecoverySourceConflict.review
    }
  }
  var recoverySourceState: [String: Any] {
    ["status": recoverySourceStatus.rawValue, "isRecovered": isRecoveredSource,
      "hasRecord": recoverySourceRecord != nil,
      "originalFormat": recoverySourceRecord?.format as Any? ?? NSNull()]
  }
}

enum RecoverySourceConflict: LocalizedError {
  case review
  var errorDescription: String? {
    "The recovered document's original could not be verified. Use Save As to review the destination."
  }
}

extension PreparedDocumentOutput {
  func contentDigest() throws -> String {
    switch self {
    case .data(let data): return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    case .file(let file): return try RecoverySourceReader.capture(file.url).sha256
    }
  }
}

extension AutomationService {
  static var recoverySourceSchema: [String: Any] {
    ["type": "object", "additionalProperties": false,
      "required": ["status", "isRecovered", "hasRecord", "originalFormat"],
      "properties": [
        "status": ["type": "string", "enum": RecoverySourceStatus.allCases.map(\.rawValue)],
        "isRecovered": ["type": "boolean"], "hasRecord": ["type": "boolean"],
        "originalFormat": ["type": ["string", "null"],
          "enum": DocumentIO.Format.allCases.map { $0.rawValue as Any } + [NSNull()]],
      ]]
  }
  static var recoverySourceCapabilities: [String: Any] {
    ["contextLimitBytes": NativeArchive.maximumRecoveryContextBytes,
      "verification": "Recovery retains original format, volume/inode/birth identity, size, mtime, SHA-256 and a bookmark when available. Verification runs off the main actor. Save rechecks verified recovered files before AppKit coordination.",
      "states": RecoverySourceStatus.allCases.map(\.rawValue),
      "review": "Changed/replaced/missing/unavailable, legacy or invalid provenance requires Save As. A moved original is rebound only after bookmark and fingerprint verification. Format-specific review remains required.",
      "privacy": "Source paths, hashes and bookmarks remain local to recovery archives; ordinary saves, copies, API downloads and API state omit them. Ordinary Open/uploads ignore embedded provenance.",
      "limitations": "Independent indexed discovery supplements AppKit when originals disappear. See recoveryDiscovery for its state and retry operation. An occupied old path may resolve to its replacement, which verification rejects. No filesystem compare-and-swap guarantee. Sandbox entitlement, network/removable volume and live macOS 14/Intel qualification remain open. Source capture adds bounded sequential file reads.",
      "adobe": "No live-desktop recovery source operation in the pinned Adobe v2 contract."]
  }
}
