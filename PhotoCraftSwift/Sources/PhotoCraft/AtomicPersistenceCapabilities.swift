import Foundation
import PhotoCraftCore

extension AutomationService {
  static var atomicPersistenceCapabilities: [String: Any] {
    [
      "scope": "Native recovery, recovery preferences and local Save/Save As/Save a Copy output.",
      "publication":
        "Private sibling staging followed by relative atomic rename in the retained parent directory. Destination and parent identity are checked before publication.",
      "synchronization":
        "fsync followed by F_FULLFSYNC before publication; unsupported F_FULLFSYNC falls back to the successful fsync. Actual I/O and space errors reject publication.",
      "unsupportedFullSyncErrors": ["EINVAL", "ENOTSUP", "ENOSYS"],
      "visibility": [
        "newFileHiddenFlag": false,
        "preservesExistingHiddenFlag": true,
        "preservesOtherStagingFlags": true,
        "policy":
          "Normalize UF_HIDDEN on the retained staging descriptor before synchronization; validate it before publication. Dot-prefixed destination names retain their normal filename visibility.",
      ] as [String: Any],
      "maximumWriteBytes": AtomicFileWriter.chunkBytes,
      "cleanup":
        "Failed or cancelled staging checks the temporary inode before unlinking through the retained directory descriptor. An observed replacement at that name is preserved.",
      "errors":
        "Existing save/recovery error envelopes remain unchanged. Failed preparation or pre-publication writes leave the existing destination and document state intact.",
      "limits":
        "No parent-directory persistence, hardware power-loss, network-filesystem or complete external-file coordination guarantee. Identity checks do not provide a filesystem compare-and-swap; external metadata changes after validation are not prevented.",
    ]
  }
}
