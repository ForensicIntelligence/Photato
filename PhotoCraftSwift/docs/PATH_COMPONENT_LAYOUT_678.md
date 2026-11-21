# Align and distribute components on an editable path

Open the Paths panel and focus a saved path, work path, vector mask or shape path. Use Path Selection and Shift-click to add whole components. Choose Path Alignment for two or more components. Choose Distribute Paths for three or more. Both menus are available from the canvas context menu. Alignment uses the selected curves' combined bounds, and distribution preserves the two outside positions for the selected edge or spacing mode.

The edit moves whole components, including their Bézier handles, and uses one Undo. When the selected geometry can be expressed as translations of its live primitives, Photato retains their controls. Other editable contour changes remain available in the native file format.

In RGB 8- and 16-bit documents with supported solid fills and strokes, PSD and PSB preserve editable axis-aligned rectangles, rounded rectangles and ellipses sharing a layer. The vector mask record retains component order and boolean operations. The origination record retains each primitive. The importer checks that each primitive agrees with its contour before restoring its controls.

The Photato API provides `paths.layout`. Photato Actions file version 80 stores the mode and component indices and calculates positions again during playback. Earlier path Action versions are still readable.

All 256 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. 15 of 15 owned PSD, PSB, RGBA, native archive and editable-coordinate outputs matched byte for byte across builds. An independent PSD reader found three indexed rectangle and ellipse primitives in each of six owned PSD and PSB samples from each build and checked their alignment and spacing from the stored bounds.

Live Photoshop layout comparison, exact Adobe-produced file bytes, arbitrary live origins and shapes outside the supported PSD paint and stroke settings remain open. Native Photato archives retain the edited curves. [Adobe path component controls](https://helpx.adobe.com/photoshop/desktop/draw-shapes-paths/create-shapes/manage-path-components.html) · [Adobe PSD/PSB specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [psd-tools shape records](https://psd-tools.readthedocs.io/en/latest/reference/psd_tools.api.shape.html) · [Qualification](SOURCE_PUBLICATION_678.md).
