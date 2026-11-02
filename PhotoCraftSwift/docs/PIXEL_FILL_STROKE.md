# Color Fill and Stroke

Photoshop 2026 is the reference. This increment adds the missing Edit > Stroke raster workflow and expands solid-color Fill. It does not close the full Fill/Stroke package or establish Photoshop pixel equivalence.

Edit > Stroke provides a color, integer width, Inside/Center/Outside placement, blending mode, opacity field and slider, and Preserve Transparency. A current pixel selection supplies the outline; with no selection, a raster layer's unmasked alpha supplies it. Pixel masks and auxiliary channels use the canvas boundary when there is no selection. No pixels are painted outside the canvas. Live text, shapes and Smart Objects require an explicit supported rasterization workflow.

The color Fill dialog retains foreground/background/custom color, black, 50% gray, white and the existing Content-Aware handoff. It adds blend modes, opacity and Preserve Transparency for supported targets. Partial opacity no longer reaches the old composite/mask100%-only error. Fill reaches the selected canvas area even beyond a small layer's current storage. Existing off-canvas pixels, mask placement, hierarchy, profiles and layer properties remain. Pattern, History, scripted fills, Behind/Clear modes and complete color/ink/temporal/multiple-layer semantics remain open.

RGB raster layers (including Background), pixel masks, alpha/spot channels and Quick Mask use one native engine. Position locks do not prevent color painting; inherited image locks reject raster painting, full locks reject mask painting, and transparency locks retain alpha. Scalar planes blend in displayed gray and apply inversion once. Original retained spot gray words outside the edit remain intact. Unsupported contexts stay unavailable rather than flattening live content. Existing component/ink Fill retains its previous Normal-only implementation.

Native controls capture the document and editing target, then prepare the edit off the main thread. Cancel, changed targets and changed documents publish nothing. An accepted edit creates one Undo entry; no-ops do not dirty the document. Dialog controls introduce no new canvas tool or modifier action. The opacity slider and number field are linked. Exact native layout, color-panel behavior, modal validation and Photoshop factory defaults still need live qualification.

The Stroke kernel is independently implemented with GRAY8 disc extrema and zero outside the canvas. Odd Center widths interpolate neighboring integer-radius bands. Width1–250 is an explicit current working limit; the retrieved current Photoshop page does not establish its maximum. Initial width1/Center/Normal/100% and per-open-document retained settings are implementation choices awaiting Photoshop preference/default qualification. Exact Photoshop edge/corner/antialias/gray/blend/HDR/profile behavior is open.

## Optional automation

The Photato catalogue now has 235 commands. `pixels.fill` and `pixels.stroke` accept color RGBA0–1, optional opacity0–1, mode and Preserve Transparency. Stroke additionally requires integer width1–250 and accepts location. Supply layerID (and mask=true for its pixel mask), or target with an alpha/spot UUID or quickMask. The explicit target must match the current native editing target. Unknown/missing/invalid parameters are rejected. State and capabilities expose pixelPaint availability, target, current settings, busy/selection state and parameter/result schemas.

Both commands share the native engine and prepared history path, with source revision/authentication/busy/stale/revoke/cancel and target checks. Existing legacy layer.fill and channel/ink/component operations keep their separate contracts. Portable Actions41 resolve layer/channel targets by semantic identity; older operation minima remain. Native archive support stays through84; pixel edits do not create a new document format.

The pinned Adobe v2 contract has no separately qualified destructive selection Fill/Stroke endpoint. No route or unverified actionJSON descriptor is invented. Existing layer-style strokes, fills and resource jobs retain their contracts; complete action/job equivalence remains open.

## Evidence

All 17 new cases pass: 7 model, 8 application and 2 imaging cases. Of 1178 affected optimized cases, 1175 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. An independent reader verifies 1080 alpha bytes across nine owned Stroke outputs. Sparse 300,000 × 300,000 Stroke and implicit full-canvas Fill are tested. Exact Photoshop edges/blends/defaults, live UI, full current suite, supported platforms, dense maximum capacity and physical 60fps remain unqualified.

The native tests are offscreen AppKit checks, not a physical Photoshop session. Last actual Photoshop access349 found the Mac locked; no later live access is claimed. Installed preview283, private source backup298 and store archive332 remain unchanged. No installation, push, archive, upload, review or release is performed here. All104 complete work-package scopes remain open.

Sources: [Adobe Stroke](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/stroke-selection-layer-color.html), [Adobe color Fill](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/fill-selection-layer-color.html), [feature catalogue](https://www.adobe.com/products/photoshop/features/all.html).
