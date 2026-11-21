# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **681** · The 10 most recent entries, newest first.

## 2026-11-20 — Step 681 — Keep the shape exterior attached to the canvas

Moving a cutout now moves its contour while the fill reaches the current canvas edges. Canvas Size and Crop update the exterior, and supported PSD and PSB files retain the editable shape.

All 292 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The owned live Photoshop comparison timed out. Adobe’s public vector-mask and canvas documentation informed the expected behavior. Exact Photoshop live-shape output, transformed exteriors and very large styled fills remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-681) · [Details](PhotoCraftSwift/docs/EDITABLE_SHAPE_CANVAS_681.md).

## 2026-11-20 — Step 680 — Subtract the first component of a shape layer

A leading Subtract cuts a hole in the shape layer’s canvas fill. The contour remains editable in Photato and in supported PSD and PSB files.

All 287 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Sparse full-canvas rendering has been qualified for an integer-aligned solid fill on a 300,000 × 300,000 document without a visible stroke. The exterior currently retains the canvas frame set when it was created. Canvas resizing, moved or rotated exteriors in PSD, large gradients and strokes, and a direct Photoshop comparison of live shape data remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-680) · [Details](PhotoCraftSwift/docs/SHAPE_SUBTRACTION_680.md).

## 2026-11-20 — Step 679 — Reorder, combine and merge path components

Move selected path components forward or backward, change how they overlap, or merge their closed outlines. Merged vector shapes remain editable in supported PSD and PSB files.

All 263 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop comparison and Adobe-authored byte equality remain open. Merge requires closed contours and a mergeable overlap region. The unbounded exterior of a leading subtraction on a shape layer remains open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-679) · [Details](PhotoCraftSwift/docs/PATH_COMPONENT_OPERATIONS_679.md).

## 2026-11-20 — Step 678 — Align and distribute components on an editable path

Select several whole components on one path and align their edges, distribute their centers, or space them evenly. Supported compound shape layers remain editable in PSD and PSB.

All 256 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Live Photoshop layout comparison, exact Adobe-produced file bytes, arbitrary live origins and shapes outside the supported PSD paint and stroke settings remain open. Native Photato archives retain the edited curves.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-678) · [Details](PhotoCraftSwift/docs/PATH_COMPONENT_LAYOUT_678.md).

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
