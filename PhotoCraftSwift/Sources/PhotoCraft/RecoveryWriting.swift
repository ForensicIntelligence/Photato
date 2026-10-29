import AppKit
import PhotoCraftCore

typealias RecoveryEncoder = @Sendable (CraftDocument, URL, Data?) throws -> Void

enum NativeRecoveryWriting {
  static func isRecovery(_ operation: NSDocument.SaveOperationType) -> Bool {
    ![.saveOperation, .saveAsOperation, .saveToOperation].contains(operation)
  }
  static func write(_ document: CraftDocument, to url: URL, context: Data?) throws {
    try NativeArchive.writeRecovery(document, context: context, to: url)
  }
}

/// The main actor captures the value before AppKit blocks it. The file writer
/// must never dispatch back to that actor before calling unblockUserInteraction.
final class RecoveryWriteState: @unchecked Sendable {
  struct Snapshot: Sendable {
    let id: UUID
    let document: CraftDocument
    let encode: RecoveryEncoder
    let context: Data?
  }
  private let lock = NSLock()
  private var snapshot: Snapshot?

  func begin(_ document: CraftDocument, context: Data?, encoder: @escaping RecoveryEncoder) -> UUID {
    lock.lock()
    defer { lock.unlock() }
    precondition(snapshot == nil)
    let id = UUID()
    snapshot = Snapshot(id: id, document: document, encode: encoder, context: context)
    return id
  }
  func current() -> Snapshot? {
    lock.lock()
    defer { lock.unlock() }
    return snapshot
  }
  func finish(_ id: UUID) {
    lock.lock()
    defer { lock.unlock() }
    if snapshot?.id == id { snapshot = nil }
  }
}
