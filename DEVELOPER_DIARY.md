# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **783** · The 10 most recent entries, newest first.

## 2026-11-27 — Step 783 — Match Photoshop RGB16 TIFF white-matte samples

Save Transparency off now uses Photoshop’s RGB16 working grid for aligned Normal raster layers. Layer opacity is promoted before compositing. The white matte is applied to the merged image, and layered output keeps the original editable RGB16 pixels and opacity.

Independent libtiff decoding matched all 82,557 distinct RGB16 samples in two Photoshop 27.2 patterned files and the earlier spot-only copy. The latter also matched all 2,881 spot samples. The patterned files match through classic and BigTIFF output, including the tested planar ZIP variant. A separate opaque Debug benchmark saved byte-identical files and took 15.60 seconds versus 25.62 seconds on the same host.

Xcode built the native app. All 7 focused imaging and 4 focused app and HTTP tests passed. Both optimized architectures passed all 301 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The measured path covers aligned Normal RGB16 raster layers without masks. Other blend modes, masks, transformed or grouped layers, and full Photoshop file serialization still require independent comparison.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-783) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_783.md).

## 2026-11-27 — Step 782 — Preserve selected channels in flat TIFF copies

Native TIFF Save and Save a Copy offer separate Alpha Channels and Spot Colors checkboxes. Both start checked when present, and either channel type can survive a flattened TIFF or BigTIFF.

Photato saved an RGB16 spot-only copy and kept its layered source open. Photato and Photoshop 27.2 reopened the copy with only the named spot plate. Photoshop also reopened the flattened Float32 BigTIFF with both named channels and its separate opacity sample. LibTIFF matched all 25,929 measured alpha and spot samples exactly.

Xcode built the native app. All 6 focused imaging and 3 focused app and HTTP tests passed. Both optimized architectures passed all 299 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

In the live RGB16 comparison, 5,474 of 8,643 process-color words differed by one code. Quick Mask and dense multi-gigabyte layered interchange also remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-782) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_782.md).

## 2026-11-27 — Step 781 — Keep saved alpha and spot channels in layered TIFF

Layered TIFF and BigTIFF now keep saved alpha and spot plates in RGB, Grayscale, CMYK and Lab. Associated or straight composite opacity stays separate from the named channels. Names, display colors, spot solidity and channel IDs survive Open and lossless Save.

Photoshop 27.2 opened the final Photato RGB8, RGB16 and RGB32 BigTIFFs with both Proof ink and Alpha 2 visible in Channels and with Coating selected in the editable layer stack. LibTIFF independently matched all 17,286 alpha and spot samples, including the Float32 words. Native tests also round-tripped RGB, Grayscale, CMYK and Lab fixtures.

Xcode built the native app. All 5 focused imaging and 2 focused app and HTTP tests passed. Both optimized architectures passed all 297 selected tests, including PSD channel and spot operations. Intel ran under Rosetta. Both slices of the Universal preview rendered offscreen.

Flattened TIFF alpha and spot output, Quick Mask, very large layered files and byte identity for complete Photoshop files remain open. Some rich Photoshop blocks still require big-endian TIFF or PSD.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-781) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_781.md).

## 2026-11-27 — Step 780 — Open dense RGB TIFFs without intermediate planes

Eligible opaque RGB8 and RGB16 TIFFs now stream directly into editable tiles. The same path reads classic TIFF and BigTIFF while keeping the original document bit depth.

A 27,000 × 27,000 uncompressed RGB16 BigTIFF was opened and saved through the native codec. The output directory was beyond 4 GiB. An independent libtiff read verified all 2,187,000,000 components against the quantization measured in Photoshop. All 53,055 TIFF samples in the separate Photoshop 27.2 reference matched Photato exactly. The 4,099 × 521 output files from builds 779 and 780 were byte-identical.

Xcode built the native app. All 5 focused imaging and 2 focused app and HTTP tests passed. Both optimized architectures passed all 274 selected tests, with Intel running under Rosetta. Both slices of the Universal preview rendered offscreen.

The dense test covers a flattened, untagged, interleaved RGB16 image without transparency. Dense layered files, other color modes and profiles, and full-format byte equality remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-780) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_780.md).

## 2026-11-27 — Step 779 — Save BigTIFF files with 64-bit offsets

Use BigTIFF format is available in the TIFF save dialog. Photato writes 64-bit offsets for image strips and pyramid previews while keeping supported TIFF compression, profiles, layers and saved selections.

Photoshop 27.2 opened the layered BigTIFF with the Masked coating layer selected and re-saved the Gray8 BigTIFF losslessly. All 23,091 samples matched. A separate sparse test wrote and reopened a first image directory and image strip beyond 4 GiB. File and Data output matched on the tested layered images.

