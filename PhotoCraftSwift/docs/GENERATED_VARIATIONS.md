# Generated-image variations

Select an unlocked generated image layer. Properties shows its prompt and Generate… control. In the AI sheet, choose the selected layer as the result destination to append an accepted image as another variation. New layer remains the default. Background generation retains its separate workflow.

Properties shows saved alternatives as thumbnails. Select one to change the visible result, or use its trash control to delete it. Selection and deletion share native Undo/Redo. A Photato archive retains the alternatives, original returned bytes, descriptive records and the selected result. These controls work offline without an available model. Generate still needs a supported, available provider and native approval; preparing the sheet never starts a model.

The first append preserves the existing edited working raster and original bytes inside an ordinary embedded native Smart Object. Each alternative is a source layer with a visibility-only Layer Comp. Parent transform, mask, warp, styles and filters continue through the existing Smart Object pipeline. Appending or deleting assigns a new source identity to that instance, leaving other duplicates unchanged. A source-hash-bound descriptive PtGV index references the originals and comps. New images use the existing colour conversion and bicubic cover placement to fit the initial rectangle. No provider model, seed, final prompt or attestation is invented.

## Optional API

GET /v1/documents/{id}/ai reports variationTargetLayerID and selectedVariations. The latter is null or contains layerID, selectedCompID and entries with compID, requestID, initialPrompt and originalSHA256. Existing record/original-download routes resolve the selected alternative, with transfer permission and integrity/revision checks.

POST /v1/documents/{id}/ai accepts prepare with the current revision, prompt and optional targetLayerID. The target must be the active unlocked generated image layer; omitted or null means a new layer. Preparation requires the existing workspace permissions and a native document window. Every model request still requires native approval. The immutable job captures its destination; stale/cancelled callbacks cannot edit a changed document, and accepted originals still enter the saved-result inbox before placement.

Use the existing typed smartObject.layerComp command and a reported compID to select an alternative through the shared native history path. To remove one, POST the AI operation deleteVariation with revision, layerID and variationID, where variationID is the reported compID. Invalid, busy, stale and permission checks remain enforced. No new Adobe-compatible variation endpoint is claimed: the pinned Firefly v2 resource-job contract has no corresponding interactive system-result layer operation. Both existing API interfaces remain supported independently.

## Limits and evidence

Save as Photato to retain editable alternatives. Ordinary non-native Save detects variation-data loss; derived copies/downloads retain their existing contract. Native PSD generative-layer interchange remains unsupported. Edit Contents or Replace Contents can invalidate the bound index and fall back to ordinary Smart Object controls; Rasterize discards alternatives. Deleting the final variation uses normal layer deletion and retains its keep-at-least-one-layer guard. Existing 64 MiB encoded-source, 256 MiB owned-content and Layer Comp limits apply.

Generate… is not Generate Similar conditioning. Enhance Detail, voting/favourites, broader source edits, real provider output, exact defaults/output and supported physical-platform/performance qualification remain open. Native format 92, Actions 60 and 271 typed commands are unchanged. No new menu, shortcut or tool-modifier action is added.

[Build 517 evidence](GENERATED_VARIATIONS_517.json) records54 selected tests and 9 new tests passing in Debug, optimized Apple Silicon and translated Intel. Native UI checks used owned synthetic coloured results, with no actual model request. They verify selection/deletion/history and separate native save/reopen, not Photoshop/provider output equality. Full AI07 and earlier failures remain open.
