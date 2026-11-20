[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-08.md) · [Next page](part-06.md)

## 2026-11-20 — Step 657 — Place Smart Objects at their source print size

Place Embedded and Place Linked now size artwork from its print resolution and the destination ppi. Resize Image During Place fits oversized artwork after converting to document pixels. The Photato API exposes the same geometry through an explicit physical sizing option.

All 1,463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The live Photoshop comparison remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-657) · [Details](../PhotoCraftSwift/docs/PLACEMENT_RESOLUTION_657.md).

## 2026-11-20 — Step 656 — Recover linked Smart Objects after moving a folder

PSD and PSB files now keep both linked-file locations. Locate Package Sources can find approved artwork in nested folders after a document moves. Desktop and API operations use the same lookup when updating or packaging the document.

All 1,457 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The live Photoshop comparison remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-656) · [Details](../PhotoCraftSwift/docs/PORTABLE_LINKED_PATHS_656.md).

## 2026-11-20 — Step 655 — Add General placement preferences

General settings now control automatic fit, the placement transform preview and whether new embedded artwork becomes a Smart Object or a pixel layer. Command–K opens the native General pane. The Photato API exposes the three persistent preferences and explicit pixel-layer placement for new embedded and PDF artwork.

All 1,452 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The direct Photoshop comparison is still open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-655) · [Details](../PhotoCraftSwift/docs/PLACEMENT_PREFERENCES_655.md).

## 2026-11-20 — Step 654 — Place and update gigabyte-scale linked Smart Objects

A 1.18 GB linked PSB passed native and approved API placement, background refresh, repeated packaging, relink, embedding and Undo. Linked native, PSD and PSB outputs matched across both compiled architectures.

All 1,446 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-654) · [Details](../PhotoCraftSwift/docs/LARGE_LINKED_ORIGINALS_654.md).

## 2026-11-20 — Step 653 — Preserve Smart Object placement identifiers

Apple Silicon and Intel under Rosetta wrote identical 1,182,448,710-byte PSBs from the same nested edit. Duplicate Smart Filter masks and copied linked previews survive save and reopen.

All 1,407 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-653) · [Details](../PhotoCraftSwift/docs/PLACED_LAYER_IDENTIFIERS_653.md).

## 2026-11-19 — Step 652 — Keep gigabyte-scale originals in Undo and Redo

Spilled history states share the existing file-backed original. Undo and Redo keep the bytes, and insufficient disk space rejects the edit atomically.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-652) · [Details](../PhotoCraftSwift/docs/GIGABYTE_SMART_OBJECT_HISTORY_652.md).

## 2026-11-19 — Step 651 — Keep gigabyte-scale originals through Edit Contents

A 1.18 GB PSB retains its exact original and editable samples through placement, a nested edit and reopen. Native files use archive version 97 for these originals.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-651) · [Details](../PhotoCraftSwift/docs/GIGABYTE_SMART_OBJECTS_651.md).

## 2026-11-19 — Step 650 — Retain large embedded originals on disk

Large PSB originals remain editable in native projects, PSD and PSB. The 275.7 MB test retained two shared instances, and the 525.1 MB file retained its original bytes.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-650) · [Details](../PhotoCraftSwift/docs/FILE_BACKED_SMART_ORIGINALS_650.md).

## 2026-11-19 — Step 649 — Place and reopen larger Photoshop originals

PSD, PSB and chunked native Smart Object sources have a local 256 MiB budget. The two previously rejected PSBs retained exact bytes and editable contents, and a 262.5 MB reference passed native and PSB round trips.

All 1,372 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed an offscreen launch. The Debug save-sheet check passed on an isolated rerun after the sheet missed the suite's deadline.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-649) · [Details](../PhotoCraftSwift/docs/LARGE_EMBEDDED_ORIGINALS_649.md).

## 2026-11-19 — Step 648 — Keep large embedded sources once

A three-source native save dropped from 201.8 MB to 100.9 MB. The parent PSB and the three original sources kept identical bytes.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-648) · [Details](../PhotoCraftSwift/docs/EMBEDDED_SOURCE_RECORDS_648.md).

## 2026-11-19 — Step 647 — Keep large generated Smart Object sources editable

Two large deep-colour Smart Objects keep editable child data in PSD and PSB. Independent checks matched all 134,316,048 child samples.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-647) · [Details](../PhotoCraftSwift/docs/EMBEDDED_SMART_SOURCE_647.md).

## 2026-11-19 — Step 646 — Speed up large editable Smart Filter files

The 9-megapixel editable Smart Filter test dropped from 164.4 to 7.2 seconds on optimized Apple Silicon. Three PSD and PSB exports matched the previous Photato codec byte for byte.

All 1,357 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed offscreen launch checks.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-646) · [Details](../PhotoCraftSwift/docs/PSD_SMART_FILTER_PAGING_646.md).

## 2026-11-19 — Step 645 — Keep Gradient Overlay editable

Standard Gradient Overlay keeps its stops and placement through PSD and PSB. Six exports of three Photoshop 27.4 RGB8 files matched all 737,280 merged RGBA samples.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-645) · [Details](../PhotoCraftSwift/docs/PSD_GRADIENT_OVERLAY_645.md).

## 2026-11-19 — Step 644 — Match linked raster previews to saved mask samples

Supported linked RGB8 and RGB16 previews apply the separately quantized Photoshop layer and mask samples. Six file comparisons confirmed the tested output.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-644) · [Details](../PhotoCraftSwift/docs/LINKED_PREVIEW_644.md).

## 2026-11-19 — Step 643 — Open nested Photoshop Smart Objects

An iterative decoder opens nested editable Smart Objects without exhausting the worker stack. The eight-level round trip and the previously failing Execute Actions workflow passed.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-643) · [Details](../PhotoCraftSwift/docs/PSD_NESTED_SOURCES_643.md).

## 2026-11-19 — Step 642 — Read older solid shapes and their pixel masks

Older live solid-fill shapes open as editable layers and keep the separate pixel mask. Both unchanged exports matched the reference layer, mask and preview samples.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-642) · [Details](../PhotoCraftSwift/docs/PSD_LEGACY_SHAPES_642.md).

## 2026-11-19 — Step 641 — Keep rounded rectangles and dashed ellipses editable

PSD and PSB retain supported solid fills, rounded corners and dotted or dashed ellipse strokes. Six independently checked exports retained the tested layer samples and shape records.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-641) · [Details](../PhotoCraftSwift/docs/PSD_ROUNDED_ELLIPSE_641.md).

## 2026-11-19 — Step 640 — Keep Photoshop rectangles editable

Supported axis-aligned RGB rectangles open as editable layers. Photoshop-format tests verified the rendered samples and the retained rectangle descriptors.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-640) · [Details](../PhotoCraftSwift/docs/PSD_LIVE_RECTANGLES_640.md).

## 2026-11-19 — Step 639 — Keep vector outlines when printing

Include Vector Data preserves eligible outline shapes and text in native print and PDF output. An independent PDF check verified the vector paths and raster backdrop.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-639) · [Details](../PhotoCraftSwift/docs/VECTOR_PRINT_639.md).

## 2026-11-19 — Step 638 — Save document print settings with the artwork

Native documents retain committed print settings and hard-proof conditions. Editable PSD and PSB update supported Photoshop Print Information and Print Style fields.

All 1,171 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-638) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_638.md).

## 2026-11-19 — Step 637 — Remember print defaults and restore supported Photoshop settings

Photato remembers accepted native print defaults and restores supported Print Information and Print Style fields when opening Photoshop files.

All 1,171 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-637) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_637.md).

## 2026-11-19 — Step 636 — Fit and clip large prints at their original sample resolution

Photato fits high-resolution photos to paper while retaining original samples, and can prepare just the visible region of a much larger document printed at a fixed scale.

All 1,168 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-636) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_636.md).

## 2026-11-19 — Step 635 — Print a selection from a large document

The desktop and authenticated PDF route can prepare a small selection from a sparse document at the maximum canvas dimensions.

All 1,166 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-635) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_635.md).

## 2026-11-19 — Step 634 — Print native CMYK and saved spot separations

Print and the authenticated PDF download create named process and spot pages for eligible CMYK, Duotone and Multichannel artwork.

All 1,163 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-634) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_634.md).

## 2026-11-19 — Step 633 — Return standard Multichannel plates to editable CMYK

Returning a standard ordered process set to CMYK keeps extra plates as editable spots. Eligible PSD and PSB files retain the merged process values through the round trip.

All 1,139 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-633) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_633.md).

## 2026-11-19 — Step 632 — Keep native CMYK and Lab components when flattening to Multichannel

Eligible layered CMYK and Lab documents preserve their numerical components through the Multichannel conversion and Delete Channels, including independent black ink.

All 1,136 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-632) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_632.md).

## 2026-11-19 — Step 631 — Preserve spot inks in Multichannel Photoshop files

Multichannel PSD and PSB output preserves saved spot inks as printing plates, including their density, swatch, Solidity and identifier.

All 1,133 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-631) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_631.md).

## 2026-11-19 — Step 630 — Keep Workflow Guide highlights visible across controls and dialogs

The Workflow Guide moves clear of a covered target. Its lessons highlight specific dialog fields and buttons and accept Show Me to replay the cue.

All 1,130 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-630) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_630.md).

## 2026-11-19 — Step 629 — Keep saved masks and printing plates in one Multichannel order

The Channels panel can place masks before or between printing plates. Photato archives, PSD and PSB preserve the same sequence.

All 1,129 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-629) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_629.md).

## 2026-11-19 — Step 628 — Drag channel rows and keep menu cues aligned

Drag an individual channel to duplicate, copy, reorder or delete it. The Workflow Guide follows the actual popup row once AppKit has positioned the menu.

All 1,125 selected tests passed in each configuration. The two signed macOS 14+ archive slices also passed offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-628). [Development notes](../PhotoCraftSwift/docs/CHANNEL_DRAG_628.md).

## 2026-11-19 — Step 627 — Integrate Workflow Guide cues with the expanded Channels panel

The validated source combines menu and dialog cues, process-channel deletion, and isolated Sky Replacement wheel input.

A repaired Debug candidate passed 44 targeted cases. A remaining intermittent popup placement issue was resolved before the 628 source qualification.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-627). [Development notes](../PhotoCraftSwift/docs/CHANNEL_GUIDE_INTEGRATION_627.md).

## 2026-11-19 — Step 626 — Delete process channels through the Channels panel

Deleting selected RGB, CMYK or Lab components converts the retained separations into editable Multichannel plates. Layered input requests merge consent.

All 29 selected development cases passed, including shared native and HTTP validation.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-626). [Development notes](../PhotoCraftSwift/docs/PROCESS_CHANNEL_DELETION_626.md).

## 2026-11-19 — Step 625 — Merge spot ink into the supported process channels

The shared spot-merge command keeps the expected component layout and performs one undoable document edit.

All 29 selected development cases passed. Exact comparison against Adobe-authored physical printing samples remains open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-625).

## 2026-11-19 — Step 624 — Duplicate channels into the current image or another document

Duplicate Channel uses native numerical samples and the dimensions, depth and channel rules of the destination. The app and API share that path.

All 25 selected development cases passed, including ownership, cancellation and document history.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-624).

## 2026-11-19 — Step 623 — Convert layerless ink documents back to editable image modes

Mode conversion can use the retained native separations and preserves supported large ink rasters. The Image Mode menu and Photato API share the conversion.

The development runs covered exact native component samples, mode round trips and large workspaces. The publication gate is the combined 628 matrix.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-623).

## 2026-11-19 — Step 622 — Resize and crop editable Multichannel plates

Canvas Size, Crop and supported nearest-neighbour geometry retain editable sparse printing plates and saved channel data.

The development run covered native and API geometry plus sparse file round trips. The public cumulative qualification is recorded in 628.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-622).

## 2026-11-19 — Step 621 — Follow native menus and dialogs in the Workflow Guide

The guide follows menu rows and submenus as they open. Supported dialog controls flash automatically, with Show Me available to replay the cue.

The repaired preview passed 11 selected cases, including Duplicate Layer, Save As and an unrelated sheet. A later matrix exposed a popup placement issue repaired in 628.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-621). [Development notes](../PhotoCraftSwift/docs/WORKFLOW_GUIDE_HIGHLIGHTS_621.md).

