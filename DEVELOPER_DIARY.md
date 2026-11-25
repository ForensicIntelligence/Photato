# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **734** · The 10 most recent entries, newest first.

## 2026-11-25 — Step 734 — Keep Vanishing Point grid spacing and export square planes

Vanishing Point saves the Grid Size with the document. Use the number field or slider to set a shared spacing from 1 to 1,000. The overlay updates without repainting the image. Native documents, editable PSD and PSB and the authenticated Photato API retain fractional values.

In Photoshop 27.2.0, the Photato square-to-camera export reopened as a blue calibrated grid with size 73. The companion PSB also reopened at 73. The square PSD and PSB match 41 numeric fields in Adobe’s saved grid. Each file has its own plane ID. The corrected single-parallel trapezoid displayed a blue grid too. The two-plane file reopened at 91.25 after changing only the spacing tokens in its original Photoshop resource.

The desktop session timed out when launching the isolated Photato preview for direct input. Its native sheet was rendered offscreen in both appearances. Live keyboard and slider interaction, general projected grid placement, and the Photoshop measurement tools still need qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-734) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_734.md).

## 2026-11-24 — Step 733 — Keep Vanishing Point grids editable in PSD and PSB

Photato opens supported Photoshop Vanishing Point grids as editable planes. A connected grid stays attached to its parent edge. PSD and PSB retain the original plane record byte for byte when an edit changes only the pixels.

The owned Photoshop 27.2.0 files cover an oblique plane with a thin hinged child and two independent planes. The native tests reopen both relations, preserve the original records and verify that moving the parent updates the joined plane. The authenticated API returns and replays the measured settings, applies a Brush stroke, downloads PSD and PSB, and undoes the edit.

Photoshop displayed both grids in Photato’s new two-plane PSD. Its Vanishing Point filter also opened the matching PSB and displayed the moved parent grid from a second PSD. Exact-parallel Photoshop export, grid settings and measurement tools still need work. A diagnostic exact-parallel grid opened with distorted geometry.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-733) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_733.md).

## 2026-11-23 — Step 732 — Repair directly on cropped Vanishing Point layers

Vanishing Point can now apply Brush, Stamp and pasted repairs to an existing cropped pixel layer. The layer grows where needed and keeps its identity, original pixels and mask position. The native editor and authenticated Photato API use the same edit.

On the 1,600 × 1,200 owned layered PSD, Heal On extends the 1 × 1 Repair raster inside the selection. The existing-layer and separate-layer renders match across the full composite. The selected crop hashes match in Xcode Debug and both optimized architectures. The native editor and authenticated API retain the existing layer ID, its two underlying layers, the protected swatch, the archive and Undo. PNG export retains the tested repair sample.

The saved Photoshop Off-mode fixture preserves the repaired layer and its perspective data. The corresponding Photato crop still differs at 455 of 901 pixels, by a mean 0.71 RGB8 levels per channel. Both outputs preserve the protected swatch. Photato preserved the imported Photoshop plane record byte for byte through a native archive and PSD re-export. Editable PSD exchange of the perspective planes remains open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-732) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_732.md).

## 2026-11-23 — Step 731 — Blend projected repairs with Vanishing Point Heal

Vanishing Point adds Heal Off, Luminance and On for the Brush, Stamp and pasted patches. Luminance matches the surrounding light while keeping the source color differences. On blends both light and color. The native workspace and authenticated Photato API share the renderer.

On the 1,600 × 1,200 owned texture, Luminance lowered the mean lighting error on 901 defect pixels from 0.06803 to 0.00137. On lowered the mean RGB error from 0.15817 to 0.00000. The tested crop hashes agree in Xcode Debug and both optimized slices. The native and authenticated HTTP paths agree on each mode’s preview, editable archive, source and Undo. The core checks cover RGB8, RGB16, RGB32, a translucent pasted patch and an active selection.

The solver bounds each local repair region, including its one-pixel boundary, to 4,194,304 pixels. Applying into an imported 1 × 1 transparent repair layer leaves an out-of-bounds defect unchanged. The New Layer option handled the same repair. Photoshop 2026 pixel comparison and full product retouch acceptance remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-731) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_731.md).

## 2026-11-23 — Step 730 — Preserve Vanishing Point cameras at the canvas size limit

Vanishing Point can now apply a local correction with the default camera on a sparse 300,000 × 300,000 document. The editable archive and authenticated Photato API retain and replay the resolved focal length.

A 300,000 × 300,000 sparse document passed the native preview, Apply, archive reopen, HTTP archive download, and Undo. The API accepted the default camera and replayed the resolved 300,000-pixel focal length. The automatic and explicit camera controls produced the same local composite crop on both optimized slices and in Xcode Debug. Separate core tests cross the 100,000-pixel boundary in both document orientations and retain a calibrated 500,000-pixel focal length.

The automatic-camera edit produced a 2,048 × 2,048 preview in 104 ms on optimized Apple Silicon and 185 ms under Rosetta on this sparse fixture.

The maximum-size fixture is sparse and the correction uses one tile. Editable archives with focal lengths above 100,000 pixels require build 730 or later. Photoshop 2026 opened the reference modal on the owned texture fixture. The app disappeared before a stamp could be applied, so Adobe pixel equivalence remains open. Adobe documents the PSB dimension limit separately from this native workflow.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-730) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_730.md).

## 2026-11-23 — Step 729 — Keep narrow Vanishing Point strokes visible

A narrow perspective stamp can partially cover a row of pixels even when the pixel centers lie outside it. Vanishing Point now renders that coverage for Clone Stamp and Brush, including pixels partly inside a clipped plane.

