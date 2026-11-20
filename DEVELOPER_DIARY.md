# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **668** · The 10 most recent entries, newest first.

## 2026-11-20 — Step 668 — Wrap editable Smart Objects around a cylinder

Cylinder Warp curves artwork around a product mockup in the native Warp sheet. PSD and PSB keep the editable shape when a Smart Object is reopened, replaced or relinked.

All 134 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The prior Intel RGB32 difference reproduced in a separate run. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop document query timed out. The Cylinder renderer uses published measurements. A Photoshop-authored Cylinder PSD, live mouse interaction and byte-identical Photoshop rerendering remain unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-668) · [Details](PhotoCraftSwift/docs/CYLINDER_WARP_668.md).

## 2026-11-20 — Step 667 — Keep Smart Object Warp editable in PSD and PSB

PSD and PSB now reopen supported Smart Object Warp presets, cubic meshes and nonuniform split grids as editable settings. Relinking a missing original restores its live Warp.

1,537 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop document query timed out. Unchanged saved samples and Photato-regenerated pixels were checked separately. An independent reader compared the encoded merged image planes in both outputs against Photoshop’s stored preview. In each format, 24 of 1,048,576 component bytes differ by one level, including three alpha bytes. Live Photoshop rerendering, Cylinder, PDF Warp and pre-Warp reconstruction of saved pixel masks remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-667) · [Details](PhotoCraftSwift/docs/EDITABLE_SMART_OBJECT_WARP_667.md).

## 2026-11-20 — Step 666 — Relink perspective artwork after reopening PSD and PSB

PSD and PSB preserve the image preview, location and four-corner placement of a linked Smart Object when its original is missing. Free Transform uses the saved artwork frame. Relinking restores source-based perspective editing.

1,511 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Photoshop's live document query timed out. The file and pixel comparisons use Photato and owned fixtures. Live Photoshop interchange, linked PDF perspective and non-identity Warp descriptors remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-666) · [Details](PhotoCraftSwift/docs/LINKED_PROJECTIVE_SMART_OBJECTS_666.md).

## 2026-11-20 — Step 665 — Reopen perspective Smart Objects and continue editing

Embedded Smart Objects with perspective placement keep their original bytes and editable corners in PSD and PSB. Free Transform starts from the saved artwork frame.

1,507 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Live Photoshop document scripting timed out after the read-only version query. Projective linked files, projective PDFs and editable non-identity Warp still need Photoshop-file coverage. Intel tests ran under Rosetta.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-665) · [Details](PhotoCraftSwift/docs/PROJECTIVE_SMART_OBJECT_ROUNDTRIP_665.md).

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
