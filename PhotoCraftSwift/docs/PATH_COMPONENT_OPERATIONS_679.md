# Reorder, combine and merge path components

Focus a saved path, vector mask or shape path and select Path Selection. Shift-click whole components or drag a marquee from the canvas outside a component. The marquee selects groups with anchors inside its rectangle.

Use Path Arrangement to bring a component forward or to the front, or send it backward or to the back. Joined contours travel with their component. The new storage order follows the existing boolean sequence, so a subtraction can affect a different portion of the artwork after it moves.

Use Path Operations to combine, subtract, intersect, or exclude selected components. Merge Shape Components resolves the closed outlines and checks the resulting filled region. A total difference bound of one millionth of a square document pixel accounts for numerical residue in the vector solver. The resulting outline remains editable. Supported solid-color RGB 8- and 16-bit shapes can preserve that outline in PSD or PSB.

The same editing engine powers `paths.components`, native Undo, and Actions file version 81. `paths.select` with `marqueeScope` set to `components` selects whole components using document coordinates.

All 263 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. All nine owned PSD, PSB and RGBA files matched byte for byte across the three builds. 13 of all 15 outputs matched, including native archives and coordinate data. The largest editable merge coordinate difference under Rosetta was 1.42e-14 document pixels. An independent PSD reader verified the editable contour order and boolean records in six owned files per configuration. It recognized merged outlines as vector shape layers.

Live Photoshop comparison and Adobe-authored byte equality remain open. Merge requires closed contours and a mergeable overlap region. The unbounded exterior of a leading subtraction on a shape layer remains open. [Adobe path component controls](https://helpx.adobe.com/photoshop/desktop/draw-shapes-paths/create-shapes/manage-path-components.html) · [Adobe PSD/PSB specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [Qualification](SOURCE_PUBLICATION_679.md).
