[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-07.md)

## 2026-11-20 — Step 676 — Switch between path Warp and Free Transform

Switch between Warp and Free Transform while editing paths, masks or shape contours. The mesh follows later placement changes, and the whole edit applies in one Undo.

All 202 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Photoshop-authored path output, exact guide and mode behavior in Photoshop, and physical canvas speed remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-676) · [Details](../PhotoCraftSwift/docs/PATH_WARP_SWITCH_676.md).

## 2026-11-20 — Step 675 — Warp editable paths on the canvas

Warp saved paths, vector masks and shape contours in the main canvas. Switch from Free Transform and apply both changes in one Undo. The same edit works in the Photato API and Actions.

All 198 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Photoshop-authored warp output, switching from edited Warp back to Free Transform, and physical canvas performance remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-675) · [Details](../PhotoCraftSwift/docs/PATH_WARP_675.md).

## 2026-11-20 — Step 674 — Transform editable paths across layers

Select saved paths, vector masks and shape contours across layers and transform them together with Command-T. The Photato API and native Actions support the same atomic edit.

All 192 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop comparison, native path isolation, and editable Warp for paths remain open. Direct edits to shape contours can replace live primitive controls with editable cubic geometry.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-674) · [Details](../PhotoCraftSwift/docs/CROSS_LAYER_PATHS_674.md).

## 2026-11-20 — Step 673 — Select path anchors with a Direct Selection marquee

Direct Selection now previews and selects anchors inside a dragged marquee. Shift adds to the selection. The same operation is available through the Photato API.

All 186 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The marquee operates on the active path. Simultaneous path selection across layers and exact Photoshop hit testing, modifiers and cursor comparisons remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-673) · [Details](../PhotoCraftSwift/docs/DIRECT_SELECTION_MARQUEE_673.md).

## 2026-11-20 — Step 672 — Transform selected paths, contours and anchors

Command-T now transforms a saved path, vector mask or shape contour independently of its layer. Select whole contours or individual anchors and apply the same edit through the Photato API or an Action.

All 156 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Shape contours remain editable as Bézier geometry. A contour edit can replace the live primitive controls. Direct Selection marquee, path selection across layers, path Warp, and live Photoshop comparisons of partial projective transforms remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-672) · [Details](../PhotoCraftSwift/docs/PATH_TRANSFORM_672.md).

## 2026-11-20 — Step 671 — Keep vector masks editable in Perspective and Distort

Perspective and Distort now move linked vector masks with the artwork and keep unlinked masks fixed. Masks remain editable after native, PSD and PSB saves.

All 131 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The original PDF was placed by Photoshop. Photato applied the reference transforms. Exact Photoshop anchors and pixels, independent Free Transform on a selected path, and vector masks with non-neutral Warp remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-671) · [Details](../PhotoCraftSwift/docs/PROJECTIVE_VECTOR_MASKS_671.md).

## 2026-11-20 — Step 670 — Keep PDF Smart Object perspective editable

Embedded and linked PDF pages keep editable Perspective and Distort placement in PSD and PSB. Photato renders the source PDF at a density suited to the projected detail and retains the saved corners.

All 109 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. Photoshop 2026 reported version 27.2.0, then timed out on its read-only document query. The original test PDF was placed by Photoshop. The projected test variants were generated by Photato. Live Photoshop perspective comparisons and maximum dense source capacity remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-670) · [Details](../PhotoCraftSwift/docs/PDF_PERSPECTIVE_670.md).

## 2026-11-20 — Step 669 — Keep PDF Smart Object Warp editable

Embedded and linked PDF Smart Objects retain editable Warp in PSD and PSB. The renderer resamples the original PDF when the Warp magnifies the artwork. The page, crop and layer controls stay editable.

All 88 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The running Photoshop scripting interface timed out. The independent Photoshop-authored PSD supplies the original PDF page and crop. A Photoshop-authored PDF with Warp, live Adobe rendering comparisons and full dense PDF capacity remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-669) · [Details](../PhotoCraftSwift/docs/PDF_SMART_OBJECT_WARP_669.md).

## 2026-11-20 — Step 668 — Wrap editable Smart Objects around a cylinder

Cylinder Warp curves artwork around a product mockup in the native Warp sheet. PSD and PSB keep the editable shape when a Smart Object is reopened, replaced or relinked.

