# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **769** · The 10 most recent entries, newest first.

## 2026-11-27 — Step 769 — Save and reopen larger classic TIFF files

Supported Grayscale, CMYK and Lab TIFF strips stream through local file Open and Save. Photato keeps the original numerical channels and uses bounded strips for the copy or composite.

A 16,384 × 17,408 Gray16 file opened, saved and reopened through the native file APIs. The source exceeded 512 MiB and libtiff compared all 285,212,672 samples against the rewritten output. The reopened copy retained its embedded color profile. The Xcode tests include a 36-megapixel Gray16 copy, editable CMYK layers and a separate sparse file above 512 MiB.

The Xcode project built and all 47 selected imaging and 14 app and HTTP tests passed. Both optimized architectures passed all 237 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

Supported local classic TIFFs use 32-bit offsets. Larger RGB TIFF streams, tiled component TIFF, BigTIFF, some specialized layered blocks and more Photoshop sample comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-769) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_769.md).

## 2026-11-27 — Step 768 — Open larger grayscale, CMYK and Lab TIFFs

Photato decodes supported classic TIFF strips into editable, file-backed color planes. Gray, CMYK and Lab data retain their original component values and supported precision as well as an RGB display preview.

Independent libtiff comparisons matched 258,014,000 native 16-bit channel words across ZIP, predicted LZW and raw TIFF inputs, including a 6,000 × 6,000 grayscale image and a planar CMYK control. The measured opacity plane was fully opaque in those four comparisons. A rotated Gray8 fixture separately verified associated alpha. An edited 36-megapixel grayscale copy reopened from a Photato archive with its complete edited component data intact.

The Xcode project built and all 44 selected imaging and 13 app and HTTP tests passed. Both optimized architectures passed all 233 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

This checkpoint changes supported classic strip input. The 512 MiB encoded desktop limit, large TIFF output, tiled component TIFF, BigTIFF, layered capacity and independent Photoshop transparency comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-768) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_768.md).

## 2026-11-27 — Step 767 — Preserve the TIFF color profile choice

The TIFF save panel now has an Embed Color Profile checkbox. It follows the document’s profile choice by default and accepts a per-file override. The TIFF writer preserves the sample values with either choice.

An independent decoder matched all 2,048 Gray16 samples with the Photoshop references in four profile cases on each architecture. Tagged and untagged copies also matched those samples when saved through the native Photato panel. The imaging tests cover flat and layered RGB, grayscale, CMYK and Lab, plus Indexed Color without an embedded profile.

The Xcode project built and 39 focused imaging and 12 app, panel and HTTP tests passed. Both optimized architectures passed all 227 selected tests. The extracted Universal preview rendered offscreen on each slice. Intel ran under Rosetta.

The checks establish TIFF profile choice and sample preservation in the tested cases. Photoshop TIFF opacity, whole-file equivalence and larger component TIFF documents are still open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-767) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_767.md).

## 2026-11-27 — Step 766 — Match grayscale TIFF output with transparency off

TIFF Save Transparency off writes the measured white-matted grayscale samples for aligned Normal layers at 8 and 16 bits per channel. Layered TIFF copies keep their editable layer samples and opacities.

Independent decoding matched every grayscale sample in two flattened Photoshop 27.2.0 references. All four flattened and layered Photato comparisons match across Debug, Apple Silicon and translated Intel. The 16 PSD and PSB regression files also agree across those builds.

The Xcode project built and all 37 focused imaging and 11 app and HTTP tests passed. Both optimized architectures passed all 226 selected tests. The extracted Universal preview rendered offscreen on each slice. Intel ran under Rosetta.

The independent TIFF comparison covers decoded grayscale samples. TIFF with Save Transparency on, complex blends, very large component output and whole-file equality with Photoshop remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-766) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_766.md).

## 2026-11-27 — Step 765 — Match grayscale PSD and PSB previews

PSD and PSB now compose the merged preview from native gray samples on aligned Normal layers at 8 and 16 bits per channel. The preview is white-matted when the composite has transparency. Opaque composites omit the merged opacity plane. Save retains the original editable layer samples and opacities.

Four Photoshop 27.2.0 PSD saves cover opaque and transparent stacks at both depths. An independent decoder matched every merged sample in the Photato PSD and PSB files with Raw and RLE encoding. The 16 comparison files match byte for byte across Debug, optimized Apple Silicon and translated Intel.

The Xcode project built and all 37 focused imaging and 11 app and HTTP tests passed. Both optimized architectures passed all 226 selected tests. The extracted Universal preview rendered offscreen on each slice. Intel ran under Rosetta.

The Adobe comparisons cover the merged previews of the tested layer stacks. Whole-file equality, Adobe’s layer bounds and Gray16 rounding on re-save, and grayscale TIFF opacity remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-765) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_765.md).

## 2026-11-27 — Step 764 — Open larger PNG palettes as editable RGB

Open can now expand larger PNG palettes with partial opacity or multiple transparent entries into editable RGB8. The importer streams packed scanlines to scratch storage and builds file-backed RGB tiles. It handles standard and Adam7 layouts and applies EXIF rotations.

All 36 focused imaging cases and eleven app and HTTP cases passed in Xcode Debug. Both optimized architectures passed all 225 selected tests. Intel ran under Rosetta.

Photato had rejected the 8,389,632-pixel palette control. Photoshop 27.2.0 opened it in RGB8. The revised Photato reader matched all 8,389,632 original straight RGBA samples in an independent replay. The sparse 36,006,000-pixel Adam7 test retained all sampled colors and opacity. The EXIF rotation test kept the canvas file-backed and moved the tested pixels to their expected positions. Photoshop’s PNG copy preserved all visible color and opacity in the 8.39-megapixel control. Its save normalized hidden RGB at 8,192 fully transparent positions. Export container equality remains open.

The new path applies to palettes that require RGB expansion. Editable Indexed Color and Bitmap still use their existing size limit. Maximum-size dense imports and animated PNG remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-764) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_764.md).

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
