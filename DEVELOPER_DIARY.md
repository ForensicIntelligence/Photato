# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **756** · The 10 most recent entries, newest first.

## 2026-11-26 — Step 756 — Control merged transparency in TIFF saves

TIFF Save Transparency controls the merged preview. Turning it off composites the preview over white and omits the merged opacity sample. Editable layers, layer masks and named saved selections retain their samples. The checkbox starts checked, preserving the previous Photato export behaviour.

All 21 focused Xcode Debug checks and 81 optimized cases per architecture passed. The selected scope covers TIFF, raster encoding options, native save options and API transfers. Each architecture passed the four new regression tests. Intel ran under Rosetta. The expanded baseline inventory remains documented with checkpoint 755.

The independent TIFF parser confirmed the measured white-matte equation across all 9,216 colour samples and an unchanged 3,072-byte selection channel. The matched matted output differs from Photoshop by one sample value in 316 red, 50 green and 104 blue samples. Other colour modes and the Photoshop factory checkbox default still need reference checks.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-756) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_756.md).

## 2026-11-26 — Step 755 — Keep saved selections in layered RGB8 TIFFs

Layered 8-bit RGB TIFFs can retain named saved selections alongside editable layer masks and the merged image’s transparency. Open and Save preserve the channel name, sampled values, and display polarity.

All 17 focused Debug checks passed. All 63 focused TIFF cases passed on each optimized architecture, including the three new regressions. The broader inventory discovered 5,952 cases per architecture. Results were 5,844 passed, 89 failed, 15 skipped and 4 incomplete on Apple Silicon, 5,835 passed, 98 failed, 15 skipped and 4 incomplete on Intel under Rosetta. Every failing case and incomplete verdict also occurred when replayed against the hash-verified public 754 source. The Intel video-cancellation case had variable diagnostics on repeat. The evidence names failed, skipped and incomplete cases. The earlier checkpoint used a narrower inventory.

An independent TIFF reader matched all 24,576 saved-selection bytes and all 98,304 process and opacity bytes across eight opaque and transparent output variants. The process and opacity comparison used the equivalent flat Photato export. The two Photoshop-authored files retained their editable layers, layer masks, and 6,144 exact saved-selection bytes. Photoshop reopened the Photato export and displayed its saved selection by name. Its TIFF re-export kept all 3,072 selection bytes. Across those three Adobe TIFFs, all 82,944 raw editable layer and mask samples matched the source PSD. The matched transparent exports differed by one byte value in 266 red, 54 blue, and 50 opacity samples. The Green and saved selection planes matched exactly. The test fixtures preserve the Photoshop image samples and layer blocks with unrelated file metadata removed. Complete file bytes, other channel depths, spot inks, and Quick Mask still require qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-755) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_755.md).

## 2026-11-26 — Step 754 — Calibrate manual Vanishing Point grid spacing

The Vanishing Point preview and raster grid now use the same plane scale as the Measure tool when you enter Grid Size manually. Keeping a manual size and linking a measurement of the same size now produces the same grid.

All 69 focused Debug tests passed. Both optimized architectures passed 883 of 885 selected tests, including the new grid-spacing regression. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

The corrected tilted rectangle grid matches all 51,233 marked RGBA samples in the equivalent measurement-linked control. All 105,704 marked samples on the straight-on control remain exact, as do its complete PSD and PNG files. Photoshop’s preview spacing on the tilted reference agrees with the corrected geometry at the observed zoom. An independent Photoshop grid raster is still needed to qualify the exact coordinates, color and alpha. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/define-perspective-planes-in-vanishing-point.html).

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-754) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_754.md).

## 2026-11-26 — Step 753 — Render a Vanishing Point grid onto a layer

Use Render Grids to Document in Vanishing Point to draw plane edges and grid lines onto the selected layer. New Layer keeps the result separate from the source pixels. The option resets every session, and Undo restores the prior document.

All 68 focused Debug tests passed. Both optimized architectures passed 882 of 884 selected tests, including the three new grid cases. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

A 1,600 × 768 dense grid previously reached the rendering work cap. The fixed implementation meters each tile draw and checks coverage across a tile boundary. A separate 1,600 × 1,200 PSD reopened with its raster and editable plane intact. The installed Photoshop menu showed grid rendering. Exact Photoshop grid positions and pixel values remain open. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/define-perspective-planes-in-vanishing-point.html).

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-753) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_753.md).

## 2026-11-26 — Step 752 — Reuse the Vanishing Point preview geometry

Vanishing Point retains its resolved planes as you pan, zoom and apply pixel-only workspace edits. Valid changes to plane settings resolve new geometry. Invalid changes leave the last valid scene available.

