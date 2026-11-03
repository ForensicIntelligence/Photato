# Quick Mask and saved selections

S05 retains its full original scope: editable Quick Mask display/painting, saved alpha selections, Save/Load and combination operations, channel shortcuts. Photoshop2026 is the reference. C01 is queued next and starts after S05 completes and is tested.

The366 increment added Photoshop coverage combinations, persistent Quick Mask defaults, double-click/Option-click toolbar behavior, same-size cross-document alpha Save/Load, asynchronous one-step history and source revision/cancellation guards. The optional `channel.edit` API uses the same native channel engine. API state includes `quickMaskOptions`; `quickMaskOptions` is an action, not a new HTTP route. Cross-document `saveSelection`/`loadSelection` requires `sourceDocumentID` and `sourceRevision` for an explicitly shared source. The request path names the destination. Only that destination receives an undo step.

Owned Photoshop27.2.0 files establish the RGB8 gray combination results, for both loading selections and saving into existing alpha channels. Add is coverage union, Subtract removes incoming coverage, and Intersect multiplies it. At8-bit precision, the shared rounded product is `round(a*b/255)`. These operations differ from the current geometric selection-tool combinations. Changing Quick Mask display options preserves selection coverage.

## Completion checks

- Compile and run the new Core/Imaging/App cases and affected channel/selection/API/persistence tests against a frozen manifest.
- Verify all stored mask samples against the independently parsed owned Photoshop references.
- Check16/32-bit loading/storing and display semantics; qualify any format quantization instead of assuming a native round trip proves Photoshop equality.
- Review all dialog source/destination options, including New Document and applicable layer/channel sources.
- Verify native Q, toolbar options/reversal, alpha/channel shortcuts, painting, overlay, Cancel, one-step Undo/Redo and reopen on a disposable document.
- Verify API state/schema/defaults, equivalent operations, invalid dimensions/revisions, busy interaction, source closure/revocation and cancellation.
- Record both API interface impact. Existing Adobe jobs preserve auxiliary PSD/PSB channels; dedicated mask routes are absent. Unsupported actionJSON operations must remain explicit.
- Record universal build/runtime coverage and retain untested supported-platform, full-product performance and byte-parity gates.

S05 is **in progress**. This document does not close the package or qualify all Photoshop functionality. See `WORKING_CHECKPOINT_369.json` for the current worker and immutable evidence paths.

## Verified checkpoint366

All 15 new cases and all 266 affected optimized tests pass, with 0 failed assertions, 0 unexpected errors and 0 crashes. The 491.43-second optimized build and 34.724-second affected run used 7,065 unchanged frozen inputs and 1,003 production Swift files. The independent reader checks640 Photoshop gray samples and384native target samples (1,152bytes) across six owned16/32-bit outputs. Its initial fixed channel offset was wrong for native files with merged transparency; the failing inspection is retained and the corrected comparison derives the named-plane start from header and names. No native output was changed to satisfy that correction.

S05 is still in progress: finish the remaining Save/Load source/destination cases and live UI qualification before closure. C01 is preselected next. The full current suite, all-input Photoshop output, supported physical Macs and60fps qualification remain open. Installed preview283, private source backup363 and store archive332 are unchanged; no installation, source push, archive, binary upload or release.

## Checkpoint367 — standalone selection documents

Save Selection now offers Document New. The result is an auxiliary-only Multichannel document, matching the observed Photoshop8/16 workflow. It has no image layer or printing plate. Native85 preserves all three depths and sparse maximum-size masks. Standalone8/16 PSD/PSB output supports four compression modes and retained document metadata; the existing Multichannel reader limit is8,388,608pixels. Standalone32-bit and active Quick Mask PSD/PSB output remain unsupported; use the native format.

The optional Photato API uses `channel.edit` with `action: "saveSelection", newDocument: true` and optional `name`. Document-transfer permission is required; success returns201 and a new shared document. Downloading that file requires archive version85. Load Selection accepts strict `source` descriptors, including component, transparency and pixel/vector-mask sources, with existing sourceDocumentID/sourceRevision leases for another shared document. `selectionChannels` state exposes available source descriptors and save/load/new-document/new-alpha availability. These operations share native transactions and leave a New destination's source history untouched. There is no new Adobe route; channel actionJSON descriptors remain unsupported.

All17 new cases and all388 affected optimized tests pass, with0 failed assertions,0 unexpected errors and0 crashes. The run used7,074 unchanged frozen inputs and1,007 production Swift files. Independent checks cover16 owned PSD/PSB outputs with1,024 raw samples/1,536bytes. S05 remains in progress pending native live UI and remaining qualification; C01 is preselected and starts after S05 completes and is tested. The full current suite, all-input Photoshop output, full supported-platform coverage, dense maximum capacity and60fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. No installation, source push, archive, binary upload or release.

**Next complete major function: C01 — Component visibility and edit targeting.** Separate viewing and editing targets; finish grayscale/color display, temporary pixel/vector-mask rows, real painting/filtering targets, eye gestures and factory channel shortcuts. Include native/API state, history/cancel and focused tests. Begin after S05 is complete and tested.

## Checkpoint368 — workflow and architecture checks

All 432 affected optimized tests pass on Apple Silicon and translated Intel, including all 11 new cases on each architecture. There are no failed assertions, unexpected errors or crashes. The runs used 7,084 unchanged frozen inputs and 1,010 production Swift files.

Earlier367Source03 native checks cover Quick Mask painting, Undo/Redo, named alpha and standalone documents, cross-document inverted Load, existing-alpha Add, channel shortcuts, options and reopen. Independent inspection verifies1,920,000 native gray samples. The saved-document alias and composite-transform regression tests pass. The Multichannel Properties repair compiles; its live recheck and the packaged native-operation check were blocked by a locked Mac. The standard RGB8 profile pair matches the independently captured Photoshop digest for every colour; other profile pairs retain separate fidelity checks. The universal package and unsigned Xcode Release resource path are verified.

S05 remains in progress; its current-source live recheck awaits an unlocked Mac. C01 is queued after completion. General profile/CMM fidelity, the full current suite, physical supported-platform coverage, dense maximum capacity and sustained60fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. See [evidence](SELECTION_ACCEPTANCE_REFERENCES_368.json), [profile behaviour](SELECTION_LUMINOSITY.md) and [the next-major plan](NEXT_MAJOR_C01.md).

## Checkpoint369 — Quick Mask visibility

All 454 affected optimized tests pass on Apple Silicon and translated Intel, including all five new Quick Mask visibility cases on each architecture. There are0 failed assertions,0 unexpected errors and0 crashes. All7,085 frozen inputs and1,010 production Swift files remained unchanged.

The eye now controls overlay visibility while retaining Quick Mask mode. Native brush gesture entry and routed/API strokes reject a hidden mask, as observed in Photoshop. Showing the overlay restores painting; Undo removes only the stroke. The current universal369 UI check passes. Earlier368Source02 label/Multichannel/composite checks are recorded separately, including64 colored samples and1,920,000 gray samples from independently inspected UI saves. No pixel-exact brush-kernel claim is made.

S05 remains in progress against its full acceptance criteria; C01 stays queued. Other hidden-target Fill/filter/tool contexts, general profile/CMM fidelity, full current suite, physical supported-platform coverage, dense maximum capacity and sustained60fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. See [visibility guide](QUICK_MASK_VISIBILITY.md) and [current evidence](QUICK_MASK_VISIBILITY_REFERENCES_369.json).
