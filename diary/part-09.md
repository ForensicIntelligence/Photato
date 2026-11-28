[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-08.md)

## 2026-11-27 — Step 768 — Open larger grayscale, CMYK and Lab TIFFs

Photato decodes supported classic TIFF strips into editable, file-backed color planes. Gray, CMYK and Lab data retain their original component values and supported precision as well as an RGB display preview.

Independent libtiff comparisons matched 258,014,000 native 16-bit channel words across ZIP, predicted LZW and raw TIFF inputs, including a 6,000 × 6,000 grayscale image and a planar CMYK control. The measured opacity plane was fully opaque in those four comparisons. A rotated Gray8 fixture separately verified associated alpha. An edited 36-megapixel grayscale copy reopened from a Photato archive with its complete edited component data intact.

The Xcode project built and all 44 selected imaging and 13 app and HTTP tests passed. Both optimized architectures passed all 233 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

This checkpoint changes supported classic strip input. The 512 MiB encoded desktop limit, large TIFF output, tiled component TIFF, BigTIFF, layered capacity and independent Photoshop transparency comparisons remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-768) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_768.md).

## 2026-11-27 — Step 767 — Preserve the TIFF color profile choice

The TIFF save panel now has an Embed Color Profile checkbox. It follows the document’s profile choice by default and accepts a per-file override. The TIFF writer preserves the sample values with either choice.

An independent decoder matched all 2,048 Gray16 samples with the Photoshop references in four profile cases on each architecture. Tagged and untagged copies also matched those samples when saved through the native Photato panel. The imaging tests cover flat and layered RGB, grayscale, CMYK and Lab, plus Indexed Color without an embedded profile.

The Xcode project built and 39 focused imaging and 12 app, panel and HTTP tests passed. Both optimized architectures passed all 227 selected tests. The extracted Universal preview rendered offscreen on each slice. Intel ran under Rosetta.

The checks establish TIFF profile choice and sample preservation in the tested cases. Photoshop TIFF opacity, whole-file equivalence and larger component TIFF documents are still open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-767) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_767.md).

## 2026-11-27 — Step 766 — Match grayscale TIFF output with transparency off

TIFF Save Transparency off writes the measured white-matted grayscale samples for aligned Normal layers at 8 and 16 bits per channel. Layered TIFF copies keep their editable layer samples and opacities.

Independent decoding matched every grayscale sample in two flattened Photoshop 27.2.0 references. All four flattened and layered Photato comparisons match across Debug, Apple Silicon and translated Intel. The 16 PSD and PSB regression files also agree across those builds.

The Xcode project built and all 37 focused imaging and 11 app and HTTP tests passed. Both optimized architectures passed all 226 selected tests. The extracted Universal preview rendered offscreen on each slice. Intel ran under Rosetta.

The independent TIFF comparison covers decoded grayscale samples. TIFF with Save Transparency on, complex blends, very large component output and whole-file equality with Photoshop remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-766) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_766.md).

## 2026-11-27 — Step 765 — Match grayscale PSD and PSB previews

PSD and PSB now compose the merged preview from native gray samples on aligned Normal layers at 8 and 16 bits per channel. The preview is white-matted when the composite has transparency. Opaque composites omit the merged opacity plane. Save retains the original editable layer samples and opacities.

Four Photoshop 27.2.0 PSD saves cover opaque and transparent stacks at both depths. An independent decoder matched every merged sample in the Photato PSD and PSB files with Raw and RLE encoding. The 16 comparison files match byte for byte across Debug, optimized Apple Silicon and translated Intel.

The Xcode project built and all 37 focused imaging and 11 app and HTTP tests passed. Both optimized architectures passed all 226 selected tests. The extracted Universal preview rendered offscreen on each slice. Intel ran under Rosetta.

The Adobe comparisons cover the merged previews of the tested layer stacks. Whole-file equality, Adobe’s layer bounds and Gray16 rounding on re-save, and grayscale TIFF opacity remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-765) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_765.md).

## 2026-11-27 — Step 764 — Open larger PNG palettes as editable RGB

Open can now expand larger PNG palettes with partial opacity or multiple transparent entries into editable RGB8. The importer streams packed scanlines to scratch storage and builds file-backed RGB tiles. It handles standard and Adam7 layouts and applies EXIF rotations.

All 36 focused imaging cases and eleven app and HTTP cases passed in Xcode Debug. Both optimized architectures passed all 225 selected tests. Intel ran under Rosetta.

Photato had rejected the 8,389,632-pixel palette control. Photoshop 27.2.0 opened it in RGB8. The revised Photato reader matched all 8,389,632 original straight RGBA samples in an independent replay. The sparse 36,006,000-pixel Adam7 test retained all sampled colors and opacity. The EXIF rotation test kept the canvas file-backed and moved the tested pixels to their expected positions. Photoshop’s PNG copy preserved all visible color and opacity in the 8.39-megapixel control. Its save normalized hidden RGB at 8,192 fully transparent positions. Export container equality remains open.

The new path applies to palettes that require RGB expansion. Editable Indexed Color and Bitmap still use their existing size limit. Maximum-size dense imports and animated PNG remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-764) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_764.md).

## 2026-11-27 — Step 763 — Open indexed PNGs with complex transparency

Open now creates an editable RGB8 layer from a PNG palette with partial opacity or multiple transparent entries. The decoder retains straight RGB and all per-pixel opacity. A palette with one or zero fully transparent entries and no partial opacity stays editable as Indexed Color.

All 35 focused imaging tests and ten app and HTTP tests passed in Xcode Debug. Both optimized architectures passed all 223 selected tests. Intel ran under Rosetta.

Photoshop 27.2.0 opened all five owned controls in the same modes as Photato. Independent decoding matched 748 straight RGBA imports and 187 retained indices. The graded-palette Photoshop PNG copy matched all 187 source RGBA samples, including hidden RGB. The second Photoshop PNG copy verified all 187 rendered samples for the unused-opacity control, including the fully transparent pixels outside the visible bounds.

The comparisons cover the tested palette tables and exact decoded samples. Complete PNG container equality and animated indexed PNG import remain open. Photoshop also opened an owned 8,389,632-pixel palette PNG beyond the current Photato restricted PNG limit.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-763) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_763.md).

## 2026-11-27 — Step 762 — Match layered grayscale PNG samples

Saving an eligible layered Grayscale PNG now blends the retained gray and opacity samples directly. The 16-bit calculation promotes layer opacity before composing. Transparent pixels within the visible bounds retain the bottom layer’s gray, and pixels outside those bounds use transparent white.

All 28 focused imaging tests and nine app and HTTP tests passed in Xcode Debug. Both optimized architectures passed all 215 selected tests. Intel ran under Rosetta.

Photoshop 27.2.0 opened four owned three-layer PSDs and saved PNG copies at 8 and 16 bits, each with opaque and transparent base cases. An independent reader compared all 16,384 gray and alpha pairs across standard and Adam7 Photato exports. All pairs matched, including hidden gray. The four noninterlaced exports also matched Photoshop’s filtered scanlines byte for byte. A fifth 16-bit reference distinguished the two half-tie rounding orders at 32 positions. All 128 gray and alpha pairs across its ordinary and Adam7 exports matched.

