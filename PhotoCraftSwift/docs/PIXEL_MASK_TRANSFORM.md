# Pixel-mask Free Transform

Select the pixel-mask thumbnail, unlink it from the layer and deselect any pixel selection. Command-T opens the existing Free Transform controls for that mask. Scale, Rotate, Skew, Distort, Perspective, fixed rotations and flips use the same native controls, numeric fields, nine reference positions and modifier cursors. Return applies; Escape cancels. Linked masks and selected mask regions stay unavailable in this branch, so the command cannot silently transform layer pixels.

The engine maps immutable raw grayscale samples in document coordinates. Nearest Neighbor, Bilinear and Bicubic(default) retain the mask depth without color conversion. Unit-grid transforms copy raw samples. The mask's independent exterior value, enabled state, density, feathering and inversion survive, as do layer pixels, geometry, styles, profiles and other document content. Transformed coverage outside the canvas remains stored in a new mask rectangle/placement.

A coalesced off-main proxy, at most1024pixels per side, supplies composition and gray/overlay mask previews. Adjustments leave the source document/history intact. Apply samples the original mask once and publishes one Free Transform Undo. Source/target changes, cancellation, API revocation, read/close and tool/focus loss prevent stale publication. This does not yet qualify physical60fps.

## API and Actions

`mask.transform` requires layerID and a nine-value row-major matrix mapping original to destination document coordinates. Optional interpolation uses the three named methods. The requested layer must be the current editable unlinked pixel-mask target, with no selection. Typed state/schema/capabilities expose availability, active target, mode, reference, matrix, preview/commit/error and interpolation. The native/API transaction, target preservation, validation and history are shared. There are229commands.

```json
{"command":"mask.transform","revision":"<current>","parameters":{"layerID":"<UUID>","matrix":[1,0,24,0,1,16,0,0,1],"interpolation":"Bicubic"}}
```

Semantic mask-transform Actions require35. Older operations retain their previous minimum versions and a falsely labeled34file is rejected. Native83 remains unchanged. Adobe's pinned v2 PixelMask schema defines source, offset, isEnabled and isLinked; it does not define a projective Free Transform matrix. Those resource/placement operations and their existing compatibility gaps remain distinct. No route or unverified actionJSON descriptor is invented.

## Validation and remaining work

All 16 new cases pass. Of 711 affected optimized cases, 710 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 186 analytical grayscale samples across four transforms. Sparse 300,000 × 300,000 masks are tested. Exact Photoshop samples, mask bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

The16new tests cover three depths/raw grid words/scalar exterior/projective sampling, placement and property preservation, sparse dimensions, history/Actions35/native persistence, actual offscreen mouse/Return, all16modifiers, gray/overlay proxies, coalescing, API/profile/archive consistency, invalid/locked/stale/busy/revoked/canceled requests and read/close/focus/tool lifecycle. These are owned/native tests, not Photoshop execution. Last actual native Photoshop access349 reported the Mac locked; no unchanged access poll was repeated.

Selected-mask regions, linked-mask combined transforms, Smart Filter/vector masks and channels/components remain separate workflows. Remaining G01 and all104package scopes stay open. Eleven historical strict rendering/interchange cases remain after the332stale-test repair, plus the opacity snapshot gate. Installed283, private source298 and store archive332 are unchanged.

[Evidence](PIXEL_MASK_TRANSFORM_REFERENCES.json) · [Mask linking](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/unlink-layers-and-masks.html) · [Transform options](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/transform-manipulate-reshape/transformation-options-in-adobe-photoshop.html)
