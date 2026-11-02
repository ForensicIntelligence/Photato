# Pattern Fill

Photoshop2026 remains the reference. The native Fill dialog now offers Pattern and a Custom Pattern choice. This extends the raster Fill workflow and does not close the full A07 package or establish Photoshop numerical/UI equivalence.

Edit > Fill keeps the previous palette/custom-color controls and Content-Aware handoff. Selecting Pattern displays saved preset names in the content row. Empty/loading sources are disabled. Document-owned patterns take precedence over library assets with the same ID. Contents and the selected ID are remembered within the open document; the full Photoshop preference/default/picker presentation remains unqualified. Existing Define Pattern/import/library workflows supply the presets; this increment does not add a new library-management interface.

Pattern Fill uses the same prepared paint transaction as color Fill: selection/canvas coverage, mode/opacity, raster transparency locks, mask/auxiliary-channel gray and display inversion, target validation, undo and cancellation. Transparent pattern texels preserve original destination words. Existing off-canvas data, masks, profile metadata and current selection remain. Unsupported live content is not rasterized implicitly. Standard native placement uses the existing premultiplied wrapping bilinear sampler in document coordinates. Exact Photoshop origin/phase/scale/sampling/HDR/profile/target behavior is still open.

The asset is captured when the request is accepted. Replacing or deleting a library preset later cannot change that work. Raster output is baked and reopens without the source preset. Portable Pattern Actions42 embed the asset, placement, settings and semantic layer/channel target; they can replay without the library. Solid paint Actions41 and all earlier minima remain. Native archive support stays through84. Existing16MP per-pattern/64MP aggregate preset budgets and action/API resource limits remain disclosed development limits, not claimed Photoshop capacities. One-pixel/implicit constant patterns retain sparse full-target optimization; a general dense maximum-size patterned fill is not qualified.

## Optional API

The catalogue remains235commands. `pixels.fill` accepts patternID instead of color. Its normal target, mode, opacity and Preserve Transparency parameters retain their contracts. A request must choose exactly one source; absent, ambiguous or unknown assets are rejected. pixelPaint state exposes available pattern IDs/names/dimensions/depth/source, loading/availability and remembered Contents. Patterns resolve once from the document before the native library. Existing binary document import can carry document-owned presets; no new remote pattern import/management endpoint is claimed.

Optional placement specifies scale, angle and phase through the shared sampler. This is an explicit Photato API option, not a claim that Photoshop's Fill dialog has these controls. Desktop/API source revisions, current target, busy/stale/revoke/cancel and one-step history use the same path. No Adobe endpoint or unverified actionJSON descriptor is invented; published v2 resource and style operations remain distinct and their unresolved conformance gates stay open.

## Evidence

All 13 new cases pass: 6 model, 5 application and 2 imaging cases. Of 1204 affected optimized cases, 1201 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. Independent modulo/pixel and PNG readers verify 4320 RGBA bytes across eight owned raw outputs and one PNG. Sparse 300,000 × 300,000 localized and implicit-uniform pattern fills are tested. Exact Photoshop phase/kernel/profile/defaults, live UI, full current suite, supported platforms, dense maximum capacity and physical60fps remain unqualified.

Native checks use offscreen AppKit controls, not a physical Photoshop session. Last actual native Photoshop access349 encountered the locked Mac; no later access is claimed. Installed preview283, private source backup298 and store archive332 remain unchanged. No installation, source push, archive, upload, review or release is performed. All104complete work-package scopes remain open, including History/scripted fills, native color/ink/temporal/filter-mask/multiselect cases, exact profiles/defaults/pattern range, complete current suite, supported platforms, dense maximum capacity and physical60fps.

Reference: [Adobe's Fill sources guide](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/content-aware-fills.html).