The default camera projected the failing 48-megapixel fixture to about 0.81 pixels of vertical brush thickness. The repaired fixture paints 20 pixels across two rows, with about 39% opacity near the center. Independent integration matched 36 native depth, hardness and pixel-offset cases within 0.003 normalized opacity. Rotated-plane and plane-clipping checks passed. The native preview and full render agree, and the selected crop matches the authenticated API. The source layer, local Undo, accepted edit, editable archive and document Undo also match. The tested thicker 24-megapixel and fixed-camera 48-megapixel crops retain their previous bytes.

The first edited 48-megapixel overview took 68 ms on optimized Apple Silicon and 109 ms under Rosetta once the source was ready. The overview retains 2,048 × 1,536 display pixels.

Photoshop 2026 opened Vanishing Point on the owned reference image. The UI exposed the dialog and its OK and Cancel controls. The process disappeared before a reference export, so Adobe pixel equivalence remains open. The default camera also reaches a separate save limit above 100,000 pixels on the longer canvas side. Healing modes and Photoshop plane interchange still need qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-729) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_729.md).

## 2026-11-23 — Step 728 — Reuse the editor composite for Vanishing Point previews

Vanishing Point opens from the ready editor composite when it matches the current document. A local correction on a plain top pixel layer updates only its coverage. Apply commits the prepared preview as one editable history step.

The 24-megapixel native canvas kept its full-resolution preview. The 48-megapixel case used a 2,048 × 1,536 overview. Both edited preview buffers matched their independent full renders. Local Undo restored the earlier preview. Apply kept the accepted layer ID, and the authenticated API produced the same selected crop. Protecting the source, native save and reopen, and document Undo also passed.

The first 24-megapixel edit from a cold workspace took 1.49 s on Apple Silicon and 2.88 s under Rosetta. The adjacent build 727 measurements were 2.94 s and 5.26 s. With the editor composite ready, the first 24-megapixel stamp took 519 ms on Apple Silicon. The second edit preview took 1.2 ms. The first edit in the 48-megapixel overview took 64 ms.

The 48-megapixel repair used the same explicit camera projection as the 24-megapixel control. A narrow stamp on the larger fixture with default camera inference produced no sampled correction in builds 727 and 728. Its projected footprint and direct Photoshop output still need qualification. The timings measure software preview publication on one host.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-728) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_728.md).

## 2026-11-23 — Step 727 — Extend perspective texture repair to large canvases

Vanishing Point can repair a selected texture on a full-resolution product image and keep the correction on an editable layer. The plane solver now accepts an off-axis plane whose corner rays all point in front of the camera. The desktop workspace and Photato API share the same edit.

The editable 6,000 × 4,000 repair used two correction tiles. The selected texture matched the 2,048 × 1,536 reference byte for byte. The same selected crop matched in the 48-megapixel overview control and on a sparse 300,000 × 300,000 canvas. The tested native and authenticated API repairs preserved the original layer, editable archive and exact Undo. Their selected composite matched across optimized architectures.

The first 24-megapixel workspace preview took 2.94 s on optimized Apple Silicon and 5.26 s under Rosetta. The Xcode Debug preview took 65.1 s. The separate 48-megapixel control produced a 2,048 × 1,536 overview.

The 300,000 × 300,000 control uses a sparse canvas and a local selected repair. The Photoshop comparison, durable PSD perspective-plane metadata and Stamp healing modes remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-727) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_727.md).

## 2026-11-23 — Step 726 — Keep cropped-layer retouch previews regional

Clone Stamp and Healing Brush now redraw the affected area when a plain, integer-aligned transparent layer grows. The renderer includes both the old and new tile bounds, including when expansion shifts the layer origin. The native editor and authenticated Photato API use the same compositor.

The independent Xcode Debug checks matched raw composites at RGB8, RGB16 and RGB32. The cropped portrait replays matched the saved PNG, editable archive, authenticated API and exact Undo. Each optimized architecture matched all 12 build 725 PNGs across ordinary and cropped correction layers.

The cropped correction layer's first preview took 115–124 ms on optimized Apple Silicon, compared with 498–554 ms in the adjacent build 725 run. A scripted 48-sample cropped-layer stroke published 42 Clone Stamp and 41 Healing Brush previews. The preceding build published three for each tool on the same fixture.

These measurements cover software rendering and publication of previews. Physical pointer-to-display cadence and direct comparison with Photoshop 2026 remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-726) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_726.md).

## 2026-11-23 — Step 725 — Speed up RGB8 and RGB16 retouch sample conversion

Photato converts allocated tiles when a bounded sRGB raster changes to 8 or 16 bits per channel. Clone Stamp and Healing Brush use the faster conversion when preparing samples for a stroke. The desktop and authenticated Photato API share that conversion.

On the 2,096 × 2,592 portrait, the Apple Silicon depth conversion took 119 ms for RGB8 and 117 ms for RGB16. The former scalar loop took 194 and 193 ms. Every raw sample word matched at both depths on both optimized architectures. Each architecture matched all 12 build 724 PNGs across ordinary and cropped correction layers. Preview, commit, editable reopen and authenticated API pixels matched, with one Undo per stroke.

The ordinary New Layer first preview took 117–125 ms on optimized Apple Silicon after source selection. In the adjacent build 724 run it took 181–192 ms. A scripted 48-sample gesture produced 42 Clone Stamp and 41 Healing Brush software previews on an ordinary new layer. The cropped control produced 3 and 3, respectively.

The timings measure software preparation and the first complete preview on one test host. Physical pointer-to-display cadence and direct Photoshop comparison remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-725) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_725.md).
