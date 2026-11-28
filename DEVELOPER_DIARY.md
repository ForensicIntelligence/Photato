# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **777** · The 10 most recent entries, newest first.

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

## 2026-11-27 — Step 773 — Stream editable TIFF layers when saving

Photato writes editable TIFF layers to disk past the former 512 MiB layer limit. Native Save and Save a Copy use the staged writer with either small or paged merged images.

Two little-endian RLE TIFF saves retained 40 editable layers. Each carried 628 MB of editable layer data. An independent reader matched all 614.4 million authored RGB and opacity samples on each file, and Photato reopened both with layer names, positions and visibility intact. Sixteen small layered TIFF variants were identical between file and Data output and reopened with their saved selections.

Xcode built the native app. All 12 focused imaging and 8 app and HTTP tests passed. Both optimized architectures passed all 248 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

The capacity controls cover classic TIFF with editable RGB8 layers. Near-limit files, unsupported Photoshop descriptors, tiled input and broader direct Photoshop comparisons still need qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-773) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_773.md).

## 2026-11-27 — Step 772 — Open larger editable TIFF layer data

Photato can open classic TIFF files with editable Photoshop layer data above the previous 512 MiB limit. It reads the layer samples in bounded ranges and keeps the original layers editable.

Two independently built 12,000 × 12,000 TIFFs each contained 576 MB of editable layer data. Photato restored the authored RGB and opacity samples in both byte orders. On these sparse fixtures, the standalone native decoder peaked at 7.2 MiB for big endian and 7.6 MiB for little endian. Two further controls retained their 300 ppi setting, TIFF description and XMP title.

Xcode built the native app. All 10 focused imaging and 7 app and HTTP tests passed. Both optimized architectures passed all 246 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

This checkpoint removes the input limit for the tested layer container. Larger layer payloads when saving, unsupported Photoshop descriptors, additional TIFF layouts and broader byte comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-772) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_772.md).

## 2026-11-27 — Step 771 — Keep named selections in large layered TIFFs

Large layered RGB8 TIFFs now keep named selections alongside editable layers, layer masks and composite opacity. A saved channel can be loaded as a selection after reopening the file.

Photato reopened an 11,000 × 10,000, 660 MB TIFF with both named selections, their channel IDs, two editable layers and a local layer mask. An independent parser checked all 220 million saved-selection bytes and all 110 million opacity bytes. In two Photoshop captures, all 6,144 authored selection samples matched, with and without a separate opacity sample.

Xcode built the native app. All 10 focused imaging and 6 app and HTTP tests passed. Both optimized architectures passed all 245 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

The new evidence covers classic stripped RGB8 TIFFs with named non-spot channels. Larger embedded layer payloads, additional channel types and depths, tile layouts, JPEG-in-TIFF and BigTIFF still need qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-771) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_771.md).

## 2026-11-27 — Step 770 — Stream larger RGB TIFF files through Open and Save

Photato opens supported large classic RGB8, RGB16 and RGB32 TIFF strips as ordinary editable RGB rasters and writes large copies through bounded regions. The files retain working profiles and the selected transparency behavior.

A 9,000 × 8,000 RGB16 control opened above 512 MiB, saved as a 576 MB TIFF and reopened with its ICC profile and measured opacity samples. An independent parser matched all 288 million packed color and alpha words against the authored raster and established document encoder samples. Focused RGB8, RGB16 and RGB32 packing checks compare standard and Display P3 profiles, profile embedding and transparency choices against the established encoder.

The native Xcode target built and all three new imaging and six selected app/HTTP tests passed. Both optimized architectures passed all 241 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

The checks cover selected classic RGB strip inputs and output. Large saved auxiliary channels, component tiles, JPEG-in-TIFF, BigTIFF and complete Photoshop sample and storage comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-770) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_770.md).

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
