# Source checkpoint 676

Native Swift 0.3.0, build 676, 20 November 2026.

Switch between Warp and Free Transform while editing paths, masks or shape contours. The mesh follows later placement changes, and the whole edit applies in one Undo.

All 202 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The new tests exercise mixed transform order, a horizon between paths, changing a mesh handle after a perspective edit, mode switching with Apply and Cancel, Actions replay, and authenticated API validation. All 12 earlier whole-layer vector mask outputs match byte for byte.

9 of nine owned mixed-transform PSD, PSB and RGBA outputs agree byte for byte across the three builds. 2 of three native archives also match. The largest recorded change in editable curve coordinates across the builds is 1.48e-11 pixels.

For the owned 1,024-knot case, reusing the fitted Warp curves took a median 0.78 ms on Apple Silicon and 1.56 ms under Rosetta. This measures geometry preparation independently of canvas drawing and display.

Photoshop-authored path output, exact guide and mode behavior in Photoshop, and physical canvas speed remain open.

[Development record](PATH_WARP_SWITCH_676.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_676.json)
