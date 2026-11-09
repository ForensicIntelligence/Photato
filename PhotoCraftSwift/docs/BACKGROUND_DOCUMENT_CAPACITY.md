# Background generation and document size

Build 504 separates document geometry from the system model's visual-reference size. The native Background below subject destination and the existing optional Photato AI interface now admit the application's document geometry, up to 300,000 pixels per side. The 90-gigapixel logical bound is not a claim that dense output at that size fits a particular Mac, scratch disk or processing time.

The selected foreground still requires a visible root pixel layer with an enabled mask. Groups, clipping context, Smart Objects and projective sources retain their separate restrictions. Original layers, masks, selections and canvas dimensions are retained; the accepted generated background is placed below the captured subject by the existing prepared command, with one Undo. The generated original and descriptive provenance remain available offline.

For newly admitted large documents, an isolated paged compositor evaluates the subject and its mask before area reduction to at most 2,048 pixels per side and 4,194,304 reference pixels. The dominant dimension is set exactly, avoiding a floating-point floor to 2,047. Profile conversion and display packing follow reduction. Existing mask/transform/kernel resource validation still applies. The old admitted small-document reference math is unchanged. Output placement uses the existing aspect-cover geometry renderer and its bounded-patch/paged output path; it does not substitute a low-resolution editing document. Large dense output still requires real time and storage.

The model's accepted original remains limited to 32 MiB, with a 128 MiB raster-decode budget. These are provider-result input limits, separate from document dimensions. No new model, cloud provider, entitlement, network endpoint, menu, shortcut or modifier action is introduced. Actual model generation, outpainting, variants, output/default/quality fidelity and platform/performance qualification remain required.

## Optional API

POST /v1/documents/{id}/ai with operation prepare and intent background uses the same new eligibility, reference preparation, native approval and history as the desktop. Existing workspace-panel permission, native-window, revision, busy and lifecycle guards remain. Preparation opens the native sheet; it does not run a headless model. Background capability metadata now reports document, reference and composition-patch limits separately. Placement-record schema dimensions admit 300,000 while retaining the descriptive version-1 format. GET state and original-result transfer retain the existing routes and authorization.

This desktop lifecycle has no matching operation in the pinned Photoshop v2 contract, so no Adobe route is invented. Existing typed command count 267, native format 92 and Actions format 60 are unchanged.

## Verification

All 56 focused Debug methods pass on 7,724 frozen Source03 inputs, including eight new methods. They cover long sides, above-eight-megapixel references, maximum logical reference/record geometry, exact current-layer mask sampling, all RGB depths, source retention, one Undo/Redo, native archive reopen, real HTTP state/schema/approval/original transfer, cancellation/source replacement and invalid geometry. The unchanged owned Photoshop RGB32 merged-plane reference still passes. A separate Python reader verifies all 8,192 bytes of the new literal reference capture.

The native sandboxed app opens the owned 4,097 by 2,049 RGB/16 masked document with the correct title and mask controls. An attempt to open the AI sheet closes the CUA connection; whether the sheet appeared is unverified. Screenshot and reset/rebind also fail. The app remains alive in an AppKit event loop and is preserved. Full AI-sheet interaction, real generation and normal Quit are not qualified. Optimized/universal and physical-platform verification for build 504 are pending a later batch. Full AI04 and overall Photoshop parity remain open.