Complete PNG files differ. Photoshop’s observed profile setting left the reference untagged and the exported files also differ in metadata and compressed IDAT bytes. The numerical check covers aligned Normal layers with a shared profile. Masked or transformed stacks, other blend modes, TIFF and Photoshop merged previews still need separate verification.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-762) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_762.md).

## 2026-11-27 — Step 761 — Preserve grayscale PNG samples and profiles

Open retains Grayscale PNG as an editable gray plane with straight opacity. Packed 2-bit and 4-bit values expand to 8-bit. Eligible flat 8-bit and 16-bit Save output retains the exact gray and opacity samples, including hidden gray, along with embedded profiles and declared gamma.

All 36 focused Xcode Debug tests passed. Both optimized architectures passed all 214 selected tests, including the three new Grayscale PNG regressions. Intel ran under Rosetta.

Six independently generated files matched all 1,122 gray/alpha pairs on import. All 2,244 pairs in twelve standard and Adam7 exports matched. A 36-megapixel sparse control preserved the six sampled pairs through PNG and native archive round trips. Candidate 01 discarded declared gamma. The corrected reader retains the color interpretation of all three tested gamma values and the embedded gray ICC control. Layered grayscale still goes through the RGB composite. Its output differs from a diagnostic based on the measured RGB Normal model. Independent Photoshop Grayscale output and complete file equality remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-761) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_761.md).

## 2026-11-27 — Step 760 — Show and hide Vanishing Point edges

Vanishing Point adds a checked Show Edges control in Options with a Command-H binding. Turning it off hides plane borders, grids and idle selection outlines. Selection outlines reappear during a drag. Measurement visibility and grids rendered into the image remain independently controlled.

All five focused Xcode Debug tests passed. Both optimized architectures passed all 210 focused tests, including the new Show Edges regression. Intel ran under Rosetta.

Photoshop 27.2.0 showed Show Edges checked in Vanishing Point with Command-H. The Photato tests cover overlay state. The live Options and keyboard checks remain pending. Independent verification of Photoshop’s grid raster is still open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-760) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_760.md).

## 2026-11-26 — Step 759 — Preserve hidden RGB when opening PNGs

Opening eligible 8-bit and 16-bit RGB PNGs preserves colour beneath transparent pixels. The reader keeps straight samples in the working space, including alpha zero and the smallest nonzero alpha. The existing conversion still handles colour-space changes and providers outside the supported layout and size budget.

All 33 selected Xcode Debug checks passed, including native archive and HTTP import. All 135 focused optimized checks passed on each architecture, including the two new tests. Intel ran under Rosetta.

All 3,840 decoded RGBA bytes matched in three owned Photoshop PNGs. Three synthetic PNGs also matched 1,064,960 decoded bytes with and without an embedded RGB profile. The 16-bit controls span all 65,536 red sample values in both ordinary and Adam7-interlaced files. A 36-megapixel control preserved the 20 sampled bytes while mapping four document tiles totalling 256 KiB. That storage figure excludes ImageIO’s decoded provider. Whole-file PNG equality remains unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-759) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_759.md).

## 2026-11-26 — Step 758 — Preserve straight RGBA in PNG exports

PNG exports retain straight colour and alpha samples in 8-bit and 16-bit RGB. In supported Normal raster stacks, the PNG export follows Photoshop’s observed behaviour for RGB beneath fully transparent pixels.

All 31 selected Xcode Debug checks passed, including native save and API checks. All 133 focused optimized checks passed on both architectures, including the new PNG checks for Adam7 interlacing and very low opacity. Intel ran under Rosetta.

All 3,840 decoded RGBA bytes in three owned Photoshop PNG exports matched, covering RGB8, RGB16 and RGB8 offset layers. The PNG containers still differ in metadata and compression. The Open path in this checkpoint still discards hidden RGB beneath zero alpha.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-758) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_758.md).

## 2026-11-26 — Step 757 — Match Normal RGB8 raster composition

Normal blends between supported aligned 8-bit RGB raster layers use the measured integer compositing formula. The dense, paged and sparse render paths share the arithmetic. Default pixel masks remain editable.

All 22 focused Xcode Debug checks passed, including native Save and authenticated transfers. All 131 selected optimized tests passed on each architecture. The suite covers TIFF, raster encoding, Normal layer blends, layer-layout and group rendering, and file transfer options. Intel ran under Rosetta.

The two owned Photoshop TIFF captures and the committed output regression match all 27,648 sampled colour, opacity, and saved-selection bytes with Save Transparency enabled and disabled. The independent TIFF strip reader compared the Adobe-authored files against outputs from the original PSD. Whole TIFF files retain different container bytes. An independent 131,072-pixel Normal merge comparison also matched all visible samples and opacity. Hidden RGB at zero opacity remains different in two merge-fixture variants.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-757) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_757.md).

## 2026-11-26 — Step 756 — Control merged transparency in TIFF saves

TIFF Save Transparency controls the merged preview. Turning it off composites the preview over white and omits the merged opacity sample. Editable layers, layer masks and named saved selections retain their samples. The checkbox starts checked, preserving the previous Photato export behaviour.

All 21 focused Xcode Debug checks and 81 optimized cases per architecture passed. The selected scope covers TIFF, raster encoding options, native save options and API transfers. Each architecture passed the four new regression tests. Intel ran under Rosetta. The expanded baseline inventory remains documented with checkpoint 755.

The independent TIFF parser confirmed the measured white-matte equation across all 9,216 colour samples and an unchanged 3,072-byte selection channel. The matched matted output differs from Photoshop by one sample value in 316 red, 50 green and 104 blue samples. Other colour modes and the Photoshop factory checkbox default still need reference checks.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-756) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_756.md).

## 2026-11-26 — Step 755 — Keep saved selections in layered RGB8 TIFFs

Layered 8-bit RGB TIFFs can retain named saved selections alongside editable layer masks and the merged image’s transparency. Open and Save preserve the channel name, sampled values, and display polarity.

All 17 focused Debug checks passed. All 63 focused TIFF cases passed on each optimized architecture, including the three new regressions. The broader inventory discovered 5,952 cases per architecture. Results were 5,844 passed, 89 failed, 15 skipped and 4 incomplete on Apple Silicon, 5,835 passed, 98 failed, 15 skipped and 4 incomplete on Intel under Rosetta. Every failing case and incomplete verdict also occurred when replayed against the hash-verified public 754 source. The Intel video-cancellation case had variable diagnostics on repeat. The evidence names failed, skipped and incomplete cases. The earlier checkpoint used a narrower inventory.

