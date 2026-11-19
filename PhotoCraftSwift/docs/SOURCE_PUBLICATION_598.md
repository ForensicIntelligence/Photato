# Source checkpoint 598

Native Swift 0.3.0, build 598, 19 November 2026. Whole-canvas rendering reuses feathered tiles for eligible integer-aligned rectangular vector masks.

A 300,000 × 300,000 document with a rectangular vector mask and a sparse raster edit rendered in 197 tiles in the regression test. The tile index reuses the rendered samples across the canvas. On a 37.8 MP RGB32 control, median whole-canvas render time went from 3.912 s to 0.103 s on Apple Silicon and from 8.245 s to 0.194 s under Rosetta. Each median uses three alternating runs on the same host.

The 37.8 MP and 300,000 × 300,000 controls each matched 11,560 sampled Float32 words against build 597 on both architectures. For the larger control the new whole-canvas render was compared with the previous viewport render.

All 912 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed offscreen launch and signature checks and declare macOS 14 as their minimum. Only the app’s build number changed after compilation. Packaging checks recorded the executable hashes and verified the new metadata.

Fresh Photoshop samples remain pending after an AppleEvent timeout. Broad curved and subpixel paths, RGB32 bottom-layer opacity proofs, complex stacks, physical Intel and macOS 14 runtime checks, and full Photoshop byte parity remain open. The 1,000 px maximum-canvas stripe exceeded the 200-second validation cutoff.

[Development record](DEVLOG.md#dev-step-598) · [Validation data](WHOLE_VECTOR_FEATHER_598.json).
