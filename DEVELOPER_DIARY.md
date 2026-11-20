# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **660** · The 10 most recent entries, newest first.

## 2026-11-20 — Step 660 — Free Transform follows Smart Object artwork

Free Transform handles follow an affine Smart Object's saved corners. Side and corner drags scale along the artwork's axes, and the angle field reads its current rotation. The Photato API exposes the frame and commit delta.

All 1,477 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe handle behavior, displayed scale percentages and output fidelity remain unverified. The Intel runtime used Rosetta, and the macOS 14 minimum was checked in the signed binary.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-660) · [Details](PhotoCraftSwift/docs/ORIENTED_SMART_OBJECT_TRANSFORM_660.md).

## 2026-11-20 — Step 659 — Read the original transform of linked Smart Objects

Properties and Free Transform now use the original geometry of linked artwork when a reopened PSD or PSB has only a cached preview. The Photato API reports the same source transform, rotation and bounds.

All 1,472 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe Properties values, rounding, handle orientation, physical Intel, a macOS 14 runtime and full assistive-technology behavior remain unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-659) · [Details](PhotoCraftSwift/docs/LINKED_SMART_OBJECT_GEOMETRY_659.md).

## 2026-11-20 — Step 658 — Custom Smart Object geometry for template jobs

The Adobe-compatible template API can set Smart Object size, position, rotation, skew and anchor. Jobs can place artwork relative to other layers and change the geometry of a linked PSD without supplying its original artwork again.

All 1,468 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe hosted-service pixels, unobserved geometry defaults, physical Intel and a macOS 14 runtime remain unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-658) · [Details](PhotoCraftSwift/docs/ADOBE_SMART_OBJECT_TEMPLATE_658.md).

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
