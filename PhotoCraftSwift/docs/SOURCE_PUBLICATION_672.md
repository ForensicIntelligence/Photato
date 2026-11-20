# Source checkpoint 672

Native Swift 0.3.0, build 672, 20 November 2026.

Command-T now transforms a saved path, vector mask or shape contour independently of its layer. Select whole contours or individual anchors and apply the same edit through the Photato API or an Action.

All 156 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The path workflow passed native canvas gesture, Return, Undo, Action replay, authenticated editing, and PSD and PSB tests. All 12 whole-layer vector mask outputs from build 671 matched byte for byte. A separate Debug comparison passed all 34 existing Pen, Shape and menu cases on both builds.

Shape contours remain editable as Bézier geometry. A contour edit can replace the live primitive controls. Direct Selection marquee, path selection across layers, path Warp, and live Photoshop comparisons of partial projective transforms remain open.

[Development record](PATH_TRANSFORM_672.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_672.json)
