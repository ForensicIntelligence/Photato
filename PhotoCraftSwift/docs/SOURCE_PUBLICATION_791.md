# Source checkpoint 791

Camera Raw reuses the decoded pixel tiles when an opaque, full-canvas RAW layer has an identity transform and Normal blending. The native compositor preserves the same Float32 sRGB values.

The adjusted 3,008 × 2,000 Nikon preview’s composite stage took 0.54 seconds versus 11.35 seconds with the prior full compositor in one arm64 Debug probe. The comparison covered every Float32 sample and the complete RGBA8 display buffer. Native testing opened the Nikon, changed Exposure, generated a preview and cancelled without altering the original file.

The desktop, Photato API preview and supported Adobe-compatible operations share the optimized compositor. The HTTP contracts, rendered samples and stored RAW settings remain the same.

Xcode built the app and both focused imaging tests passed. Both optimized architectures passed all 351 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The measurement isolates compositing. Native decoding, exposure processing, display conversion and end-to-end interactive latency still need improvement. Exact Adobe output and physical Intel qualification remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,524,734 bytes with SHA-256 `cf16ba789d88f9261109117077e74f574bbd5e92eeaadf3cef07463f6d9cccb4`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_791.json) · [Development record](DEVLOG.md#dev-step-791).
