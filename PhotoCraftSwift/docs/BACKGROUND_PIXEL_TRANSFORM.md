# Background selected-pixel Free Transform

**Checkpoint350:** Move/V now moves/copies selected pixels through the shared preview/commit engine, including Shift constraints and Option-arrow copies. pixels.move and pixels.transform copy/state share Actions34; native83 remains. Earlier Move gaps below describe historical349 scope. [Current guide](SELECTED_PIXEL_MOVE.md).

Command-T and the existing Edit/Transform modes now accept a pixel selection on an editable RGB Background layer. Scale, Rotate, Skew, Distort, Perspective, numeric/reference controls and direct selected flips/rotations share the existing transform session and effective modifier cursors. Background remains the opaque bottom layer at Normal/100% and its original canvas size; the layer is neither moved nor converted. Image/full protection still prevents editing. Other target contexts and whole-layer Background transforms remain separate work.

The background swatch is captured when a transform begins. Source coverage is replaced with that color, then the transformed selected contribution is composited over the remainder. Preview, Apply, Undo/Redo and Actions share the same captured value even if the palette later changes. Identity retains every original word and creates no history. Tiled damage regions preserve untouched samples, including native HDR words. Background output clips to the canvas; ordinary layers retain their existing transparent holes and off-canvas transformed samples. Virtual interpolation support clips before Background storage admission. Sparse maximum-dimension checks do not establish practical maximum dense capacity.

## API and storage

`pixels.transform` retains its layerID/matrix/interpolation contract and adds optional opaque RGBA backgroundColor. On Background, omission captures the native background swatch. On ordinary layers this option rejects. State/schema/capabilities add background identity and the currently captured backgroundColor (null for ordinary pixels). The typed command count remains227. Existing layer.transform still means whole-layer transformation. No unsupported published Adobe selected-pixel endpoint/actionJSON descriptor is invented; the create-composite direct-Background transform guard is preserved.

```json
{"command":"pixels.transform","revision":"<current>","parameters":{"layerID":"<Background UUID>","matrix":[1,0,12,0,1,8,0,0,1],"interpolation":"Bicubic","backgroundColor":[1,1,1,1]}}
```

New Background transform Actions store target/matrix/interpolation/captured color and require33. Ordinary selected-pixel Actions retain31; Background conversion/clear Actions retain32; older libraries remain readable with their original requirements. Native83 remains unchanged. The generic engine reconciles authoritative RGB component planes after edits. Native history/API cancellation, revision/source/target/lifecycle and revocation guards remain shared.

## Evidence and remaining work

All14 new cases pass. Of617 affected optimized cases,616 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies3,072 analytical RGBA channels across four Background transforms. Sparse300,000 ×300,000 editing and clipped virtual support are tested. Exact Photoshop pixels/soft overlap/interpolation/defaults/UI, full-current-suite, supported Macs, maximum dense capacity and physical60fps remain unqualified.

The14 new cases cover identity/HDR words, three depths and explicit RGB native planes, opaque holes/clipping/identity, soft coverage, all interpolators/projective matrices, Actions/legacy requests/history, invalid colors/locks/stale/canceled work, sparse maximum dimensions, captured native preview/commit, all16 modifiers, actual HTTP/profile/native/PSD results, default/explicit swatches, read/close and proxy bounds. The independent vectors use owned RGB samples and analytical formulas; they are not Photoshop output. Native access was attempted at349 and the Mac was locked. All104 workflow packages remain open.

[Evidence](BACKGROUND_PIXEL_TRANSFORM_REFERENCES.json) · [Adobe clearing](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/delete-or-cut-selected-pixels.html) · [Adobe transforms](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html)
