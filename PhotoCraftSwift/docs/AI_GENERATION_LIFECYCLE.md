# Generated images and saved originals

Photato captures the initial prompt and source document when opening Apple’s system image-generation interface. Accepting an image prepares a new layer for that captured source. A changed or closed source cannot receive a late result. Each accepted placement adds one Undo step.

The original returned file is saved locally before decoding, conversion or placement. If placement is cancelled, fails, or becomes stale, the original remains available from **Photato > Generated Results…**. The AI sheet also has **Saved Results…**. **Open Original** creates a separate unsaved document without invoking a model. **Move to Trash** removes only the chosen saved original; nothing is purged automatically. Reopening a native Photato document also retains its generated-layer record and original file independently of the model.

The record includes the initial prompt, request and source IDs, times, selected style when returned, and original MIME type, byte count and SHA-256. The system delegate has no typed model, seed or final edited-prompt fields. Those fields remain unknown. Original file metadata is preserved but has not been interpreted or independently qualified. The recorded processing route describes the platform policy; it is not provider attestation.

Generation uses the interactive system UI. macOS26 supports the documented on-device route on eligible Apple Silicon systems; macOS27 uses Apple Private Cloud Compute. Availability remains subject to Apple’s system settings and service checks. Photato does not silently substitute another cloud provider. Text prompt refinement has its own on-device capability gate.

The selected placement workflow supports still RGB8/16/32 documents. Originals are limited to 32 MiB; published inbox entries are limited to 512 MiB and 256 items. It reserves space for the largest accepted result before presenting generation. Storage failure leaves the native request unacknowledged so it can report the problem and permit a retry. Actual system-sheet retry behavior still needs live qualification. Corrupt entries stay visible with an error rather than hiding other originals. Abrupt process/power-loss recovery and orphaned staging-file accounting remain unqualified; injected write failures do not prove those cases. Ordinary non-native Save rejects losing the generated record/original; Save a Copy or an explicit API download produces derived output.

## Optional API

The API uses the same native job and document engine. State reports hardware availability, native canStart eligibility, request IDs, phase, selected provenance and session-authorized saved-result IDs. These IDs are authorized by the actual document session; importing a document with the same UUID does not grant access to the private inbox. There is no global inbox listing API.

| Request | Behavior |
| --- | --- |
| `GET /v1/documents/{id}/ai` | State and current revision |
| `POST /v1/documents/{id}/ai` | Strict `prepare`, `cancel`, `openSaved` or `trashSaved` operation |
| `GET /v1/documents/{id}/ai/records/{layerID}` | Generated-layer record |
| `GET /v1/documents/{id}/ai/results/{layerID}` | Retained original from a generated layer |
| `GET /v1/documents/{id}/ai/saved-records/{resultID}` | Record for an authorized saved result |
| `GET /v1/documents/{id}/ai/saved-results/{resultID}` | Original for an authorized saved result |

Control requests require `operation` and the current `revision`, plus `prompt` for prepare, `requestID` for cancel, or `resultID` for saved-result operations. No extra fields are accepted. Prepare requires workspace-panel permission and an existing desktop window; it only opens the native prompt sheet. A human starts and approves generation in the system UI. Cancel accepts the current image request or reported prompt-refinement ID.

Original downloads and openSaved require document-transfer permission. openSaved checks document/lifecycle/share capacity, returns201, and registers a fresh unsaved shared document without modifying the source. trashSaved requires local-saving permission and an idle document. Reads recheck service/token generation, sharing, source revision, permissions and file identity after background work. Optional `X-Photato-Revision` guards downloads.

These are Photato desktop operations. The pinned Firefly v2 contract has no matching interactive system-sheet lifecycle endpoint; no Adobe route or proprietary model equivalence is invented. Firefly compatibility also does not host Photoshop plugins. Third-party plugin compatibility remains the separate AUT03 audit.

## Qualification and remaining work

All 67 selected optimized methods pass on Apple Silicon and translated Intel, including 30 new methods. Owned PNGs and controlled asynchronous gates cover stale/cancel/close/duplicate callbacks, failed preparation/storage, atomic publication, corruption/quotas/symlinks, original bytes, native archive recovery, history and API permissions/session ownership. All nine existing menu and nine cursor methods, plus seven independent RGB32 regressions, pass in the same batches. No model is invoked.

Debug source11 passes 67 focused methods. Earlier Debug batches crashed and remain unresolved. Native live interaction, provider output/metadata, physical supported platforms, performance, exact Photoshop behavior, full suite and the complete AI07 scope remain open. See [evidence](AI_GENERATION_LIFECYCLE_475.json).
