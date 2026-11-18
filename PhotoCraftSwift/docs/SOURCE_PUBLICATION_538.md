# Source checkpoint 538

Native Swift 0.3.0, build 538, 17 November 2026. The shared primary paint brush now reaches 5,000 px through Brush Tip controls, Brush Settings, the existing bracket shortcut, presets and typed HTTP. Adobe lists this range for Brush and Adjustment Brush, and step 455 observed a 5,000 px Eraser in the installed Photoshop. Live verification of the current Photoshop Pencil control remains open. [Adobe Brush and Adjustment Brush limits](https://community.adobe.com/questions-712/brush-size-limits-at-5000px-1181701).

Brush Tip controls keep exact numeric entry and use a logarithmic slider. A defined brush retains its sampled diameter up to the existing 2,500 px bitmap limit. Legacy strokes, retouch brushes, and secondary tips retain their separate diameter rules. Specialty painting kernels retain their footprint limits.

Strokes over 2,048 px use the complete renderer with tile-aligned coverage bands. Where a selection is present, the bands are limited to its projected extent. The stroke-wide work budget and atomic publication still apply. The new path checks cancellation during large dabs. All 197 focused and seven retained compositing methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Both executables from the universal ZIP passed the offscreen workspace check.

The full-size test deposited a 5,000 px color-dynamics dab on a 5,408 × 5,408 RGB8 surface. Independent executable slices produced the same digest across all 116,985,856 RGBA bytes and painted 19,642,833 nonzero-alpha pixels. The render took 2.11 seconds on Apple Silicon and 3.72 seconds under Rosetta. These are software measurements for one complete dab. The independent 24-dab native comparison also matched build 537 byte for byte on both architectures.

The AppKit and HTTP tests use a small document to verify the actual 5,000 px value, held preview, commit, exact Action replay, Undo and rejection above the maximum. The core tests separately cover the full footprint, color coverage and band boundaries, transformed selection clipping and atomic rejection under excess work. Source and package checks retain macOS 14 minimum metadata. Current locking prevented an interactive Photoshop recheck. Physical display timing, large-tip responsiveness and exact Photoshop brush output remain open.

[Development record](DEVLOG.md#dev-step-538) · [Validation evidence](BRUSH_DIAMETER_538.json) · [Frozen source](SOURCE_SNAPSHOT_538.json)
