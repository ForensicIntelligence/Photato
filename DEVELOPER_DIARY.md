# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **804** · The 10 most recent entries, newest first.

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

## 2026-11-28 — Step 799 — Apply ISO-adaptive Camera Raw defaults

Camera Raw can use an XMP preset that varies supported numerical adjustments with the source photo’s ISO. Select it as the master or a camera override. The Sensor panel shows the recorded ISO when available.

Adobe Camera Raw 18.1.1 generated the reference with Exposure 0 at ISO 400 and +2 at ISO 1600. Photato opened the synthetic ISO 800 DNG with Exposure +1. Adobe’s Load Settings command used the fixed top-level values on the Adobe reference. Photato keeps that fixed behavior in its separate Load Settings command.

Adobe documents a midpoint of 5 for Luminance Noise Reduction at ISO 800 when the endpoints are 0 at ISO 400 and 10 at ISO 1600. [Adobe ISO-adaptive preset documentation](https://helpx.adobe.com/lightroom-classic/desktop/help/iso-adaptive-presets.html).

Xcode built the app. All three new tests and nine related tests passed, covering EXIF ISO, endpoint clamping, the documented midpoint, fixed XMP overrides, validation and matching Photato raster samples. Both optimized architectures passed all 374 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Creating adaptive presets from a Photato filmstrip, adaptive categorical adjustments, and byte-identical Adobe RAW output remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-799) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_799.md).

## 2026-11-28 — Step 798 — Set Camera Raw defaults by camera model and body

Camera Raw Settings can apply Photato Default, Camera Settings or an XMP preset to new RAWs. Rules can match a model or a specific body serial number. Open and Place use the saved choice. Existing sidecar and embedded adjustments take priority.

The signed native app added a camera model from the synthetic Bayer DNG, loaded an XMP preset and opened the RAW with Exposure +1.25. The Sensor panel showed the camera decoder’s 0.9 shadow boost. Cancelling kept the original DNG bytes and created no companion XMP.

Adobe Camera Raw’s documented Raw Defaults include master, model and body overrides, plus presets. Photato exposes the native decoder’s supported sensor defaults under Camera Settings. [Adobe Raw Defaults](https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/acr-raw-defaults.html).

Xcode built the app. All three new focused tests and six related tests passed, covering RAW Open and Place raster equivalence, stored settings, revision conflicts and authenticated upload precedence. Both optimized architectures passed all 371 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Camera Settings still differs from the Adobe reference at 18,044,832 of 18,048,000 Nikon RGB16 samples. Both TIFFs use the same dimensions, RGB16 sRGB profile and 300 ppi and were exported without output sharpening.

ISO-adaptive presets, Adobe camera profiles and byte-identical Adobe RAW output remain open. The built-in batch import workspaces still use their existing import policy.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-798) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_798.md).

## 2026-11-28 — Step 797 — Save a developed image directly from Camera Raw

Command–S opens Save Image from the local Camera Raw source workspace. The same native format controls can save TIFF, JPEG, PNG or PSD with the current adjustments and output settings. The source stays open for further adjustment.

The signed native app saved a 512 × 384 RGB16 sRGB TIFF with Exposure set to +0.75. Cancelling a second save kept the adjustment visible. Closing Camera Raw preserved the DNG and left the directory without an XMP sidecar.

Adobe’s Camera Raw Save Options also exposed JPEG XL, AVIF and DNG. Photato keeps sensor-preserving DNG Copy in the existing settings menu.

Xcode built the app and the focused test verified all four file formats through the native encoder and authenticated API. Both optimized architectures passed all 368 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Rendered JPEG XL and AVIF destinations, output sharpening, installed ICC choices and Adobe RAW pixel and file-byte parity remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-797) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_797.md).

## 2026-11-28 — Step 796 — Speed up exact Camera Raw profile conversion

Photato packs the same opaque RGB input for ColorSync without copying the source raster tile by tile. Hidden RGB and source alpha survive conversion. Opaque output avoids a second pass to restore alpha.

The full Nikon RGB8 Display P3 conversion took 5.71 seconds, down from 11.91 seconds in three alternating arm64 Debug trials. The stored samples and RGBA8 bytes matched the prior Photato path.

Twelve lossless Adobe Camera Raw TIFFs captured the nine synthetic sharpening variants, their baseline, and a separate Nikon pair. An independent TIFF reader found 16,562,956 changed RGB samples in Adobe’s Nikon Screen Standard export. The unsharpened Photato and Adobe Nikon exports differed at 18,044,936 of 18,048,000 RGB samples with the same visible sRGB16, 300 ppi and sizing choices.

Xcode built the app and two focused imaging tests passed, covering historical samples, signed float values, and hidden color. Four workflow and five opening regressions also passed. Both optimized architectures passed all 367 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The timing covers profile conversion in Debug. The Adobe comparison leaves sensor development, sharpening and file-byte equivalence open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-796) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_796.md).

## 2026-11-28 — Step 795 — Set Camera Raw output profile, bit depth, resolution and size

The native Camera Raw panel applies five RGB color profiles, 8- or 16-bit output, independent PPI, and six aspect-ratio-preserving resize modes. The defaults preserve the source interpretation. The selected settings are saved for later opens.

Adobe Camera Raw 18.1.1 exposed those resize modes and separate resolution, color space and depth controls. The signed Photato app took the same 3,008 × 2,000 Nikon source to 1,504 × 1,000, RGB8 Display P3 and 300 ppi. Image Size confirmed 300 ppi in the opened copy. The original NEF and directory contents stayed intact.

Xcode built the app and four new focused Debug tests passed, along with the five earlier opening tests. Both optimized architectures passed all 365 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The recorded checks cover the resulting geometry, profile, depth and PPI. Output sharpening, installed and non-RGB ICC profiles, and byte-identical Adobe output remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-795) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_795.md).
