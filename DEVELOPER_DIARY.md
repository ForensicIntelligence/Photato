# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **796** · The 10 most recent entries, newest first.

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

## 2026-11-28 — Step 794 — Open Camera Raw files as images, Smart Objects or copies

Camera Raw offers Open Image, Open Object and Open Copy. Image and Copy create an editable Background. Object retains the embedded sensor data and editable development settings. Image and Object save source settings using the current file policy. Copy leaves the original and its sidecar intact.

Photoshop 2026 with Camera Raw 18.1.1 and the signed Photato test app opened identical Nikon inputs as 3,008 × 2,000 RGB16 documents. Command–O and Shift–Command–O saved +1.00 and +0.75 Exposure to matching sidecars. Option–Command–O opened +1.50 with no sidecar. All original NEF bytes stayed identical.

Xcode built the app and all five focused tests passed. Coverage includes exact stored RGB16 samples, current integer raster rounding, aborting a stale source write, protected original files, and authenticated API behavior. Both optimized architectures passed all 361 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Photoshop output ICC, dimensions, sharpening, and full pixel/file equivalence remain open. Photato’s current RGB16 compositor applies integer Normal rounding to Background layers, while eligible RAW objects can retain the original decoded values.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-794) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_794.md).

## 2026-11-28 — Step 793 — Reuse the decoded sensor in Camera Raw

Repeated RGB adjustments can reuse the native sensor raster from the current Camera Raw workspace. Open and OK can reuse those samples before applying the same development command and document color conversion.

Three full Nikon D70s arm64 Debug trials measured median command preparation of 2.64 seconds with the same sensor raster and 6.38 seconds with a fresh decode. The processed command output, Float32 composite, and RGBA8 display bytes matched. The signed app made two exposure changes and opened the result as a 3,008 × 2,000 RGB16 document with the original NEF embedded.

Xcode built the app and all three focused app tests passed, including color-managed masked output, exact cache key requirements, cancellation and history. Both optimized architectures passed all 356 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The benchmark covers command preparation in Debug. The first sensor decode and edits to sensor controls still require Core Image processing. Rendered Adobe equivalence and the 60 fps editing target remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-793) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_793.md).

## 2026-11-28 — Step 792 — Faster Camera Raw exposure and color temperature

The Camera Raw engine applies exposure, relative color temperature and tint together in one tile pass for eligible RGB8 and RGB16 images. It reuses exact gain calculations for integer sample codes and evaluates other retained samples with the original arithmetic.

The same Nikon exposure test took 6.38 seconds for RAW develop command preparation, compared with 13.93 seconds in build 791’s arm64 Debug probe. The full preview buffers matched byte for byte. The signed app opened the adjusted Nikon as a 3,008 × 2,000 RGB16 document with its embedded RAW intact. Closing without saving preserved the source.

Xcode built the app and both focused core tests passed. They cover every RGB8 and RGB16 sample code, archived raster tiles, alpha, and legacy off-grid values. Both optimized architectures passed all 353 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The timings cover command preparation in Debug. Rendered Adobe equivalence and broad real-time editing remain open. RGB32 and multi-stage settings retain the existing development path.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-792) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_792.md).

## 2026-11-28 — Step 791 — Faster Camera Raw preview compositing

Camera Raw reuses the decoded pixel tiles when an opaque, full-canvas RAW layer has an identity transform and Normal blending. The native compositor preserves the same Float32 sRGB values.

The adjusted 3,008 × 2,000 Nikon preview’s composite stage took 0.54 seconds versus 11.35 seconds with the prior full compositor in one arm64 Debug probe. The comparison covered every Float32 sample and the complete RGBA8 display buffer. Native testing opened the Nikon, changed Exposure, generated a preview and cancelled without altering the original file.

Xcode built the app and both focused imaging tests passed. Both optimized architectures passed all 351 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The measurement isolates compositing. Native decoding, exposure processing, display conversion and end-to-end interactive latency still need improvement. Exact Adobe output and physical Intel qualification remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-791) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_791.md).

