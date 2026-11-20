# Layer thumbnails and embedded originals in the Photoshop manifest

## 20 November 2026

Checkpoint 663 added document and layer metadata. This checkpoint implements the optional `includeLayerThumbnails` and `extractSmartObjectData` fields on `POST /v2/generate-manifest`. Both default to false. Adobe's current OpenAPI schema lists JPEG and PNG thumbnail options. The response carries links in each layer's `thumbnail` and in `smartObject.extracted` for eligible embedded objects. [Manifest request](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/manifest-migration) · [Manifest response](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/manifest-response-migration)

Photato renders a solo layer or group using the native renderer and exports a JPEG or PNG with a maximum edge of 256 pixels. Positive `maximumThumbnailDepth` values limit previews by nesting depth. Zero includes all depths. `trimToTransparency` uses occupied pixels in the rendered thumbnail source. Adjustment layers and empty renders use a white preview. The JPEG encoder accepts named quality, standard or optimized baseline and native progressive encoding. Explicit progressive scan counts remain unavailable. Comparing thumbnail geometry, defaults and encoded bytes with Adobe's hosted endpoint remains open.

Extraction serves the original embedded bytes and reuses the same asset URL for matching instances. External Smart Object links stay as locators in the response. Downloads use the existing local bearer-authenticated asset store. Attachments consume the same byte budget as other job outputs, expire after the longest requested hosted manifest lifetime or the one-hour default, and become available only when the job succeeds. Stopping resource jobs revokes existing assets.

## Validation

The new tests cover thumbnail depth, PNG trim geometry, blank adjustments, JPEG output, exact PSB embedded bytes, opt-in and bearer checks, linked source handling, joint storage limits and expiry. The prior RGB32 renderer and PSD output tests remain in the regression selection.

The first Debug run passed 19 of 20 checks. The thumbnail test stopped before submitting its request because the fixture used an Invert adjustment that the PSD writer cannot serialize. The revised fixture uses an editable Levels adjustment supported by the PSD writer. In the second run the thumbnail had the expected dimensions and retained the layer's 60% opacity. The pixel assertion now checks alpha byte 153. The JPEG checks identified baseline and progressive frames, and the extraction test confirmed that two embedded instances share one download.

All 20 focused tests passed on the final Debug candidate. The optimized Apple Silicon suite passed 1,503 tests after one Workflow Guide submenu-highlight test passed in an isolated rerun on the same executable. Eight PSD files exported by the optimized Intel libraries matched the complete files from checkpoint 663 byte for byte.

1,502 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen.

The manifest tests verified PNG crop geometry, thumbnail nesting, blank adjustment previews, JPEG frames, exact PSB Smart Object bytes, shared-instance URLs, authorization, expiry and the combined storage budget.

[Qualification](SOURCE_PUBLICATION_664.md)