An independent TIFF reader matched all 24,576 saved-selection bytes and all 98,304 process and opacity bytes across eight opaque and transparent output variants. The process and opacity comparison used the equivalent flat Photato export. The two Photoshop-authored files retained their editable layers, layer masks, and 6,144 exact saved-selection bytes. Photoshop reopened the Photato export and displayed its saved selection by name. Its TIFF re-export kept all 3,072 selection bytes. Across those three Adobe TIFFs, all 82,944 raw editable layer and mask samples matched the source PSD. The matched transparent exports differed by one byte value in 266 red, 54 blue, and 50 opacity samples. The Green and saved selection planes matched exactly. The test fixtures preserve the Photoshop image samples and layer blocks with unrelated file metadata removed. Complete file bytes, other channel depths, spot inks, and Quick Mask still require qualification.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-755) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_755.md).

## 2026-11-26 — Step 754 — Calibrate manual Vanishing Point grid spacing

The Vanishing Point preview and raster grid now use the same plane scale as the Measure tool when you enter Grid Size manually. Keeping a manual size and linking a measurement of the same size now produces the same grid.

All 69 focused Debug tests passed. Both optimized architectures passed 883 of 885 selected tests, including the new grid-spacing regression. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

The corrected tilted rectangle grid matches all 51,233 marked RGBA samples in the equivalent measurement-linked control. All 105,704 marked samples on the straight-on control remain exact, as do its complete PSD and PNG files. Photoshop’s preview spacing on the tilted reference agrees with the corrected geometry at the observed zoom. An independent Photoshop grid raster is still needed to qualify the exact coordinates, color and alpha. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/define-perspective-planes-in-vanishing-point.html).

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-754) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_754.md).

## 2026-11-26 — Step 753 — Render a Vanishing Point grid onto a layer

Use Render Grids to Document in Vanishing Point to draw plane edges and grid lines onto the selected layer. New Layer keeps the result separate from the source pixels. The option resets every session, and Undo restores the prior document.

All 68 focused Debug tests passed. Both optimized architectures passed 882 of 884 selected tests, including the three new grid cases. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

A 1,600 × 768 dense grid previously reached the rendering work cap. The fixed implementation meters each tile draw and checks coverage across a tile boundary. A separate 1,600 × 1,200 PSD reopened with its raster and editable plane intact. The installed Photoshop menu showed grid rendering. Exact Photoshop grid positions and pixel values remain open. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/define-perspective-planes-in-vanishing-point.html).

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-753) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_753.md).

## 2026-11-26 — Step 752 — Reuse the Vanishing Point preview geometry

Vanishing Point retains its resolved planes as you pan, zoom and apply pixel-only workspace edits. Valid changes to plane settings resolve new geometry. Invalid changes leave the last valid scene available.

All 65 focused Debug tests passed. Both optimized architectures passed 879 of 881 selected tests, including the new scene reuse case. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

A 32-plane Debug replay read the scene across 240 view updates. Geometry reads fell from 93.70 ms to 0.057 ms with the same checksum. The measurement excludes drawing and compositor work. Exact Photoshop raster and overall interactive frame rate remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-752) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_752.md).

## 2026-11-26 — Step 751 — Navigate the Vanishing Point preview

Vanishing Point adds a Zoom tool with point-anchored zoom, Option to zoom out and a rectangle to zoom in on a region. Space temporarily pans and X temporarily magnifies the preview. Command–plus and Command–minus zoom. Command–0 fits the preview. Preview navigation leaves the edit program and document undo history intact.

All 64 focused Debug tests passed, including anchor preservation and navigation cursors across all 16 modifier combinations. Both optimized architectures passed 878 of 880 selected tests, including the two new navigation cases. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

Offscreen Xcode captures confirm the fitted, zoomed and panned sheet in light and dark appearances. Live pointer input and exact Photoshop rectangle zoom and double-click behavior remain unqualified. Exact Photoshop paste raster output remains open. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/uk/photoshop/using/vanishing-point.html).

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-751) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_751.md).

## 2026-11-25 — Step 750 — Resize and nudge floating Vanishing Point pastes

Floating Vanishing Point pastes now have side handles for changing width or height independently. The arrow keys move a selected paste by one pixel. Shift and an arrow move it by ten. The current handle and modifiers are reflected in the pointer.

All 62 focused Debug tests passed. Each optimized architecture passed 876 of 878 selected tests, including the updated side-handle and nudge assertions. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics. The replay image of a side stretch, nudge and undo/redo matched across Debug and both optimized builds.

An independent nine-impulse RGB8 donor showed that Photoshop’s plain, Flip and Flop results differ from exact donor mapping at 112, 2,432 and 2,436 pixels. All three preserved every pixel outside the patch. The reflected responses moved different distances at different locations and had fractional spill. Exact Photoshop raster parity remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-750) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_750.md).

## 2026-11-25 — Step 749 — Paste clipboard pixels before choosing a perspective plane

Clipboard images pasted into Vanishing Point now start at the upper-left of the document at their original pixel size. They can be placed before any plane exists. Dragging the paste onto a fitted face preserves the grabbed point as the image adopts perspective.

All 62 focused Debug tests passed. Each optimized build passed 876 of 878 selected tests, including both new cases. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics. The replay PNG matched byte for byte across Debug and both optimized builds.

The direct 96 × 48 Flip comparison matched Photoshop at 1,789 pixels and differed at 2,819. All pixels outside the patch were preserved. Paste origin and dimensions now match the Photoshop control. Photoshop’s resampling still needs separate qualification.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-749) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_749.md).

## 2026-11-25 — Step 748 — Transform clipboard and layer pastes in Vanishing Point

Vanishing Point selects Marquee after clipboard paste. Press T to show scale and rotation handles and the Flip and Flop controls. Shift constrains scale or movement and snaps rotation. Option centers the resize or duplicates a moved paste. Finishing a gesture adds one workspace Undo.

All 60 focused Debug tests passed. Each optimized build passed 874 of 876 selected tests, including the three new cases. Intel ran under Rosetta. The same two inherited failures repeated their diagnostics. Four replay PNGs matched byte for byte across Debug and both optimized builds.

The comparison used a 96 × 48 Photoshop Flip and a Photato replay aligned to the same pixel origin and size on a synthetic front-facing plane. Of 4,608 pixels in the patch, 1,789 matched and 2,819 differed. Photato preserved every pixel outside the patch. The Photoshop capture stayed at its upper-left paste origin. A second Flip reproduced the same Adobe RGB raster. Opening Transform with both reflection controls off kept the ordinary Adobe paste unchanged. Free canvas placement, side handles, and Photoshop’s on-plane raster and rotation behavior need separate checks.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-748) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_748.md).

## 2026-11-25 — Step 747 — Sample the Vanishing Point preview with Eyedropper

Vanishing Point’s Eyedropper samples the composite at the pointer. With Preview on, it sees the active draft. With Preview off, it sees the original. The sampled color becomes the workspace Brush color. Press I for Eyedropper and B to return to Brush.

The authenticated Photato command `vanishingPoint.sampleColor` accepts an image point and optional preview operations and returns the visible color and coverage without changing the shared document revision or Undo history.

All 57 focused tests passed in Debug. Both optimized builds passed 871 of 873 selected tests. The new desktop and HTTP Eyedropper check passed on Apple Silicon and Intel under Rosetta. The two inherited color-profile and layer-effect failures repeated their previous diagnostics.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-747) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_747.md).

