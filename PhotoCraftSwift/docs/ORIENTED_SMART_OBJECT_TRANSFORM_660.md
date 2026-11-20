# Free Transform follows Smart Object artwork

## 20 November 2026

Opening Free Transform on an already rotated or skewed Smart Object previously drew handles around its document-aligned bounding rectangle. Side drags then scaled along the document's axes. The artwork and its preview could therefore move differently from what the handles suggested. This also affected a reopened linked PSD or PSB when a cached preview was the only available image.

Adobe documents Smart Object orientation, the Free Transform reference point, and Shift and Option behavior in its desktop guides. The installed Photoshop session timed out on a read-only version and document-count query. Exact live Adobe handle hit areas, displayed percentages, and rendered pixels remain open. [Adobe Free Transform](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html) · [Smart Object orientation](https://helpx.adobe.com/uk/photoshop/desktop/create-manage-layers/smart-objects/reset-smart-object-transforms.html)

## Changes

- For a single affine Smart Object, the draft starts from the four saved artwork corners and its true center. The hit test distinguishes the oriented interior from the area surrounding it. Place Embedded and Place Linked previews use the same frame when eligible.
- Side and corner drags scale in the artwork's axes. The opposite edge or corner stays fixed during a regular drag. Option scales around the current reference point, and Shift toggles proportional scaling. Resize and rotate cursors follow the action and update when modifiers change during a drag.
- The angle field starts from the artwork's orientation. Numeric scaling is relative to the draft's starting placement. The reference-point presets and document-axis flips use the same frame and preserve the chosen pivot.
- Photato exposes draft corners, angle, scale and the native commit delta through `transformReference.artworkFrame`. The existing `layer.transform` command applies the same delta. A frame can be unavailable for projected, warped, selection and multi-layer transforms. Source formats, the shader and the Adobe job schemas use their existing paths.

The retained geometry lives in `SmartObjectGeometry.swift` and `SmartObjectTransformFrame.swift`. The canvas, Options bar, transform draft and placement entry points share that geometry. `ToolCursorPolicies.swift` and `CanvasView.swift` route cursor changes, and `TransformReferenceAPI.swift` describes and encodes the new state.

## Validation

The five new tests cover linked PSD and PSB reopen, sheared and rotated artwork, native pointer and modifier handling, preview pixels and one Undo, absolute angle and a document-axis flip, and the local HTTP state and commit.

The first Debug source passed four of five tests. The failing case showed that an embedded Smart Object opens through the projective layer workspace. It still had an angle of zero and a document-aligned frame. The second source starts that workspace from the saved artwork frame and composes an explicit Distort or Perspective mapping in the original source coordinates. The regression now checks that Distort can still move one corner while preserving the opposite one.

All 1,477 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

In the actual native Options bar, the owned linked PSD opened Free Transform at 30° in build 660 and at 0° in build 659. Both live runs canceled through the existing control. The AppKit tests also verified modifier gestures and one Undo, the exact preview and committed pixels in the linked fixture, and the embedded Smart Object's Distort mapping.

[Qualification](SOURCE_PUBLICATION_660.md)
