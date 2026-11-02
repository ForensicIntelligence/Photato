# Color Range selection

Select → Color Range… now opens a native Swift dialog. Photoshop 2026 is the target; this increment implements sampled colors, six color presets, highlights/midtones/shadows, Fuzziness, Localized Color Clusters/Range, three eyedroppers, Invert and previews. The independently written native kernel is not numerically qualified against Photoshop. Skin Tones/Detect Faces, Out of Gamut and Adobe preset formats remain unavailable. Full S02 is still open.

The large image preview provides None, Grayscale, Black Matte, White Matte and Quick Mask modes. The selection thumbnail switches between Selection and Image; Command temporarily changes preview presentation. Shift adds a sampled color and Option subtracts; Option takes precedence together. Sampling uses original image coordinates and colors even when clicking a mask preview. The sampler operation is captured for the gesture and shares the ModifierCursorView lifecycle. Control does not invent a new action. Save/Load use version1 Photato JSON presets rather than Adobe proprietary presets.

## Shared selection model

Color Range samples the visible RGB composite, including layer placement, masks, opacity and appearance; it does not require an unlocked ordinary pixel layer. The source is converted to SDR sRGB for classification without changing the document or original samples/profile/depth. An existing selection constrains the new result by coverage intersection; deselect first to select across the whole canvas.

Samples use CIE Lab D65 Euclidean distance with a linear falloff over Fuzziness0–200; zero selects exact colors. Add samples take maximum coverage and subtract samples constrain its complement. Localized samples multiply linear radial falloff using normalized sample positions and Range as a percentage of the image diagonal (half-pixel minimum). Hue-sector presets suppress neutral gray; tonal ranges use sRGB luminance0–255 with configurable threshold(s) and Fuzziness. Invert is applied before source alpha, so invisible pixels stay excluded. These are explicit Photato formulas, not claims about Adobe's implementation or exact defaults.

Coordinate-independent classification maps implicit samples and stored tiles without allocating a logical full plane. Localized work visits sample support bounds and checks cancellation. There is no new36MP or side-dimension admission limit; the sparse300000×300000 test is allocation/admission evidence, not practical maximum dense-image qualification. Previews use bounded display buffers. Changes coalesce, stale generations cannot publish, Cancel/read/close cancel tasks, and source revision is checked before commit. Acceptance makes one Color Range Undo transaction. Actions saves final coverage using the existing selection recording format, rather than rerunning classification.

## API

`selection.colorRange` brings the Photato catalogue to 219 commands. Supply partial `settings`, or a version1 Photato JSON `presetBase64`, exclusively. The `colorRange` state exposes availability, workspace/preview status, settings, accepted preset and errors; capabilities contain all parameter/result/state schemas, actual defaults and unsupported modes. RGB/document-target, existing shared-document limits, request size, busy/stale/revocation and history rules apply. Parameters are validated before mutation; no server filesystem access is exposed.

```json
{"command":"selection.colorRange","revision":"<current revision>","parameters":{"settings":{"kind":"sampled","fuzziness":40,"samples":[{"color":{"r":1,"g":0,"b":0,"a":1},"point":{"x":0.25,"y":0.5}}]}}}
```

Adobe's published Photoshop v2 interface has no dedicated Color Range route. Its generic execute-actions operation does not make every Photoshop event supported. Unverified semantic Color Range descriptors remain unsupported; no route or descriptor contract is invented. Existing shared selection coverage is native Actions support, distinct from Adobe actionJSON compatibility.

## Validation

All 14 new and 127 affected optimized cases pass, with zero failures, unexpected errors or crashes. The separate checker verifies10 analytical mask bytes. Sparse300000×300000 classification is tested; physical maximum-capacity editing,60fps, complete current suite and Photoshop numerical/UI/default/platform acceptance remain open.

Focused cases cover add/subtract, alpha/inversion, hue/tonal controls, localized positions, fuzziness, presets and malformed input, sparse maximum dimensions, cancellation, history/Actions, profile/depth retention, prior selections, locked sources, preview and sampling, source changes, document read/close, HTTP/native/preset equality, schemas, invalid/busy/stale requests and deterministic sharing revocation. Cursor tests enumerate all16 modifier combinations for each sampler, capture/restoration and factory menu binding. A separate Python checker checks owned analytical output without the Swift decoder. These tests are not live Photoshop or native-user acceptance. Last actual UI access remains341's locked-Mac observation; no fresh capture is claimed. Native82/Actions30/all 104 package scopes and installed283/private full298/store332 are unchanged.

[Evidence](COLOR_RANGE_REFERENCES.json) · [Adobe Color Range guide](https://helpx.adobe.com/photoshop/desktop/make-selections/freehand-selections/select-a-color-range-in-photoshop.html)
