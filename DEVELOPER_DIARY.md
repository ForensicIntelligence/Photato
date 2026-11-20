# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **657** · The 10 most recent entries, newest first.

## 2026-11-20 — Step 657 — Place Smart Objects at their source print size

Place Embedded and Place Linked now size artwork from its print resolution and the destination ppi. Resize Image During Place fits oversized artwork after converting to document pixels. The Photato API exposes the same geometry through an explicit physical sizing option.

All 1,463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The live Photoshop comparison remains open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-657) · [Details](PhotoCraftSwift/docs/PLACEMENT_RESOLUTION_657.md).

## 2026-11-20 — Step 656 — Recover linked Smart Objects after moving a folder

PSD and PSB files now keep both linked-file locations. Locate Package Sources can find approved artwork in nested folders after a document moves. Desktop and API operations use the same lookup when updating or packaging the document.

All 1,457 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The live Photoshop comparison remains open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-656) · [Details](PhotoCraftSwift/docs/PORTABLE_LINKED_PATHS_656.md).

## 2026-11-20 — Step 655 — Add General placement preferences

General settings now control automatic fit, the placement transform preview and whether new embedded artwork becomes a Smart Object or a pixel layer. Command–K opens the native General pane. The Photato API exposes the three persistent preferences and explicit pixel-layer placement for new embedded and PDF artwork.

All 1,452 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The direct Photoshop comparison is still open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-655) · [Details](PhotoCraftSwift/docs/PLACEMENT_PREFERENCES_655.md).

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
