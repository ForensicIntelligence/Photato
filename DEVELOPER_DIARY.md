# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **613** · The 10 most recent entries, newest first.

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

## 2026-11-19 — Step 607 — Choose sparse Photoshop layer samples across the canvas

The editable 300,000 × 300,000 RLE PSB with paint across its first row reopened in 1.72 s on Apple Silicon and 2.70 s under Rosetta. All raster bits matched. Its 4,690 retained tiles occupied about 293 MiB.

The raw and mixed-compression controls each went from 8,911 mapped tiles to 21. Row inspection preserved the live cursor and continued to reject malformed input in both PSD and PSB. All 940 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-607) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_607.md).

## 2026-11-19 — Step 606 — Reopen sparse editable PSB raster layers

Photato reopened the 8.45 GB, 300,000 × 300,000 RGB8 PSB in 1.65 s on Apple Silicon and 2.61 s under Rosetta. Every raster bit matched and six tiles used 384 KiB of mapped sample storage. The independent decoder checked 900,000 layer and 900,000 merged row lengths per architecture, plus 72 sampled channel values.

The 300,000 × 131 RGB8 file went from 14,064 mapped tiles to four. RGB16 and RGB32 PSBs and RGB8 and RGB16 PSDs reopened with every raster bit preserved in the tested deep and legacy fixtures. All 938 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-606) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_606.md).

## 2026-11-19 — Step 605 — Stream repeated rows in sparse PSB files

Photato saved the 11.26 GB editable solid-fill PSB at 300,000 × 300,000 pixels in 3.22 s and reopened it in 2.12 s. An independent reader checked all 1,200,000 merged row lengths and 140 sampled channel values. These were single runs on the same Mac.

The 300,000 × 131 RLE file was byte-identical to build 604. Save time went from 10.97 s to 0.30 s on Apple Silicon and from 17.54 s to 0.34 s under Rosetta. All 932 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-605) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_605.md).

## 2026-11-19 — Step 604 — Reuse wide vector Feather profiles at canvas edges

At 110.25 px Feather, the rounded 300,000 × 300,000 control went from 5,632 rendered patches to 119. Apple Silicon went from 110.45 s to 13.47 s. Under Rosetta it went from 171.10 s to 25.76 s. All 226,872 sampled RGBA words matched the build 603 whole render on each architecture. These are single runs on the same Mac.

All 307,518,180 RGBA words in four complete renders matched build 603 on each architecture. The controls include RGB8, RGB16, RGB32, an inverted group mask, and independent raster and pixel-mask edits. All 924 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-604) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_604.md).
