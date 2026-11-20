# Source checkpoint 674

Native Swift 0.3.0, build 674, 20 November 2026.

Select saved paths, vector masks and shape contours across layers and transform them together with Command-T. The Photato API and native Actions support the same atomic edit.

All 192 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

New tests cover panel ranges, Command-click, canvas focus, multi-path marquee, a shared transform and one Undo, Actions playback and authenticated API editing. All 12 earlier whole-layer vector mask outputs matched byte for byte.

Live Photoshop comparison, native path isolation, and editable Warp for paths remain open. Direct edits to shape contours can replace live primitive controls with editable cubic geometry.

[Development record](CROSS_LAYER_PATHS_674.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_674.json)
