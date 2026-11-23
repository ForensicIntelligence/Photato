# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **730** · The 10 most recent entries, newest first.

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

## 2026-11-23 — Step 724 — Reuse the canvas composite for Clone Stamp and Healing Brush

Clone Stamp and Healing Brush can reuse the prepared canvas composite for Current & Below and All Layers. The renderer checks that the cached document matches the requested source and layer cutoff. Source selection, previews and authenticated Photato edits share this sampling path.

On the 2,096 × 2,592 portrait, the optimized Apple Silicon raw sampling step went from 190.2 ms to 0.17 ms with a ready exact composite. Under Rosetta it went from 352.4 ms to 0.22 ms. All source bytes matched. The six optimized portrait edits matched build 723 PNGs exactly. The editor preview, commit and authenticated API output matched. Each repair stayed on an editable correction layer after reopening and could be reversed with one Undo.

With the ordinary New Layer action, Apple Silicon rendered the first preview in 183–192 ms. Using a compact 2 × 2 raster that had to expand, the first preview took 641–682 ms. The normal sparse New Layer raster can update a small region. Depth conversion still took most of its first-frame time. Both layer geometries produced the same tested PNGs.

These tests compare Photato’s output across configurations and against a clean portrait reference. Live Photoshop comparison is still open. Raw sampling time measures a single preparation stage. Actual pointing-device feedback and physical frame cadence remain open. The Clone Stamp still requires the user to match both source texture and tone.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-724) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_724.md).

## 2026-11-23 — Step 723 — Refine hair in Select and Mask

Select and Mask adds Refine Hair for a rough selection or an existing layer mask. Photato recovers soft strand coverage near the subject and keeps it editable. The native workspace previews the result before committing. The optional Photato API uses the same refinement.

The owned patterned-backdrop control recovered 85.0% of missing strand coverage, with 3.5% false coverage in nearby background. Partial-coverage alpha error fell from 0.335 to 0.104. Seven fixtures matched mask and PNG output bytes across Debug, optimized Apple Silicon and Intel under Rosetta. Masks stayed editable through native, PSD and PSB reopen. The independent reader matched stored coverage in both Photoshop file formats.

The measured reference set includes wigs, toy hair, fibers and two controlled backdrops. Darkening the new background can reveal residual color on very fine strands. Complex backgrounds and strands far from the coarse mask still need manual refinement. Live Photoshop comparison and physical VoiceOver and keyboard checks remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-723) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_723.md).

## 2026-11-23 — Step 722 — Keep projected Smart Object edges stable when relinking

Relinking a projected Smart Object to the same source preserves its rendered appearance in the tested PSD and PSB files. The original placement, editable Smart Filters and their mask stay with the layer.

The test moves a linked PSB, opens the document from its saved preview and relinks the same source bytes. Photato matches every rendered byte in the initial cache, resolved link and edited reopen at RGB8, RGB16 and RGB32. A filter-mask stroke and a filter reorder retain separate Undo steps. The authenticated Photato API matches the native rebind and Undo. An independent reader recovered the external filenames, projected corners and filter order in twelve files per configuration. It decompressed the painted filter mask and found the marked center at zero coverage in each edited file.

The verified case uses an unchanged local linked file and two native filters. The outputs compare Photato before and after reopening and relinking. Direct Photoshop comparisons, other deformation geometries and the full Smart Filter and linked-source acceptance workflows remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-722) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_722.md).

## 2026-11-23 — Step 721 — Preserve editable type and RGB32 composites in layered Photoshop files

Layered PSD and PSB exports place the editable text record and its padding before the following protection record. Photato can still open older files written with the uncounted pad. Whole-pixel translations of editable text now render the same way before and after reopening an RGB32 file.

The mixed document keeps editable type and its protection settings, group and pixel masks, an Exposure adjustment, and a projected embedded Smart Object with an editable Gaussian Blur and filter mask. Initial and edited reopens match every rendered RGBA byte at 8, 16 and 32 bits per channel in PSD and PSB. An independent reader recovered the tagged structure in all twelve files per configuration. An independent comparison matched 294,912 stored merged channel words per configuration, including the transparency plane. Authenticated Photato downloads matched the native files byte for byte.

The test uses exact file-representable group opacity. Photoshop files store the group opacity in one byte, so a literal 84% differs from the saved 214/255. These tests use owned input and compare round-trip output with Photato’s own pre-save render. Direct Photoshop reopening, Adobe pixel equivalence, linked asset rebind and broader Smart Filter ordering remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-721) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_721.md).
