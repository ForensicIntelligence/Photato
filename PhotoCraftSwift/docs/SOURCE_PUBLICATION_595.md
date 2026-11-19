# Source checkpoint 595

Native Swift 0.3.0, build 595, 19 November 2026. Large-canvas vector-mask Feather limits broad coverage preparation to the viewport and its filter margin.

On Apple Silicon, the 15 × 7 viewport through a 24,576 px mask at 1,000 px Feather took 8.506 s in build 594 and 1.367 s in build 595. The 250 px curved control took 6.063 s and 0.206 s. Each architecture matched all 420 sampled Float32 alpha words in build 594. The regression tests verify bounded input work at 300,000 × 300,000 pixels and whole-versus-regional coverage on a separate curved and inverted contour. [Adobe canvas size](https://helpx.adobe.com/au/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/file-size.html).

All 907 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted universal package passed the offscreen check and declare macOS 14 as the minimum. These tests establish rasterization equivalence for the measured viewport workload. Full-canvas broad masks, physical Intel and macOS 14, interactive frame pacing, and complete Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-595) · [Validation data](VECTOR_FEATHER_VIEWPORT_595.json).