All 65 focused Debug tests passed. Both optimized architectures passed 879 of 881 selected tests, including the new scene reuse case. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

A 32-plane Debug replay read the scene across 240 view updates. Geometry reads fell from 93.70 ms to 0.057 ms with the same checksum. The measurement excludes drawing and compositor work. Exact Photoshop raster and overall interactive frame rate remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-752) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_752.md).

## 2026-11-26 — Step 751 — Navigate the Vanishing Point preview

Vanishing Point adds a Zoom tool with point-anchored zoom, Option to zoom out and a rectangle to zoom in on a region. Space temporarily pans and X temporarily magnifies the preview. Command–plus and Command–minus zoom. Command–0 fits the preview. Preview navigation leaves the edit program and document undo history intact.

All 64 focused Debug tests passed, including anchor preservation and navigation cursors across all 16 modifier combinations. Both optimized architectures passed 878 of 880 selected tests, including the two new navigation cases. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

Offscreen Xcode captures confirm the fitted, zoomed and panned sheet in light and dark appearances. Live pointer input and exact Photoshop rectangle zoom and double-click behavior remain unqualified. Exact Photoshop paste raster output remains open. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/uk/photoshop/using/vanishing-point.html).

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-751) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_751.md).

## 2026-11-25 — Step 750 — Resize and nudge floating Vanishing Point pastes

Floating Vanishing Point pastes now have side handles for changing width or height independently. The arrow keys move a selected paste by one pixel. Shift and an arrow move it by ten. The current handle and modifiers are reflected in the pointer.

All 62 focused Debug tests passed. Each optimized architecture passed 876 of 878 selected tests, including the updated side-handle and nudge assertions. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics. The replay image of a side stretch, nudge and undo/redo matched across Debug and both optimized builds.

An independent nine-impulse RGB8 donor showed that Photoshop’s plain, Flip and Flop results differ from exact donor mapping at 112, 2,432 and 2,436 pixels. All three preserved every pixel outside the patch. The reflected responses moved different distances at different locations and had fractional spill. Exact Photoshop raster parity remains open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-750) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_750.md).

## 2026-11-25 — Step 749 — Paste clipboard pixels before choosing a perspective plane

Clipboard images pasted into Vanishing Point now start at the upper-left of the document at their original pixel size. They can be placed before any plane exists. Dragging the paste onto a fitted face preserves the grabbed point as the image adopts perspective.

All 62 focused Debug tests passed. Each optimized build passed 876 of 878 selected tests, including both new cases. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics. The replay PNG matched byte for byte across Debug and both optimized builds.

The direct 96 × 48 Flip comparison matched Photoshop at 1,789 pixels and differed at 2,819. All pixels outside the patch were preserved. Paste origin and dimensions now match the Photoshop control. Photoshop’s resampling still needs separate qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-749) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_749.md).

## 2026-11-25 — Step 748 — Transform clipboard and layer pastes in Vanishing Point

Vanishing Point selects Marquee after clipboard paste. Press T to show scale and rotation handles and the Flip and Flop controls. Shift constrains scale or movement and snaps rotation. Option centers the resize or duplicates a moved paste. Finishing a gesture adds one workspace Undo.

All 60 focused Debug tests passed. Each optimized build passed 874 of 876 selected tests, including the three new cases. Intel ran under Rosetta. The same two inherited failures repeated their diagnostics. Four replay PNGs matched byte for byte across Debug and both optimized builds.

The comparison used a 96 × 48 Photoshop Flip and a Photato replay aligned to the same pixel origin and size on a synthetic front-facing plane. Of 4,608 pixels in the patch, 1,789 matched and 2,819 differed. Photato preserved every pixel outside the patch. The Photoshop capture stayed at its upper-left paste origin. A second Flip reproduced the same Adobe RGB raster. Opening Transform with both reflection controls off kept the ordinary Adobe paste unchanged. Free canvas placement, side handles, and Photoshop’s on-plane raster and rotation behavior need separate checks.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-748) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_748.md).

## 2026-11-25 — Step 747 — Sample the Vanishing Point preview with Eyedropper

Vanishing Point’s Eyedropper samples the composite at the pointer. With Preview on, it sees the active draft. With Preview off, it sees the original. The sampled color becomes the workspace Brush color. Press I for Eyedropper and B to return to Brush.

The authenticated Photato command `vanishingPoint.sampleColor` accepts an image point and optional preview operations and returns the visible color and coverage without changing the shared document revision or Undo history.

All 57 focused tests passed in Debug. Both optimized builds passed 871 of 873 selected tests. The new desktop and HTTP Eyedropper check passed on Apple Silicon and Intel under Rosetta. The two inherited color-profile and layer-effect failures repeated their previous diagnostics.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-747) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_747.md).