## 2026-11-25 — Step 746 — Scale and rotate floating perspective selections with handles

Floating Marquee selections now have corner scale controls and a rotation handle. Hold Shift when rotating to snap in 15-degree steps. The editor and API use the same perspective transform, and the drag takes one Undo.

All 56 focused tests passed. They cover a linked hinge, cursor feedback, resizing, rotation and matching desktop/API output. Light and Dark captures show the new handles and the existing numeric controls.

Both optimized builds passed 870 of 872 selected tests. The three new tests passed on Apple Silicon and Intel under Rosetta. The two inherited color-profile and layer-effect failures repeated their previous diagnostics. All six transform replays matched byte for byte across Debug and both optimized builds.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-746) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_746.md).

## 2026-11-25 — Step 745 — Paint straight perspective strokes with Shift

Shift-drag draws a straight path with Vanishing Point Brush and Stamp. Shift-click connects to the previous endpoint when it belongs to the same tool on an eligible face. The pointer changes for straight strokes and Stamp source sampling. A Marquee can be cleared while painting.

The 53 focused tests passed. They cover the renderer, cursor modifier combinations, and matching desktop and API edits with Undo. Exact Photoshop stroke pixels remain open.

Both optimized builds passed all three new cases and 867 of 869 overall. The two inherited failures repeated. All eight owned replays matched across Debug, Apple Silicon and Intel. The matching Universal preview ships with this checkpoint.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-745) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_745.md).

## 2026-11-25 — Step 744 — Constrain perspective retouching to a Marquee

Vanishing Point Brush and Stamp now stay inside the drawn Marquee when applying marks. A selection can extend across a hinge. Stamp can still sample from outside the rectangle, and the Photato API accepts the same selection per stroke.

All 50 focused Xcode tests passed, including a one-pixel footprint split at the selection edge and desktop/API output with one Undo. Photoshop exited before producing reference pixels on the owned two-face guide.

Both optimized builds passed the two new tests and 864 of 866 overall. The inherited failures repeated, and all eight native replays matched byte for byte across Debug, Apple Silicon and Intel. The source checkpoint includes the matching Universal preview.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-744) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_744.md).

## 2026-11-25 — Step 743 — Paint and clone across linked Vanishing Point planes

Brush and Stamp now follow the perspective around a hinge with Allow Multi-surface Operations enabled. Destination clipping is a separate control. An aligned Stamp keeps the same donor displacement as the stroke moves to the linked face. The desktop and API use the same renderer and Undo.

On two owned guides, Brush, Stamp and the healed Brush reached both faces. Turning wrapping off kept the Brush on the starting face. A Photoshop stroke raster for direct comparison is still missing.

All 48 focused Xcode tests passed. Both optimized builds passed all four new tests and 862 of 864 selected tests overall. The two inherited failures repeated their previous results. All eight owned replay PNGs match across Debug and both optimized builds. The matching Universal preview now ships with the source checkpoint on GitHub.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-743) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_743.md).

## 2026-11-25 — Step 742 — Improve floating selection sampling in Vanishing Point

Vanishing Point now uses bicubic sampling when a floating selection lands between pixels. Photoshop references on a synthetic pattern of stripes and dots showed the small overshoots produced by cubic interpolation. On the left-to-right two-wall image, the average donor interior error fell from 2.14 to 0.81 RGB levels. All five full patches improved. The narrow receiving area in one synthetic capture got slightly worse.

All 44 focused Xcode tests passed. The desktop editor and authenticated Photato API produce the same subpixel edit with one Undo.

Both optimized builds passed 858 of 860 selected tests. The two inherited failures repeated their diagnostics. All five replay PNGs agree across Debug, Apple Silicon and Intel.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-742) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_742.md).

## 2026-11-25 — Step 741 — Preserve Vanishing Point fold angles in Photoshop files

PSD and PSB guides can keep their editable fold angles when moving between Photato and Photoshop. Photoshop reopened newly written guides at 45°, 90° and 135°. The reader also recovered the same off-centre camera from the three Photoshop saves. Untouched guide records and merged RGB samples survived both file formats.

A new Marquee comparison used the corrected 90° guide. On the centre row, Photato matched Photoshop's patch extent in one direction and was one pixel wider in the other. The colors differ, even with Feather set to 0.

All 43 focused checks passed. Both optimized builds passed 857 of 859 selected tests and repeated the same two existing failures. The twenty test PSD and PSB files match across the three builds.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-741) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_741.md).

## 2026-11-25 — Step 740 — Recover editable right-angle Photoshop hinges

Photato can open both planes in an owned PSD saved after its hinge angle was edited to 90° in Photoshop. The previous build dropped the guides. The three stored vanishing directions reveal an off-centre camera that would be missed by assuming the centre of the image. Using that camera brings the native scene width ratio within 0.00001 of Photoshop's export.

Both PSD and PSB round trips preserve the perspective record and every merged RGB sample. All 40 focused tests passed, including the authenticated Photato API replay. Newly authored hinge angles and exact color and edge coverage of the Marquee edit still need comparison.

Each optimized architecture passed 855 of 857 selected tests. The same two failures repeated their build 739 diagnostics. All six native reference files matched across Debug, Apple Silicon and Intel. Both locally signed preview slices opened offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-740) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_740.md).

## 2026-11-25 — Step 739 — Wrap Vanishing Point selections across linked planes

Vanishing Point can draw and move a selection across a hinge. The outline follows both planes without an extra edge down the middle. Floating patches can sample and land across the hinge, and the Photato API uses the same edit and Undo rules as the desktop.

All 38 focused Xcode Debug tests passed. The offscreen workspace check covered both appearances and all 16 modifier combinations on each face. On the same two-wall image in Photoshop, a floating patch crossed the hinge but reached 59 pixels less far into the right wall. Exact placement on that face and pixel agreement remain open. A second guide with unequal wall lengths is ready for comparison.

Both optimized architectures passed 853 of 855 selected tests. The two failures repeated the build 738 diagnostics, and the Photato replays matched across the three build configurations. Both slices of the locally signed preview opened offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-739) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_739.md).

## 2026-11-25 — Step 738 — Add perspective Marquee and floating patches

Vanishing Point can create and move a rectangle in perspective. A floating selection can sample another part of the image, then move, scale or rotate as a patch. The existing document selection still protects pixels. The authenticated Photato API uses the same sampling and Undo path. All 35 focused tests passed.

Photoshop and Photato moved the same full-plane patch 20 pixels right and 10 down. The untouched strips matched. The translated area still differs in eight-bit rounding and feather coverage. A marquee that wraps across a hinge and live Source-mode drag comparison remain open.

Both optimized architectures passed 850 of 852 selected tests, with the same two failures as build 737. Photato produced identical replay files in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the locally signed preview opened offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-738) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_738.md).

## 2026-11-25 — Step 737 — Export Vanishing Point scenes

