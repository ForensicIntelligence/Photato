# Source checkpoint 745

Vanishing Point Brush and Stamp use the start and end points of a Shift-drag to paint a straight stroke. Shift-click links the previous endpoint on an eligible face. The cursor reflects straight strokes and Stamp sampling. Brush and Stamp can clear an active Marquee without switching tools. The authenticated Photato API shares the renderer through `straightStroke`.

All 32 Core and 21 App and HTTP focused tests passed. The new regressions check endpoint rendering, cursor feedback for all 16 keyboard modifier combinations, and matching native/API document output with Undo. Exact Photoshop dab and hinge behavior still need a reference raster.

Apple Silicon and Intel under Rosetta each passed 867 of 869 selected optimized tests, including all three new cases. The two inherited failures repeated build 744’s diagnostics. All eight native PNGs matched across Debug and both optimized builds. On each owned guide, Shift mode matched the explicit two-point Brush output byte for byte and produced a different result from the freehand path.

The extracted Universal preview’s ad-hoc signature verified, and both macOS 14.0 slices rendered the workspace offscreen. The ZIP is 77,682,357 bytes. Its SHA-256 is `52cecc0eb164ce868565a8190f7a0201b8f8335a03892802712c3e75cfafd585`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable qualification](SOURCE_PUBLICATION_745.json) · [Development record](DEVLOG.md#dev-step-745) · [API](AUTOMATION_API.md#linked-brush-and-stamp-strokes).
