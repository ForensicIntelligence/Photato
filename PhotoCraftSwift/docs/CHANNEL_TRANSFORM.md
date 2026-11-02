# Auxiliary-channel Free Transform

Select an alpha channel, spot channel or Quick Mask in Channels, then use Command-T or Edit > Transform. Whole planes and selected regions share Scale, Rotate, Skew, Distort, Perspective, fixed rotations/flips, numeric controls, nine reference positions and the existing modifier cursor policy. Return applies; Escape cancels. Individual color/ink components, multiple active channels and channel Move/V gestures remain separate work.

Channel coverage is numeric. Whole planes share the pixel-mask projective sampler; selected regions use the immutable opaque selected-content compositor with scalar RGB and ignored redundant alpha. Nearest Neighbor, Bilinear and Bicubic(default) retain the depth without color transfer. Output clips to the channel's existing canvas. Vacated/exterior values use the captured native background swatch's editing gray, applying selectedAreas or spot inversion once. Other channels, layer content/geometry, profiles, names and display/retained records survive. Retained Float32 spot source gray transforms with coverage and is reused only where its density remains compatible.

The coalesced off-main preview uses a proxy of at most1024pixels per side and captures the source, selection, target, fill and gray/overlay mode. It does not edit the real document/history per pointer input. Apply samples the original once and publishes one Free Transform Undo. Source/target changes, revocation, cancellation, read/close and focus/tool loss prevent stale publication. Physical60fps remains unqualified.

## API and Actions

Use existing `channel.view` to select the channel, then `channel.transform` with target (UUID or quickMask), a nine-value row-major document-coordinate matrix and optional interpolation. Optional backgroundValue supplies editing gray0to1; omission captures the native swatch. Optional copy=true duplicates selected or full-plane channel content over unchanged source through the shared compositor. Native Free Transform Option still means centered scaling, not copying. Typed state/schema/capabilities expose the current/captured channel, selection, fill, mode, matrix, reference, preview/commit/error and interpolation. There are230commands.

```json
{"command":"channel.view","revision":"<current>","parameters":{"target":"<channel UUID>","overlay":false}}
{"command":"channel.transform","revision":"<current>","parameters":{"target":"<channel UUID>","matrix":[1,0,24,0,1,16,0,0,1],"interpolation":"Bicubic","backgroundValue":1}}
```

The target must match the native editing channel. Desktop/API use the same preparation, revision/source/target validation, transaction, Undo/Redo and retained document state. New semantic channel-transform Actions require36 and resolve alpha/spot by name+occurrence or Quick Mask role; older operation minimum versions are retained and falsely labeled35files are rejected. Native83 is unchanged.

Adobe's pinned v2 contract has no dedicated auxiliary-channel transform route or qualified channel actionJSON descriptor. Existing layer/resource operations remain distinct. No route is invented; complete published API conformance stays open.

## Validation and remaining work

All 16 new cases pass. Of 744 affected optimized cases, 743 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 768 analytical grayscale samples across four transforms. Sparse 300,000 × 300,000 channel planes are tested. Exact Photoshop samples, channel bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

The16new cases cover whole/selected alpha/spot/Quick Mask at three depths, scalar/exterior/display inversion, soft copy and redundant alpha, projective methods, raw Float32 spot-gray movement, portable duplicate names, history/Actions36/native archives, invalid/stale/busy/revoked/canceled/changed targets, actual offscreen pointer/Return, all16modifier cursors, coalesced previews, native/API/profile equivalence and PSD/PSB channel persistence. Existing mask transforms and their independent vectors remain covered after sampler extraction. These are native/owned outputs, not Photoshop execution.

Last actual native Photoshop access349 reported the Mac locked. Exact Photoshop channel backgrounds/bounds/soft overlap/kernels/defaults/bytes/UI/cursor/platform/dense capacity and physical60fps remain unqualified. Channel Move, color/ink components, multi-layer transforms, linked/selected/filter/vector mask targets, Warp/repeat and other major workflows remain. All104package scopes are unclosed. The strict opacity snapshot and11historical rendering/interchange cases remain open. Installed283, private source298 and store archive332 are unchanged.

[Evidence](CHANNEL_TRANSFORM_REFERENCES.json) · [Channel editing](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/manage-channels-in-the-channels-panel.html) · [Grayscale masks](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/alpha-channels-and-masks-in-photoshop.html) · [Transform commands](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/transform-manipulate-reshape/apply-transformations.html)