## 2026-11-19 — Step 620 — Keep maximum-size Multichannel printing plates editable

PSB can retain sparse editable spots and masks up to 300,000 × 300,000 pixels. Large Photato archives use format 93.

All 1025 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-620) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_620.md).

## 2026-11-19 — Step 619 — Rank Workflow Guide suggestions and highlight each step

Open Photato > Settings > Workflow Guide to control visibility, launch behavior and the suggestion limit. Choose Show Me while a guide is open to repeat its highlight. Preferences are stored locally.

All 972 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-619) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_619.md).

## 2026-11-19 — Step 618 — Save deep RGB Photoshop files without a merged preview

The File Handling preference and explicit Photato API setting apply to eligible native saves, Image Processor output, and file downloads. Adobe v2 continues to write its existing merged preview.

All 970 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-618) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_618.md).

## 2026-11-19 — Step 617 — Add the optional Workflow Guide

Open Window > Workflow Guide to browse suggestions for the selected layer, tool or other editor context. The guide runs locally and links to the development diary. The authenticated Photato capability catalogue exposes the same lessons.

All 968 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-617) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_617.md).

## 2026-11-19 — Step 616 — Write native Photoshop separations and Gray32 previews from stored blocks

A two-layer 1,531 × 5,491 Gray32 control matched all 34,060,421 bytes from build 615. Restoring the same sparse layers and writing the file took 274.9 milliseconds in the paired Apple Silicon Debug run, down from 44.80 seconds.

All 964 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-616) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_616.md).

## 2026-11-19 — Step 615 — Keep large Grayscale, CMYK and Lab Photoshop planes sparse

The native file reader opened an independently authored 300,000 × 300,000 Grayscale/16 PSB and matched all 18,432 checked gray and alpha words. The Apple Silicon Debug run took 2.61 seconds and retained 24 KiB of mapped component samples.

Build 614 exhausted a 384 KiB scratch limit on the smaller 1,531 × 5,491 control. Build 615 opened it under that allowance and matched all 19,842 checked words. All 963 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-615) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_615.md).

## 2026-11-19 — Step 614 — Read large ZIP-compressed Photoshop layers and masks as sparse rasters

The native file reader opened an independently authored 300,000 × 128 RGB8 PSB with a ZIP-compressed layer, translated mask and saved alpha. All 36,864 checked component words matched. The Apple Silicon Debug run took 5.48 seconds.

Build 613 reached the 768 KiB scratch limit on the same control. Build 614 read the editable layer, mask and saved alpha into six tiles using 384 KiB of mapped storage. All 962 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-614) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_614.md).

## 2026-11-19 — Step 613 — Import large flattened RGB PSD and PSB without staging all process planes

The native file reader opened a 300,000 × 300,000 flattened RGB8 PSB with transparency and saved alpha in 13.58 seconds in one Apple Silicon Debug run. All 36,864 checked RGBA and 1,024 saved alpha words matched the independent input.

Build 612 reached a 768 KiB scratch limit on the 1,201 × 30,001 control. Build 613 opened it with three RGBA tiles and one saved-alpha tile. All 961 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-613) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_613.md).

## 2026-11-19 — Step 612 — Save large PSD and PSB channels with repeated rows

The file writer and reader round-tripped a 300,000 × 300,000 RGB8 PSB with an editable fill, a saved alpha, a spot channel and Quick Mask. All 15,360 stored alpha and spot samples matched. The 15.48 GB file took 6.95 seconds to write and 16.77 seconds to reopen in one Apple Silicon Debug run.

Independent executions saved the same 1,201 × 30,001 document on 611 and 612. All 7,924,054 output bytes matched. One Debug run took 38.41 seconds on 611 and 37.3 ms on 612. All 960 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-612) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_612.md).

## 2026-11-19 — Step 611 — Import large PSD and PSB saved channels into sparse tiles

The native reader opened a synthetic 300,000 × 300,000 grayscale PSB in 4.22 seconds in one Apple Silicon Debug run. All 9,216 stored alpha samples and both editable grayscale layer samples matched the authored input. The saved alpha used 192 KiB of mapped sample storage.

A smaller 1,201 × 30,001 PSB retained all 10,593 checked alpha samples within a 768 KiB scratch allowance. Build 610 exceeded that allowance. The test set covers RGB8 Raw and PackBits and RGB16 and RGB32 PackBits. All 958 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-611) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_611.md).

## 2026-11-19 — Step 610 — Read saved Photoshop channels without a merged preview

A synthetic sparse 300,000 × 300,000 PSB opened with the exact editable raster in 3.5 ms on Apple Silicon Debug. The reader skipped 270 GB of unused logical raw preview data.

The native reader matched all 4,016 editable-layer and saved-channel sample words across 80 independently assembled PSD and PSB controls. A loopback regression covered Photato import, truncated-input rejection, and both job interfaces. All 957 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-610) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_610.md).

## 2026-11-19 — Step 609 — Set PSD and PSB file compatibility

Always includes a merged preview. Ask prompts during eligible desktop saves. Never skips the preview for RGB8 documents without saved channels. Unattended Ask saves include the preview by default.

All 1,974 PSD and 1,732 PSB placeholder bytes matched across five Adobe controls. Native saves, copy and cancellation passed, along with loopback API saves and downloads for all three settings. All 954 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-609) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_609.md).

## 2026-11-19 — Step 608 — Save full-width sparse raster edits to PSB

The 300,000 × 300,000 RGB8 PSB with paint across the first row saved in 9.20 s on Apple Silicon and 10.40 s under Rosetta. It reopened in 1.78 s and 2.86 s respectively. All authored raster bits matched.

An independent encoder matched all 8,445,600,024 bytes of RLE tables and payloads on each architecture. Separate Apple Silicon RGB16 and RGB32 checks preserved both raster layers and their mask. All 941 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-608) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_608.md).

## 2026-11-19 — Step 607 — Choose sparse Photoshop layer samples across the canvas

The editable 300,000 × 300,000 RLE PSB with paint across its first row reopened in 1.72 s on Apple Silicon and 2.70 s under Rosetta. All raster bits matched. Its 4,690 retained tiles occupied about 293 MiB.

The raw and mixed-compression controls each went from 8,911 mapped tiles to 21. Row inspection preserved the live cursor and continued to reject malformed input in both PSD and PSB. All 940 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-607) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_607.md).

## 2026-11-19 — Step 606 — Reopen sparse editable PSB raster layers

Photato reopened the 8.45 GB, 300,000 × 300,000 RGB8 PSB in 1.65 s on Apple Silicon and 2.61 s under Rosetta. Every raster bit matched and six tiles used 384 KiB of mapped sample storage. The independent decoder checked 900,000 layer and 900,000 merged row lengths per architecture, plus 72 sampled channel values.

The 300,000 × 131 RGB8 file went from 14,064 mapped tiles to four. RGB16 and RGB32 PSBs and RGB8 and RGB16 PSDs reopened with every raster bit preserved in the tested deep and legacy fixtures. All 938 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-606) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_606.md).

## 2026-11-19 — Step 605 — Stream repeated rows in sparse PSB files

Photato saved the 11.26 GB editable solid-fill PSB at 300,000 × 300,000 pixels in 3.22 s and reopened it in 2.12 s. An independent reader checked all 1,200,000 merged row lengths and 140 sampled channel values. These were single runs on the same Mac.

The 300,000 × 131 RLE file was byte-identical to build 604. Save time went from 10.97 s to 0.30 s on Apple Silicon and from 17.54 s to 0.34 s under Rosetta. All 932 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-605) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_605.md).

## 2026-11-19 — Step 604 — Reuse wide vector Feather profiles at canvas edges

At 110.25 px Feather, the rounded 300,000 × 300,000 control went from 5,632 rendered patches to 119. Apple Silicon went from 110.45 s to 13.47 s. Under Rosetta it went from 171.10 s to 25.76 s. All 226,872 sampled RGBA words matched the build 603 whole render on each architecture. These are single runs on the same Mac.

All 307,518,180 RGBA words in four complete renders matched build 603 on each architecture. The controls include RGB8, RGB16, RGB32, an inverted group mask, and independent raster and pixel-mask edits. All 924 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-604) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_604.md).

## 2026-11-19 — Step 603 — Reuse exact composited tiles under solid vector Feather

The 300,000 × 75 control went from 39 rendered patches to 15. The RGB16 wide-Feather control went from 156 to 111.

The full 300,000 × 300,000 rounded-mask control completed in 6.47 s on Apple Silicon and 13.10 s under Rosetta, with 28 rendered patches. The maximum-size ellipse completed in 64.16 s on Apple Silicon and 113.97 s under Rosetta, with 9,804 rendered patches. The rounded mask at 110.25 px Feather completed in 110.45 s on Apple Silicon and 171.10 s under Rosetta, with 5,632 rendered patches. Across the three composites, all 745,024 RGBA words in 26 sampled regions matched build 602 viewports on each architecture. These are single runs on the same Mac.

All 922 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-603) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_603.md).

## 2026-11-19 — Step 602 — Skip solid pieces of dense feathered vector masks

At 1,000 px Feather, the interior viewport of the maximum-size document needed no scratch transfer, down from 51,595,425 source pixels. The whole 49,155 × 73 wide-Feather control transferred 18,434,046 source pixels, down from 36,890,622.

Whole-mask preparation for the 300,000 × 300,000 control at 110.25 px Feather took 10.39 s on Apple Silicon and 14.14 s under Rosetta. The four checked regions matched all 42,286 coverage words against build 601 viewport output on each architecture. These measurements are single runs on the same Mac.

Ten mask controls matched build 601 across all 10,873,881 Float32 coverage words per architecture. Two additional whole-canvas RGB32 layer stacks matched all 28,706,520 RGBA words per architecture. The controls cover both mask polarities, short and wide Feather through 1,000 px, Boolean holes, partial cells, and near-edge viewports on a 300,000 × 300,000 document. All 920 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-602) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_602.md).

## 2026-11-19 — Step 601 — Render sparse curved Feather from stored coverage

The sparse inverted rectangle control rendered in two patches, down from 36. The distant curved mask on a 300,000 × 300,000 canvas used 46, down from 92. Both controls matched the complete build 600 render.

All 918 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-601) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_601.md).

## 2026-11-19 — Step 600 — Prove RGB32 raster-base opacity with rectangular Feather

The 37.8 MP opaque-base test with 2 px Feather went from 52.80 s to 0.02 s on Apple Silicon and from 69.40 s to 0.02 s under Rosetta. These are single runs on the same host.

The 300,000 × 300,000 opaque-base test at 1,000 px completed in 1.27 s on Apple Silicon and 1.79 s under Rosetta. The narrow and wide opaque controls and the distant inverted-hole control each matched 9,248 sampled Float32 words on each architecture against the corresponding build 599 37.8 MP controls.

All 916 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-600) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_600.md).

## 2026-11-19 — Step 599 — Reuse wide vector-mask Feather windows

The 300,000 × 300,000 stress case with an inverted 1,000 px Feather mask completed in 35.71 s on Apple Silicon and 49.08 s under Rosetta. Build 598 exceeded the 200-second cutoff on Apple Silicon. The new whole-canvas output matched all 11,560 sampled Float32 words of the previous viewport output on each architecture.

All 914 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-599) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_599.md).

## 2026-11-19 — Step 598 — Render whole-canvas rectangular vector masks

A 300,000 × 300,000 document with a rectangular vector mask and a sparse raster edit rendered in 197 tiles in the regression test. The tile index reuses the rendered samples across the canvas. On a 37.8 MP RGB32 control, median whole-canvas render time went from 3.912 s to 0.103 s on Apple Silicon and from 8.245 s to 0.194 s under Rosetta. Each median uses three alternating runs on the same host.

All 912 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-598) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_598.md).

## 2026-11-19 — Step 597 — Reuse window sums during wide mask Feather

Wide Feather reuses the second filter pass’s window sums when they fit a bounded cache. The 1,000 px vector viewport went from 1.001 s to 0.933 s on Apple Silicon. The RGB32 pixel-mask control went from 0.180 s to 0.135 s and the oversize Smart Filter mask from 0.867 s to 0.821 s. These are medians of three alternating runs on the same host. All 1,155 sampled Float32 coverage or output words matched build 596 bit for bit on each architecture across eight vector, raster and Smart Filter cases.

