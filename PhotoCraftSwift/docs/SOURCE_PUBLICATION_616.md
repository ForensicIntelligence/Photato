# Source checkpoint 616

Native Swift 0.3.0, build 616, 19 November 2026. Large Grayscale, CMYK and Lab Photoshop saves reuse unchanged layer samples. Eligible Gray32 previews reuse the same row writer.

A two-layer 1,531 × 5,491 Gray32 control matched all 34,060,421 bytes from build 615. Restoring the same sparse layers and writing the file took 274.9 milliseconds in the paired Apple Silicon Debug run, down from 44.80 seconds.

All 964 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

This benchmark used one sparse control. Layer masks, large dense files and live Photoshop exchange remain open for this path.

[Development record](DEVLOG.md#dev-step-616) · [Validation data](PSD_NATIVE_OUTPUT_616.json).
