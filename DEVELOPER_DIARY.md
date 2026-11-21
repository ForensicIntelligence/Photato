# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **677** · The 10 most recent entries, newest first.

## 2026-11-20 — Step 677 — Isolate a path’s layer while editing

Double-click a selected shape path or vector mask with either path selection tool to isolate its layer in the Layers and Paths panels. Double-click away from the path, turn off layer filtering, or choose another filter to exit.

All 225 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop comparison and physical Intel and macOS 14 testing remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-677) · [Details](PhotoCraftSwift/docs/PATH_ISOLATION_677.md).

## 2026-11-20 — Step 676 — Switch between path Warp and Free Transform

Switch between Warp and Free Transform while editing paths, masks or shape contours. The mesh follows later placement changes, and the whole edit applies in one Undo.

All 202 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Photoshop-authored path output, exact guide and mode behavior in Photoshop, and physical canvas speed remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-676) · [Details](PhotoCraftSwift/docs/PATH_WARP_SWITCH_676.md).

## 2026-11-20 — Step 675 — Warp editable paths on the canvas

Warp saved paths, vector masks and shape contours in the main canvas. Switch from Free Transform and apply both changes in one Undo. The same edit works in the Photato API and Actions.

All 198 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Photoshop-authored warp output, switching from edited Warp back to Free Transform, and physical canvas performance remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-675) · [Details](PhotoCraftSwift/docs/PATH_WARP_675.md).

## 2026-11-20 — Step 674 — Transform editable paths across layers

Select saved paths, vector masks and shape contours across layers and transform them together with Command-T. The Photato API and native Actions support the same atomic edit.

All 192 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop comparison, native path isolation, and editable Warp for paths remain open. Direct edits to shape contours can replace live primitive controls with editable cubic geometry.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-674) · [Details](PhotoCraftSwift/docs/CROSS_LAYER_PATHS_674.md).

## 2026-11-20 — Step 673 — Select path anchors with a Direct Selection marquee

Direct Selection now previews and selects anchors inside a dragged marquee. Shift adds to the selection. The same operation is available through the Photato API.

All 186 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The marquee operates on the active path. Simultaneous path selection across layers and exact Photoshop hit testing, modifiers and cursor comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-673) · [Details](PhotoCraftSwift/docs/DIRECT_SELECTION_MARQUEE_673.md).

## 2026-11-20 — Step 672 — Transform selected paths, contours and anchors

Command-T now transforms a saved path, vector mask or shape contour independently of its layer. Select whole contours or individual anchors and apply the same edit through the Photato API or an Action.

All 156 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Shape contours remain editable as Bézier geometry. A contour edit can replace the live primitive controls. Direct Selection marquee, path selection across layers, path Warp, and live Photoshop comparisons of partial projective transforms remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-672) · [Details](PhotoCraftSwift/docs/PATH_TRANSFORM_672.md).

## 2026-11-20 — Step 671 — Keep vector masks editable in Perspective and Distort

Perspective and Distort now move linked vector masks with the artwork and keep unlinked masks fixed. Masks remain editable after native, PSD and PSB saves.

All 131 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The original PDF was placed by Photoshop. Photato applied the reference transforms. Exact Photoshop anchors and pixels, independent Free Transform on a selected path, and vector masks with non-neutral Warp remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-671) · [Details](PhotoCraftSwift/docs/PROJECTIVE_VECTOR_MASKS_671.md).

## 2026-11-20 — Step 670 — Keep PDF Smart Object perspective editable

Embedded and linked PDF pages keep editable Perspective and Distort placement in PSD and PSB. Photato renders the source PDF at a density suited to the projected detail and retains the saved corners.

All 109 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. Photoshop 2026 reported version 27.2.0, then timed out on its read-only document query. The original test PDF was placed by Photoshop. The projected test variants were generated by Photato. Live Photoshop perspective comparisons and maximum dense source capacity remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-670) · [Details](PhotoCraftSwift/docs/PDF_PERSPECTIVE_670.md).

## 2026-11-20 — Step 669 — Keep PDF Smart Object Warp editable

Embedded and linked PDF Smart Objects retain editable Warp in PSD and PSB. The renderer resamples the original PDF when the Warp magnifies the artwork. The page, crop and layer controls stay editable.

All 88 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen. The running Photoshop scripting interface timed out. The independent Photoshop-authored PSD supplies the original PDF page and crop. A Photoshop-authored PDF with Warp, live Adobe rendering comparisons and full dense PDF capacity remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-669) · [Details](PhotoCraftSwift/docs/PDF_SMART_OBJECT_WARP_669.md).

## 2026-11-20 — Step 668 — Wrap editable Smart Objects around a cylinder

Cylinder Warp curves artwork around a product mockup in the native Warp sheet. PSD and PSB keep the editable shape when a Smart Object is reopened, replaced or relinked.

All 134 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The prior Intel RGB32 difference reproduced in a separate run. Both slices of the signed macOS 14+ universal preview launched offscreen. The installed Photoshop document query timed out. The Cylinder renderer uses published measurements. A Photoshop-authored Cylinder PSD, live mouse interaction and byte-identical Photoshop rerendering remain unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-668) · [Details](PhotoCraftSwift/docs/CYLINDER_WARP_668.md).