All 909 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-597) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_597.md).

## 2026-11-19 — Step 596 — Reuse source bands during wide mask Feather

Wide Feather reuses source row bands for vector, pixel and Smart Filter masks. The 1,000 px vector viewport went from 1.343 s to 0.995 s on Apple Silicon. The oversize Smart Filter mask control went from 1.483 s to 0.862 s. These are medians of three alternating runs on the same host. All 1,155 sampled Float32 coverage or output words matched build 595 bit for bit on each architecture across eight vector, raster and Smart Filter cases.

All 908 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-596) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_596.md).

## 2026-11-19 — Step 595 — Prepare vector-mask Feather around the viewport

Large-canvas vector-mask Feather limits broad coverage preparation to the viewport and its filter margin. On Apple Silicon, the 15 × 7 viewport through a 24,576 px mask at 1,000 px Feather took 8.506 s in build 594 and 1.367 s in build 595. The 250 px curved control took 6.063 s and 0.206 s.

All 907 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-595) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_595.md).

## 2026-11-19 — Step 594 — Match measured short vector-mask Feather responses

The 1.5 px and 2 px vector-mask Feather settings now reproduce the measured Photoshop step and corner responses. Dense rendering, paged whole-canvas rendering and tiled viewports produced identical alpha words at the tested coordinates.

All 905 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-594) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_594.md).

## 2026-11-19 — Step 593 — Bound vector mask Feather on large canvases

Vector masks accept Feather through 1,000 px and keep their paths editable in native documents, PSD and PSB. The maximum sparse canvas test used four patches, and the native and HTTP settings share the same 1,000 px range.

All 904 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-593) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_593.md).

## 2026-11-19 — Step 592 — Bound Smart Filter mask Feather on large documents

Smart Filter masks accept Feather through 1,000 px and render projected mask regions on sparse large documents. The maximum sparse canvas test updates two distant mask regions. The Properties controls and Photato API use the same limit and retain an editable mask on save.

All 887 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-592) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_592.md).

## 2026-11-19 — Step 591 — Match measured fractional RGB32 Feather schedules

Aligned 32-bit raster masks now use Photoshop’s measured filter schedules at 14 fractional Feather settings. The comparisons cover texture, lines and edges. Apple Silicon matched every sample. The Intel texture comparison found five differences, each one Float32 step.

All 861 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-591) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_591.md).

## 2026-11-19 — Step 590 — Match integer raster-mask Feather stages

Aligned RGB8 and RGB16 raster-layer masks now use integer-rounded Feather stages in rendering and clipping merges. The 34 Photoshop control files cover points, textures and translated masks. An independent reader checked 51,578 native PSD colour words in each test configuration. All matched the saved Apple Silicon Photoshop references.

All 858 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. The independent Photoshop Rosetta capture remains pending.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-590) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_590.md).

## 2026-11-19 — Step 589 — Apply Feather in raster clipping merges and stamps

Merge Clipping Mask, Stamp Group, and eligible Merge Down and Stamp Down commands now use Feather on contributing raster clips. Saved RGB32 layer output matches five Photoshop cases at 250 or 1,000 px on both architectures. The tests also exercise sparse 300,000 × 300,000 documents and verify Undo through the desktop model and HTTP.

All 856 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. The lower-radius Intel comparisons still have differences of up to two Float32 steps.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-589) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_589.md).

## 2026-11-19 — Step 588 — Support layer-mask Feather through 1,000 px

Layer-mask Feather now accepts 0–1,000 px in the native controls, Photato API and editable files. The renderer streams the wide filter. The saved 250 and 1,000 px RGB32 controls match exactly on both tested architectures, and the editable 1,000 px setting survives native, PSD and PSB round trips.

All 850 selected checks passed across the suite and focused recheck in Debug, optimized Apple Silicon and Intel under Rosetta. Fractional settings and other mask geometries still need exact Photoshop comparisons.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-588) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_588.md).

## 2026-11-19 — Step 587 — Match staged RGB32 pixel-mask Feather

Aligned RGB32 layer masks use a staged square filter at whole-pixel Feather radii from 3 to 100 px. It follows the canvas and stored mask edges, including masks that extend outside the canvas. In the app tests, 34,975 coverage samples matched the 21 saved Apple Silicon references exactly. All 844 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta.

Photoshop's 250 and 1,000 px textured controls also match the model. The current app range is 100 px. Fractional radii, a few Intel rounding cases, and the wider control are still in development.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-587) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_587.md).

## 2026-11-19 — Step 586 — Bound pixel-mask Feather rendering

Pixel-mask Feather now renders requested regions on 300,000 × 300,000 documents without preparing a full padded mask. Existing Feather output is preserved across the tested depths and transforms. All 842 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta.

Separate Photoshop tests reproduced the saved 100, 250 and 1,000 px line samples. The two-dimensional Intel results still need investigation before widening the control.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-586) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_586.md).

## 2026-11-19 — Step 585 — Add three arithmetic clipping blend modes

Linear Dodge (Add), Subtract and Divide now work in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel. The HDR checks include masked clips, mixed opacity and translated Divide layers.

All 787 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The tests compare 96 saved Photoshop results per architecture.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-585) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_585.md).

## 2026-11-19 — Step 584 — Preserve pixel masks in clipping merges and stamps

Supported clipping merges and stamps preserve the editable base pixel mask and apply contributing masks at 8, 16 and 32 bits per channel. The tests cover disabled masks, integer offsets, Density and partial clip opacity. Stamp Group and Stamp Down retain the contributing mask on its own layer.

All 782 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. Feather on a contributing mask remains in development.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-584) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_584.md).

## 2026-11-18 — Step 583 — Add four clipped blend modes

Multiply, Darken, Lighten and Difference now participate in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel.

The saved Photoshop comparison matched 62,736 stored sample words per architecture. All 776 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-583) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_583.md).

## 2026-11-18 — Step 582 — Preserve independent clipping in merges and stamps

Supported raster clipping merges and stamps preserve Blend Clipped Layers as Group, the base blend mode, and its opacity. The saved pixels for the tested Multiply cases matched with the underlying backdrop visible or hidden.

The native editor and both local API families share the updated behavior. All 773 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-582) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_582.md).

## 2026-11-18 — Step 581 — Merge and stamp adjacent clipped layers

Merge Down and Stamp Down now work between adjacent Normal raster clips in the same clipping stack. Merge Down keeps the destination clipped and removes the upper layer. Stamp Down keeps both rows and the upper selection.

The stored raster matches the tested 8-, 16- and 32-bit Photoshop outputs. The first ActionJSON expansion found a stack overflow. Reusing the raster-output helper repaired it, and all 769 selected tests passed on each configuration.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-581) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_581.md).

## 2026-11-18 — Step 580 — Match Screen clipping and unchanged stamp history

Screen clips now participate in supported RGB8 and RGB16 merges and stamps. In-place stamps create an Undo step even when the stored pixels stay identical.

The saved-layer comparisons cover 36 Photoshop results. The 12 larger results account for 93,264 exact stored samples. The native editor and both local API families use the same implementation. All 765 selected checks passed in each configuration.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-580) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_580.md).

## 2026-11-18 — Step 579 — Add in-place Stamp Down and Stamp Group

Option-Command-E now stamps into an existing raster when one eligible layer is selected. Stamp Down updates the layer beneath it. Stamp Group updates the base of a supported clipping stack. Both commands preserve the selected layer and the rest of the stack.

The updated raster matched saved 8-, 16- and 32-bit Photoshop references. The native menu, local API, Actions and Undo share the two operations. All 761 selected tests passed in each of the three configurations.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-579) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_579.md).

## 2026-11-18 — Step 578 — Add contextual Merge Clipping Mask

Selecting the base of a supported raster clipping stack now makes Command-E run Merge Clipping Mask. The command combines visible clips into the base and removes the consumed clips. Hidden clips contribute no color. The base keeps its opacity, blend mode and stored geometry, including transparent or off-canvas samples.

The save-and-reopen tests compare 8-, 16- and 32-bit Photoshop reference layers. Undo, Actions and both local Adobe-compatible job routes are covered. All 757 selected checks passed on each of the three build configurations.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-578) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_578.md).

## 2026-11-18 — Step 577 — Preserve stored RGB32 pixel masks when merging and stamping

Normal 32-bit layer output now uses stored pixel masks. The comparison covers saved binary coverage and feathered selections, including transparency and the Intel rounding at tiny alpha values. A small translated mask in a 300,000 × 300,000 document used two render patches.

All 752 selected tests passed in Debug and in both optimized configurations. Both slices of the extracted local validation archive passed their offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-577) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_577.md).

## 2026-11-18 — Step 576 — Match stored RGB32 Normal merge and stamp samples

Merging and stamping 32-bit Normal layers now matches the saved Photoshop samples in the tested raster stacks. These tests cover very low alpha, transparent pixels, partial layer opacity and an opaque Background. A fresh Intel capture also confirmed that its saved alpha differs from Apple Silicon on one older fixture.

The new tests compare the stored layer before and after reopening a PSD. All 750 selected tests passed in each of the three build configurations. Both slices in the local universal archive passed their offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-576) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_576.md).

## 2026-11-18 — Step 575 — Render sparse stamps at maximum canvas size

Stamp Layers and Stamp Visible now skip large empty areas of a sparse document. A 300,000-pixel-square test document with two separated layers used two render patches. The tests covered raster stacks, simple groups, a translucent canvas background and both stamp operations at 8, 16 and 32 bits per channel.

Both ActionJSON job routes matched saved Photoshop layer samples for tagged and untagged files. All 749 selected tests passed in all three build configurations. Both slices of the local universal archive passed their offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-575) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_575.md).

## 2026-11-18 — Step 574 — Add Stamp Layers and Stamp Visible

Stamp Layers combines selected artwork on a new layer. Stamp Visible does the same for visible artwork. Both preserve the original layers and can be undone in one step. Photato exposes the shortcuts in the Layer menu and supports the same operation in recorded Actions and through the API.

The saved Photoshop references match at 8, 16 and 32 bits per channel. The test documents include locked layers, clipping, hidden layers and selections across different groups. All 745 selected tests passed in each of the three configurations. Both slices of the universal validation archive passed their offscreen workspace checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-574) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_574.md).

## 2026-11-18 — Step 573 — Match HDR Normal rounding at the Float32 underflow boundary

On Intel, very small color contributions can disappear during 32-bit Normal compositing. Photato now matches the measured rounding, including products just below the smallest normal Float32 value. The Apple Silicon build keeps its fused calculation.

The new tests compare 57,504 straight color and alpha words with separately saved Photoshop results on each architecture. An ordinary opaque source that covers the canvas retains its original colors over uniform backdrop alpha. Grouped clipping can preserve those colors even when the base alpha varies. All 708 selected tests passed in all three configurations. The local universal archive passed both offscreen workspace checks. The translucent test also exposed a difference in Merge Visible that remains open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-573) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_573.md).

## 2026-11-18 — Step 572 — Match Intel HDR Normal layer and group compositing

Photoshop's Intel build rounds the multiply and add separately when compositing 32-bit Normal layers. On Apple Silicon it uses a fused operation. Photato now follows those results for color, alpha and the opacity of supported groups. The tests use separately captured Photoshop results for each architecture.

The tested results match 264,192 Photoshop sample words on each architecture. That includes the masked Display P3 conversion that differed on Intel in build 571. All 705 selected tests passed in each configuration. Independent HDR clipping still differs.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-572) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_572.md).

## 2026-11-18 — Step 571 — Fix HDR PSD and PSB compression for Photoshop

Photoshop was reading plain ZIP as predicted ZIP on 32-bit layers. This could corrupt HDR colors when opening a PSD or PSB exported by Photato. New exports use the prediction expected for those layers. ZIP requests for the merged preview write raw data because Photoshop refused ZIP in that section. Photato still reads its older files.

