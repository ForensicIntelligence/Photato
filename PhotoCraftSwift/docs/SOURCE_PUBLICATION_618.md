# Source checkpoint 618

Native Swift 0.3.0, build 618, 19 November 2026. Eligible editable RGB8, RGB16, and RGB32 PSD and PSB files can omit the merged preview while keeping saved alpha, spot and Quick Mask planes.

The File Handling preference and explicit Photato API setting apply to eligible native saves, Image Processor output, and file downloads. Adobe v2 continues to write its existing merged preview.

All 970 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

A separate parser matched all 270 saved words across six fixture files. Live Photoshop reopen and byte comparison for deep placeholders remain open.

[Development record](DEVLOG.md#dev-step-618) · [Validation data](DEEP_COMPATIBILITY_618.json).