## 2026-11-28 — Step 790 — Camera Raw DNG storage preferences

Camera Raw settings now control whether a local DNG writes XMP inside the source, writes a sibling, or opens and saves embedded settings while leaving the sibling alone. The default honors an existing companion before saving settings in the DNG.

The installed Adobe Camera Raw 18.1.1 File Handling panel exposed the three DNG Sidecars choices and selected embedded XMP by default. The signed Photato replay wrote +1.75 to a new sibling and kept the DNG byte-identical. The embedded-only mode read +0.75 from the DNG despite a sidecar at +2.50. After saving +0.50 in the DNG, the companion and source sensor payload stayed byte-identical. Adobe read Photato’s DNG sidecar at +1.75 and the embedded-only copy at +0.50.

Xcode built the app. Nine focused imaging cases and two app and HTTP cases passed. Both optimized architectures passed all 349 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Embedded preview regeneration, camera-specific defaults, Camera Raw database routing, physical Intel testing and exact Adobe render equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-790) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_790.md).

## 2026-11-28 — Step 789 — Save camera RAW adjustments in XMP sidecars

Camera Raw’s Done button now writes or updates the companion XMP for supported non-DNG originals. Photato keeps the camera file unchanged and retains unrelated XMP metadata. Nikon files with a verified sensor directory decode at full size from both Finder and retained bytes.

Adobe Camera Raw 18.1.1 created a sidecar for the CC0 Nikon D70s reference at Exposure +1.25. Photato read the Nikon at 3,008 × 2,000 pixels, created its own sibling and updated an existing Adobe-authored XMP. Adobe reopened the updated sidecar at Exposure +1.50. The original NEF’s SHA-256 stayed identical and all other top-level Adobe Camera Raw scalar settings stayed the same.

Xcode built the app. Four focused imaging tests and one authenticated HTTP test passed. Both optimized architectures passed all 345 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Camera Raw database and storage preferences, camera-specific defaults, RAW variants unsupported by Apple’s decoder, physical Intel testing and byte-for-byte Adobe render equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-789) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_789.md).

## 2026-11-27 — Step 788 — Save Camera Raw settings in the original DNG

Camera Raw’s Done button now saves changes into a locally opened DNG and closes the editor. If the image opened with an XMP sidecar, Photato embeds its metadata and backs up the sidecar before removing it when required by the sandbox. The source sensor bytes stay intact.

Photato and Adobe Camera Raw 18.1.1 saved Exposure +1.75 in the DNG sidecar test and preserved all 393,216 sensor bytes. Adobe reopened the updated Photato DNG. Photato also retained the separate sensor exposure through its own embedded settings.

Xcode built the app. Three focused imaging tests and one authenticated HTTP test passed. Both optimized architectures passed all 340 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

This covers the tested classic DNG settings. Other RAW sidecar writing, camera-specific defaults and settings databases, DNG preview regeneration, physical Intel testing, and pixel-level Adobe Camera Raw equivalence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-788) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_788.md).

## 2026-11-27 — Step 787 — Save editable Camera Raw settings in DNG copies

Camera Raw can export a DNG copy with supported adjustments embedded as XMP. The copy retains original sensor bytes, and the source stays unchanged.

Camera Raw 18.1.1 opened the Photato copy with Exposure +1.50, Contrast +21, Highlights −17 and Vibrance +9. All 393,216 sensor bytes matched the original and the Adobe-saved file. The sandboxed Photato export matched the tested copy byte for byte.

Xcode built the app. Three focused imaging tests and one real authenticated HTTP test passed. Both optimized architectures passed all 336 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

In-place Done, importing sidecar-only metadata into edited DNGs, general RAW-to-DNG conversion, preview regeneration, Apple-only sensor controls in XMP and exact Photoshop pixel rendering remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-787) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_787.md).