Photoshop opened the tested files on Apple Silicon and Intel under Rosetta. The saved 32-bit grayscale samples match across both formats and save encodings. All 694 selected tests passed in each of three build configurations. The local universal archive passed both offscreen workspace checks. A separate mismatch remains in the Intel masked merge.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-571) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_571.md).

## 2026-11-18 — Step 570 — Preserve the working profile when merging before conversion

Merging eligible RGB layers before an Image Mode change now uses their working-profile samples. If the composite is already a single full-canvas layer, the conversion uses its original color and alpha planes. The existing Normal merge routine handles integer rounding for supported RGB stacks before promotion to 32 Bits/Channel.

All 35,840 words in the three valid Photoshop references match on each optimized architecture. All 678 selected tests passed in each build configuration. The two external HDR merge cases still need readable references.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-570) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_570.md).

## 2026-11-18 — Step 569 — Match HDR grayscale conversion and ICC gamma boundaries

32-bit RGB documents now convert to the default linear gray space using the measured source primaries. Promotion to 32 Bits/Channel uses the measured boundaries for fixed-point ICC gamma curves.

All 8,510,976 samples in 257 tested precision promotions and 194,560 samples in 38 RGB32-to-Gray32 cases match Photoshop on each architecture. All 661 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta.

Follow-up testing measured 4,410 rounding thresholds for 16-bit grayscale. Separate Float32 luminance products ordered all of the samples correctly. A 4,096-interval curve fits the measured thresholds, but its exact endpoint calculation remains open. Build 569 continues to use ColorSync for this conversion.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-569) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_569.md).

## 2026-11-18 — Step 568 — Match half-gamma promotion and Gray32 PSD layer stacks

RGB and grayscale gamma 0.5 profiles now promote to 32 Bits/Channel using the measured rounding on each architecture. PSD and PSB use native gray samples for supported 32-bit layer stacks.

All 2,142,336 stored samples from 59 tested conversion cases match the corresponding Photoshop files on each architecture. Five Gray32 layer stacks match all 960 merged words under each of four compression modes in PSD and PSB. All 657 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-568) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_568.md).

## 2026-11-18 — Step 567 — Use the source tone curves for 32-bit RGB and Gray

Promoting an 8-bit or 16-bit RGB or grayscale document to 32 bits now uses the supported tone curves from its current ICC profile.

All 1,976,832 samples from 54 supported cases match the files saved by Photoshop 2026 byte for byte on both tested architectures, using a separate Photoshop run on each architecture. Photoshop itself returned different values across architectures for 13,057 samples from the gamma and parametric cases. The Swift conversion matches the rounding observed on each architecture. All 651 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The desktop conversion and the authenticated Photato command produce the same stored samples and both Undo correctly. Both universal app slices passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-567) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_567.md).

## 2026-11-18 — Step 566 — Preserve opaque Gray32 merged samples in PSD and PSB

PSD and PSB exports now preserve all 32-bit grayscale samples when the document contains one visible, opaque Background. The writer uses the stored grayscale samples for the merged image and leaves out the redundant transparency plane. Saved auxiliary channels still follow the grayscale plane.

An independent reader checked every sample of the 16 × 12 test image against a raw PSD saved by Photoshop 2026 at checkpoint 511. All 192 merged samples match byte for byte in PSD and PSB in all four compression modes. The comparison covers the grayscale plane and the channel count. All 629 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The tests also cover a saved auxiliary channel, hidden Background, both API encoders, and authenticated Photato downloads. Both universal app slices passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-566) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_566.md).

## 2026-11-18 — Step 565 — Add Allow Tool Recording to Actions

The Actions menu now controls whether a new recording captures Brush and other supported painting and retouching gestures. Tool gestures still edit pixels and appear in Undo when the setting is off.

All 608 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. In 52 channel-stroke sequences, both recording settings produced the same raw samples as direct editing and the same per-architecture output as build 564. Forty older Brush step encodings also matched. Both universal slices passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-565) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_565.md).

## 2026-11-18 — Step 564 — Record Brush Actions for color channels

Photato Actions can record Brush strokes on process color components, Duotone gray, and Multichannel ink plates. Playback resolves the recorded target against the current document, respects its selection, and takes one Undo to reverse.

All 583 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. On each architecture, 52 tested channel strokes replayed to the same samples as direct editing and matched build 563’s raw planes. Forty legacy Brush step encodings also matched. Both slices of the macOS 14+ validation archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-564) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_564.md).

## 2026-11-18 — Step 563 — Record and replay Quick Mask Actions

Enter Quick Mask, edit the selection with Brush or Pencil, and exit in one Action. Replay starts with the new document’s selection and can be undone in one step.

All 558 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. On both architectures, 24 Quick Mask sequences and 24 older Fill Action encodings matched build 562 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-563) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_563.md).

## 2026-11-18 — Step 562 — Record Brush Actions for masks and channels

Brush strokes on Smart Filter masks and saved channels now play back in Actions. A stroke above a shape can still create an ordinary pixel layer.

All 531 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 96 direct and prepared Brush output buffers and 12 older Action encodings matched build 561 byte for byte on each architecture. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-562) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_562.md).

## 2026-11-18 — Step 561 — Record Paint Bucket Actions

Paint Bucket clicks can now be saved in an Action. Playback uses the new document’s layer, mask, or visible composite. A recorded pattern stays with the Action.

All 527 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 240 color-region masks and 18 direct bucket buffers matched build 560 byte for byte on both architectures. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-561) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_561.md).

## 2026-11-18 — Step 560 — Add Clear to Edit Fill and Stroke

Choose Clear to erase pixels within a selection, along an outline, or across a whole pixel layer. Clear uses the existing Fill and Stroke API commands and can be recorded as a Photato Action.

All 522 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. On each architecture, 264 existing Fill, Stroke, and Path Clear pixel buffers and the legacy settings JSON matched build 559 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-560) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_560.md).

## 2026-11-18 — Step 559 — Paint Bucket Clear and automation

Clear removes alpha from the color region you click. The Photato API can configure the Paint Bucket or fill a region using the same options. Separated sparse fills and full solid fills also update much larger canvases without a whole-canvas write loop in the tested cases.

All 486 selected tests passed across three builds. The 624 actual dense and paged writeback comparisons matched on each optimized architecture. Live Photoshop output comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-559) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_559.md).

## 2026-11-18 — Step 558 — Large Paint Bucket and Magic Wand regions

Magic Wand and Paint Bucket now page large color selections. The tested sparse cases work on 300,000-pixel-square canvases, and a uniform opaque fill can update the whole canvas without allocating pixel tiles.

All 481 selected tests passed across three builds. Existing coverage and bucket buffers matched build 557 byte for byte. Dense maximum-size timing, other fill modes and exact Photoshop comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-558) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_558.md).

## 2026-11-18 — Step 557 — Brush and Pencil blend-mode shortcuts

On the canvas, Shift-plus and Shift-minus cycle paint modes. Shift-Option-Q selects Behind and Shift-Option-R selects Clear on Brush. The shortcut changes the next stroke, so you can switch modes without interrupting the stroke underway.

All 454 selected tests passed across three builds. They cover direct shortcuts, focus, the cursor, Undo and the Photato API. Live Photoshop keyboard comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-557) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_557.md).

## 2026-11-18 — Step 556 — Behind and Clear

The Brush Mode picker now has Behind and Clear. Behind puts paint underneath existing pixels. Clear removes their alpha and also works with Pencil. You can hold the grave-accent key to use Clear for a Brush stroke.

All 418 selected tests passed across three builds. They check pixel math, transparent and locked layers, Undo, replay and the Photato API. Exact Photoshop pixel comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-556) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_556.md).

## 2026-11-18 — Step 555 — Brush keyboard controls

Braces change brush hardness. The arrow keys rotate the tip, and holding Shift makes a larger turn. Option and number keys set smoothing. The test for an active stroke confirms that keyboard changes apply to the next stroke.

All 413 selected tests passed across three builds. The desktop and HTTP settings produced matching stroke pixels. Live Photoshop key behavior and exact stroke placement still need checks.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-555) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_555.md).

## 2026-11-18 — Step 554 — Round brush hardness

The four factory Round presets now change smoothly from soft feathering to an opaque core with a narrow edge. The aligned nonzero-hardness samples improved from a worst alpha difference of 161 to 12 of 255 levels. The two hard dabs from a separate document were within 2 levels. Older recorded settings still replay with their original profiles.

All 411 selected tests passed across three builds. The next measurements cover exact pointer placement, intermediate hardness settings and continuous strokes.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-554) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_554.md).

## 2026-11-18 — Step 553 — Wider Soft Round tip

Soft Round and Soft Round Pressure Opacity now paint with a wider falloff at zero hardness. Across six saved Photoshop dabs, the new renderer was within 3 alpha levels after lining up the centers. The three held-out sizes were within two levels. The previous renderer was off by up to 35. Older Actions still replay with their original brush settings.

The 409 selected tests passed in Debug and both optimized builds. The next brush checks cover exact pointer positions, harder tips and continuous strokes.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-553) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_553.md).

## 2026-11-18 — Step 552 — Brush opacity and flow number keys

With the canvas focused, number keys set opacity and Shift-number keys set flow. Airbrush swaps which modifier controls each value. Two digits set an exact percentage. This shares the existing settings used by the Options bar and the API.

The tests passed in Debug and both optimized builds. A closer look at 28 saved Photoshop dabs showed that every one extends beyond the current brush footprint. Exact brush pixels and a live shortcut check remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-552) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_552.md).

## 2026-11-18 — Step 551 — Faster paint output for wide brushes

Photato calculates independent brush output tiles in parallel and installs them in their original order. The 5,000 px brush on a 24 MP workspace reached its first offscreen AppKit draw in 181 ms, down from 315 ms. All 338 checked buffers match build 550 on each architecture.

All 401 selected tests passed in Debug and both optimized builds. Physical display cadence and exact Photoshop brush output remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-551) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_551.md).

## 2026-11-18 — Step 550 — Faster drawing on large canvases

Photato composes eligible tone stacks and packs the changed display rows in parallel. The 5,000 px brush on a 24 MP workspace reached its first offscreen AppKit draw in 304 ms, down from 460 ms. All 192 checked buffers match build 549 on each architecture.

All 400 selected tests passed in Debug and both optimized builds. Physical display cadence and exact Photoshop brush output remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-550) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_550.md).

## 2026-11-18 — Step 549 — Faster coverage for large brush strokes

The brush calculates wide-dab coverage in parallel. The 5,000 px example on the 24 MP workspace reached its first AppKit draw in 457 ms, compared with 502 ms in the paired build 548 trials. All 146 tested buffers matched build 548.

All 398 selected tests passed in each configuration. Wide brushes still need faster output and physical display testing. The 24 saved Photoshop brush cases still differ.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-549) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_549.md).

## 2026-11-18 — Step 548 — Faster first draw for wide Normal brushes

The brush prepares its Normal ink once per stroke. The 5,000 px example on the 24 MP workspace reached its first AppKit draw in 505 ms, compared with 679 ms in the paired build 547 trials. All 121 tested outputs matched.

All 397 selected tests passed in each configuration. Large-tip editing still needs faster coverage work and physical display testing.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-548) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_548.md).

## 2026-11-18 — Step 547 — Reuse work during a wide brush stroke

Wide raster brushes keep their coverage between pointer samples. On the 24 MP trial, nine prefixes of a 5,000 px stroke took 4,749 ms with the complete painter and 1,872 ms with retained coverage on Apple Silicon. All 60 saved painting outputs matched.

All 395 selected tests passed in each configuration. The cost of a new wide dab and physical editing cadence remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-547) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_547.md).

## 2026-11-17 — Step 546 — Faster canvas updates

Changed pixels now go directly into the display buffer. At 12.5% zoom, Apple Silicon display conversion for the 5,000 px brush fell from 357 to 103 ms on the 24 MP test image. All 80 saved outputs match build 545 on each architecture.

All 392 selected tests passed in the three configurations. Large brushes still need faster preparation to reach the display target.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-546) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_546.md).

## 2026-11-17 — Step 545 — Faster composition under tone layers

The renderer combines a raster and eligible tone layers in one pass through its tiles. On Apple Silicon, the 5,000 px first-dab software composition fell from 1,628 to 124 ms on the 24 MP test image. The hosted AppKit first draw took 896 ms in the paired runs.

