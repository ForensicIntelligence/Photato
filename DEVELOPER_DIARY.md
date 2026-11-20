# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **635** · The 10 most recent entries, newest first.

## 2026-11-19 — Step 635 — Print a selection from a large document

The desktop and authenticated PDF route can prepare a small selection from a sparse document at the maximum canvas dimensions.

All 1,166 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-635) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_635.md).

## 2026-11-19 — Step 634 — Print native CMYK and saved spot separations

Print and the authenticated PDF download create named process and spot pages for eligible CMYK, Duotone and Multichannel artwork.

All 1,163 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-634) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_634.md).

## 2026-11-19 — Step 633 — Return standard Multichannel plates to editable CMYK

Returning a standard ordered process set to CMYK keeps extra plates as editable spots. Eligible PSD and PSB files retain the merged process values through the round trip.

All 1,139 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-633) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_633.md).

## 2026-11-19 — Step 632 — Keep native CMYK and Lab components when flattening to Multichannel

Eligible layered CMYK and Lab documents preserve their numerical components through the Multichannel conversion and Delete Channels, including independent black ink.

All 1,136 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-632) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_632.md).

## 2026-11-19 — Step 631 — Preserve spot inks in Multichannel Photoshop files

Multichannel PSD and PSB output preserves saved spot inks as printing plates, including their density, swatch, Solidity and identifier.

All 1,133 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-631) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_631.md).

## 2026-11-19 — Step 630 — Keep Workflow Guide highlights visible across controls and dialogs

The Workflow Guide moves clear of a covered target. Its lessons highlight specific dialog fields and buttons and accept Show Me to replay the cue.

All 1,130 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-630) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_630.md).

## 2026-11-19 — Step 629 — Keep saved masks and printing plates in one Multichannel order

The Channels panel can place masks before or between printing plates. Photato archives, PSD and PSB preserve the same sequence.

All 1,129 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-629) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_629.md).

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