Xcode built the native app. All 3 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 272 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

The high-offset test used a sparse file. Dense multi-gigabyte composite and editable-layer output and broader Photoshop container comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-779) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_779.md).

## 2026-11-27 — Step 778 — Open BigTIFF files with 64-bit offsets

Photato opens supported BigTIFFs as editable documents. Its native reader uses 64-bit offsets to find strips, rectangular tiles, metadata and supported Photoshop layer records.

Photato and Photoshop 27.2 decoded all 23,091 grayscale samples from a test strip stored at byte 4,295,032,832, beyond the classic TIFF offset limit. The standalone native reader peaked at 19.7 MiB of memory on that sparse file. A separate big-endian BigTIFF matched 141,932 individually authored CMYK16 samples. The tests also compared indexed, bitmap and editable layer records with their classic TIFF references.

Xcode built the native app. All 4 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 268 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

The >4 GiB test used a sparse file with a small image at a high offset. Dense multi-gigabyte pixel and Photoshop-layer payloads, BigTIFF output and broader format comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-778) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_778.md).

## 2026-11-27 — Step 777 — Save JPEG-compressed TIFFs

TIFF Save and Save a Copy can use JPEG compression for opaque RGB8 and Gray8 images. Choose JPEG Quality from 0 through 12. Supported editable layers, profiles, storage orders and optional reduced-resolution previews are preserved.

Independent libtiff decoding opened the three JPEG TIFF outputs. Photoshop 27.2 reopened the grayscale TIFF and both RGB8 files with their editable overlay selected in the RGB cases. Photato produced identical file and Data output for the tested job. Quality settings changed the compressed bytes and the TIFF records the native encoder’s chroma layout. Photato also reopened 1 × 1 with all 13 settings and 30,000 × 33 at three settings.

Xcode built the native app. All 3 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 263 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

JPEG changes the composite samples. Choose lossless compression to keep named selection channels. The exact Photoshop quality curve, JPEG output bytes and decoding differences remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-777) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_777.md).

## 2026-11-27 — Step 776 — Open JPEG-compressed TIFFs

Photato opens opaque Gray8 and RGB8 JPEG-compressed classic TIFFs as editable images. The decoder handles strips, rectangular tiles and separate RGB channels and keeps the original resolution, profiles and supported editable TIFF layers.

All 346,365 color samples from seven authored TIFFs matched the full-file ImageIO TIFF decoder. The five grayscale and explicit RGB fixtures also matched all 207,819 samples from an independent libtiff decode. Photoshop 27.2 opened the grayscale tile and subsampled YCbCr strip references. Against their lossless Photoshop copies, 484 of 23,091 gray samples differed by one code. 65,314 of 69,273 YCbCr-derived RGB samples differed, with a mean of 14.14 and maximum of 123 codes on the high-chroma pattern.

Xcode built the native app. All 3 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 259 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

Photoshop color reconstruction and JPEG IDCT rounding still differ on the measured inputs. JPEG TIFF save, legacy JPEG compression and additional component, density and corruption cases remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-776) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_776.md).

## 2026-11-27 — Step 775 — Save TIFF image pyramids

Save Image Pyramid is available for classic RGB, Grayscale, CMYK and Lab TIFFs. Photato saves three smaller previews alongside the original image and optional editable layers.

The native compact writer matched all 3,945,867 reduced RGB8 samples in three Photoshop 27.2 references, with matching dimensions, density and primary pixels. The staged writer separately matched all 776,832 preview samples on its reference. An Adobe two-pixel control also kept three one-pixel previews. Photoshop opened the Photato wide output at full document dimensions.

Xcode built the native app. All 2 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 255 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

Direct Photoshop sample comparisons cover opaque RGB8. Wider HDR, profile, alpha and component-mode comparisons, Indexed/Bitmap pyramids and complete file-layout equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-775) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_775.md).

## 2026-11-27 — Step 774 — Open tiled TIFFs with native components

Photato opens supported tiled classic TIFFs as editable images. The native decoder retains color components, opacity and profiles and trims the physical tile padding at the image edges.

Independently authored rectangular CMYK16 tiles matched all 141,932 color words and retained 225 ppi. Six more RGB8, Gray16 and RGB32 controls matched all 94,900 authored samples across raw, LZW and ZIP. The checks include both byte orders, interleaved and planar layouts, straight opacity and floating-point prediction.

Xcode built the native app. All 15 selected imaging and 8 app and HTTP tests passed. Both optimized architectures passed all 252 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

TIFF output continues to use strips. Further layered or associated-alpha tile combinations, JPEG-compressed component TIFFs, BigTIFF and wider Photoshop byte comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-774) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_774.md).
