# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **792** · The 10 most recent entries, newest first.

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

## 2026-11-27 — Step 786 — Open Camera Raw sidecar and embedded XMP settings

File Open and Place Embedded now read a same-name RAW XMP sidecar. If there is no usable sibling, Photato uses supported settings embedded in the source. The resulting RAW Smart Object retains the original sensor bytes and the chosen settings.

Photoshop Camera Raw 18.1.1 loaded the embedded DNG at Exposure +0.75 and Contrast +21. With a partial sibling it loaded Exposure +1.25 and left Contrast at the default 0. The sandboxed Photato app opened the same RAW file, selected by itself in the file picker, and reproduced that settings precedence.

Xcode built the native app. All 3 focused workflow and authenticated HTTP tests passed. Both optimized architectures passed all 332 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

This compares opening settings and retained RAW source bytes. Pixel-level Camera Raw equivalence, writing settings back to DNG, automatic sidecar writes, and broader sensor models remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-786) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_786.md).

## 2026-11-27 — Step 785 — Read and write Camera Raw XMP settings

Camera Raw Load Settings accepts XMP presets for sensor RAW and rendered RGB. Save Settings includes Camera Raw XMP and Photato JSON. XMP applies supported fields to the current draft, with preview and Undo. The sensor source remains editable and its original bytes are preserved.

Adobe Camera Raw 18.1.1 loaded both Photato presets. On the DNG the sensor white balance was 6800 K with tint −4 and Exposure +1.25. The rendered example retained Exposure −0.35 and relative temperature +31 and tint −24. Adobe re-exported 75 matching fields, including a custom curve point and vignette style. It omitted eight inactive subcontrols.

Xcode built the native app. All 5 focused workspace and authenticated HTTP tests passed. Both optimized architectures passed all 329 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The comparison covers settings values. Adobe and Photato rendering, automatic same-name sidecars, DNG-embedded settings, color profiles and local masks need separate testing and support.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-785) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_785.md).

## 2026-11-27 — Step 784 — Keep active Quick Mask in layered TIFF

Lossless layered TIFF and BigTIFF now reopen in Quick Mask mode when the mask was active at Save. The temporary mask stays editable. Composite opacity, saved alpha and spots retain their independent controls.

All 20,962 independent RGB16 auxiliary samples matched the Adobe references through both classic and BigTIFF saves. In a separate test, both apps opened a 19,000 × 19,000, 4.34 GB layered RGB16 BigTIFF with two editable raster layers, one saved alpha and one spot channel. LibTIFF verified distant strip samples and a first directory beyond 4 GiB.

Xcode built the native app. All 8 focused imaging and 5 focused app and HTTP tests passed. Both optimized architectures passed all 303 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The active Quick Mask comparisons cover owned RGB16 references with and without composite opacity. Flattened copies omit the temporary mask. Whole-file equality, other Photoshop color and depth combinations, and a multi-gigabyte editable layer payload still need independent comparison.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-784) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_784.md).

## 2026-11-27 — Step 783 — Match Photoshop RGB16 TIFF white-matte samples

Save Transparency off now uses Photoshop’s RGB16 working grid for aligned Normal raster layers. Layer opacity is promoted before compositing. The white matte is applied to the merged image, and layered output keeps the original editable RGB16 pixels and opacity.

Independent libtiff decoding matched all 82,557 distinct RGB16 samples in two Photoshop 27.2 patterned files and the earlier spot-only copy. The latter also matched all 2,881 spot samples. The patterned files match through classic and BigTIFF output, including the tested planar ZIP variant. A separate opaque Debug benchmark saved byte-identical files and took 15.60 seconds versus 25.62 seconds on the same host.

Xcode built the native app. All 7 focused imaging and 4 focused app and HTTP tests passed. Both optimized architectures passed all 301 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The measured path covers aligned Normal RGB16 raster layers without masks. Other blend modes, masks, transformed or grouped layers, and full Photoshop file serialization still require independent comparison.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-783) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_783.md).
