# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **617** · The 10 most recent entries, newest first.

## 2026-11-19 — Step 617 — Add the optional Workflow Guide

Open Window > Workflow Guide to browse suggestions for the selected layer, tool or other editor context. The guide runs locally and links to the development diary. The authenticated Photato capability catalogue exposes the same lessons.

All 968 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-617) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_617.md).

## 2026-11-19 — Step 616 — Write native Photoshop separations and Gray32 previews from stored blocks

A two-layer 1,531 × 5,491 Gray32 control matched all 34,060,421 bytes from build 615. Restoring the same sparse layers and writing the file took 274.9 milliseconds in the paired Apple Silicon Debug run, down from 44.80 seconds.

All 964 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-616) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_616.md).

## 2026-11-19 — Step 615 — Keep large Grayscale, CMYK and Lab Photoshop planes sparse

The native file reader opened an independently authored 300,000 × 300,000 Grayscale/16 PSB and matched all 18,432 checked gray and alpha words. The Apple Silicon Debug run took 2.61 seconds and retained 24 KiB of mapped component samples.

Build 614 exhausted a 384 KiB scratch limit on the smaller 1,531 × 5,491 control. Build 615 opened it under that allowance and matched all 19,842 checked words. All 963 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-615) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_615.md).

## 2026-11-19 — Step 614 — Read large ZIP-compressed Photoshop layers and masks as sparse rasters

The native file reader opened an independently authored 300,000 × 128 RGB8 PSB with a ZIP-compressed layer, translated mask and saved alpha. All 36,864 checked component words matched. The Apple Silicon Debug run took 5.48 seconds.

Build 613 reached the 768 KiB scratch limit on the same control. Build 614 read the editable layer, mask and saved alpha into six tiles using 384 KiB of mapped storage. All 962 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-614) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_614.md).

## 2026-11-19 — Step 613 — Import large flattened RGB PSD and PSB without staging all process planes

The native file reader opened a 300,000 × 300,000 flattened RGB8 PSB with transparency and saved alpha in 13.58 seconds in one Apple Silicon Debug run. All 36,864 checked RGBA and 1,024 saved alpha words matched the independent input.

Build 612 reached a 768 KiB scratch limit on the 1,201 × 30,001 control. Build 613 opened it with three RGBA tiles and one saved-alpha tile. All 961 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-613) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_613.md).

## 2026-11-19 — Step 612 — Save large PSD and PSB channels with repeated rows

The file writer and reader round-tripped a 300,000 × 300,000 RGB8 PSB with an editable fill, a saved alpha, a spot channel and Quick Mask. All 15,360 stored alpha and spot samples matched. The 15.48 GB file took 6.95 seconds to write and 16.77 seconds to reopen in one Apple Silicon Debug run.

Independent executions saved the same 1,201 × 30,001 document on 611 and 612. All 7,924,054 output bytes matched. One Debug run took 38.41 seconds on 611 and 37.3 ms on 612. All 960 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-612) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_612.md).

## 2026-11-19 — Step 611 — Import large PSD and PSB saved channels into sparse tiles

The native reader opened a synthetic 300,000 × 300,000 grayscale PSB in 4.22 seconds in one Apple Silicon Debug run. All 9,216 stored alpha samples and both editable grayscale layer samples matched the authored input. The saved alpha used 192 KiB of mapped sample storage.

A smaller 1,201 × 30,001 PSB retained all 10,593 checked alpha samples within a 768 KiB scratch allowance. Build 610 exceeded that allowance. The test set covers RGB8 Raw and PackBits and RGB16 and RGB32 PackBits. All 958 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-611) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_611.md).

## 2026-11-19 — Step 610 — Read saved Photoshop channels without a merged preview

A synthetic sparse 300,000 × 300,000 PSB opened with the exact editable raster in 3.5 ms on Apple Silicon Debug. The reader skipped 270 GB of unused logical raw preview data.

The native reader matched all 4,016 editable-layer and saved-channel sample words across 80 independently assembled PSD and PSB controls. A loopback regression covered Photato import, truncated-input rejection, and both job interfaces. All 957 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-610) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_610.md).

## 2026-11-19 — Step 609 — Set PSD and PSB file compatibility

Always includes a merged preview. Ask prompts during eligible desktop saves. Never skips the preview for RGB8 documents without saved channels. Unattended Ask saves include the preview by default.

All 1,974 PSD and 1,732 PSB placeholder bytes matched across five Adobe controls. Native saves, copy and cancellation passed, along with loopback API saves and downloads for all three settings. All 954 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-609) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_609.md).

## 2026-11-19 — Step 608 — Save full-width sparse raster edits to PSB

The 300,000 × 300,000 RGB8 PSB with paint across the first row saved in 9.20 s on Apple Silicon and 10.40 s under Rosetta. It reopened in 1.78 s and 2.86 s respectively. All authored raster bits matched.

An independent encoder matched all 8,445,600,024 bytes of RLE tables and payloads on each architecture. Separate Apple Silicon RGB16 and RGB32 checks preserved both raster layers and their mask. All 941 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-608) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_608.md).
