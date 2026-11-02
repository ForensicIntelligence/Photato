# Duplicate Image

Image > Duplicate… opens Duplicate Image with the source name, an editable As field, Duplicate Merged Layers Only, OK and Cancel. It creates a new active unsaved document. The original document, save association and history are unchanged. The copy has a fresh document identity and independent native history, save, close and recovery lifecycle. Undo in the copy applies to subsequent edits; it does not delete the new document.

The all-layer path copies the whole modeled document. It preserves layers and local IDs, masks, saved channels, selection, guides, paths, profiles, resolution, comps, variables, patterns, metadata and temporal data. Keeping local IDs preserves references inside the new document. Value storage shares immutable backing until editing requires a copy. Embedded editing uses the new parent NSDocument; no existing child edit link is transferred. External linked artwork still refers to the same external source; this is not an Embed All command. Source authorizations and exact Photoshop handling of every specialized context still need independent workflow qualification.

Merged static RGB duplication uses the full visible canvas and ignores selection while rendering; it retains the selection in the copy. It bakes the editable stack to a single layer at document precision. Transparency is retained, unlike Flatten Image's white paper composition. Hidden layers are excluded. Visible Background identity is retained when applicable. Native component, palette/ink and temporal documents can be copied with all layers; their merged option remains unavailable until numerical/plate/frame composition is supported. The application does not silently substitute an RGB preview.

Preparation runs away from the main actor. The source busy flag clears before presenting the copy. If its native sheet is still attached, presentation waits for the sheet-end callback; closing the queued copy removes that request. The copy becomes the active tab when the sheet detaches. Cancellation, changed source/session, closed documents and changed lifecycle generations prevent publication. Native modal guards block conflicting edits; API transfer permission, authorization, revision, shared-document and transfer-generation checks apply to publication. Logical maximum dimensions are not replaced by a new megapixel limit; the API's existing memory and eight-shared-document budgets still apply.

## APIs

Photato command document.duplicate accepts optional name and merged (Boolean, default false), requires document transfers and the source revision, and returns 201 with a new shared-document state. A denied transfer returns 403; invalid input 400, unavailable composition 422, busy/stale/cancelled/revoked 409, and existing transfer/sharing/resource limits remain. State exposes documentDuplicate availability, dialogOpen, mergedAvailable and mergedUnavailableReason. Capabilities and parameter/result documentation distinguish new-document creation from an edit to the source. There are 237 typed Photato commands; native 84 and Actions 43 are unchanged.

Adobe's public desktop UXP Document.duplicate(name?,mergeLayersOnly?) documents the reference operation. It is not a Firefly HTTP endpoint. The pinned Firefly contract has no dedicated document-duplication route; no route is invented and the duplicate is not mapped to white Flatten Image. Multi-document recorded Actions and generic action descriptor execution remain open. Both supported API interfaces and their actual coverage remain documented independently.

## Verification

All 15 new cases pass. Of 233 affected optimized cases, 233 pass; 0 fail with 0 assertions and 0 unexpected errors. There are 0 crashes. Independent analytical/PNG readers verify 48 RGBA bytes across three document depths.

Merged native component, palette/ink and temporal composition, multi-document Actions, exact Photoshop output/defaults/live UI, supported Macs, full current suite, dense maximum capacity and physical 60fps remain open. All 104 complete package scopes remain open. Rust comparisons do not determine Photoshop acceptance.

The cases use owned artwork, offscreen native document controls and real loopback HTTP. They cover whole-document state, native component planes, exact retained floating samples, sparse 300,000 × 300,000 copy/merged output, independent save/history, Cancel/stale source and in-flight cancellation/revocation. They do not establish live Photoshop equivalence. Installed283/private source backup298/store archive332 remain unchanged; no installation, source push, archive, upload or release.

[Adobe desktop help](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/import-files/open-and-import-files-in-photoshop.html) · [Adobe UXP Document](https://developer.adobe.com/photoshop/uxp/2022/ps-reference/classes/document) · [Evidence](DOCUMENT_DUPLICATE_REFERENCES.json)
