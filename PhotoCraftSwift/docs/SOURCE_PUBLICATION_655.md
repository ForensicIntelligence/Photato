# Source checkpoint 655

Native Swift 0.3.0, build 655, 20 November 2026.

General settings now control automatic fit, the placement transform preview and whether new embedded artwork becomes a Smart Object or a pixel layer. Command–K opens the native General pane. The Photato API exposes the three persistent preferences and explicit pixel-layer placement for new embedded and PDF artwork.

All 1,452 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

Both optimized builds separately passed the 1.18 GB linked PSB workflow. Automatic refresh and package reuse retained the same original and updated SHA-256 values across architectures.

The installed Photoshop 27.2.0 replied to a version query, then timed out before starting the disposable placement script. Live comparison of placement, PPI, sampling, relink and package resolution remains open.

[Developer Diary](DEVELOPMENT_DIARY.md) · [Development record](PLACEMENT_PREFERENCES_655.md) · [Validation data](SOURCE_PUBLICATION_655.json)
