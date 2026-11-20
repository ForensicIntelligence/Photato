# Source checkpoint 636

Native Swift 0.3.0, build 636, 19 November 2026.

Photato fits high-resolution photos to paper while retaining original samples, and can prepare just the visible region of a much larger document printed at a fixed scale.

All 1,168 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

An independent PDF parser matched all 72,000,000 embedded 16-bit samples of a 24-megapixel photo. The rendered scale crop from a sparse 300,000-side canvas matched its control. Physical printer output and matching Photoshop output remain unqualified. Live Photoshop comparison remains open.

[Development record](DEVLOG.md#dev-step-636) · [Validation data](SOURCE_PUBLICATION_636.json)
