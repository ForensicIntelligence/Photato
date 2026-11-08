import Foundation
import PhotoCraftCore

extension AutomationService {
  static var atomicPersistenceCapabilities: [String: Any] {
    [
      "scope": "Native recovery, recovery preferences and local Save/Save As/Save a Copy output.",
      "publication":
        "Private sibling staging followed by relative atomic rename in the retained parent directory. Destination and parent identity are checked before publication.",
      "synchronization":
        "Staged-file fsync followed by F_FULLFSYNC before publication; unsupported F_FULLFSYNC falls back to the successful file fsync. After relative rename, fsync the same retained directory descriptor before confirming this writer's commit. Actual pre-publication I/O and space errors reject publication.",
      "unsupportedFullSyncErrors": ["EINVAL", "ENOTSUP", "ENOSYS"],
      "directorySynchronization": [
        "required": true, "phase": "after-relative-rename", "descriptor": "Retained O_SEARCH directory; no listing permission or path reopening required.",
        "interruptions": "EINTR retries after publication, including when cancellation arrives; other errors fail confirmation without silently falling back.",
      ] as [String: Any],
      "postPublicationFailure": [
        "domain": AtomicFileWriter.PublicationFailure.errorDomain,
        "code": "Underlying POSIX errno", "filePublished": true,
        "behavior": "The writer retains its published destination and reports an explicit localized persistence error. It does not roll back or claim the old version is unchanged. Existing save/recovery error envelopes carry the message; failed completion must not be treated as confirmed persistence.",
        "scope": "Publication describes this writer's target. Enclosing NSDocument, batch or export coordination may have its own staging and final publication.",
        "preferences": "Failed settings/history writes retain the confirmed in-memory values, revisions and timer. If published settings differ from their recorded disk baseline, later updates reject as externally changed; restart explicitly reloads the file. A failure does not promise old disk bytes.",
      ] as [String: Any],
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
        "Directory synchronization covers this writer's own rename. No unconditional hardware power-loss, network-filesystem, enclosing NSDocument publication or complete external-file coordination guarantee. Identity checks do not provide a filesystem compare-and-swap; external metadata changes after validation are not prevented.",
    ]
  }
}