All 64 output comparisons were exact and all 390 selected tests passed in each configuration. Large-tip display cadence remains open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-545) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_545.md).

## 2026-11-17 — Step 544 — Faster wide brushes

The renderer prepares the brush tip once per dab. Wide brushes now start their first canvas preview from the initial pointer sample. The 24 MP hosted test measured first draw at 2,343 ms for a 5,000 px soft brush, compared with 2,442 ms in build 543.

All 64 output comparisons were exact and 388 selected tests passed in each of the three configurations. Large-tip display cadence remains open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-544) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_544.md).

## 2026-11-17 — Step 543: reuse gradient samples

Large gradients reuse identical colour samples, and fill rendering writes a tile at a time. On Apple Silicon the 2,048 × 2,048 Perceptual raster fell from 351 to 49 ms. All 84 test images matched build 542 byte for byte.

All 372 selected tests passed in Debug and both optimized builds. The three saved Photoshop Gradient Map differences remain.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-543) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_543.md).

## 2026-11-17 — Step 542: get the same gradient pixels on Apple Silicon and Intel

Linear and Perceptual gradients now round the nonlinear part of sRGB the same way across the two builds. All 18 Gradient Map buffers that differed in build 541 now match, and the 32 tested Brush buffers are byte-identical to the prior build.

All 370 selected tests passed. The same three RGB8 Gradient Map fixtures still differ from Photoshop by at most one RGB8 level.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-542) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_542.md).

## 2026-11-17 — Step 541: faster feedback with large brushes

The brush preview and flat compositor now write changed pixels one tile at a time. In the 24 MP hosted workspace, the 1,800 px brush showed its first preview in 489 ms, down from 802 ms. The 5,000 px brush took 2.50 seconds, down from 3.61.

All 266 selected tests passed. The compiled builds reproduced all 32 brush outputs and 144 composite buffers from build 540 on each architecture. The larger brushes still need further responsiveness work.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-541) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_541.md).

## 2026-11-17 — Step 540: get the same linear Brush pixels on Apple Silicon and Intel

A single-precision power calculation in the sRGB transfer caused six Brush cases to disagree across the two builds. The transfer now calculates that step at higher precision and rounds to Float32. All 32 tested Brush outputs agree across architectures. The compiled transfer also agrees on every nonnegative finite Float32 input, and all 251 selected tests passed.

The 5,000 px Brush still takes 3.70 seconds to draw its first preview in the 24 MP hosted test. The smaller 64 px Brush drew 119 times during two seconds of input.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-540) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_540.md).

## 2026-11-17 — Step 539: render large brush dabs faster

The 5,000 px color-dynamics test took 0.52 seconds on Apple Silicon, down from 1.99. Brush rendering now updates one tile at a time.

All 205 selected tests passed. The optimized Apple Silicon and Intel builds reproduced the same bytes for both full-size brush tests. Live editing cadence still needs measurement.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-539) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_539.md).

## 2026-11-17 — Step 538: use a 5,000 px brush

Set a primary Brush diameter up to 5,000 pixels from the native controls or API. Large strokes process small regions before committing, with the same Undo and recorded Action behavior.

All 204 selected checks passed. The optimized Apple Silicon and Intel versions rendered the same bytes for a full-size dab and the 24 earlier Brush samples. Wide strokes still need performance work.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-538) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_538.md).

## 2026-11-17 — Step 537: record Pencil strokes in Actions

The Pencil now plays back in Actions. A recorded stroke keeps the points, brush settings and destination. Auto Erase checks the first pixel in the playback document, so the same step can switch between foreground and background on different images.

All 199 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. A new 24-dab Photoshop comparison measured the Brush's edge softness across six sizes. Exact brush pixels still differ.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-537) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_537.md).

## 2026-11-17 — Step 536: Shift-click with Brush and Pencil

Paint a point, then Shift-click to draw a straight connection. The pointer shows when there's a point to connect to. One Undo removes the connection.

All 178 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The desktop and API produced the same Photato document for both tools. A Brush Action also replayed the connection. Photoshop's brush left different alpha samples in the test sheet, so exact Brush output still needs work.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-536) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_536.md).

## 2026-11-17 — Step 535: set the ordinary Brush to 10% smoothing

The Brush opens at 10% smoothing. You can still set it to 0%, and your choice follows the workspace across document tabs. Saved Actions and presets use their recorded settings.

All 167 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. For the tested corner stroke, the new default produced the same native pixels from the desktop, HTTP and recorded replay. Exact Photoshop brush pixels and physical display timing still need verification.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-535) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_535.md).

## 2026-11-17 — Step 534: start the Brush worker during input

Photato now queues work for the first mark during input. The worker starts a median 0.23 ms after input. Across two rounds of the 24-megapixel test, the median time through the first AppKit draw was 27.52 ms to 20.77 ms.

All 114 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The preview and the committed stroke matched the complete native command. Undo restored the original. Physical editing cadence and Photoshop Brush pixel comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-534) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_534.md).

## 2026-11-17 — Step 533: start the first Brush frame sooner

On a ready canvas, Photato starts preparing the first Brush mark when the input arrives. The following frames still collect every sample. In the 24-megapixel AppKit test, median time from input to preparation fell from 18.12 ms to 0.20 ms. The median time through software drawing was 29.45 ms to 29.14 ms.

All 100 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. The measured stroke matches the full native command before and after commit, with one Undo. Physical display timing and Photoshop Brush pixel comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-533) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_533.md).

## 2026-11-17 — Step 532: reuse tiles after recompositing

A small edit used to write every pixel in the composited patch back into the canvas. Photato can now reuse complete tiles and copy just the affected rows at an edge. On the 24-megapixel Brush test, p95 for installing the patch fell from 0.96 ms to 0.16 ms. The composite and preview hashes matched build 531.

All 99 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The retained Photoshop 2026 files cover 20 owned RGB32 examples. Their represented merged pixels match. The first input driver showed a longer delay before preparation. The independently scheduled test recorded a lower end-to-end p95. Physical display timing and the broader Photoshop workflows still need verification.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-532) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_532.md).

## 2026-11-17 — Step 531: find the tiles a stroke changed

An edit to one part of a large canvas used to sort tile keys for the whole image. The damage check now skips tiles that share the same pixel storage as the previous frame. In the 24-megapixel test, p95 for a single-tile damage check fell from 1.58 ms to 0.33 ms. The complete preview, reduced preview and working sample hashes matched build 530.

All 90 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The hosted AppKit tests time the application through drawing. Physical 60 fps and Photoshop comparisons remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-531) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_531.md).

## 2026-11-17 — Step 530: send ready previews straight to AppKit

When a preview is ready, Photato now asks the attached AppKit canvas to draw. On the hosted Brush test, the median wait between the preview being ready and the draw beginning fell from 6.49 ms to 1.46 ms. In the same test, input-to-draw p95 fell from 14.36 ms to 9.86 ms.

All 59 selected tests pass in Debug, optimized Apple Silicon and translated Intel. The original 1200 × 800 fixture provides the before-and-after comparison. A separate 24 MP layered test verifies the new AppKit path and exact brush pixels. Physical display timing still needs testing.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-530) · [Measurements](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_530.md).

## 2026-11-17 — Step 529: test a different way to store canvas previews

I tried sharing unchanged memory between brush previews on large canvases. The previews matched the old bytes, but the 24-megapixel benchmark became slower. The separate memory test also rose from about 106 MB to 199 MB with two frames retained. I kept the results and restored build 528.

A follow-up using an AppKit test window found that the Brush preview often waited around 11 ms between being ready and the draw beginning. That delay is the next place to look. The test measures AppKit callbacks. Physical display timing still needs testing.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-529) · [Measurements](../PhotoCraftSwift/docs/CANVAS_PREVIEW_EXPERIMENT_529.json).

## 2026-11-17 — Step 528: open JPEG XL still images

Photato can open JPEG XL stills through File > Open and the optional API on systems with an ImageIO reader for the format. The two lossless fixtures, one RGB8 and one RGBA16, match all 280 authored sample values. The imported image remains separate from its original file and can be saved as a native document.

ImageIO presented a two-frame test file as one image. Photato now checks the codestream before it decodes the file and rejects animations with an explicit message. JPEG XL export and wider color and HDR checks remain open. The installed Photoshop Open dialog was reached, but it did not open the fixture folder through automation.

[Workflow](../PhotoCraftSwift/docs/JPEG_XL_IMPORT.md) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-528).

## 2026-11-17 — Step 527: avoid repeat save format scans

The Save As panel and API now reuse their writable-format decisions. JPEG and OpenEXR with transparency disabled use the existing exact opacity check. Once the raster is known to be opaque, another check can use that result until an alpha edit invalidates it.

All four new tests pass. Two broader runs hit an inherited channel-separation HTTP connection error, also reproduced on build 526. That test passed with the rest of its class in isolation on both builds. The timing evidence covers opacity checks on 24 and 36 megapixel images.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-527).

## Source update — 16 November 2026, builds 525–526

Selections now retain their exact contour during ordinary painting previews. Rectangular and elliptical marquees can be moved with Space while being drawn, then resized again after Space is released. Polygon vertices no longer start a drag of the old selection.

All 86 selected tests pass in Debug, optimized Apple Silicon and translated Intel, including 15 new tests. The universal package passes its checks. Native launch and window title are verified; live editing and save/reopen remain unqualified because the automation controls stalled in macOS's file chooser. Full functionality and physical 60 fps remain open.

[Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_526.md) · [525 record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-525) · [526 record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-526).

<a id="dev-step-526"></a>

## 2026-11-16 — Step 526: reposition a marquee while drawing

Hold the mouse button while drawing a rectangular or elliptical selection, press Space and move it, then release Space to resize again. The draft retains its combine mode, anti-alias and feather settings. Escape, tool/focus/source changes and busy-state changes discard it. An unfinished polygon also keeps ownership of its later clicks, including clicks inside the previous selection.

The new tests cover both marquee tools and all 16 modifier combinations, final mouse-release movement, cancellation, history, Actions, archive and the existing HTTP selection.shape command. The first polygon cursor assertion confused the toolbar icon with the existing lasso cursor; that test-only correction and the interrupted broad run are retained. No production binary or prior test assertion changed for the repair.

All 86 selected tests and all 15 new tests across builds 525–526 pass in each tested configuration. The universal app launches with Photato - Untitled-1. Native automation then stalls in the system file chooser, so live editing/save/reopen/normal Quit are not marked passed. Full Photoshop cursor/default behavior, temporary Command pixel movement and off-canvas committed selection coverage remain open.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-526) · [Workflow](../PhotoCraftSwift/docs/SELECTION_INTERACTION.md) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_526.md).

<a id="dev-step-525"></a>

## 2026-11-16 — Step 525: retain selection contours during painting

Painting previews used to rebuild the selection outline by scanning the entire dense canvas, even when coverage had not changed. The contour now scans only the selection bounds and is retained for unchanged coverage/view settings. Ordinary pixel, mask and Adjustment Brush previews keep a matching outline on screen while their next image is prepared. Changed or cancelled requests cannot publish a stale or partial contour.

For a small selection on 24/36MP canvases, the optimized contour takes about 0.041ms on Apple Silicon and 0.061ms under Intel translation. The frozen native-524 traversal, recompiled in the same test binaries, takes 217/330ms and 372/563ms. Every contour segment matches. This measures contour preparation; it is not a Photoshop comparison, whole-stroke latency or physical display frame rate.

The initial 22 focused Debug tests pass. Final combined qualification is recorded under build 526. Earlier temporary checkouts had disappeared, so the exact public source and 13 unchanged local model/fixture inputs were restored into a persistent workspace. The older dirty checkout remains untouched. All original scopes and failures remain tracked.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-525) · [Contour preparation](../PhotoCraftSwift/docs/SELECTION_CONTOURS.md).

## Source update — 2026-11-09, build 524

Selection borders support dragging and arrow keys; replacement feedback starts on press. Canvas Size retains zoom/pan. Debug and normal optimized ARM/translated Intel each pass 65 selected methods, including all 13 new methods. Universal package checks pass; live UI inspection is unavailable this session.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-524) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_524.md).

