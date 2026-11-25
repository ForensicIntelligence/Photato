# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **739** · The 10 most recent entries, newest first.

## 2026-11-25 — Step 739 — Wrap Vanishing Point selections across linked planes

Vanishing Point can draw and move a selection across a hinge. The outline follows both planes without an extra edge down the middle. Floating patches can sample and land across the hinge, and the Photato API uses the same edit and Undo rules as the desktop.

All 38 focused Xcode Debug tests passed. The offscreen workspace check covered both appearances and all 16 modifier combinations on each face. On the same two-wall image in Photoshop, a floating patch crossed the hinge but reached 59 pixels less far into the right wall. Exact placement on that face and pixel agreement remain open. A second guide with unequal wall lengths is ready for comparison.

Both optimized architectures passed 853 of 855 selected tests. The two failures repeated the build 738 diagnostics, and the Photato replays matched across the three build configurations. Both slices of the locally signed preview opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-739) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_739.md).

## 2026-11-25 — Step 738 — Add perspective Marquee and floating patches

Vanishing Point can create and move a rectangle in perspective. A floating selection can sample another part of the image, then move, scale or rotate as a patch. The existing document selection still protects pixels. The authenticated Photato API uses the same sampling and Undo path. All 35 focused tests passed.

Photoshop and Photato moved the same full-plane patch 20 pixels right and 10 down. The untouched strips matched. The translated area still differs in eight-bit rounding and feather coverage. A marquee that wraps across a hinge and live Source-mode drag comparison remain open.

Both optimized architectures passed 850 of 852 selected tests, with the same two failures as build 737. Photato produced identical replay files in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the locally signed preview opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-738) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_738.md).

## 2026-11-25 — Step 737 — Export Vanishing Point scenes

Vanishing Point can export perspective planes as textured 3DS meshes or as a VPE scene, with one PNG per plane. Export to 3DS includes the VPE companion. The native filter writes a new folder. The authenticated Photato API downloads the exported files as a ZIP and leaves the document and Undo history intact.

Blender opened the camera, meshes and PNG textures from both Photato reference scenes. An independent reader checked the VPE scene and its companion images. All 21 focused Core cases and 11 corrected Xcode Debug app and HTTP cases passed. Photoshop produced different camera values, hinged texture sizes and square texture pixels. After Effects import and DXF remain open.

Both optimized architectures passed 847 of 849 selected tests. The same two cases failed as in build 736. All nine fixture outputs matched byte for byte across Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the signed preview opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-737) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_737.md).

## 2026-11-25 — Step 736 — Render Vanishing Point measurement annotations

Vanishing Point now shows angles alongside editable measurement lengths. Render Measurements writes the lines, endpoints and labels onto a pixel layer when applying the filter. The authenticated Photato API can request the same output. Both paths keep editable measurements and use the same selection and Undo rules.

Photoshop 27.2.0 reopened the Photato PSD with a separate raster layer carrying the marks, and reopened the PSB with the linked grid and editable measurements still present. Two attempts to capture Photoshop’s own raster output ended with its document menus and Save unavailable. Adobe raster styling, further angle comparisons and CAD export remain open.

Both optimized architectures passed 844 of 846 selected tests, including all three new cases. The two inherited color-profile and layer-effect failures repeated. Xcode built the Debug app and passed 29 focused core, app and HTTP tests. Each generated PSD and PSB matched byte for byte in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the signed macOS 14+ preview opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-736) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_736.md).

## 2026-11-25 — Step 735 — Measure and calibrate Vanishing Point planes

Measure lines can be moved, resized and calibrated against a known length. Connected planes share the calibration and can link their grid spacing to it. Independent planes retain their own scale. The native workspace and the authenticated Photato API keep measurements editable in native documents, PSD and PSB.

Photoshop 27.2.0 opened both Photato exports with the linked grid and two editable measures. It displayed 40.01 and 30.01 for Photato’s 40 and 30. On an Adobe-authored angled plane, the largest observed difference was about 0.23 units. Angle labels, raster annotation and CAD export remain open.

Both optimized architectures passed 841 of 843 selected tests, including all four new cases. The two inherited color-profile and layer-effect failures repeated. Xcode built the Debug app and passed the 26 focused core, app and HTTP tests. The generated PSD and PSB each matched byte for byte in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the locally signed macOS 14+ preview opened offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-735) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_735.md).

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
