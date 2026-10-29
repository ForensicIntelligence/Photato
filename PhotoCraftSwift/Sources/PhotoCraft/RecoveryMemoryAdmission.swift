import AppKit
import PhotoCraftCore

enum RecoveryMemoryFailure: LocalizedError {
  case workspaceChanged
  var errorDescription: String? {
    "The workspace changed while checking recovery capacity. Existing backups are preserved; retry recovery."
  }
}

struct RecoveryReadAllowance: Sendable {
  let rasterBytes: Int
  let metadataBytes: Int
  static let unrestricted = Self(rasterBytes: 1_073_741_824, metadataBytes: NativeArchive.maximumBytes)
}

struct RecoveryMemoryUsage: Sendable {
  let limitBytes: Int
  let estimatedUsedBytes: Int
  var availableBytes: Int { max(0, limitBytes - min(limitBytes, estimatedUsedBytes)) }
  var metadataReadLimitBytes: Int { min(64 * 1024 * 1024, availableBytes / 4) }
}

enum RecoveryMemoryPolicy {
  static let defaultLimit = limit(physicalMemory: ProcessInfo.processInfo.physicalMemory)
  static func limit(physicalMemory: UInt64) -> Int {
    Int(min(4 * 1024 * 1024 * 1024, max(256 * 1024 * 1024, physicalMemory / 4)))
  }
  static func add(_ values: Int...) -> Int {
    values.reduce(0) { result, value in
      let next = result.addingReportingOverflow(max(0, value))
      return next.overflow ? Int.max : next.partialValue
    }
  }
  /// Two Float32 RGBA canvases and two 8-bit display buffers, rounded to tile
  /// edges. This is an admission allowance, not an RSS/GPU allocation measurement.
  static func renderAllowance(width: Int, height: Int) -> Int {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= Surface.maxPixels / height else { return Int.max }
    let w = ((width + Surface.tileSide - 1) / Surface.tileSide) * Surface.tileSide
    let h = ((height + Surface.tileSide - 1) / Surface.tileSide) * Surface.tileSide
    return w * h * 40
  }
  static func documentCost(_ document: CraftDocument, actualRenderBytes: Int = 0) -> Int {
    add(document.estimatedBytes, 65_536, document.layers.count * 4096,
      (document.paths?.count ?? 0) * 1024, (document.patterns?.count ?? 0) * 1024,
      max(actualRenderBytes, renderAllowance(width: document.width, height: document.height)))
  }
  static func allowance(_ metadata: NativeArchive.RecoveryMetadata,
    usage: RecoveryMemoryUsage) -> RecoveryReadAllowance?
  {
    let reserve = add(metadata.manifestBytes * 4, 65_536,
      renderAllowance(width: metadata.width, height: metadata.height))
    guard reserve <= usage.availableBytes else { return nil }
    return .init(rasterBytes: min(1_073_741_824, usage.availableBytes - reserve),
      metadataBytes: usage.metadataReadLimitBytes)
  }
}

/// Session values retain COW backing only while the worker accounts for them.
/// No AppKit or EditorStore objects cross the actor boundary.
struct RecoveryMemoryInput: Sendable {
  let session: EditorSession
  let actualRenderBytes: Int
  var estimatedBytes: Int {
    RecoveryMemoryPolicy.add(
      RecoveryMemoryPolicy.documentCost(session.document, actualRenderBytes: actualRenderBytes),
      session.residentHistoryBytes)
  }
  static func used(_ values: [Self]) throws -> Int {
    var total = 0
    for value in values {
      try Task.checkCancellation()
      total = RecoveryMemoryPolicy.add(total, value.estimatedBytes)
    }
    try Task.checkCancellation()
    return total
  }
}

@MainActor extension CraftDocumentController {
  var recoveryMemorySignature: [String] {
    documents.compactMap { document in
      guard let doc = document as? CraftNSDocument else { return nil }
      return "\(ObjectIdentifier(doc)):\(doc.store.sessionGeneration):\(doc.store.channelCompositeRevision)"
    }
  }
  var recoveryMemoryInputs: [RecoveryMemoryInput] {
    documents.compactMap { document in
      guard let doc = document as? CraftNSDocument else { return nil }
      let store = doc.store
      let image = store.image.map { $0.bytesPerRow * $0.height } ?? 0
      let mask = store.maskViewImage.map { $0.bytesPerRow * $0.height } ?? 0
      return .init(session: store.session,
        actualRenderBytes: RecoveryMemoryPolicy.add(store.surface?.allocatedBytes ?? 0, image, mask))
    }
  }
}