## Source update — 2026-11-09 UTC, build 523

Layer-mask and Adjustment Brush previews now retain stroke coverage. The owned model workload processes about 60 accepted previews/s; physical display FPS remains unverified. Debug 52/52 and optimized ARM/translated Intel 69/69 selected methods pass. Native mask/adjustment history, Properties, save/reopen/Quit and universal package checks pass.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-523) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_523.md).

## Source update — 9 November2026 UTC, build 522

Masked adjustment previews improve about 23× in the controlled workload. All 30 selected tests pass on optimized ARM and translated Intel, including eight methods since public 520. Actual optimized universal paint/history/Properties/save/reopen/Quit and static package checks pass. Processing remains near 27/s for masks; physical 60 fps and live Sky scrolling remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-522) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_522.md).

## Source update — 9 November 2026 UTC, build 520

Color and vibrance now works with Adjustment Brush through native painting, editable Properties, masks, history, archive, Actions 61 and the optional API. Debug and each optimized architecture pass 46 selected methods/all 12 new. Actual native save/reopen/normal Quit and universal static checks pass. Independent Photoshop output still differs; full B08/A04 and all earlier failures remain open. Next: Q03, major stillneeded.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-520) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_520.md).

## Source update — 9 November 2026 UTC, build 519

Large Sky selection/replacement now retains working-resolution masks/output and visible full-detail previews. Scrolling/zooming imagery stays inside the viewport. Legacy previews, true 100% zoom, existing View shortcuts and read-only API viewport state are tested. Current Debug passes 15 focused checks/all 9 new viewport-display methods; optimized Apple Silicon and translated Intel each pass 63/all 34 new increment methods. Universal static checks pass; actual Sky sheet verification remains open after native inspection disconnected. Full AI09 and earlier failures remain open. Next: B08, major stillneeded.

[519 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-519) · [Workflow/API](../PhotoCraftSwift/docs/LARGE_SKY_WORKSPACE.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_519.md).

## Source update — 9 November 2026 UTC, build 518

Video keyframes now support multi-selection, an immutable clipboard and atomic paste, delete, move, duplicate and interpolation edits through native controls and the optional API. All 46 selected tests and 12 new tests pass in Debug, optimized Apple Silicon and translated Intel. Actual native group editing, save/reopen and universal static checks pass. Photoshop 2026 supplied the observed menu and single-layer timing/value reference; full SP01 and earlier failures remain open. Next: AI09, major stillneeded.

[518 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-518) · [Workflow/API](../PhotoCraftSwift/docs/KEYFRAME_GROUP_EDITING.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_518.md).

## Source update — 9 November 2026 UTC, build 517

Generated-image alternatives now remain in one native layer, with a Properties thumbnail chooser, deletion, Undo/Redo and offline save/reopen. All54 selected tests and9 new tests pass in Debug, optimized Apple Silicon and translated Intel. Actual native UI and universal static checks pass. Test images are owned synthetic fixtures; no actual provider generation or Photoshop-output equality is claimed. Full AI07 and prior failures remain open. Next: SP01 timeline/video, major stillneeded.

[517 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-517) · [Workflow/API](../PhotoCraftSwift/docs/GENERATED_VARIATIONS.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_517.md).

## Source update — 9 November 2026 UTC, build 516

Editable RGB PSD/PSB artboards now retain geometry, backgrounds, presets, children, origins and scoped guides. Debug and optimized Apple Silicon pass 74/74 selected tests; translated Intel passes 73/74, with the same older nine-assertion paging failure reproduced on retained public515. All 11 new methods and exact owned Photoshop merged references pass in every configuration. Native save/reopen, Photoshop reopen and universal static checks pass. Full I04/L07, prior failures and full parity remain open.

[516 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-516) · [Workflow/API](../PhotoCraftSwift/docs/PSD_ARTBOARDS.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_516.md).

## Source update — 9 November 2026 UTC, build 515

Original artboard projects now open with editable bounds, backgrounds, presets and children. Reframing/export preserves saved source appearances. All 46 selected tests and all 10 new methods pass in Debug, optimized Apple Silicon and translated Intel. Native Properties, Cancel, history, Save As/reopen and normal Quit pass, as do universal static checks. Full I03, editable PSD/PSB artboard interchange and earlier failures remain open.

[515 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-515) · [Workflow/API](../PhotoCraftSwift/docs/PCRAFT_ARTBOARDS.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_515.md).

## Source update — 9 November 2026 UTC, build 514

Auto-Blend now keeps visible editable source layers when seamless blending is enabled and transparent-area fill is off. Photomerge also retains the photograph names. Fill adds a merged layer; translucent sources still use the documented isolation fallback.

Debug and optimized ARM pass 37/37 focused tests, including all nine new methods. Intel passes 36/37 and eight of nine new methods; its exact linear-RGB comparison remains failed. Native commit, Undo/Redo and saved PSD reopening were checked. The Intel difference is isolated to the same color-transfer behavior in the retained build 513; the stored component comparison is unchanged. The original assertion remains required. Full blending fidelity, large-photo capacity, all prior failures and Photoshop parity remain open.

[514 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-514) · [Workflow/API](../PhotoCraftSwift/docs/EDITABLE_PHOTO_BLEND.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_514.md).

## Source update — 9 November 2026 UTC, build 513

Legacy Macintosh RGB proofing is now available in the native app and API. Shared Apple RGB profiles also work for document creation and output. Native controls, cancellation, Command-Y and saved/reopened PSD components were checked.

All seven new tests pass in Debug and both optimized architectures. Broader runs pass 54/55 on Apple Silicon and 52/55 on translated Intel. The remaining Gray-profile and frozen-proof failures reproduce on the actual retained build 512 binary; they remain open. The universal package passes static checks and is unlaunched. Full color-proofing and Photoshop parity are unfinished.

[513 — Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-513) · [Workflow/API](../PhotoCraftSwift/docs/APPLE_RGB_PROOF.md) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_513.md).

## Source update — 9 November 2026 UTC, build 512

Merge Channels now works through the native Channels panel and the optional API. Assign grayscale images to RGB, CMYK, Lab or Multichannel output. The result opens as a new document; only the chosen sources close.

All 15 new tests pass in Debug and both optimized architectures. The broader run passes 68/69, with the same legacy Multichannel failure reproduced on public build 511. Actual RGB16 and Multichannel16 saves reopen correctly and match all 960 Photoshop reference component values. Full parity and the recorded cleanup work remain open.

[512 — Merge Channels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-512) · [Usage/API](../PhotoCraftSwift/docs/MERGE_CHANNELS.md) · [Validation](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_512.md).

## Source update — 8 November 2026, build 511

Photoshop rejected our Gray32 PSD exports even though Photato could reopen them. The writer omitted HDR toning metadata for grayscale. That is fixed in the shared native and API export path.

All 32 selected tests pass in Debug and both optimized architectures. Photoshop opens all eight tested PSD/PSB compression variants. A separate Float32 merged-preview difference remains. Merge Channels reference work is recorded, but that command is still in progress.

[511 — Gray32 Photoshop file export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-511) · [Validation and remaining work](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_511.md).

## Source update — 8 November 2026, build 510

The diary now includes reviewed adjustment values, language/plugin audits and editable gradient profile conversion. The current workflow passes all14new tests in Debug and both optimized architectures, plus a native save/reopen check. The broader run has a known Intel failure, independently reproduced on public506; it remains required.

- [507 — Reviewed adjustment values](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-507)
- [508 — AI, language and plugin acceptance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-508)
- [509 — Plugin host requirements](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-509)
- [510 — Editable gradient profiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-510)

[Validation and remaining gaps](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_510.md).

## Source update — 8 November 2026, build 506

Photato now has a local learned upscaling workflow. Image > Generative Upscale creates a separate 2× or 4× document using an optional BSD-licensed Real-ESRGAN model. The original stays unchanged. Native progress, cancellation and API create/cancel share the same preparation.

All 46 selected methods pass in Debug, optimized Apple Silicon and translated Intel; 19 archive-tool checks pass. The diary includes the failed compiles, Intel half-precision repair and inherited archive path-guard correction. This remains an unfinished development alpha.

- [506 — Local learned upscaling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-506)
- [Workflow and API](../PhotoCraftSwift/docs/LOCAL_SUPER_RESOLUTION.md)
- [Validation and remaining gaps](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_506.md)

## Source update — 8 November 2026, build 505

Generated backgrounds now prepare bounded references from larger masked subjects. The image workspace also offers an explicit request to edit a reference image on eligible Apple Silicon Macs running macOS 27 or later. Ordinary editing still targets macOS 14+.

All 81 focused methods pass in Debug, optimized Apple Silicon and translated Intel, including 20 new methods from 504–505. The records include failed attempts, the unresolved native AI-sheet connection failure and the limits of the model checks.

- [504 — Background generation on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-504)
- [505 — Edit a reference image](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-505)

[Source delivery and remaining gaps](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_505.md). Standalone website promotion remains pending.

## Source update — 8 November 2026, build 503

People selection now works beyond the former small-image admission limit. Apple text-service readiness explains missing device, system, model or signed-capability requirements. The Remove tool can mark background people for review before an explicit apply.

The current source passes 114 focused methods in Debug and each optimized architecture, including all 31 new 501–503 methods. The diary records the failed attempts and the portrait-classification correction. Full Photoshop functionality and output parity remain unfinished.

- [501 — Select People on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-501)
- [502 — Report Apple text-service availability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-502)
- [503 — Review people before removal](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-503)

[Source delivery, validation and remaining gaps](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_503.md). The standalone website and canonical historical-evidence pipeline remain separately pending.

## Source update — 8 November2026

Build500 passes its42 focused Debug tests and the same42 optimized tests on Apple Silicon and translated Intel. Actual sandboxed export, Cancel/history and normal Quit checks pass. This source snapshot includes the work through500; it does not establish full Photoshop parity or a full-suite pass.

- [487 — Share the person-selection model](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-487)
- [488 — Image styles and canvas size](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-488)
- [489 — Native Remove tool](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-489)
- [490 — Generated backgrounds](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-490)
- [491 — Reference images for generation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-491)
- [492 — Reviewed edit plans](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-492)
- [493 — Profile changes on large documents](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-493)
- [494 — Directory durability](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-494)
- [495 — Paged Warp](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-495)
- [496 — PSD vector path semantics](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-496)
- [497 — Untagged files and sandboxed copies](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-497)
- [498 — Large colour-mode files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-498)
- [499 — Paths to Illustrator](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-499)
- [500 — Repair native asset export](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-500)

The detailed private attempt records remain retained. The canonical history-index and website refresh are still pending; [delivery details](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_500.md).

# Photato development diary

<!-- process-note:start -->
## Source code and compatibility testing

Photato is a native Swift image editor targeting Photoshop 2026 functionality. The open-source PhotoCraft Rust project provides inspiration and licensed implementation material. Photoshop 2026 defines the behavior we need to reproduce. Ported code keeps its MIT/Apache licensing and credits. We record the source and license of dependencies and test fixtures.

For Photoshop compatibility, we use public Adobe documentation and Photoshop’s normal interface with our own test artwork. We record controls, defaults, shortcuts and results, and examine saved files. Some compatibility facts come from installed metadata and script definitions; Adobe’s script code is not incorporated into Photato.

We port licensed PhotoCraft code where suitable and write independent Swift code for the editor, macOS interface and APIs. We have not decompiled or disassembled Photoshop executables, extracted proprietary algorithm code, or copied Adobe’s proprietary implementation into Photato.

Tests compare results with the original Rust implementation, public file specifications and Photoshop-generated test files. They cover editing, previews, cancellation, undo/redo, saving and APIs. Byte-identical results are claimed only for tested cases. Mismatches and untested behavior remain in the record, along with source/build hashes, commands, failed attempts and repairs.

This is independent implementation with black-box compatibility research. Research and implementation happen within the same project, so this is not a claim of formal clean-room separation. Observing behavior and examining saved files are part of the process; the diary does not claim that no reverse engineering of any kind occurred. The restriction on decompiling, disassembling or copying Photoshop’s proprietary implementation remains explicit.

<!-- process-note:end -->

