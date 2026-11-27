# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **759** · The 10 most recent entries, newest first.

## 2026-11-26 — Step 759 — Preserve hidden RGB when opening PNGs

Opening eligible 8-bit and 16-bit RGB PNGs preserves colour beneath transparent pixels. The reader keeps straight samples in the working space, including alpha zero and the smallest nonzero alpha. The existing conversion still handles colour-space changes and providers outside the supported layout and size budget.

All 33 selected Xcode Debug checks passed, including native archive and HTTP import. All 135 focused optimized checks passed on each architecture, including the two new tests. Intel ran under Rosetta.

All 3,840 decoded RGBA bytes matched in three owned Photoshop PNGs. Three synthetic PNGs also matched 1,064,960 decoded bytes with and without an embedded RGB profile. The 16-bit controls span all 65,536 red sample values in both ordinary and Adam7-interlaced files. A 36-megapixel control preserved the 20 sampled bytes while mapping four document tiles totalling 256 KiB. That storage figure excludes ImageIO’s decoded provider. Whole-file PNG equality remains unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-759) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_759.md).

## 2026-11-26 — Step 758 — Preserve straight RGBA in PNG exports

PNG exports retain straight colour and alpha samples in 8-bit and 16-bit RGB. In supported Normal raster stacks, the PNG export follows Photoshop’s observed behaviour for RGB beneath fully transparent pixels.

All 31 selected Xcode Debug checks passed, including native save and API checks. All 133 focused optimized checks passed on both architectures, including the new PNG checks for Adam7 interlacing and very low opacity. Intel ran under Rosetta.

All 3,840 decoded RGBA bytes in three owned Photoshop PNG exports matched, covering RGB8, RGB16 and RGB8 offset layers. The PNG containers still differ in metadata and compression. The Open path in this checkpoint still discards hidden RGB beneath zero alpha.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-758) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_758.md).

## 2026-11-26 — Step 757 — Match Normal RGB8 raster composition

Normal blends between supported aligned 8-bit RGB raster layers use the measured integer compositing formula. The dense, paged and sparse render paths share the arithmetic. Default pixel masks remain editable.

All 22 focused Xcode Debug checks passed, including native Save and authenticated transfers. All 131 selected optimized tests passed on each architecture. The suite covers TIFF, raster encoding, Normal layer blends, layer-layout and group rendering, and file transfer options. Intel ran under Rosetta.

The two owned Photoshop TIFF captures and the committed output regression match all 27,648 sampled colour, opacity, and saved-selection bytes with Save Transparency enabled and disabled. The independent TIFF strip reader compared the Adobe-authored files against outputs from the original PSD. Whole TIFF files retain different container bytes. An independent 131,072-pixel Normal merge comparison also matched all visible samples and opacity. Hidden RGB at zero opacity remains different in two merge-fixture variants.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-757) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_757.md).

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
