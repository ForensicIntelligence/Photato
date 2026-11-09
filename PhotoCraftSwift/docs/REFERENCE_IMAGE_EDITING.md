# Reference image use

Build 505 adds an explicit request to edit the chosen reference image. Choose Create with Apple Intelligence, keep New image layer as the destination, choose one reference, then set Use image as to Image to edit. Enter the requested changes and use Generate. The system interface still requires the person's approval. The accepted result is added as a new layer through the existing transaction; the reference file and original document layers are unchanged.

Inspiration remains the default. Its system strategy, document-size hint and existing version-1 reference encoding are unchanged. Editing requires an eligible Apple Silicon Mac running macOS 27 or later and a chosen image. The native popup disables an unavailable edit choice, and action-time validation rejects unsupported or missing inputs. It never converts an edit request into an inspiration request. Model readiness is checked separately: supported configuration is not a claim that a model is ready.

The implementation sets the actual ImagePlaygroundOptions.creationStrategy to editExisting. The captured, orientation-corrected reference preview supplies the closest-size hint for editing. Inspiration/background retains the captured document-size policy, and macOS 26 keeps its existing presentation behavior. Exact output size and model results remain system-controlled. The system UI can replace the input or alter settings; this record describes the initial request, not an attestation of final provider input.

The input remains one still PNG/JPEG/TIFF/HEIC, up to 16 MiB and 64 MP, with a 2,048-side preview. Accepted originals retain their prior 32 MiB/file and 128 MiB/raster-decode bounds and local Generated Results storage. No headless generation, deprecated ImageCreator, new provider, signing entitlement or network service is introduced.

## Optional Photato API

POST /v1/documents/{id}/ai with operation prepare accepts referenceUse equal to inspiration(default) or editExisting for image intent. Editing requires nonnull reference={dataBase64:...}; omitted/null reference is not treated as a saved or implicit input. Unsupported editing returns 422, invalid/irrelevant parameters return 400, and missing transfer/workspace permissions retain 403. Native window, current revision, busy/lifecycle and post-preparation token/share/permission checks remain. Background intent rejects an explicit referenceUse.

Preparation only opens the native workspace sheet; it starts no model. State and job schemas expose referenceUse, and state reports referenceEditingSupported separately from actual image availability. The opaque revision changes with the draft mode. Input preparation cannot publish after that revision or transfer permission changes. Existing cancel, saved-result and original-transfer routes remain.

Reference metadata uses its existing version 1 with optional requestedUse=editExisting. Legacy/default inspiration omits the new field. The native layer/archive and selected-reference API keep the captured mode even when a later draft changes. API role is imageToEdit for that request, with providerAttested=false; default role remains visualInspiration. Reference original bytes are still not embedded; reopening the generated original alone does not restore its input context. Native 92, Actions 60 and 267 typed editing commands are unchanged. No corresponding interactive lifecycle is defined in the pinned Photoshop v2 contract; no Adobe route is invented.

## Remaining scope

This is an explicit reference-editing request, not a Photoshop identity/composition or masked-selection contract. Multiple references, Style/Composition controls, drawn markup, selection-directed edits, variations, exact provider/default/output fidelity, model quality, real generation, live AI-sheet accessibility and supported physical-platform/performance qualification remain required. Full AI05 is open. Core editing remains macOS 14+; unavailable optional AI does not disable ordinary editing.