Vanishing Point can export perspective planes as textured 3DS meshes or as a VPE scene, with one PNG per plane. Export to 3DS includes the VPE companion. The native filter writes a new folder. The authenticated Photato API downloads the exported files as a ZIP and leaves the document and Undo history intact.

Blender opened the camera, meshes and PNG textures from both Photato reference scenes. An independent reader checked the VPE scene and its companion images. All 21 focused Core cases and 11 corrected Xcode Debug app and HTTP cases passed. Photoshop produced different camera values, hinged texture sizes and square texture pixels. After Effects import and DXF remain open.

Both optimized architectures passed 847 of 849 selected tests. The same two cases failed as in build 736. All nine fixture outputs matched byte for byte across Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the signed preview opened offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-737) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_737.md).

## 2026-11-25 — Step 736 — Render Vanishing Point measurement annotations

Vanishing Point now shows angles alongside editable measurement lengths. Render Measurements writes the lines, endpoints and labels onto a pixel layer when applying the filter. The authenticated Photato API can request the same output. Both paths keep editable measurements and use the same selection and Undo rules.

Photoshop 27.2.0 reopened the Photato PSD with a separate raster layer carrying the marks, and reopened the PSB with the linked grid and editable measurements still present. Two attempts to capture Photoshop’s own raster output ended with its document menus and Save unavailable. Adobe raster styling, further angle comparisons and CAD export remain open.

Both optimized architectures passed 844 of 846 selected tests, including all three new cases. The two inherited color-profile and layer-effect failures repeated. Xcode built the Debug app and passed 29 focused core, app and HTTP tests. Each generated PSD and PSB matched byte for byte in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the signed macOS 14+ preview opened offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-736) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_736.md).

## 2026-11-25 — Step 735 — Measure and calibrate Vanishing Point planes

Measure lines can be moved, resized and calibrated against a known length. Connected planes share the calibration and can link their grid spacing to it. Independent planes retain their own scale. The native workspace and the authenticated Photato API keep measurements editable in native documents, PSD and PSB.

Photoshop 27.2.0 opened both Photato exports with the linked grid and two editable measures. It displayed 40.01 and 30.01 for Photato’s 40 and 30. On an Adobe-authored angled plane, the largest observed difference was about 0.23 units. Angle labels, raster annotation and CAD export remain open.

Both optimized architectures passed 841 of 843 selected tests, including all four new cases. The two inherited color-profile and layer-effect failures repeated. Xcode built the Debug app and passed the 26 focused core, app and HTTP tests. The generated PSD and PSB each matched byte for byte in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the locally signed macOS 14+ preview opened offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-735) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_735.md).

## 2026-11-25 — Step 734 — Keep Vanishing Point grid spacing and export square planes

Vanishing Point saves the Grid Size with the document. Use the number field or slider to set a shared spacing from 1 to 1,000. The overlay updates without repainting the image. Native documents, editable PSD and PSB and the authenticated Photato API retain fractional values.

In Photoshop 27.2.0, the Photato square-to-camera export reopened as a blue calibrated grid with size 73. The companion PSB also reopened at 73. The square PSD and PSB match 41 numeric fields in Adobe’s saved grid. Each file has its own plane ID. The corrected single-parallel trapezoid displayed a blue grid too. The two-plane file reopened at 91.25 after changing only the spacing tokens in its original Photoshop resource.

The desktop session timed out when launching the isolated Photato preview for direct input. Its native sheet was rendered offscreen in both appearances. Live keyboard and slider interaction, general projected grid placement, and the Photoshop measurement tools still need qualification.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-734) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_734.md).

## 2026-11-24 — Step 733 — Keep Vanishing Point grids editable in PSD and PSB

Photato opens supported Photoshop Vanishing Point grids as editable planes. A connected grid stays attached to its parent edge. PSD and PSB retain the original plane record byte for byte when an edit changes only the pixels.

The owned Photoshop 27.2.0 files cover an oblique plane with a thin hinged child and two independent planes. The native tests reopen both relations, preserve the original records and verify that moving the parent updates the joined plane. The authenticated API returns and replays the measured settings, applies a Brush stroke, downloads PSD and PSB, and undoes the edit.

Photoshop displayed both grids in Photato’s new two-plane PSD. Its Vanishing Point filter also opened the matching PSB and displayed the moved parent grid from a second PSD. Exact-parallel Photoshop export, grid settings and measurement tools still need work. A diagnostic exact-parallel grid opened with distorted geometry.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-733) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_733.md).

## 2026-11-23 — Step 732 — Repair directly on cropped Vanishing Point layers

Vanishing Point can now apply Brush, Stamp and pasted repairs to an existing cropped pixel layer. The layer grows where needed and keeps its identity, original pixels and mask position. The native editor and authenticated Photato API use the same edit.

On the 1,600 × 1,200 owned layered PSD, Heal On extends the 1 × 1 Repair raster inside the selection. The existing-layer and separate-layer renders match across the full composite. The selected crop hashes match in Xcode Debug and both optimized architectures. The native editor and authenticated API retain the existing layer ID, its two underlying layers, the protected swatch, the archive and Undo. PNG export retains the tested repair sample.

The saved Photoshop Off-mode fixture preserves the repaired layer and its perspective data. The corresponding Photato crop still differs at 455 of 901 pixels, by a mean 0.71 RGB8 levels per channel. Both outputs preserve the protected swatch. Photato preserved the imported Photoshop plane record byte for byte through a native archive and PSD re-export. Editable PSD exchange of the perspective planes remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-732) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_732.md).

## 2026-11-23 — Step 731 — Blend projected repairs with Vanishing Point Heal

Vanishing Point adds Heal Off, Luminance and On for the Brush, Stamp and pasted patches. Luminance matches the surrounding light while keeping the source color differences. On blends both light and color. The native workspace and authenticated Photato API share the renderer.

On the 1,600 × 1,200 owned texture, Luminance lowered the mean lighting error on 901 defect pixels from 0.06803 to 0.00137. On lowered the mean RGB error from 0.15817 to 0.00000. The tested crop hashes agree in Xcode Debug and both optimized slices. The native and authenticated HTTP paths agree on each mode’s preview, editable archive, source and Undo. The core checks cover RGB8, RGB16, RGB32, a translucent pasted patch and an active selection.

The solver bounds each local repair region, including its one-pixel boundary, to 4,194,304 pixels. Applying into an imported 1 × 1 transparent repair layer leaves an out-of-bounds defect unchanged. The New Layer option handled the same repair. Photoshop 2026 pixel comparison and full product retouch acceptance remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-731) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_731.md).

## 2026-11-23 — Step 730 — Preserve Vanishing Point cameras at the canvas size limit

Vanishing Point can now apply a local correction with the default camera on a sparse 300,000 × 300,000 document. The editable archive and authenticated Photato API retain and replay the resolved focal length.

A 300,000 × 300,000 sparse document passed the native preview, Apply, archive reopen, HTTP archive download, and Undo. The API accepted the default camera and replayed the resolved 300,000-pixel focal length. The automatic and explicit camera controls produced the same local composite crop on both optimized slices and in Xcode Debug. Separate core tests cross the 100,000-pixel boundary in both document orientations and retain a calibrated 500,000-pixel focal length.

