# Channel blending

Open Layer > Layer Style > Blending Options, or choose Blending Options in the layer context menu. The Advanced Blending section has Red, Green and Blue checkboxes. Deselect a channel to preserve that backdrop component while the enabled channels use the existing composite. All three deselected currently makes the layer contribute nothing. These alpha, transparent-backdrop and group policies remain candidates until independently checked in Photoshop 2026.

The same controls support private preview, Cancel, one committed Undo transaction, style copy/paste and clear. Channel-only settings are available on adjustment layers and large RGB documents without allocating effect maps. Other effects keep their separate availability and limits. Stored source pixels remain unchanged.

## Optional API and storage

Existing `layer.style` and `layer.style.patch` accept `restrictedChannels`, an optional array of distinct excluded IDs: 0 = Red, 1 = Green, 2 = Blue. For example, `[0]` excludes Red and `[]` explicitly enables all three. Null clears channel exclusions. A new or replacement style with this field omitted uses the legacy representation; omitting the field from a style patch preserves the existing value. Non-RGB exclusions reject rather than treating display RGB as document components. State returns the field in each layer style; discovery describes channel and effect capacity separately.

The setting requires native archive 89 and Actions 56. Native downloads require `X-Photato-Archive-Version: 89`; earlier feature combinations also accept that envelope without changing their minimum versions. Existing portable style operations preserve the field, and mislabeled older libraries reject. Timeline channel choices hold until the next Style key. PSD/PSB uses the public `brst` component records, including an empty record for explicit all-on state. Other unsupported advanced metadata remains guarded.

There are still 261 typed commands. The pinned Firefly v2 `BlendOptions` schema contains blend mode and opacity, with no channel-exclusion field. No dedicated Adobe route, descriptor execution or plug-in runtime was added.

## Validation and remaining work

Checkpoint 461 passes 58 focused Debug methods and the same 58 optimized methods per architecture, including 17 new methods. Coverage includes all eight channel sets at 8/16/32 bit, represented blend modes, masks, transforms, groups, clipping, effects, adjustments, native/API/history errors, native 89, Actions 56, PSD/PSB records and maximum sparse geometry. Bounded raster updates are compared pixel-for-pixel with full rendering. This does not measure 60 fps.

Seven existing independent Photoshop RGB32 regressions pass on both retained build 460 architectures and the current selected configurations. They protect unrestricted output and do not establish new channel-exclusion Photoshop equivalence. The selected 384-byte captures match across Debug and both optimized architectures. See the [evidence](CHANNEL_BLENDING_461.json) for source bindings, failed attempts and strict word comparisons.

Early attempts exposed incorrect selectors and new test references that confused encoded values, stored linear samples and ordinary Normal composition rounding. Existing measured composition math stayed unchanged. A separate regression demonstrated unnecessary full-canvas damage before the pointwise invalidation repair. No old numerical assertion or tolerance was changed.

Live native controls, focus, preview, history and Close/Quit acceptance remain pending the existing automation connection issue. No build 461 app was launched or installed. Non-RGB exclusion, split Blend If, knockout, advanced clipping/mask flags and their complete editable interchange remain unfinished. Exact Photoshop alpha, effect, group, HDR, default and output behavior, physical platforms, performance, full-suite acceptance and all earlier failures remain open under the original L03 scope. L04 layer styles and effects is next, then L05.

[Adobe advanced blending guide](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/apply-layer-effects/use-advanced-blending-options.html) · [Public PSD specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
