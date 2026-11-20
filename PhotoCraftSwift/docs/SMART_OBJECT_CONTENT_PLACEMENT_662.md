# Fit replacement artwork inside an existing Smart Object

## 20 November 2026

Adobe documents an embedded Smart Object replacement that fits or fills its existing frame. The frame keeps its position and dimensions. The new artwork remains a nested Smart Object, including the parts hidden by a fill crop. Alignment defaults to the frame's top-left corner. The installed Photoshop 2026 bundle reports version 27.2.0. The read-only AppleEvent request timed out, and a separate macOS Accessibility probe could see the process but could not query its windows. The disposable PSD comparison stayed local to Photato. [Adobe workflow](https://developer.adobe.com/firefly-services/docs/photoshop/guides/workflows/smart_object/) · [Public API schema](https://github.com/AdobeDocs/ffs-photoshop-API/blob/main/static/photoshopv2-api.json)

The earlier Photato job could scale replacement source dimensions or apply a document-space transform to the outer layer. It had no operation to retain the replacement within the old frame. `SmartObjectContentPlacement.swift` builds a nested, editable source using the original frame's pixel dimensions and resolution. The frame uses the destination document's RGB working profile and depth. The renderer clips to the child canvas. Its single layer retains the full ingredient and its independent transform. PSD and PSB export use the existing embedded source writer. The regular Replace Smart Object command commits the result, preserving the outer layer coordinates and mask placement. `Frames.swift` supplies the same fit and fill scale calculation as the native Frame tool. `SmartObject.swift` skips mask-coordinate recalculation when replacement keeps the existing transform.

`AdobeSmartObjectEdit.swift` accepts `smartObject.contentPlacement` on existing embedded objects. The request can pass a JPEG, PNG, TIFF, PSD or PSB as the ingredient. The Photato API accepts `contentPlacement` on `smartObject.replace` for a shared source document and still honors its source revision and instance scope. `SmartObjectContentPlacementAPI.swift`, `AutomationCommands.swift`, `AutomationSmartObjects.swift` and `AutomationService.swift` supply parsing, command details and discovery. The old replace behavior continues when callers omit the field. Both APIs reject combinations with options that resize the outer frame. Linked, skewed, projected, warped and pixel-masked rotated frames are outside the corresponding Adobe contract.

## Validation

`SmartObjectContentPlacementTests.swift` exercises corner and center alignment, cropping, retained source bytes, unmodified outer geometry, editable native and PSD/PSB round trips, documented request conflicts, and the two authenticated local HTTP entry points. The Photato case checks source revisions, replacement of multiple instances, editable masks and one Undo. The Adobe-facing case uses a controlled transport for generated fixture bytes. Independent Adobe output remains to be measured.

The first Debug run passed three of five cases. The two clipping checks used an opaque parent background, so the composite was fully opaque even where the Smart Object contributed nothing. The second source clears the parent background so the tests measure transparency at the frame edge. It also checks that JPEG, TIFF and PSD ingredients retain their exact original bytes and confirms capability discovery. Six new cases and all five existing Frame tool cases passed in Debug. The first source and test log are retained. Broader regressions and both optimized builds are running. A separate owned fixture uses a 36 × 24 frame at (16, 12) and a right-aligned 2× fill. The exported PSD reopens with the same frame and the full PNG. The verified local composite has transparent pixels immediately outside the frame.

## Source publication

The first staged secret scan matched the field holding the public Adobe contract's SHA-256. The digest was verified against the downloaded specification and kept under an explicit checksum field. The failed scan was retained for the publication record.

## Template inspection

The Adobe workflow follows composition with `POST /v2/generate-manifest` so a client can inspect the template before editing it again. Photato already renders an artboard manifest, but it has no dedicated equivalent route for reading a composite job's output. The next API step is the published document inspection request and job result, including stable layer identifiers and editable Smart Object, blend and mask metadata. Optional thumbnails, XMP and extracted artwork carry separate output requirements. [Adobe manifest contract](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/manifest-migration)

All 1,493 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

Both authenticated local HTTP routes exercised frame-contained replacement. The native, PSD and PSB round trips kept the nested asset and the rotation of the enclosing frame. The tests retained exact source asset bytes and verified local composite bytes, transparent clipping, editable masks and one Undo for the Photato command.

[Qualification](SOURCE_PUBLICATION_662.md)