The automatic-camera edit produced a 2,048 × 2,048 preview in 104 ms on optimized Apple Silicon and 185 ms under Rosetta on this sparse fixture.

The maximum-size fixture is sparse and the correction uses one tile. Editable archives with focal lengths above 100,000 pixels require build 730 or later. Photoshop 2026 opened the reference modal on the owned texture fixture. The app disappeared before a stamp could be applied, so Adobe pixel equivalence remains open. Adobe documents the PSB dimension limit separately from this native workflow.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-730) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_730.md).

## 2026-11-23 — Step 729 — Keep narrow Vanishing Point strokes visible

A narrow perspective stamp can partially cover a row of pixels even when the pixel centers lie outside it. Vanishing Point now renders that coverage for Clone Stamp and Brush, including pixels partly inside a clipped plane.

The default camera projected the failing 48-megapixel fixture to about 0.81 pixels of vertical brush thickness. The repaired fixture paints 20 pixels across two rows, with about 39% opacity near the center. Independent integration matched 36 native depth, hardness and pixel-offset cases within 0.003 normalized opacity. Rotated-plane and plane-clipping checks passed. The native preview and full render agree, and the selected crop matches the authenticated API. The source layer, local Undo, accepted edit, editable archive and document Undo also match. The tested thicker 24-megapixel and fixed-camera 48-megapixel crops retain their previous bytes.

The first edited 48-megapixel overview took 68 ms on optimized Apple Silicon and 109 ms under Rosetta once the source was ready. The overview retains 2,048 × 1,536 display pixels.

Photoshop 2026 opened Vanishing Point on the owned reference image. The UI exposed the dialog and its OK and Cancel controls. The process disappeared before a reference export, so Adobe pixel equivalence remains open. The default camera also reaches a separate save limit above 100,000 pixels on the longer canvas side. Healing modes and Photoshop plane interchange still need qualification.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-729) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_729.md).

## 2026-11-23 — Step 728 — Reuse the editor composite for Vanishing Point previews

Vanishing Point opens from the ready editor composite when it matches the current document. A local correction on a plain top pixel layer updates only its coverage. Apply commits the prepared preview as one editable history step.

The 24-megapixel native canvas kept its full-resolution preview. The 48-megapixel case used a 2,048 × 1,536 overview. Both edited preview buffers matched their independent full renders. Local Undo restored the earlier preview. Apply kept the accepted layer ID, and the authenticated API produced the same selected crop. Protecting the source, native save and reopen, and document Undo also passed.

The first 24-megapixel edit from a cold workspace took 1.49 s on Apple Silicon and 2.88 s under Rosetta. The adjacent build 727 measurements were 2.94 s and 5.26 s. With the editor composite ready, the first 24-megapixel stamp took 519 ms on Apple Silicon. The second edit preview took 1.2 ms. The first edit in the 48-megapixel overview took 64 ms.

The 48-megapixel repair used the same explicit camera projection as the 24-megapixel control. A narrow stamp on the larger fixture with default camera inference produced no sampled correction in builds 727 and 728. Its projected footprint and direct Photoshop output still need qualification. The timings measure software preview publication on one host.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-728) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_728.md).

## 2026-11-23 — Step 727 — Extend perspective texture repair to large canvases

Vanishing Point can repair a selected texture on a full-resolution product image and keep the correction on an editable layer. The plane solver now accepts an off-axis plane whose corner rays all point in front of the camera. The desktop workspace and Photato API share the same edit.

The editable 6,000 × 4,000 repair used two correction tiles. The selected texture matched the 2,048 × 1,536 reference byte for byte. The same selected crop matched in the 48-megapixel overview control and on a sparse 300,000 × 300,000 canvas. The tested native and authenticated API repairs preserved the original layer, editable archive and exact Undo. Their selected composite matched across optimized architectures.

The first 24-megapixel workspace preview took 2.94 s on optimized Apple Silicon and 5.26 s under Rosetta. The Xcode Debug preview took 65.1 s. The separate 48-megapixel control produced a 2,048 × 1,536 overview.

The 300,000 × 300,000 control uses a sparse canvas and a local selected repair. The Photoshop comparison, durable PSD perspective-plane metadata and Stamp healing modes remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-727) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_727.md).

## 2026-11-23 — Step 726 — Keep cropped-layer retouch previews regional

Clone Stamp and Healing Brush now redraw the affected area when a plain, integer-aligned transparent layer grows. The renderer includes both the old and new tile bounds, including when expansion shifts the layer origin. The native editor and authenticated Photato API use the same compositor.

The independent Xcode Debug checks matched raw composites at RGB8, RGB16 and RGB32. The cropped portrait replays matched the saved PNG, editable archive, authenticated API and exact Undo. Each optimized architecture matched all 12 build 725 PNGs across ordinary and cropped correction layers.

The cropped correction layer's first preview took 115–124 ms on optimized Apple Silicon, compared with 498–554 ms in the adjacent build 725 run. A scripted 48-sample cropped-layer stroke published 42 Clone Stamp and 41 Healing Brush previews. The preceding build published three for each tool on the same fixture.

These measurements cover software rendering and publication of previews. Physical pointer-to-display cadence and direct comparison with Photoshop 2026 remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-726) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_726.md).

## 2026-11-23 — Step 725 — Speed up RGB8 and RGB16 retouch sample conversion

Photato converts allocated tiles when a bounded sRGB raster changes to 8 or 16 bits per channel. Clone Stamp and Healing Brush use the faster conversion when preparing samples for a stroke. The desktop and authenticated Photato API share that conversion.

On the 2,096 × 2,592 portrait, the Apple Silicon depth conversion took 119 ms for RGB8 and 117 ms for RGB16. The former scalar loop took 194 and 193 ms. Every raw sample word matched at both depths on both optimized architectures. Each architecture matched all 12 build 724 PNGs across ordinary and cropped correction layers. Preview, commit, editable reopen and authenticated API pixels matched, with one Undo per stroke.

The ordinary New Layer first preview took 117–125 ms on optimized Apple Silicon after source selection. In the adjacent build 724 run it took 181–192 ms. A scripted 48-sample gesture produced 42 Clone Stamp and 41 Healing Brush software previews on an ordinary new layer. The cropped control produced 3 and 3, respectively.

The timings measure software preparation and the first complete preview on one test host. Physical pointer-to-display cadence and direct Photoshop comparison remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-725) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_725.md).

## 2026-11-23 — Step 724 — Reuse the canvas composite for Clone Stamp and Healing Brush

Clone Stamp and Healing Brush can reuse the prepared canvas composite for Current & Below and All Layers. The renderer checks that the cached document matches the requested source and layer cutoff. Source selection, previews and authenticated Photato edits share this sampling path.

On the 2,096 × 2,592 portrait, the optimized Apple Silicon raw sampling step went from 190.2 ms to 0.17 ms with a ready exact composite. Under Rosetta it went from 352.4 ms to 0.22 ms. All source bytes matched. The six optimized portrait edits matched build 723 PNGs exactly. The editor preview, commit and authenticated API output matched. Each repair stayed on an editable correction layer after reopening and could be reversed with one Undo.

