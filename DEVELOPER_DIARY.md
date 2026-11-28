# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **809** · The 10 most recent entries, newest first.

## 2026-11-28 — Step 809 — Browse and edit photos in Camera Raw Grid

Press G to switch the Camera Raw preview to Grid. Double-click a thumbnail to return to Loupe. Both views share selection, ratings, labels, filters and sorting. Grid keeps the adjustments and source information available.

In the native macOS window, three owned DNGs populated Grid. Option–Plus increased the thumbnail size and period hid cell information. Shift-click selected two photos. A 0.75 sensor exposure edit was still present on the second photo after opening it in Loupe.

Grid behavior follows the published Adobe Camera Raw browsing workflow. [Adobe Camera Raw Grid](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Xcode built the app and all twenty focused application tests passed. Both optimized architectures passed all 397 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The live comparison covered Photato’s camera-raw window and the documented Adobe workflow. Developed thumbnails, Stacks, virtual copies, and a live comparison against a Grid-capable Adobe build remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-809) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_809.md).

## 2026-11-28 — Step 808 — Inspect and sort Camera Raw photo metadata

Camera Raw can show a photo’s filename, format, size, camera, lens, capture time, caption and copyright. Sort by capture date, file type, camera or lens without changing the selected photos.

The native workspace sorted two owned DNGs by their actual capture instants across different time zones. Their displayed wall times run in the opposite order. Both originals remained byte-identical after inspection and sorting.

The field list follows Adobe’s Photo Info documentation. [Adobe Camera Raw overview](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/introduction-camera-raw.html).

Xcode built the app. All eighteen focused application tests passed. Both optimized architectures passed all 395 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The tests used owned DNGs and the authenticated HTTP endpoint. Photo Info’s layout and sorting were not compared against Adobe’s newer full Grid workspace. Grid, Stacks and Adobe renderer comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-808) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_808.md).

## 2026-11-28 — Step 807 — Rate and filter Camera Raw photos

The Camera Raw filmstrip can rate, label, sort and filter its photos. Number keys assign stars and color labels. A rating or label can use the existing XMP sidecar or an embedded DNG packet. Rating-only saves preserve Camera Raw adjustments.

Adobe Camera Raw 18.1.1 stored four stars and Red on both selected DNGs. Photato’s native window displayed those marks and filtered out the unmarked photo. A separate embedded DNG round trip wrote the same XMP values and preserved the sensor payload and every developed Photato sample.

The tested XMP values agree with the live Adobe reference. [Adobe Camera Raw keyboard shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode built the app. All sixteen focused application tests passed. The new cases cover filtering, Undo and Redo, clearing an inherited label, retaining unrelated metadata, and the authenticated source-settings save. Both optimized architectures passed all 393 selected cases. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

The native test checked reopening and filtering. The embedded save was verified separately through the native RAW engine. Grid, Stacks and the full Adobe renderer and export-byte comparison remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-807) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_807.md).

## 2026-11-28 — Step 806 — Save multiple developed Camera Raw images

Save Images exports selected photos from the Camera Raw filmstrip to TIFF, JPEG, PNG or PSD. It uses each photo’s saved draft, the current Camera Raw output and the native encoding settings.

Command-S opened the native Save Developed Images chooser. The selected owned RAWs produced two 512 × 384 RGB16 TIFFs. The existing TIFF kept its bytes and the new file received a numbered name. The two original DNGs kept their hashes.

The format bytes were compared with separately encoded Photato files. [Adobe Camera Raw processing and export workflow](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Xcode built the app. Thirteen focused application checks passed. The new cases verify collision-safe desktop output and byte-for-byte TIFF comparisons between the authenticated download and separately encoded outputs. Both optimized architectures passed all 390 selected cases. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

RAW filmstrip ratings, Grid, Stacks and Adobe output comparisons remain open. The authenticated ZIP uses the advertised transfer budget. Desktop export stages each file on disk.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-806) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_806.md).

## 2026-11-28 — Step 805 — Open and synchronize multiple Camera Raw photos

Select several Camera RAW files in File → Open to edit them together. The filmstrip keeps an independent settings draft for each source, applies changed controls to the selection, and copies chosen settings groups from the active photo.

Command-A selected the three owned DNGs. Option-S opened Synchronize Settings, and Command-Option-O opened three editable RGB16 Background tabs. The RAWs and existing sidecar kept their original hashes. The focused tests also check selected-copy pixels, Undo and Redo, and atomic API validation.

The selected and active controls follow the documented Adobe multi-image editing workflow. [Adobe Camera Raw filmstrip](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Xcode built the app. All eleven focused application tests passed. Both optimized architectures passed all 388 selected cases, including the filmstrip and authenticated API checks. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

The filmstrip opens when every selected file is Camera RAW. Batch developed-image export, rating and stacking controls, and the direct Adobe pixel comparison remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-805) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_805.md).

## 2026-11-28 — Step 804 — Apply Dehaze to full-size Camera Raw images

Camera Raw Dehaze now applies to supported sensor images above 36 megapixels. All existing Photato spatial Camera Raw controls have a paged path in this build.

The production RAW development command applied Dehaze to the owned 8,192 × 5,120 DNG with contrast and returned 10,240 mapped tiles. Five inspected RGB samples changed, including adjacent rows across a band boundary. The sampled alpha and all source-file bytes were retained. Using the same native decoder and opening path, a separate build 801 Debug probe retained the full 16,000 × 10,000 sensor and original bytes of a canonical DNG.

