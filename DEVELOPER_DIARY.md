# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **789** · The 10 most recent entries, newest first.

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