With the ordinary New Layer action, Apple Silicon rendered the first preview in 183–192 ms. Using a compact 2 × 2 raster that had to expand, the first preview took 641–682 ms. The normal sparse New Layer raster can update a small region. Depth conversion still took most of its first-frame time. Both layer geometries produced the same tested PNGs.

These tests compare Photato’s output across configurations and against a clean portrait reference. Live Photoshop comparison is still open. Raw sampling time measures a single preparation stage. Actual pointing-device feedback and physical frame cadence remain open. The Clone Stamp still requires the user to match both source texture and tone.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-724) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_724.md).

## 2026-11-23 — Step 723 — Refine hair in Select and Mask

Select and Mask adds Refine Hair for a rough selection or an existing layer mask. Photato recovers soft strand coverage near the subject and keeps it editable. The native workspace previews the result before committing. The optional Photato API uses the same refinement.

The owned patterned-backdrop control recovered 85.0% of missing strand coverage, with 3.5% false coverage in nearby background. Partial-coverage alpha error fell from 0.335 to 0.104. Seven fixtures matched mask and PNG output bytes across Debug, optimized Apple Silicon and Intel under Rosetta. Masks stayed editable through native, PSD and PSB reopen. The independent reader matched stored coverage in both Photoshop file formats.

The measured reference set includes wigs, toy hair, fibers and two controlled backdrops. Darkening the new background can reveal residual color on very fine strands. Complex backgrounds and strands far from the coarse mask still need manual refinement. Live Photoshop comparison and physical VoiceOver and keyboard checks remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-723) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_723.md).

## 2026-11-23 — Step 722 — Keep projected Smart Object edges stable when relinking

Relinking a projected Smart Object to the same source preserves its rendered appearance in the tested PSD and PSB files. The original placement, editable Smart Filters and their mask stay with the layer.

The test moves a linked PSB, opens the document from its saved preview and relinks the same source bytes. Photato matches every rendered byte in the initial cache, resolved link and edited reopen at RGB8, RGB16 and RGB32. A filter-mask stroke and a filter reorder retain separate Undo steps. The authenticated Photato API matches the native rebind and Undo. An independent reader recovered the external filenames, projected corners and filter order in twelve files per configuration. It decompressed the painted filter mask and found the marked center at zero coverage in each edited file.

The verified case uses an unchanged local linked file and two native filters. The outputs compare Photato before and after reopening and relinking. Direct Photoshop comparisons, other deformation geometries and the full Smart Filter and linked-source acceptance workflows remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-722) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_722.md).

## 2026-11-23 — Step 721 — Preserve editable type and RGB32 composites in layered Photoshop files

Layered PSD and PSB exports place the editable text record and its padding before the following protection record. Photato can still open older files written with the uncounted pad. Whole-pixel translations of editable text now render the same way before and after reopening an RGB32 file.

The mixed document keeps editable type and its protection settings, group and pixel masks, an Exposure adjustment, and a projected embedded Smart Object with an editable Gaussian Blur and filter mask. Initial and edited reopens match every rendered RGBA byte at 8, 16 and 32 bits per channel in PSD and PSB. An independent reader recovered the tagged structure in all twelve files per configuration. An independent comparison matched 294,912 stored merged channel words per configuration, including the transparency plane. Authenticated Photato downloads matched the native files byte for byte.

The test uses exact file-representable group opacity. Photoshop files store the group opacity in one byte, so a literal 84% differs from the saved 214/255. These tests use owned input and compare round-trip output with Photato’s own pre-save render. Direct Photoshop reopening, Adobe pixel equivalence, linked asset rebind and broader Smart Filter ordering remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-721) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_721.md).

## 2026-11-23 — Step 720 — Recover partial transparency in product cutouts

Select and Mask can recover partial coverage from a rough selection. Estimate a smooth background or choose an aligned photo of an empty textured backdrop. Erase Refinement restores the input coverage where you brush. Decontaminate Colors removes the backing color and the result can keep an editable mask or export as transparent PNG. The Photato API uses the same workflow.

Four controlled glass and fabric cases compared the exported alpha and the recovered colors over light and dark backgrounds. Partial-alpha mean absolute error fell from 0.589–0.626 to 0.062–0.117. Both backgrounds improved on all four cases. The first aligned reference test showed a visible textured imprint. Using changes in the aligned backing estimated the local transmission and reduced the measurable checkerboard imprint by 88% in the sampled clear interior. Desktop and API exported identical PNGs. Native, PSD and PSB reopened with editable masks and retained the same PNG bytes. One Undo restored each input exactly. The exported PNGs also matched across Debug, optimized Apple Silicon and optimized Intel under Rosetta. The optimized Apple Silicon prepared edit ran in 0.15 seconds on the 1,536 × 1,152 aligned test image.

The four cases use independently generated scalar alpha masks. The recovered glass still has some edge tint and near-opaque coverage errors. The photographic GT03 case from the Rhemann et al. CVPR 2009 matting dataset exceeded the smooth-background limit. The tool asked for an aligned backing, which that photographic input archive lacks. Single-image recovery against complex backgrounds, physical refraction and exact Photoshop behavior remain open. [Matting benchmark](https://static.alphamatting.com/datasets.html)

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-720) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_720.md).

## 2026-11-23 — Step 719 — Review related shadows and reflections before removing them

The Remove processing menu can find shadows and reflections around a marked object using two optional models on Apple Silicon with macOS 26 or later. The canvas shows the reviewed object and each enabled effect. Use the checkboxes or the Add and Subtract brush to refine coverage. Apply creates a correction layer with one Undo. The Photato API shares the same review and edit.

Two licensed photos checked a waste-bin shadow and a vehicle reflection. The first masks left a dark silhouette in each photo. Testing wider masks showed how much overlap was needed and where the review started to touch an unrelated effect. The smaller final margins removed the silhouettes and left the designated neighboring areas and all pixels outside the edit exact. The editor and authenticated API returned equal review masks and rendered RGBA8 bytes on both photos in each Apple Silicon configuration. One Undo restored each original document exactly. The repaired PNGs also match byte for byte across those two configurations.

The vehicle photo also suggested a shadow. The test deselected it before applying. Some grass texture remains soft and the repaired water shows slight color artifacts. Footprints, smoke, steam, water wakes, Adobe’s separate Enhance action and live Photoshop output comparisons remain open. Adobe documents a cloud provider for this feature. The optional Photato models run locally.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-719) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_719.md).

## 2026-11-21 — Step 718 — Use on-device Generative Remove from the brush and API

The Remove brush can use a configured LaMa512 model on Apple Silicon with macOS 26 or later. Generative AI on requires the device model, and Auto can select it for eligible documents. Separated or wide marks use localized repairs and commit in one Undo. Adjacent-edge brush strokes can enclose a corner. The desktop and Photato API share the selection, target, mark geometry and prepared edit.

