# Camera and lens defaults

Lens Correction can save a default for the current image's camera make, camera model, lens model, focal length and aperture. Open **Filter > Lens Correction**, adjust the correction, then choose **Settings > Set Lens Default**. A new Lens Correction draft on an exact metadata match loads that default automatically. **Lens Default**, **Previous Conversion** and **Default Correction** load settings into the draft and participate in its local Undo/Redo. **Remove Saved Lens Default** retires the saved record without changing image pixels.

Saving a default is an application preference change. It neither commits the draft nor changes the document's Undo history or dirty state. Cancel discards the image correction and retains an explicitly saved default. Previous Conversion changes only when a Lens Correction successfully publishes; preview, cancellation, failure, stale requests and document Undo/Redo do not replace it. Explicit API, Last Filter, Actions and existing Smart Filter settings stay self-contained and do not acquire a later default.

The identity comes from retained ImageIO EXIF, supported PSD EXIF resources or XMP. All five fields must be present and valid. Names use Unicode canonical normalization; matching is case-sensitive and focal length/aperture must match exactly. There is no focal-length interpolation or use of camera serial numbers or GPS. This is a library of user corrections, not a calibrated manufacturer lens-profile database.

Normal app startup shares persistent libraries across document windows. Isolated test sessions and detached stores use independent memory snapshots. Each default is a versioned atomic JSON file, bounded to 32 KiB, in the application's `Photato/LensDefaults` Application Support directory; a 64-record memory cache does not limit the number of saved lenses. Corrupt files are preserved. Removing a default moves it to `Retired` before reuse. A failed save retains the previous default and the document. A Previous Conversion write failure leaves its current-session settings available and reports a warning without blocking editing.

## API

The optional native API exposes `lensCorrection.defaults` with `identity`, `settings`, `previousConversion`, `hasSavedDefault`, `canSetDefault` and separate metadata/default/previous-conversion warnings. Its schemas and capability description are discoverable through the existing API.

Send **`filter.lens.defaults`** through the existing document-command endpoint with a current revision. The native API's preference-change permission must be enabled. For example:

```json
{
  "command": "filter.lens.defaults",
  "revision": "<current revision>",
  "parameters": {
    "operation": "set",
    "settings": {"distortion": 23}
  }
}
```

Omitted settings fields take the existing Lens Correction settings defaults. To remove, supply only `{"operation":"remove"}`. Both operations require complete capture metadata and an idle shared document. Authentication, sharing revocation, busy state and stale revisions retain their existing guards. Preference changes invalidate revisions across controller documents without altering pixels or history. Read the resolved settings from state and pass them explicitly to **`filter.apply`** to edit through the same engine, Smart Filter, Actions and document Undo path as the desktop.

There is no corresponding dedicated operation in the pinned Adobe Photoshop v2 contract. Lens Correction `actionJSON` remains unsupported; no Adobe endpoint or descriptor is invented. Current discovery has 259 typed commands. Native document version 87 and maximum Actions version 53 are unchanged.

## Validation and limits

Checkpoint 452's focused Debug run passes all 33 methods, including 13 new metadata/default/startup tests and the 11 last-mesh tests from checkpoint 450. Actual sandboxed native testing verifies Set Lens Default, Cancel, normal quit/relaunch, automatic restoration, committed Previous Conversion persistence and document Undo while retaining the original owned TIFF. The same 33 methods pass optimized Apple Silicon and Intel under Rosetta. The universal package verifies both macOS 14 deployment targets, full production sandbox entitlements, signature and exact extracted ZIP contents. A fresh native optimized launch confirms the saved default and Previous Conversion are restored. These are focused checks, not a full-suite or physical Intel/macOS 14 qualification. See [the checkpoint evidence](LENS_DEFAULTS_452.json).

The native restart test exposed a real startup wiring defect: checkpoint 450 tested the convenience initializer, while the executable used a designated initializer that omitted persistent filter libraries. Checkpoint 452 makes actual startup use a tested factory and injects both libraries. Earlier 450 tests remain valid for their tested paths; they did not establish persistence in the executable. Normal launches and isolated sessions now have explicit regression coverage.

Exact Photoshop saved-field subsets, matching/interpolation/default/session policy, manufacturer profiles, Adobe preset interchange, wider EXIF/XMP transport and numerical output remain unqualified. Photoshop's normal interface recognized the owned camera, focal length and aperture, but its Custom/Settings behavior was not fully qualified. Existing mode, depth and filter capacity restrictions remain. This increment does not close the full perspective/lens workspace package or establish Photoshop parity. No tool, modifier action, global shortcut or cursor behavior changes.
