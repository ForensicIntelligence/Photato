# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **763** · The 10 most recent entries, newest first.

## 2026-11-27 — Step 763 — Open indexed PNGs with complex transparency

Open now creates an editable RGB8 layer from a PNG palette with partial opacity or multiple transparent entries. The decoder retains straight RGB and all per-pixel opacity. A palette with one or zero fully transparent entries and no partial opacity stays editable as Indexed Color.

All 35 focused imaging tests and ten app and HTTP tests passed in Xcode Debug. Both optimized architectures passed all 223 selected tests. Intel ran under Rosetta.

Photoshop 27.2.0 opened all five owned controls in the same modes as Photato. Independent decoding matched 748 straight RGBA imports and 187 retained indices. The graded-palette Photoshop PNG copy matched all 187 source RGBA samples, including hidden RGB. The second Photoshop PNG copy verified all 187 rendered samples for the unused-opacity control, including the fully transparent pixels outside the visible bounds.

The comparisons cover the tested palette tables and exact decoded samples. Complete PNG container equality and animated indexed PNG import remain open. Photoshop also opened an owned 8,389,632-pixel palette PNG beyond the current Photato restricted PNG limit.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-763) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_763.md).

## 2026-11-27 — Step 762 — Match layered grayscale PNG samples

Saving an eligible layered Grayscale PNG now blends the retained gray and opacity samples directly. The 16-bit calculation promotes layer opacity before composing. Transparent pixels within the visible bounds retain the bottom layer’s gray, and pixels outside those bounds use transparent white.

All 28 focused imaging tests and nine app and HTTP tests passed in Xcode Debug. Both optimized architectures passed all 215 selected tests. Intel ran under Rosetta.

Photoshop 27.2.0 opened four owned three-layer PSDs and saved PNG copies at 8 and 16 bits, each with opaque and transparent base cases. An independent reader compared all 16,384 gray and alpha pairs across standard and Adam7 Photato exports. All pairs matched, including hidden gray. The four noninterlaced exports also matched Photoshop’s filtered scanlines byte for byte. A fifth 16-bit reference distinguished the two half-tie rounding orders at 32 positions. All 128 gray and alpha pairs across its ordinary and Adam7 exports matched.

Complete PNG files differ. Photoshop’s observed profile setting left the reference untagged and the exported files also differ in metadata and compressed IDAT bytes. The numerical check covers aligned Normal layers with a shared profile. Masked or transformed stacks, other blend modes, TIFF and Photoshop merged previews still need separate verification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-762) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_762.md).

## 2026-11-27 — Step 761 — Preserve grayscale PNG samples and profiles

Open retains Grayscale PNG as an editable gray plane with straight opacity. Packed 2-bit and 4-bit values expand to 8-bit. Eligible flat 8-bit and 16-bit Save output retains the exact gray and opacity samples, including hidden gray, along with embedded profiles and declared gamma.

All 36 focused Xcode Debug tests passed. Both optimized architectures passed all 214 selected tests, including the three new Grayscale PNG regressions. Intel ran under Rosetta.

Six independently generated files matched all 1,122 gray/alpha pairs on import. All 2,244 pairs in twelve standard and Adam7 exports matched. A 36-megapixel sparse control preserved the six sampled pairs through PNG and native archive round trips. Candidate 01 discarded declared gamma. The corrected reader retains the color interpretation of all three tested gamma values and the embedded gray ICC control. Layered grayscale still goes through the RGB composite. Its output differs from a diagnostic based on the measured RGB Normal model. Independent Photoshop Grayscale output and complete file equality remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-761) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_761.md).

## 2026-11-27 — Step 760 — Show and hide Vanishing Point edges

Vanishing Point adds a checked Show Edges control in Options with a Command-H binding. Turning it off hides plane borders, grids and idle selection outlines. Selection outlines reappear during a drag. Measurement visibility and grids rendered into the image remain independently controlled.

All five focused Xcode Debug tests passed. Both optimized architectures passed all 210 focused tests, including the new Show Edges regression. Intel ran under Rosetta.

Photoshop 27.2.0 showed Show Edges checked in Vanishing Point with Command-H. The Photato tests cover overlay state. The live Options and keyboard checks remain pending. Independent verification of Photoshop’s grid raster is still open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-760) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_760.md).

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
