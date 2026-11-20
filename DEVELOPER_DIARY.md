# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **664** · The 10 most recent entries, newest first.

## 2026-11-20 — Step 664 — Export thumbnail and Smart Object assets from Photoshop manifests

Photoshop document manifests can include JPEG or PNG layer previews and exact copies of embedded Smart Object originals. The assets use Photato's authenticated local download URLs.

1,502 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Direct Adobe-hosted comparison of thumbnail geometry, defaults and bytes remains open. The native encoder chooses its progressive JPEG scan count. Intel tests ran under Rosetta.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-664) · [Details](PhotoCraftSwift/docs/ADOBE_MANIFEST_ASSETS_664.md).

## 2026-11-20 — Step 663 — Inspect Photoshop templates through the Adobe-compatible manifest

The Adobe-compatible manifest reports Photoshop document and layer metadata. Use the returned layer IDs to edit the same PSD or PSB through create-composite.

1,498 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional masked RGB32 test passed on Apple Silicon. On Intel, eight PSD composites matched the previous build byte for byte and reproduced its existing differences from the Photoshop fixtures. Both slices of the signed macOS 14+ universal preview launched offscreen. Layer thumbnails, original Smart Object extraction, full layer descriptors and comparisons with Adobe's hosted results remain open. Intel tests ran under Rosetta. The preview binaries declare macOS 14.0 as the minimum system version.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-663) · [Details](PhotoCraftSwift/docs/ADOBE_DOCUMENT_MANIFEST_663.md).

## 2026-11-20 — Step 662 — Fit replacement artwork inside Smart Object frames

Fit or fill replacement artwork inside an existing embedded Smart Object frame. The new ingredient remains editable as a nested Smart Object, including artwork outside the visible frame. Both the Photato and Adobe-compatible APIs expose content placement.

All 1,493 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop did not respond to read-only AppleEvent or Accessibility window checks. Independent Adobe output and the hosted service remain unverified. Intel ran under Rosetta and the signed binaries declare macOS 14.0.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-662) · [Details](PhotoCraftSwift/docs/SMART_OBJECT_CONTENT_PLACEMENT_662.md).

## 2026-11-20 — Step 661 — Smart Object templates get editable masks and blending

Smart Object template jobs can set opacity, blend mode and editable pixel masks when they place or replace artwork. Photato exposes the supported fields in its API capabilities.

The 1,482 selected cases passed across qualification and replay in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Each initial run passed 1,481 cases. After updating the obsolete mask assertion, all 142 replay cases passed in each configuration. The application inputs and signed binary stayed byte-identical. Both slices of the signed macOS 14+ universal preview launched offscreen. Adobe's hosted service was not run. Exact Adobe mask edge, placement and color output remain unverified. The Intel runtime used Rosetta, and the macOS 14 minimum was verified in the signed binary.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-661) · [Details](PhotoCraftSwift/docs/SMART_OBJECT_TEMPLATE_APPEARANCE_661.md).

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
