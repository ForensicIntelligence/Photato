# Smart Object geometry in template jobs

## 20 November 2026

The local Firefly-compatible `POST /v2/create-composite` endpoint supported Smart Object sources with None, Fit and Fill geometry. It rejected Custom and could insert new artwork only at the root top. These gaps prevented common template jobs from placing artwork at precise dimensions, changing the transform of an existing linked object or adding artwork into a named template group.

The checked-in `Transform`, `Dimension`, `Offset`, `Skew`, `Anchor` and Smart Object add and edit schemas match Adobe's current published versions. The schemas specify integer offsets, pixel and point sizing, rotation in degrees, skew, an anchor and per-axis alignment. The installed Photoshop 2026 application timed out on a read-only version and document-count query. No documents were opened or modified in Photoshop. [Adobe OpenAPI](https://github.com/AdobeDocs/ffs-photoshop-API/blob/main/static/photoshopv2-api.json) · [Smart Object workflow](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/layer-operations-smart-objects)

## Implementation

- `AdobeSmartObjectEdit.swift` routes transform-only edits by layer name or PSD ID without requiring a replacement file. Adds accept top, bottom, above, below and into placement. Relative placement resolves the reference against the current job, so a later edit can refer to a layer created earlier in the same request.
- `AdobeSmartObjectTransform.swift` parses Custom geometry and computes a document-space transform for the existing native layer command. It supports explicit width and height, resolution conversion for points, rotation, two-axis skew, pivot and canvas alignment. An explicit offset takes precedence over alignment on that axis. The local adapter uses the center pivot when omitted and keeps the previous pivot position on axes without an explicit offset during an edit.
- The existing layer transform tracks Smart Object geometry separately from the source, preserving original artwork and using the shared editable-mask and filter behavior. Photato's existing `layer.transform` continues to take an affine delta.
- Malformed numbers, undefined shears and degenerate transforms fail. A zero dimension cannot produce an editable affine transform in the local engine.

## Validation

Five new tests in `SmartObjectWorkflowTests.swift` cover rotated PSD output against a pixel-by-pixel expectation, linked geometry-only edits, point sizing, two-axis skew around a pivot, template insertion in request order and malformed requests. The build is 658. Full hosted Adobe behavior for defaults, transform composition, validation and exact pixels needs independent comparison.

The first Debug build stopped because Swift rejected an initializer closure that captured a property before initialization. The second source uses a local set of allowed keys. It also anchors partial edits using the existing translation and the difference between the two linear transforms, which keeps an unchanged axis from drifting through addition and subtraction of the same coordinates. The first source and its build log were retained.

Four of the five targeted tests passed on the second source. The failing case exposed two coordinate systems after a linked PSD reopens. The layer transform positions its baked raster cache, while the Smart Object transform positions the original source. The third source computes the command from the original source transform and applies the resulting delta to the cached layer through the native engine. The regression checks the actual Smart Object transform on disk and also exercises Fit after the rotation. The initial assertion and failing run were retained.

Swift required an explicit `try` for inverting the source transform. The fourth source includes that correction. The two superseded optimized builds were stopped after the Debug diagnostic identified the same source error.

The source audit found the same distinction in the native Properties rotation readout and the Photato document state's transform matrix. They still expose the cache transform when only a linked file's preview is available. Those readouts need separate desktop and Photato API checks. The Adobe manifest already reads the original artwork transform.

All 1,468 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen.

The local HTTP tests matched all 320 RGBA bytes of an independently calculated quarter-turn fixture after PSD reopen. They also checked exact embedded source bytes and a linked PSD's source metadata and geometry through rotation and Fit in separate jobs.

[Qualification](SOURCE_PUBLICATION_658.md)
