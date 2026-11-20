# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **654** · The 10 most recent entries, newest first.

## 2026-11-20 — Step 654 — Place and update gigabyte-scale linked Smart Objects

A 1.18 GB linked PSB passed native and approved API placement, background refresh, repeated packaging, relink, embedding and Undo. Linked native, PSD and PSB outputs matched across both compiled architectures.

All 1,446 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-654) · [Details](PhotoCraftSwift/docs/LARGE_LINKED_ORIGINALS_654.md).

## 2026-11-20 — Step 653 — Preserve Smart Object placement identifiers

Apple Silicon and Intel under Rosetta wrote identical 1,182,448,710-byte PSBs from the same nested edit. Duplicate Smart Filter masks and copied linked previews survive save and reopen.

All 1,407 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-653) · [Details](PhotoCraftSwift/docs/PLACED_LAYER_IDENTIFIERS_653.md).

## 2026-11-19 — Step 652 — Keep gigabyte-scale originals in Undo and Redo

Spilled history states share the existing file-backed original. Undo and Redo keep the bytes, and insufficient disk space rejects the edit atomically.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-652) · [Details](PhotoCraftSwift/docs/GIGABYTE_SMART_OBJECT_HISTORY_652.md).

## 2026-11-19 — Step 651 — Keep gigabyte-scale originals through Edit Contents

A 1.18 GB PSB retains its exact original and editable samples through placement, a nested edit and reopen. Native files use archive version 97 for these originals.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-651) · [Details](PhotoCraftSwift/docs/GIGABYTE_SMART_OBJECTS_651.md).

## 2026-11-19 — Step 650 — Retain large embedded originals on disk

Large PSB originals remain editable in native projects, PSD and PSB. The 275.7 MB test retained two shared instances, and the 525.1 MB file retained its original bytes.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-650) · [Details](PhotoCraftSwift/docs/FILE_BACKED_SMART_ORIGINALS_650.md).

## 2026-11-19 — Step 649 — Place and reopen larger Photoshop originals

PSD, PSB and chunked native Smart Object sources have a local 256 MiB budget. The two previously rejected PSBs retained exact bytes and editable contents, and a 262.5 MB reference passed native and PSB round trips.

All 1,372 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed an offscreen launch. The Debug save-sheet check passed on an isolated rerun after the sheet missed the suite's deadline.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-649) · [Details](PhotoCraftSwift/docs/LARGE_EMBEDDED_ORIGINALS_649.md).

## 2026-11-19 — Step 648 — Keep large embedded sources once

A three-source native save dropped from 201.8 MB to 100.9 MB. The parent PSB and the three original sources kept identical bytes.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-648) · [Details](PhotoCraftSwift/docs/EMBEDDED_SOURCE_RECORDS_648.md).

## 2026-11-19 — Step 647 — Keep large generated Smart Object sources editable

Two large deep-colour Smart Objects keep editable child data in PSD and PSB. Independent checks matched all 134,316,048 child samples.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-647) · [Details](PhotoCraftSwift/docs/EMBEDDED_SMART_SOURCE_647.md).

## 2026-11-19 — Step 646 — Speed up large editable Smart Filter files

The 9-megapixel editable Smart Filter test dropped from 164.4 to 7.2 seconds on optimized Apple Silicon. Three PSD and PSB exports matched the previous Photato codec byte for byte.

All 1,357 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed offscreen launch checks.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-646) · [Details](PhotoCraftSwift/docs/PSD_SMART_FILTER_PAGING_646.md).

## 2026-11-19 — Step 645 — Keep Gradient Overlay editable

Standard Gradient Overlay keeps its stops and placement through PSD and PSB. Six exports of three Photoshop 27.4 RGB8 files matched all 737,280 merged RGBA samples.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-645) · [Details](PhotoCraftSwift/docs/PSD_GRADIENT_OVERLAY_645.md).
