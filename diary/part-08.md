[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-07.md)

## 2026-11-20 — Step 662 — Fit replacement artwork inside Smart Object frames

Fit or fill replacement artwork inside an existing embedded Smart Object frame. The new ingredient remains editable as a nested Smart Object, including artwork outside the visible frame. Both the Photato and Adobe-compatible APIs expose content placement.

All 1,493 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop did not respond to read-only AppleEvent or Accessibility window checks. Independent Adobe output and the hosted service remain unverified. Intel ran under Rosetta and the signed binaries declare macOS 14.0.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-662) · [Details](../PhotoCraftSwift/docs/SMART_OBJECT_CONTENT_PLACEMENT_662.md).

## 2026-11-20 — Step 661 — Smart Object templates get editable masks and blending

Smart Object template jobs can set opacity, blend mode and editable pixel masks when they place or replace artwork. Photato exposes the supported fields in its API capabilities.

The 1,482 selected cases passed across qualification and replay in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Each initial run passed 1,481 cases. After updating the obsolete mask assertion, all 142 replay cases passed in each configuration. The application inputs and signed binary stayed byte-identical. Both slices of the signed macOS 14+ universal preview launched offscreen. Adobe's hosted service was not run. Exact Adobe mask edge, placement and color output remain unverified. The Intel runtime used Rosetta, and the macOS 14 minimum was verified in the signed binary.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-661) · [Details](../PhotoCraftSwift/docs/SMART_OBJECT_TEMPLATE_APPEARANCE_661.md).

## 2026-11-20 — Step 660 — Free Transform follows Smart Object artwork

Free Transform handles follow an affine Smart Object's saved corners. Side and corner drags scale along the artwork's axes, and the angle field reads its current rotation. The Photato API exposes the frame and commit delta.

All 1,477 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe handle behavior, displayed scale percentages and output fidelity remain unverified. The Intel runtime used Rosetta, and the macOS 14 minimum was checked in the signed binary.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-660) · [Details](../PhotoCraftSwift/docs/ORIENTED_SMART_OBJECT_TRANSFORM_660.md).

## 2026-11-20 — Step 659 — Read the original transform of linked Smart Objects

Properties and Free Transform now use the original geometry of linked artwork when a reopened PSD or PSB has only a cached preview. The Photato API reports the same source transform, rotation and bounds.

All 1,472 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe Properties values, rounding, handle orientation, physical Intel, a macOS 14 runtime and full assistive-technology behavior remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-659) · [Details](../PhotoCraftSwift/docs/LINKED_SMART_OBJECT_GEOMETRY_659.md).

## 2026-11-20 — Step 658 — Custom Smart Object geometry for template jobs

The Adobe-compatible template API can set Smart Object size, position, rotation, skew and anchor. Jobs can place artwork relative to other layers and change the geometry of a linked PSD without supplying its original artwork again.

All 1,468 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The installed Photoshop session timed out. Exact Adobe hosted-service pixels, unobserved geometry defaults, physical Intel and a macOS 14 runtime remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-658) · [Details](../PhotoCraftSwift/docs/ADOBE_SMART_OBJECT_TEMPLATE_658.md).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-07.md)
