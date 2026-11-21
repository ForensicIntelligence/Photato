# Source checkpoint 679

Native Swift 0.3.0, build 679, 20 November 2026.

Move selected path components forward or backward, change how they overlap, or merge their closed outlines. Merged vector shapes remain editable in supported PSD and PSB files.

All 263 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The desktop checks cover whole-component marquee selection, stacking order, selection after a move, and Undo and Redo. Actions replay the requested operation against the target path. The Photato API returns the selected indices after an edit.

All nine owned PSD, PSB and RGBA files matched byte for byte across the three builds. 13 of all 15 outputs matched, including native archives and coordinate data. The largest editable merge coordinate difference under Rosetta was 1.42e-14 document pixels. An independent PSD reader verified the editable contour order and boolean records in six owned files per configuration. It recognized merged outlines as vector shape layers.

Live Photoshop comparison and Adobe-authored byte equality remain open. Merge requires closed contours and a mergeable overlap region. The unbounded exterior of a leading subtraction on a shape layer remains open.

[Development record](PATH_COMPONENT_OPERATIONS_679.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_679.json)
