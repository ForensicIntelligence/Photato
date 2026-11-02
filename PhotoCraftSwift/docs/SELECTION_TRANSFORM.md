# Transform Selection

Select → Transform Selection now edits the selection boundary through native Swift controls. It supports move, proportional or independent scale, rotation, skew, distort, perspective, horizontal/vertical flips and fixed rotations. Image pixels, layers, masks, channels, profile, depth and the active component/mask target are preserved. This is distinct from transforming selected image pixels; that workflow remains unavailable.

The six modes are available through Edit → Transform and the canvas context menu. Options include X/Y, width/height percentages, angle, interpolation, aspect linking and nine reference positions. Shift toggles proportional scaling and constrains rotation to15-degree steps; Option scaling uses the chosen reference. Command invokes distort, Command-Shift on side handles invokes skew, and Command-Option-Shift on corners invokes perspective. The mode captured at pointer-down stays reflected in the cursor when modifiers change. Arrow keys nudge one pixel, Shift-arrow ten. Return applies, Escape/Cancel discards. Selection Warp is disabled. Exact Photoshop gesture/default/reference-position behavior remains unqualified.

Only a bounded selection contour is prepared for the preview. Transforming that contour coalesces off the main actor without per-pointer image recomposition. Apply resamples the immutable original selection once, then publishes one named Undo transaction if the source document still matches. Cancel/read/close cancel workers; stale or revoked work cannot publish. This design avoids repeated mask degradation, but physical responsiveness/60fps still needs live measurement.

The independent engine samples raw numeric GRAY8 coverage with zero outside the canvas. It offers Nearest Neighbor, Bilinear and Bicubic (Catmull-Rom), defaulting to Bicubic. Integer grid permutations preserve bytes. Existing licensed projective/grid primitives supply matrix geometry; the selection sampling and interaction implementation are native Swift. Sparse support, interpolation halos and bounded tiled output avoid an extra8MP/36MP admission cap. Existing coefficient/coordinate guards remain. Maximum-dimension sparse tests establish storage/admission only, not practical maximum dense editing capacity or Photoshop interpolation equivalence.

## API

`selection.transform` requires nine row-major homogeneous `matrix` coefficients mapping original document coordinates to destination coordinates. Optional `interpolation` is `Nearest Neighbor`, `Bilinear` or `Bicubic`. Output clips to the existing canvas. Reject nonfinite/singular matrices, invalid parameters, projective horizons across the supported source region, stale revisions and busy documents. Native desktop/API use the same preparation/history path and preserve editing targets. The catalogue now has 224 typed commands; state/capabilities expose availability, draft mode/reference/matrix, preparation/commit status, errors and schemas.

```json
{"command":"selection.transform","revision":"<current revision>","parameters":{"matrix":[1,0,12,0,1,8,0,0,1],"interpolation":"Bicubic"}}
```

The existing native 82/Actions 30 formats are unchanged. Actions stores explicit final selection coverage; this is not an Adobe semantic transform descriptor. Adobe's published v2 contract has no dedicated border-transform route. Unverified actionJSON descriptors remain unsupported; no endpoint or proprietary implementation is invented.

## Validation

All 14 new and 356 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 320 analytical GRAY8 bytes across four transforms. Sparse 300,000 × 300,000 projective admission is tested. Exact Photoshop sampling/gestures/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

Core tests cover grid transforms, raw half-byte sampling, corner homography, soft edges, clipping, sparse maximum dimensions, validation/horizons/cancellation and history/Actions/native archives. Native/API tests cover preview isolation, all 16 modifier combinations, captured/restored cursors, menu bindings, reference/numeric controls, commit/Undo, three depths, locked layers/profiles/component/mask targets, actual HTTP equality, invalid/busy/stale/revoked/canceled work and read/close. The separate Python reader independently computes matrix inverses and nearest/bilinear sampling of owned inputs. These are native and analytical checks, not Photoshop 2026 output or live interaction acceptance. Last actual native access remains344's locked-Mac result. All 104 package scopes remain open; installed283/private full298/store332 are unchanged.

[Evidence](SELECTION_TRANSFORM_REFERENCES.json) · [Adobe transform controls](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html) · [Adobe transform options](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/transform-manipulate-reshape/transformation-options-in-adobe-photoshop.html) · [Selection borders](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/move-selection-or-selection-border.html)