All 134 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The prior Intel RGB32 difference reproduced in a separate run. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop document query timed out. The Cylinder renderer uses published measurements. A Photoshop-authored Cylinder PSD, live mouse interaction and byte-identical Photoshop rerendering remain unverified.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-668) · [Details](../PhotoCraftSwift/docs/CYLINDER_WARP_668.md).

## 2026-11-20 — Step 667 — Keep Smart Object Warp editable in PSD and PSB

PSD and PSB now reopen supported Smart Object Warp presets, cubic meshes and nonuniform split grids as editable settings. Relinking a missing original restores its live Warp.

1,537 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop document query timed out. Unchanged saved samples and Photato-regenerated pixels were checked separately. An independent reader compared the encoded merged image planes in both outputs against Photoshop’s stored preview. In each format, 24 of 1,048,576 component bytes differ by one level, including three alpha bytes. Live Photoshop rerendering, Cylinder, PDF Warp and pre-Warp reconstruction of saved pixel masks remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-667) · [Details](../PhotoCraftSwift/docs/EDITABLE_SMART_OBJECT_WARP_667.md).

## 2026-11-20 — Step 666 — Relink perspective artwork after reopening PSD and PSB

PSD and PSB preserve the image preview, location and four-corner placement of a linked Smart Object when its original is missing. Free Transform uses the saved artwork frame. Relinking restores source-based perspective editing.

1,511 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the prior Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Photoshop's live document query timed out. The file and pixel comparisons use Photato and owned fixtures. Live Photoshop interchange, linked PDF perspective and non-identity Warp descriptors remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-666) · [Details](../PhotoCraftSwift/docs/LINKED_PROJECTIVE_SMART_OBJECTS_666.md).

## 2026-11-20 — Step 665 — Reopen perspective Smart Objects and continue editing

Embedded Smart Objects with perspective placement keep their original bytes and editable corners in PSD and PSB. Free Transform starts from the saved artwork frame.

1,507 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Live Photoshop document scripting timed out after the read-only version query. Projective linked files, projective PDFs and editable non-identity Warp still need Photoshop-file coverage. Intel tests ran under Rosetta.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-665) · [Details](../PhotoCraftSwift/docs/PROJECTIVE_SMART_OBJECT_ROUNDTRIP_665.md).

## 2026-11-20 — Step 664 — Export thumbnail and Smart Object assets from Photoshop manifests

Photoshop document manifests can include JPEG or PNG layer previews and exact copies of embedded Smart Object originals. The assets use Photato's authenticated local download URLs.

1,502 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen. Direct Adobe-hosted comparison of thumbnail geometry, defaults and bytes remains open. The native encoder chooses its progressive JPEG scan count. Intel tests ran under Rosetta.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-664) · [Details](../PhotoCraftSwift/docs/ADOBE_MANIFEST_ASSETS_664.md).

## 2026-11-20 — Step 663 — Inspect Photoshop templates through the Adobe-compatible manifest

The Adobe-compatible manifest reports Photoshop document and layer metadata. Use the returned layer IDs to edit the same PSD or PSB through create-composite.

1,498 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional masked RGB32 test passed on Apple Silicon. On Intel, eight PSD composites matched the previous build byte for byte and reproduced its existing differences from the Photoshop fixtures. Both slices of the signed macOS 14+ universal preview launched offscreen. Layer thumbnails, original Smart Object extraction, full layer descriptors and comparisons with Adobe's hosted results remain open. Intel tests ran under Rosetta. The preview binaries declare macOS 14.0 as the minimum system version.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-663) · [Details](../PhotoCraftSwift/docs/ADOBE_DOCUMENT_MANIFEST_663.md).

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

## 2026-11-20 — Step 657 — Place Smart Objects at their source print size

Place Embedded and Place Linked now size artwork from its print resolution and the destination ppi. Resize Image During Place fits oversized artwork after converting to document pixels. The Photato API exposes the same geometry through an explicit physical sizing option.

All 1,463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The live Photoshop comparison remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-657) · [Details](../PhotoCraftSwift/docs/PLACEMENT_RESOLUTION_657.md).

## 2026-11-20 — Step 656 — Recover linked Smart Objects after moving a folder

PSD and PSB files now keep both linked-file locations. Locate Package Sources can find approved artwork in nested folders after a document moves. Desktop and API operations use the same lookup when updating or packaging the document.

All 1,457 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen. The live Photoshop comparison remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-656) · [Details](../PhotoCraftSwift/docs/PORTABLE_LINKED_PATHS_656.md).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-07.md)