The on-device model repaired two copies of a photograph in a 12,000 × 9,000 document. All rendered copies were byte-identical in Debug and optimized Apple Silicon. Every sampled unmarked pixel stayed exact. The authenticated API made the same document as the editor, and one Undo restored the source. An independent test used known fill samples to check two distant marks on a sparse 300,000 × 300,000 canvas with both current-layer and transparent correction-layer output. Other tests cover corner closure, blending across repair boundaries, mandatory model failure behavior and native menu availability. The optimized Intel app retained traditional Auto and rejected Generative AI on under Rosetta.

The photo’s repaired grass remains softer than the surroundings. Photoshop 27.2.0 identified itself but its editing controls were unavailable for the comparison. Automatic removal of related effects, cloud Remove processing, the Adobe Execute Actions descriptor and exact Adobe pixels remain open. The 300,000-pixel check used sparse storage and known fill samples.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-718) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_718.md).

## 2026-11-21 — Step 717 — Review and remove general distractions

Remove → Find distractions → General distractions gives you a review before it changes the image. Choose which of the six categories to apply, adjust overlay opacity and refine the marks with the brush. Apply uses the selected raster or a new correction layer and records one Undo. The Photato API shares the same review and edit.

The reviewer marked bins in two independent photographs. A sampled point on the neighboring bench stayed outside the first mask. Traditional fill and optional Apple Silicon LaMa512 fill changed only selected-mask pixels. One Undo restored each original. The authenticated API produced the exact same document as the editor with the real model on Footpath. The tests cover category-only preview, ordered brush refinement, the current selection, layer output and source sampling. The optimized Intel slice also completed the Footpath workflow under Rosetta with traditional fill. The native detection returned one fewer vegetation mark on that run.

The bin sample retained a mounting post, and a strong cast shadow remained in the Footpath photo. Classification still depends on the scene. General distractions uses the 16-megapixel Remove canvas limit. The explicit Generative AI On mode, byte-exact Photoshop output and the Adobe Execute Actions descriptor remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-717) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_717.md).

## 2026-11-21 — Step 716 — Remove extended wire and cable runs in one edit

The Remove tool’s Find distractions menu can remove extended wire and cable runs in one undoable edit. Photato can edit the selected raster or create a transparent correction layer, and the current selection continues to protect pixels. The Photato API uses the same prepared Swift edit and history.

The desktop and authenticated API produced the same document and one Undo restored the original. A 4,200 × 4,000 layered fixture processed beyond the old manual Remove limit. Four synthetic controls preserved all samples more than two pixels from the annotated wires. The repaired wire regions averaged less than two RGB8 levels of error per channel against known clean artwork. Three original-resolution photographs preserved all 1,324,130 checked roof, moon and tower pixels. The Apple Silicon and Intel results matched all 192,426,240 decoded RGBA bytes across the seven examples. A selected-region correction reopened with both raster layers and the same composite in Photato, PSD and PSB. The wider path restored all 6,656 known wide cable samples in the detector fixture without marking its horizon or short trim.

Appearance depends on the scene. Some of the moon photo’s darker fragments and the pylon’s faint wires still need manual cleanup. Camera edges, very wide or short structures, and heavily occluded cables need broader testing. Exact Photoshop wire output, the Adobe Execute Actions descriptor, General distractions and Generative AI On for Remove remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-716) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_716.md).

## 2026-11-21 — Step 715 — Fill a selection from a local reference image

Generative Fill accepts Object and Whole Image references with Swap and Place. The local Paint by Example model generates alternatives inside the editable selection. Place keeps the generated subject on transparency. The Photato API uses the same engine and saved reference context as the editor.

With the same seed and selection, the model used a teapot or orange reference to generate different subjects. The Place example added a teapot beside an existing orange and left 27,222 selected background pixels exact. Every sample outside the selection remained exact in all four owned examples. Photato, PSD and PSB preserved the result and embedded reference. An independent merged preview reader compared 8,388,608 RGBA bytes. Generate More and Generate Similar kept the first saved variation, original reference and mask after a PSB reopen. The editor and authenticated HTTP matched at the same seed.

The optional model requires Apple Silicon and macOS 26 or later and uses a visual reference without text. Place depends on foreground detection and can omit generated shadows. The installed Photoshop 27.2.0 document query timed out. Exact Firefly output, the Adobe Execute Actions descriptor, partner providers, keyboard and assistive-technology checks remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-715) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_715.md).

## 2026-11-21 — Step 714 — Guide Generate Image with Style and Composition references

Generate Image accepts an optional reference. Style transfers colours and textures to the image described by the prompt. Composition uses edges to guide layout during generation. Photato keeps the reference with the editable Smart Object for Generate More and Generate Similar. The authenticated Photato API uses the same edit and history.

Changing only the Composition reference moved the measured orange centre from x=151.5 to x=386.5 in a 512-pixel image. Changing only the Style reference moved mean red minus blue from 0.506 to -0.506. Editor and authenticated HTTP pixels matched exactly at the same seed for both modes. All four owned renders and their embedded reference samples survived Photato, PSD, and PSB reopens. An independent merged-preview reader matched each PSD and PSB to its PNG. Generate More after reopening PSB matched a fresh generation at the same seed and retained the earlier result. The optimized Apple Silicon worker and a signed sandbox harness each reproduced all four outputs byte for byte.

Local models are optional on Apple Silicon with macOS 26 or later. The Style model operates at 224 pixels internally and can soften fine detail. Composition can add objects when edges are ambiguous. The Photoshop 27.2.0 AppleEvent query timed out. Direct Photoshop reopen, Firefly output fidelity, the Firefly ActionJSON descriptor, keyboard and assistive-technology testing remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-714) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_714.md).

## 2026-11-21 — Step 713 — Edit a whole image with local instructions and saved variations

Edit → Prompt to Edit and the canvas action use the selected pixel layer and a text instruction to create alternatives on this Mac. The new editable Smart Object preserves the original layer and source alpha. The original is hidden and can be restored in one Undo. Generate More uses the saved reference. Edit This Variation starts from a chosen result. The Photato HTTP API shares the same edit and history.

The real InstructPix2Pix model delivered identical same-seed pixels through the native editor and authenticated HTTP API. A saved second variation matched the same seed run independently.On a locally generated 512 × 512 still life, a blue-teapot instruction moved the average red-minus-blue value in the sampled pot from 0.879 to −0.775. The model also changed some surrounding colours. Photato, PSD and PSB reopened with both variants and identical rendered bytes. An independent reader compared all 2,097,152 merged RGBA bytes from the PSD and PSB previews to the PNG. A 300,000 × 8 PSB kept the original source, editable placement and exact pixels at both sampled edges.

The local workflow uses the optional 512 × 512 Core ML model on Apple Silicon and macOS 26 or later. Current input support is still RGB and visible root pixel or supported generative layers outside clipping stacks. The installed Photoshop 27.2.0 document query timed out. Direct Photoshop reopening, Adobe model output equality, shared Firefly action descriptors, and live keyboard and assistive technology checks remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-713) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_713.md).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-08.md)
