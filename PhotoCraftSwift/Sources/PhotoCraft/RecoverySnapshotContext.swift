import Foundation
import PhotoCraftCore

/// The index and image commit independently. A random token identifies the exact
/// snapshot an index intent may recover, including a crash before finalization.
struct RecoverySnapshotContext: Codable, Sendable {
  var magic = "PhotatoRecovery"
  var version = 2
  let recoveryID: UUID
  let snapshotID: UUID
  let documentID: UUID
  let sourceURL: URL?
  let source: RecoverySourceRecord?

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(self)
    guard data.count <= NativeArchive.maximumRecoveryContextBytes else {
      throw CraftError.invalid("Recovery information exceeds its size limit.")
    }
    return data
  }
  static func decode(_ data: Data?) -> Self? {
    guard let data, data.count <= NativeArchive.maximumRecoveryContextBytes,
      let result = try? JSONDecoder().decode(Self.self, from: data),
      result.magic == "PhotatoRecovery", result.version == 2,
      result.sourceURL.map({ $0.isFileURL && $0.path.utf8.count <= 16_384 }) != false,
      result.source?.isValid != false
    else { return nil }
    return result
  }
}
