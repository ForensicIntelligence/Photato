# Source checkpoint 675

Native Swift 0.3.0, build 675, 20 November 2026.

Warp saved paths, vector masks and shape contours in the main canvas. Switch from Free Transform and apply both changes in one Undo. The same edit works in the Photato API and Actions.

All 198 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The six new tests cover split tangents, a dense analytic curve comparison, untouched grids, locked and stale edits, continuous drag preview, canvas cancel and commit, Actions replay, authenticated automation, and editable PSD and PSB paths. All 12 earlier whole-layer vector mask outputs still match byte for byte.

All nine owned Wave, split mesh and Cylinder PSD, PSB and RGBA outputs agree byte for byte across the three builds. 2 of three native archives also match. The largest recorded change in editable curve coordinates across the builds is 1.46e-11 pixels.

Photoshop-authored warp output, switching from edited Warp back to Free Transform, and physical canvas performance remain open.

[Development record](PATH_WARP_675.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_675.json)
