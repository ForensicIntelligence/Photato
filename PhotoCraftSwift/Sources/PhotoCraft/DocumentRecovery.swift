import AppKit
import PhotoCraftCore

extension CraftNSDocument {
  var recoveryState: [String: Any] {
    [
      "enabled": (ownerController?.autosavingDelay ?? 0) > 0,
      "intervalSeconds": ownerController?.autosavingDelay ?? 0,
      "hasSnapshot": autosavedContentsFileURL != nil,
      "hasUnautosavedChanges": hasUnautosavedChanges,
      "isWriting": recoveryWriteBusy,
      "lastWriteFailed": lastRecoveryWriteFailed,
    ]
  }

  /// Uses AppKit-managed autosave locations and recovery registration. Explicit Save,
  /// source ownership, dirty state and edit history remain separate.
  func writeRecoverySnapshot() async throws {
    guard canRunFileCommand else { throw DocumentPersistenceConflict.changed }
    fileOperationBusy = true
    recoverySnapshotRequested = true
    defer {
      recoverySnapshotRequested = false
      fileOperationBusy = false
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      autosave(withImplicitCancellability: false) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }
}

extension AutomationService {
  static var recoveryCapabilities: [String: Any] {
    [
      "defaultIntervalSeconds": 600,
      "automatic": true,
      "backgroundWriting": true,
      "snapshotCommand": "document.autosave",
      "storage":
        "Native version11 archives in Photato’s private recovery folder, registered with AppKit and an independent bounded index. Paths are not exposed by this API.",
      "storagePolicy": "See atomicPersistence for staging, synchronization and durability limits.",
      "stateEffect":
        "Captures committed content without committing unfinished fields, replacing the explicit Save source, clearing modified state or adding history.",
      "completion":
        "The request waits for AppKit autosave completion. An unchanged document may be a no-op.",
      "concurrentEditing":
        "AppKit resumes main-thread interaction after capturing an immutable value. Later edits remain unsaved by that snapshot; current state can report hasUnautosavedChanges after success.",
      "fileLifecycle":
        "File commands and API edits reject while writing. Direct document replacement rejects, close waits for the current backup to finish, and automatic backups defer during other file operations.",
      "reopen":
        "AppKit recovery restores committed content, modified state and original format association. Verified unchanged/moved originals can resume Save; other associated recoveries require Save As. See recoverySource.",
      "windowPresentation": "App-owned windows and panels present without transition animations, avoiding animation-worker starvation during repeated background opening on a suspended WindowServer. Editing and recovery share the existing native transactions; physical frame-rate qualification remains separate.",
      "limitations":
        "Complete crash/relaunch and interruption qualification, large-document responsiveness and full Photoshop recovery presentation/preferences remain under qualification.",
      "adobe": "No equivalent live-desktop recovery operation in the pinned Adobe v2 contract.",
    ]
  }
  static var recoveryStateSchema: [String: Any] {
    [
      "type": "object", "additionalProperties": false,
      "required": [
        "enabled", "intervalSeconds", "hasSnapshot", "hasUnautosavedChanges", "isWriting",
        "lastWriteFailed",
      ],
      "properties": [
        "enabled": ["type": "boolean"],
        "intervalSeconds": ["type": "number", "minimum": 0],
        "hasSnapshot": ["type": "boolean"],
        "hasUnautosavedChanges": ["type": "boolean"],
        "isWriting": ["type": "boolean"],
        "lastWriteFailed": ["type": "boolean"],
      ],
    ]
  }
}