**Release policy — updated 6 November 2026:** Photato will be a free and open-source release under MIT OR Apache-2.0, without tips, donations, in-app purchases, subscriptions or paid feature unlocks. The repository is now public at the maintainer’s request; application releases remain manually approved. Earlier entries describe the former purchase experiment as history; step237 records its removal.

<!-- current-status:start -->
<!-- current-status-step:664 -->
## Current development status — 20 November 2026

Photoshop document manifests can include JPEG or PNG layer previews and exact copies of embedded Smart Object originals. The assets use Photato's authenticated local download URLs.

1,502 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen.

[Source checkpoint 664](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_664.md) · [Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-664).

<!-- current-status:end -->

## The brief and the decisions that shaped the project

The original brief was to inspect PhotoCraft, plan the port, implement it module by module, and test each module. The target became Photoshop 2026 functionality in a fully native Swift application for macOS 14 and later, with a universal application for Apple Silicon and Intel. Optional Apple AI belongs behind platform and availability checks. The maintainer clarified at step335 that Rust is a source of inspiration, not a required first parity milestone. Missing Photoshop workflows determine the work, regardless of whether Rust implements them.

The maintainer then made several decisions that continue to govern development:

- Use Photoshop's interface, menu structure and factory shortcuts by default. A visible menu item does not establish that its function is implemented.
- Allow Apple's Private Cloud Compute as well as eligible on-device features, and describe which service is actually used.
- Release the work as an open-source fork with clear PhotoCraft attribution. Name the application **Photato**, and use the supplied icon.
- The earlier optional App Store tip experiment was removed at step237. The current release is free and open source, with no purchases or paid feature unlocks.
- Include a native Xcode project alongside the package-based build and test workflow.
- Maintain both the Photato API and an interface compatible with the published Adobe Photoshop API wherever that contract defines the operation. Desktop and API operations share the native engine.
- Record every development change, including failures and removals, from the beginning.
- Follow the current seven-pass order: **major quick wins, major still needed, minor quick wins, minor still needed, major cleanup, minor cleanup, final settings/checks**. UI, menus, shortcuts, APIs and focused tests stay with each delivered function. Full original acceptance still governs package closure.

These decisions were made at different points. The dated account below preserves those changes instead of rewriting the past as though the final requirements existed from day one.

## 7 October 2026

### Establishing the native application

The first audit inventoried 24 Rust crates and 626 unique source menu identifiers. The Swift project separated the editing model, imaging and PSD support, optional AI, and native application. Early implementation covered sparse raster storage, blending, documents, commands and history, basic tools, native storage, and a deliberately limited PSD reader and writer. The initial milestone recorded 40 passing tests and a universal build targeting macOS 14. It also recorded repairs to canvas redraw, preview tone mapping, imported-file protection, gesture history, and signing affected by Desktop synchronization. The initial sequence was later expanded retrospectively; it is not a recovered edit-by-edit transcript. [Initial source audit and port](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-001)

A professional-workflow plan distinguished source parity from Photoshop parity. Inspection of the source corrected several earlier descriptions of supposedly missing Rust functionality, so those implementations remained part of the porting obligation. Inspection of the running Photoshop interface then guided a native workspace with grouped tools, document tabs, options, layers, adjustments, rulers and scrollers. Unsupported tools stayed visibly unavailable. [Workflow plan](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-002), [first workspace](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-003)

### Correcting the AI policy

An early platform policy excluded Image Playground where it would use cloud computation. At the maintainer's request, that exclusion was removed and Private Cloud Compute was re-enabled subject to Apple's actual availability checks. The UI was changed so cloud-generated results would not be described as on-device. Local prompt refinement remained a separate capability. At that checkpoint the services were unavailable or still preparing on the test machine; live generation was not claimed. [Private Cloud Compute change](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-004)

### Geometry, selections, masks and editable documents

The port gained Free Transform, image and canvas sizing, resolution handling, resampling and undoable whole-canvas geometry. Selections expanded to coverage masks, ellipses, freehand and polygon tools, combinations, inversion and feathering. Direct pixel-mask editing, independent mask transforms, density, feather, enable/link state and PSD mask interchange followed. Independent Photoshop files exposed ordering and mask details that native round trips could not reveal. [Geometry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-005), [selection coverage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-006), [independent masks](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-007)

PSD support expanded to compressed channels and higher bit depths. Photoshop comparisons revealed that float PSD samples require linear-light handling, leading to corrections in storage and composition. Layer groups, clipping, editable paths and vector masks followed. Further work covered editable solid fills, edge feathering, mask commands, the clipboard and more compact native raster archives. The entries preserve measured residual errors rather than calling the whole format equivalent. [High-depth PSD](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-009), [groups](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-010), [paths and vectors](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-011), [solid fills](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-012), [mask and clipboard sequence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-015), [archive changes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-018)

### Attribution, support and the Photato name

Open-source attribution, bundled licenses and optional project/support links were introduced first. The App Store requirement then changed the support design: external donation destinations were replaced with StoreKit consumable tips, the external funding template was removed, and legacy donation metadata was ignored. Simulated StoreKit tests covered purchase and transaction recovery paths, while production registration, prices and release qualification remained open. The application was renamed Photato without removing upstream PhotoCraft credit or silently renaming every internal module. [Fork and attribution](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-008), [tips and removals](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-013), [Photato branding](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-014)

### Adjustments and independent references

The adjustment sequence added manual Levels, histograms and automatic correction, Curves, Hue/Saturation, Desaturate and Color Balance. The work included editable adjustment layers, destructive preview/apply paths, masks, history and PSD records. External Photoshop-produced fixtures exposed Hue/Saturation and Colorize differences that required corrections. The diary keeps source-algorithm agreement separate from Photoshop-output agreement. [Levels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-019), [histograms](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-020), [Curves](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-021), [Hue/Saturation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-022), [Color Balance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-023), [reference-driven correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-024)

## 8 October 2026

### Retouching, painting and rendering

Work continued on Hue/Saturation behavior, Threshold and Posterize. Clone Stamp gained source slots, cross-document and mask sampling, alignment and transform controls. Regional rendering and immutable preview caching supported these interactions. Expanding cropped paint targets required careful preservation of existing pixels and mask coordinates. Healing Brush, Spot Healing, patch completion, Dodge, Burn, Sponge, Blur, Sharpen, Smudge, Magic Wand and Paint Bucket were then implemented or expanded through the shared native engine. These are recorded modules with their own limits, not a declaration that every Photoshop variant of those tools is complete. [Adjustment corrections](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-025), [Clone Stamp](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-027), [regional rendering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-028), [healing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-030), [toning and focus tools](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-032), [wand and bucket](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-034)

### Patterns and gradients

A persistent pattern library and PAT interchange led to editable Pattern Fill layers and embedded PSD patterns. Profiling then guided CPU rendering improvements. Gradient work introduced retained stops, multiple shapes and interpolation modes, editable Gradient Fill, live and Classic Gradient tools, preset libraries, Gradient Map, and Stripes. Storage, clipboard, previews, history and PSD interchange were extended alongside the features. [Patterns](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-035), [Pattern Fill](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-036), [rendering optimization](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-037), [gradient foundation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-038), [Gradient Fill](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-039), [tools and presets](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-040), [Gradient Map](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-042), [Stripes](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-043)

Several subsequent milestones were research and correction rather than new tools. Photoshop-saved references were used to investigate RGB16 transparency, Smooth interpolation, neighboring stops, color conversion, stop limits, tone coordinates and Classic arithmetic. Some candidates matched bounded reference sets; remaining mismatches and unsupported Smooth behavior stayed open. This sequence is particularly important to the record: a failed hypothesis or an unresolved numerical difference must remain visible. [RGB16 transparency correction](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-045), [Smooth investigation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-046), [stop preservation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-048), [tone coordinates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-050), [Classic candidate](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-052)

### Recording the work and matching menus

A dedicated documentation audit introduced stable milestone identifiers, the oldest-first index, explicit retrospective corrections, preservation rules and a hashed evidence inventory. It identified overwritten early logs and refused to manufacture missing timestamps or commits. [First development-history audit](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-044)

Layer alignment and distribution were investigated against Photoshop and then connected to native controls. Menu alignment and factory shortcut evidence were treated separately: the default bindings were corrected from the installed factory preset, including primary and alternate shortcuts. Layer via Copy/Cut and merging/flattening followed. The requested pause was taken at version 0.2.0, with the version change distinguished from fresh application test evidence. [Layer layout](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-053), [menu alignment](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-055), [factory shortcuts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-056), [Copy/Cut](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-057), [merging](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-058), [version and pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-059)

### Native workspace organization

After resumption under the then-current UI-first priorities, work addressed workspace visibility, native document windows, tab dragging, the shared application frame, floating canvases, zoom entry, compact layouts, saved workspaces and editable panel groups. These were prerequisites for a usable native editor rather than evidence of complete Photoshop tool coverage. [Resumed priorities](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-060), [document windows](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-061), [shared frame](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-063), [saved workspaces](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-066), [dock groups](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-067)

## 9 October 2026

### Panels and layer interactions

Panel work continued with floating hosts, tear-off, stacks, columns, and retained History and Clone Source panels. Layer workflows gained New Layer, New Group and duplication dialogs, panel commands, inline naming, delete confirmation, color labels, visibility interactions, group disclosure and active-layer reveal. Thumbnail options, mask gestures, layout repairs, absolute positions and numeric-editing lifecycle followed. The detailed entries distinguish automated checks from live checks that could not run while the Mac was locked. [Floating panels](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-068), [panel columns](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-071), [layer dialogs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-073), [layer menu and naming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-076), [visibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-078), [thumbnail options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-082), [mask gestures](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-084), [numeric editing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-087)

### Xcode and the outstanding-work inventory

A native `Photato.xcodeproj` was added beside the Swift package, with application and module targets, shared schemes, universal Release configuration, resources and the macOS 14 deployment target. Channels and component previews were developed next. At the maintainer's request, implementation paused for a comprehensive parity inventory: 105 work packages, explicit gaps, dependencies and effort estimates. The estimates were engineering judgments, not promised completion dates, and some full-equivalence requirements had no defensible ETA. [Xcode project](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-088), [Channels panel](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-089), [parity inventory and estimates](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-090)

### Optional APIs and the product webpage

The optional native automation API and browser client were added as separately authorized work. Native transactions, permissions, document sharing and endpoint state were part of that increment. Subsequent decisions made API coverage mandatory for new features and established the published Adobe Photoshop v2 contract as a separate compatibility target. Both interfaces were retained over one Swift engine. Local server authentication and supported operations were not represented as Adobe's identity service or complete hosted-service compatibility. [Initial API](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-091), [API completion rule](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-094), [Adobe contract requirement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-095), [both APIs](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-096)

The Photato product webpage was created at `nusite/index.html`, following the existing forensicintelligence.ca style and showing provenance and development status. This was a separate presentation task during a pause in native feature development. [Webpage record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-097)

## 13 October 2026

### Accessibility, channels and recorded actions

Resumed work repaired native panel menu accessibility and qualified floating-panel input. Channel research distinguished visibility from the selected editing target, leading to independent RGB visibility and API state. Component-editing references and transaction design then supported recorded Photoshop actions and component integration. Failed attempts and subsequent qualification were preserved before another requested pause. [Accessibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-098), [floating-panel input](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-099), [channel behavior](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-100), [RGB visibility](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-101), [component research](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-102), [recorded actions](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-103), [pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-104)

## 19 October 2026

### Component editing and a new implementation order

The component integration resumed with native controls and both public API paths. Independent Photoshop fixtures were exercised through the shared workflow. Testing caught stale catalogue expectations and UI/context problems; repairs and repeat qualification were recorded before the requested pause. The maintainer then changed the scheduling order to major functions, minor functions, and final details. The backlog was reorganized around that order without reducing the parity requirements. [Investigation and pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-105), [component/API integration](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-106), [verified pause](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-107), [priority change](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-108), [major-workflow backlog](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-109)

### Documents, color and file preservation

