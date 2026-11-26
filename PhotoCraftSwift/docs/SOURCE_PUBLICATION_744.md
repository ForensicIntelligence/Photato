# Source checkpoint 744

Vanishing Point Brush and Stamp now constrain destination marks to the current perspective Marquee. A rectangle can extend across linked faces, and a Stamp donor can sit outside it. The desktop stores the rectangle with the stroke. The authenticated Photato API accepts the same `strokeSelection`, validates its bounds and shares rendering and Undo.

The focused Xcode suite passed all 31 Core and 19 App and HTTP tests. The geometric tests check both faces, Stamp samples and exact partial coverage at a one-pixel edge. Photoshop 2026 27.2.0 exited at the start of a Brush stroke on the owned tilted guide. The comparison still needs an Adobe raster. Shift-constrained strokes and other residual raster differences remain open.

Apple Silicon and Intel under Rosetta each passed 864 of 866 selected optimized tests, including both new tests. The existing color-profile and layer-effect failures repeated with identical diagnostics.

All eight native replay PNGs match across Debug and both optimized builds. The Brush, Stamp and healed Brush stayed inside the displayed selection and reached both linked faces. A single-plane Brush stayed on its starting face. The extracted Universal preview’s ad-hoc signature verified. Both slices target macOS 14.0 and rendered an offscreen workspace on the test Mac. The ZIP is 77,682,433 bytes with SHA-256 `4517e472da6297e73d0455cd8192f04c73fa40f4b0ea281363bee97c5e78d79c`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable qualification](SOURCE_PUBLICATION_744.json) · [Development record](DEVLOG.md#dev-step-744) · [API](AUTOMATION_API.md#linked-brush-and-stamp-strokes).
