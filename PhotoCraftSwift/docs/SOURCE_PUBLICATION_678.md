# Source checkpoint 678

Native Swift 0.3.0, build 678, 20 November 2026.

Select several whole components on one path and align their edges, distribute their centers, or space them evenly. Supported compound shape layers remain editable in PSD and PSB.

All 256 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The desktop, Actions and Photato API share one fractional translation in document coordinates. Curve handles and the unselected components retain their geometry relative to their own contours. The Paths panel now shows the filtered path inventory during isolation.

15 of 15 owned PSD, PSB, RGBA, native archive and editable-coordinate outputs matched byte for byte across builds. An independent PSD reader found three indexed rectangle and ellipse primitives in each of six owned PSD and PSB samples from each build and checked their alignment and spacing from the stored bounds.

Live Photoshop layout comparison, exact Adobe-produced file bytes, arbitrary live origins and shapes outside the supported PSD paint and stroke settings remain open. Native Photato archives retain the edited curves.

[Development record](PATH_COMPONENT_LAYOUT_678.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_678.json)