The exact comparisons use the existing Photato renderer. Adobe Dehaze and RAW output comparisons remain open.

Xcode built the app. All seven focused core tests passed. The new case verifies every stored sample of positive and negative Dehaze in RGB16 and linear Float32, including a combination with local tone and Detail. Both optimized architectures passed all 386 selected cases, including authenticated capability discovery. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

The camera and RAW layout must be supported at full size by the Apple decoder. The 65,000-pixel side and 512-megapixel area are admission bounds. The installed decoder does not return full-size rasters for the tested canonical DNGs at those two bounds.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-804) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_804.md).

## 2026-11-28 — Step 803 — Apply local tone to full-size Camera Raw images

Camera Raw can adjust Highlights, Shadows, Texture and Clarity on supported sensor images above 36 megapixels. The native processor uses the full image dimensions to choose the filter radii.

The production RAW development command applied all four controls to the owned 8,192 × 5,120 DNG and returned 10,240 mapped tiles. Five inspected RGB samples changed, including adjacent rows across a band boundary. The sampled alpha and all source-file bytes were retained.

The output comparisons use the existing Photato renderer. Adobe tone and RAW output comparisons remain open.

Xcode built the app. All six focused core tests passed. The new test covers RGB16 and linear Float32 with partial alpha, both with and without Detail sharpening. Each stored sample matches the dense Photato renderer. Both optimized architectures passed all 385 selected cases, including authenticated capability discovery. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

Dehaze still has a 36-megapixel limit in this build. The maximum RAW sensor dimensions depend on the Apple decoder.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-803) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_803.md).

## 2026-11-28 — Step 802 — Sharpen and reduce noise in full-size Camera Raw images

The Camera Raw Detail controls can sharpen and reduce luminance and color noise in eligible images above 36 megapixels. The app filters native Float32 scratch planes on disk, using the same edge handling as the dense renderer.

An offscreen run through the RAW development command processed the owned 8,192 × 5,120 DNG with all three Detail controls into 10,240 mapped tiles. Five inspected RGB samples changed, including adjacent rows across a band boundary. The sampled alpha and all source-file bytes were retained. Apple Silicon Release processed the adjustments in 23.46 seconds and reproduced every inspected Debug sample.

The exact comparisons use Photato’s dense renderer as the reference. Adobe comparison remains open.

Xcode built the app. All five focused core tests passed. The new cases compare filter-stage Float32 words and every stored sample of the RGB16 and linear Float32 result. Both optimized architectures passed all 384 selected cases, including authenticated capability discovery. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

Shadows, highlights, clarity, texture and dehaze still use the 36-megapixel limit. The source must be supported at full size by the Apple decoder. Adobe output sharpening is separate from the Detail Sharpening control.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-802) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_802.md).

## 2026-11-28 — Step 801 — Apply vignette and grain to full-size Camera Raw images

Camera Raw can apply Post Crop Vignetting and Grain to images above 36 megapixels. The workspace and Photato API use the same adjustment pipeline.

An offscreen run through the RAW development command processed the owned 8,192 × 5,120 DNG into 10,240 mapped tiles. It changed each of five inspected points, including adjacent rows across a band boundary. The inspected alpha and all original sensor file bytes were preserved.

This change compares the two Photato rendering paths. Direct Adobe comparison still needs controlled vignette and grain references.

Xcode built the app. All three focused core tests passed. The new case compares every sample of paged and dense output for all three vignette styles with grain and partial alpha in RGB16 and linear Float32. Both optimized architectures passed all 382 selected cases. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

Sharpening, noise reduction, shadows, highlights, clarity, texture and dehaze still use the 36-megapixel limit in this build. Camera compatibility and full-resolution admission depend on the Apple decoder.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-801) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_801.md).

## 2026-11-28 — Step 800 — Open and retain large Camera Raw originals

Photato now opens larger camera RAW files and keeps their sensor pixels in disk-backed tiles. Local originals above 64 MiB are snapshotted into a mapped private file. Camera Raw keeps a reduced overview for the dialog and the full sensor data for Open, Place Embedded and edits.

Photato opened both the uncompressed and packed versions of the 8,192 × 5,120 synthetic DNG. The uncompressed source retained all 83,886,726 original bytes. The signed app opened the same file in Camera Raw at full sensor dimensions. The synthetic archive test round-tripped the RAW Smart Object and matching edit samples.

Adobe Camera Raw 18.1.1 opened the owned 42-megapixel reference. Adobe documents a 65,000-pixel side limit and a 512-megapixel area limit. [Adobe Camera Raw limits](https://helpx.adobe.com/in/camera-raw/desktop/get-started/overview-and-setup/introduction-camera-raw.html).

Xcode built the app. All four new focused checks and twelve related checks passed. The tests covered mapped storage, large RAW Smart Object persistence, exact pointwise edit samples, bounded DNG XMP writes API discovery and rejection of reduced decoder output. Both optimized architectures passed all 381 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The 65,000-pixel and 512-megapixel admission bounds still depend on the decoder. The signed app was verified at 41,943,040 pixels. At the published boundaries, Apple reported reduced dimensions for the canonical synthetic DNGs. Photato now rejects those reduced outputs. Spatial Camera Raw adjustments still use the 36-megapixel limit. Adobe RAW pixel and file-byte parity remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-800) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_800.md).
