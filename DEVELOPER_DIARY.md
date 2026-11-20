# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **628** · The 10 most recent entries, newest first.

## 2026-11-19 — Step 628 — Drag channel rows and keep menu cues aligned

Drag an individual channel to duplicate, copy, reorder or delete it. The Workflow Guide follows the actual popup row once AppKit has positioned the menu.

All 1,125 selected tests passed in each configuration. The two signed macOS 14+ archive slices also passed offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-628). [Development notes](PhotoCraftSwift/docs/CHANNEL_DRAG_628.md).

## 2026-11-19 — Step 627 — Integrate Workflow Guide cues with the expanded Channels panel

The validated source combines menu and dialog cues, process-channel deletion, and isolated Sky Replacement wheel input.

A repaired Debug candidate passed 44 targeted cases. A remaining intermittent popup placement issue was resolved before the 628 source qualification.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-627). [Development notes](PhotoCraftSwift/docs/CHANNEL_GUIDE_INTEGRATION_627.md).

## 2026-11-19 — Step 626 — Delete process channels through the Channels panel

Deleting selected RGB, CMYK or Lab components converts the retained separations into editable Multichannel plates. Layered input requests merge consent.

All 29 selected development cases passed, including shared native and HTTP validation.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-626). [Development notes](PhotoCraftSwift/docs/PROCESS_CHANNEL_DELETION_626.md).

## 2026-11-19 — Step 625 — Merge spot ink into the supported process channels

The shared spot-merge command keeps the expected component layout and performs one undoable document edit.

All 29 selected development cases passed. Exact comparison against Adobe-authored physical printing samples remains open.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-625).

## 2026-11-19 — Step 624 — Duplicate channels into the current image or another document

Duplicate Channel uses native numerical samples and the dimensions, depth and channel rules of the destination. The app and API share that path.

All 25 selected development cases passed, including ownership, cancellation and document history.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-624).

## 2026-11-19 — Step 623 — Convert layerless ink documents back to editable image modes

Mode conversion can use the retained native separations and preserves supported large ink rasters. The Image Mode menu and Photato API share the conversion.

The development runs covered exact native component samples, mode round trips and large workspaces. The publication gate is the combined 628 matrix.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-623).

## 2026-11-19 — Step 622 — Resize and crop editable Multichannel plates

Canvas Size, Crop and supported nearest-neighbour geometry retain editable sparse printing plates and saved channel data.

The development run covered native and API geometry plus sparse file round trips. The public cumulative qualification is recorded in 628.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-622).

## 2026-11-19 — Step 621 — Follow native menus and dialogs in the Workflow Guide

The guide follows menu rows and submenus as they open. Supported dialog controls flash automatically, with Show Me available to replay the cue.

The repaired preview passed 11 selected cases, including Duplicate Layer, Save As and an unrelated sheet. A later matrix exposed a popup placement issue repaired in 628.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-621). [Development notes](PhotoCraftSwift/docs/WORKFLOW_GUIDE_HIGHLIGHTS_621.md).

## 2026-11-19 — Step 620 — Keep maximum-size Multichannel printing plates editable

PSB can retain sparse editable spots and masks up to 300,000 × 300,000 pixels. Large Photato archives use format 93.

All 1025 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-620) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_620.md).

## 2026-11-19 — Step 619 — Rank Workflow Guide suggestions and highlight each step

Open Photato > Settings > Workflow Guide to control visibility, launch behavior and the suggestion limit. Choose Show Me while a guide is open to repeat its highlight. Preferences are stored locally.

All 972 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-619) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_619.md).