The major document workflow expanded through persistence, the `.photato` extension, source-format preservation and source-format Save. Work on exact RGB32 samples, linear HDR editing, retained working profiles, Normal composition and grouped/clipped documents used independent references to distinguish actual precision fixes from unqualified rendering behavior. PSB integration and bounded PSD/PSB row and file decoding followed, then streamed output and safe saving. [Persistence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-110), [file extension](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-111), [source formats](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-112), [float samples](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-114), [working profiles](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-116), [Normal rendering](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-117), [groups and clipping](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-118), [PSB](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-119), [streamed saving](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-122)

### History, recovery and interruption handling

Scratch-backed undo, native archive streaming and shared tile storage addressed history and memory use. Cancellable asynchronous history navigation was followed by crash recovery, background backup writing, recovery preferences, atomic persistence and source-identity checks. The purpose was to make large documents and interrupted workflows safer without silently losing content, overwriting changed originals, or publishing stale background results. [Scratch history](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-123), [archive streaming](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-124), [asynchronous history](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-126), [recovery lifecycle](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-127), [preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-129), [atomic persistence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-130), [source identity](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-131)

## 20 October 2026

### Opening, closing and recovery management

Recovery discovery became independent of the original document location. Coordinated closing, background opening, persistent recent files and queued opens were added or expanded. Recovery maintenance, explicit salvage, damaged-index reset, background discovery and memory admission followed. These workflows include native and API behavior, preservation of backups, cancellation and failure cases. Automatic memory admission remains an estimate, not a claim of a complete paging system. [Recovery discovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-132), [closing](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-133), [opening](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-134), [recent files](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-135), [backup maintenance](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-136), [salvage](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-137), [background discovery](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-138), [memory admission](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-139)

### Saving options and TIFF interoperability

Shared native/API encoding options started with PNG and TIFF settings, then PSD/PSB compression and file-compression preferences. TIFF work addressed float preservation, byte order, channel layout and prediction, layered import, editable layered output, numeric adjustments, vector masks and global mask-display metadata. An unreliable generic descriptor conversion draft was removed from production and preserved with the conflicting reference evidence. An independent parser's limitations were also documented and handled separately; they were not used to justify weakening the application checks. [Shared encoding options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-140), [PSD/PSB compression](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-141), [file preferences](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-142), [float TIFF](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-143), [storage options](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-144), [layer import](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-145), [layer output](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-146), [rich records and rejected draft](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-147)

At verified checkpoint 147, the record reports 1,390 passing Debug tests and 1,390 passing Release tests, independent output inspection, universal packaging and native Release save checks on Apple Silicon and Rosetta. This is a qualified checkpoint, not a completed Photoshop clone. All major workflow gates remain open. [Checkpoint 147](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_147.json)

### JPEG work in progress at reconstruction

Milestone 148 is developing JPEG quality, format, matte and color-profile controls with shared native/API output. The recorded investigation distinguishes Adobe's published quality choices from Photato-specific options and keeps Photoshop quantization and progressive scan-count equivalence open. At this diary snapshot, the observed focused attempts include a compiler failure followed by a run with 47 tests and six failures. The latter exposed restart-marker handling and an incorrect assumption that the platform always embeds sRGB ICC data. Those are findings under repair, not a successful release claim. Consult the running entry for subsequent results. [Current JPEG entry](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-148)

## Changes of direction and removals

The diary records removal as deliberately as addition. Important examples include removing the earlier Private Cloud Compute exclusion; replacing external donation integration with StoreKit and deleting the funding template; correcting menu and shortcut defaults from factory evidence; removing stale format metadata where edits invalidate it; and withdrawing the unqualified TIFF descriptor-conversion draft from production. Rejected experiments remain evidence even when they do not become application code. [AI policy](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-004), [support replacement](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-013), [shortcuts](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-056), [metadata handling](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-026), [withdrawn draft](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-147)

## How the diary stays current

Every meaningful addition, modification, deletion, rename, rollback or replacement must be recorded as work proceeds. Related edits may share an entry, but the entry must identify what changed, the affected paths or modules, why it changed, its user-visible or API effect, and how it was checked. A removal must name what was removed and whether anything replaces it. Investigation, failed tests, rejected approaches, repairs and remaining gaps belong in the same record; a final successful test count cannot replace them.

The detailed entry is written in [DEVLOG](../PhotoCraftSwift/docs/DEVLOG.md) under a stable milestone anchor. Unique run folders preserve before/after identities and test evidence. At a completed checkpoint, this readable diary receives the new chronology and any material change to the narrative. The [evidence inventory](../PhotoCraftSwift/docs/DEVELOPMENT_HISTORY.json) connects the records to surviving files. These obligations are part of [the repository instructions](../PhotoCraftSwift/AGENTS.md) and [the contribution requirements](../PhotoCraftSwift/CONTRIBUTING.md#development-record).

The original extracted Rust snapshot has no preserved upstream Git history, and some early logs were overwritten. The surviving record therefore cannot prove every historical keystroke or deleted intermediate file. Missing detail stays unknown. Neither this reconstruction nor the evidence audit creates an initial commit, recovers absent files, or certifies Photoshop parity.

### JPEG checkpoint verified after the reconstruction

**Update recorded 20 October 2026 after checkpoint148.** The failures above were retained and repaired: Swift matte conversion was disambiguated, nonzero JPEG restart intervals were supported, explicit ICC insertion/removal was added, and an invalid transparent ordinary-save test was corrected without relaxing the application guard. Native Save/Copy, Photato output and Adobe-defined JPEG job quality choices now share the encoder. All1,398 Debug and1,398 Release tests pass, with independent libjpeg-turbo coefficient/sample checks, universal packaging and public Release saves on Apple Silicon/Rosetta. Default JPEG outputs and161 retained prior exports remain byte-identical to147. Five live Photoshop references establish that quality8 quantization/chroma sampling and progressive schedules still differ. The original Photoshop Untitled-1 was restored. All major gates stay open. [Verified checkpoint148](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_148.json), [detailed repairs and live evidence](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-148)

### Reading original PhotoCraft containers in Swift

Step149 adds the container groundwork for editable `.pcraft` migration: ZIP framing, Zstandard entropy decoding and BLAKE3 content verification. Procedural fixtures generated by the original Rust source cover 8-, 16- and 32-bit documents with layers and masks. The decoder verifies 42 tile addresses and 42 blob streams; an independent Zstandard encoder supplies 48 further cases, with official hash vectors and malformed-input tests. A repeat using the original dependency lock produces identical fixture bytes.

The first Swift compile failed on missing error propagation in ZIP checks. A later focused run exposed an invalid hand-built Huffman fixture; the external decoder rejected it too. Both failures remain recorded, and the repaired fixture retains its invalid predecessor as a rejection case. Final qualification passes 1,408 Debug and 1,408 Release tests, universal packaging and matching optimized decoder probes on Apple Silicon and Intel under Rosetta. Existing production modules were retained; seven internal decoder modules, one test module and attributed fixtures were added. Notices and the development records were updated.

This completes a tested dependency, not editable project import. Manifest mapping, directory bundles, desktop/API integration and full migration remain open under major item I03. No new user-facing command or API capability is advertised. The installed app and user documents/settings remain preserved. [Container foundation](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-149), [checkpoint149](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_149.json)

### Preserving the complete source project graph before native mapping

Step150 found that direct import would lose source semantics: separate pixel/transparency/position locks, unbounded raster defaults, rich text, Smart Objects and other document features are not fully represented by the native model. The increment therefore adds an internal graph and payload reader, keeping original JSON and exact numeric tokens rather than prematurely converting those features. Known source surfaces retain signed tile positions, encoded defaults and sample bytes; known blob references are verified. Guarded directory reads complement ZIP input, and linked external Smart Object files are never opened.

Three rich fixtures use the original Rust test generator, extended with layer comps, video defaults and large IDs. The first caller asserted full equality and failed because the source loader intentionally remaps extreme IDs. A second caller and manifest comparison establish that only identities and comp links change. All48 source surfaces and222 stored payloads receive independent ZIP/JSON/zstd inventory checks. Intel qualification initially fails because SwiftPM discovers tests in an arm64 process; explicitly running the existing x86_64 bundle under Rosetta repairs the harness without source changes. Focused tests pass, then a source review adds the maximum-depth empty-group boundary regression before the final freeze. Final qualification passes1,422 Debug and1,422 Release tests,24 focused tests under Rosetta and universal package checks;692 prior output/reference files remain unchanged.

Three production modules, one test module and five attributed fixture files are added; prior application/Core/AI/API/menu sources are retained. No functionality is removed, no new public import capability is advertised, and all major gates remain open. Next is native partial-lock behavior and the editable adapter with matching UI/API/history/persistence tests. [Project reader record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-150), [checkpoint150](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_150.json)

### Separating Photoshop's protection settings

Step151 verified the lock behavior on a disposable procedural document in Photoshop2026.
Transparency, Image, Position, Prevent auto-nest and All produce distinct stored flags; All
uses a high bit that the old native writer omits. A fully locked layer can still be renamed.
Image forces Transparency checked, and the Command-/ shortcut differs from clearing All
inside the dialog. Independent Python PSD/PackBits decoding checks nine saved states,
including a black fill that preserves every alpha byte. The user's original document remains
untouched. An initial parser offset mistake and custom-dialog accessibility failures are
recorded alongside successful repairs. The first Intel build-tests attempt omitted
testable imports in Release; a retained retry adds the compiler flag without source changes.

The native changes add isolated value, PSD record and Adobe field parsers, three test modules
and eleven fixture/provenance files. The current official Adobe contract matches the pinned
version and confirms contextual omitted/null/empty protection semantics. These modules remain
inactive: changing import interpretation before all command guards migrate could expose
protected content to unintended editing. Model/archive migration, painting, groups/masks,
desktop controls and both APIs are still required together. No existing functionality is
removed or replaced, and no new executable API capability is claimed.

All10 focused,1,432 Debug,1,432 Release and10 Rosetta-focused tests pass, as do universal package
checks. All1,109 previous inputs and692 previous exported/reference files remain unchanged.
Seventeen files are added. Installed117 and user settings remain preserved. The checkpoint
records the six-part activation plan; all major gates remain open.
[Protection record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-151), [checkpoint151](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_151.json)

## 2026-10-20 — Step152: protection reaches editing and both APIs

The previous isolated protection model now governs actual native edits and file persistence. Painting preserves the existing alpha stencil; Photoshop’s explicit selected Clear removes pixels. Image and position locks block their respective operations, while full-lock Rename and grouping follow the observed reference. The native dialog, layer buttons, shortcut and both API paths share those transactions. Version12 prevents older readers from silently losing partial protection; compatible existing files retain their prior version.

The first two compilations exposed test inference and initialization errors. Full01 later found94 failed assertions, mostly90 repetitions of the old TIFF partial-to-full collapse. An independent byte inventory proved all30 TIFF fixtures contain transparency-only protection. Focused06 also exposed a known unsupported little-endian opaque metadata block; the test now distinguishes that limitation from protection-only output. Later review also corrected API-only flag transitions and a reproduced protected-Fill integer quantization defect; both interrupted validations and the failing regression are preserved. Live testing then exposed initial checkbox enablement overridden during SwiftUI installation; a hosted-control regression reproduced five failures before the environment-state fix. Final59 focused,1,442 Debug,1,442 Release and20 Rosetta tests pass, with universal packaging and an owned native UI probe. This is bounded integration, not complete Photoshop parity; all major gates remain open.

[Runtime development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-152), [checkpoint152](../PhotoCraftSwift/docs/ACTIVE_CHECKPOINT_152.json)

Step153 completes the first editable original-project migration subset. Source-generated RGB 8/16/32 fixtures retain raster/group/mask/path/selection/protection data through native Open, API editing and Photato persistence. Empty-selection and file-registration regressions were reproduced and repaired; all 1,455 Debug/Release tests,13 Rosetta cases,universal packaging and an owned live workflow pass. Rich source features and all major gates remain open. See [the detailed step153 record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-153).

Step154 adds independent source/Photoshop rendering comparisons and repairs off-canvas raster-mask edge handling. The first broad cropped-mask hypothesis was disproved by controls; the final change follows the measured layer-boundary distinction. All 1,460 Debug/Release tests, 14 Rosetta cases and native/UI/API/package checks pass. Gaussian/vector/full byte parity remains open. See [step154](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-154).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-08.md) · [Next page](part-06.md)
