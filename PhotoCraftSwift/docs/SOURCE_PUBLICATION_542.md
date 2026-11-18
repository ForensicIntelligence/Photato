# Source checkpoint 542

Native Swift 0.3.0, build 542, 17 November 2026. Linear and Perceptual gradients share the extended sRGB engine's widened power operation. The gradient's SDR clamp, Float32 operands, endpoint behavior, interpolation and OKLab matrices are retained. The Gradient tool, Gradient Fill, Gradient Map and supported shape gradients use the shared ramp in native and API workflows. Adobe documents Linear interpolation in linear light and Perceptual interpolation in OKLab. [Adobe gradient interpolation](https://helpx.adobe.com/uk/photoshop/using/gradient-interpolation.html).

The actual compiled ramp agreed across Apple Silicon and Intel under Rosetta on all 343,393 checked Float32 words. An independent 80-digit evaluation reproduced all 15,633 stored interpolation outputs after correcting 53 legacy RGB words. The original Rust fixture is retained and every output remains checked exactly against its independently validated expectation. The existing Float32 cube root also matched on both runtimes across all 1,065,353,217 nonnegative Float32 bit patterns from zero through one inclusive. No cube-root change was needed.

All 144 composite buffers agree across the two optimized builds of checkpoint 542. The 18 Gradient Map buffers that differed in 541 now match. The resolved cases change 155 RGB words on Apple Silicon by up to four Float32 steps. Alpha and all 32 Brush buffers match build 541. The three saved Photoshop RGB8 Gradient Map fixtures have identical native stored pixels to build 541. They still differ from Photoshop at 38 Classic, 285 Linear and 270 Perceptual pixels out of 16,384 each. The largest difference is one RGB8 level, with exact alpha on all three fixtures.

All 370 selected methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. The first attempt failed an older API test that still expected the former count of 267 commands, reproduced on both optimized build 541 binaries. The check now expects the existing 271 commands and retains its other tests. The build 542 application executable hashes match between attempts. Both packaged architectures passed the offscreen workspace check. An older Gradient Fill fixture with unsupported PSD shape data remains outside this qualification.

## Software gradient rasterization

The comparison uses a complete 2,048 × 2,048 RGB8 gradient with three stops. Each row is the median of six render times from two trials after warmups.

| Runtime | Method | Build 541 | Build 542 |
| --- | --- | ---: | ---: |
| Apple Silicon | Classic | 142 ms | 140 ms |
| Apple Silicon | Linear | 232 ms | 291 ms |
| Apple Silicon | Perceptual | 261 ms | 329 ms |
| Intel under Rosetta | Classic | 318 ms | 329 ms |
| Intel under Rosetta | Linear | 442 ms | 538 ms |
| Intel under Rosetta | Perceptual | 475 ms | 555 ms |

These results cover rendering in isolation. The remaining RGB8 differences include 16 Linear and 24 Perceptual pixels on the grayscale strip, where equal input channels remove chromatic tone weighting from the comparison. Physical editing cadence, broader Photoshop gradient equality and actual supported-platform deployment remain open.

[Development record](DEVLOG.md#dev-step-542) · [Validation evidence](GRADIENT_ROUNDING_542.json) · [Frozen source](SOURCE_SNAPSHOT_542.json)
