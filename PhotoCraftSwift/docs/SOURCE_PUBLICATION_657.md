# Source checkpoint 657

Native Swift 0.3.0, build 657, 20 November 2026.

Place Embedded and Place Linked now size artwork from its print resolution and the destination ppi. Resize Image During Place fits oversized artwork after converting to document pixels. The Photato API exposes the same geometry through an explicit physical sizing option.

All 1,463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen.

The independent raw PSD and PSB composite check recovered a 144 × 144 pixel placement of the 600 × 600 pixel, 300 ppi source in a 72 ppi document. Both architectures wrote byte-identical native, PSD and PSB files. Both optimized builds also passed the 1.18 GB linked PSB workflow.

The installed Photoshop session timed out on a read-only request. Exact Adobe rounding, interpolation, and format-specific placement behavior remain open.

[Developer Diary](DEVELOPMENT_DIARY.md) · [Development record](PLACEMENT_RESOLUTION_657.md) · [Validation data](SOURCE_PUBLICATION_657.json)
