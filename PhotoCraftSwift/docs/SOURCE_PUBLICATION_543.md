# Source checkpoint 543

Native Swift 0.3.0, build 543, 17 November 2026. Gradient Rasterizer, Gradient Fill and Classic Gradient painting reuse ramp samples with identical Float32 coordinates. The rasterizer and ordinary Gradient Fill composition write through the existing tile writer. Large integer-depth Gradient Maps prepare the same 4,097 values their tone quantizer already selects. Continuous Float32 maps still evaluate the ramp directly. The desktop and the API share these render paths. Document formats, commands and API contracts stay compatible.

The optimized builds matched all 84 outputs against build 542, comparing 170,938,176 raw bytes on each architecture. The seven paths cover raster clips, editable fills, masked and clipped composition, Classic painting, Gradient Map layers and the direct Gradient Map command across four interpolation methods and three depths. Both optimized architectures agree on every output. The separate Gradient Map proof agrees with direct evaluation on 196,656 samples per architecture, covering every tone-grid position with both Reverse and Dither states.

All 372 selected methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. The tests include gradient workflows, PSD, compositing, Brush, history and HTTP routing. Both executables from the extracted validation ZIP passed the offscreen workspace check. The older Gradient Fill fixture with unsupported PSD shape data remains outside the selected tests.

## Software render timings

Each row is the median of six complete 2,048 × 2,048 RGB8 software renders in two trials after warmups. Each timed output matches build 542.

| Runtime | Operation | Build 542 | Build 543 |
| --- | --- | ---: | ---: |
| Apple Silicon | Classic raster | 147 ms | 48 ms |
| Apple Silicon | Linear raster | 314 ms | 48 ms |
| Apple Silicon | Perceptual raster | 351 ms | 49 ms |
| Apple Silicon | Perceptual raster, rotated 27.5° | 361 ms | 273 ms |
| Apple Silicon | Perceptual Gradient Fill composition | 586 ms | 261 ms |
| Apple Silicon | Perceptual Gradient Map composition | 522 ms | 245 ms |
| Apple Silicon | Perceptual Gradient Map command | 472 ms | 183 ms |
| Intel under Rosetta | Classic raster | 324 ms | 94 ms |
| Intel under Rosetta | Linear raster | 554 ms | 90 ms |
| Intel under Rosetta | Perceptual raster | 603 ms | 94 ms |
| Intel under Rosetta | Perceptual raster, rotated 27.5° | 598 ms | 438 ms |
| Intel under Rosetta | Perceptual Gradient Fill composition | 991 ms | 536 ms |
| Intel under Rosetta | Perceptual Gradient Map composition | 852 ms | 470 ms |
| Intel under Rosetta | Perceptual Gradient Map command | 767 ms | 355 ms |

The saved Photoshop RGB8 Gradient Maps still differ at 38 Classic, 285 Linear and 270 Perceptual pixels out of 16,384 each. The largest difference is one RGB8 level and all alpha samples agree. Physical 60 fps, interactive package verification, macOS 14 runtime validation and physical Intel testing remain open.

[Development record](DEVLOG.md#dev-step-543) · [Validation evidence](GRADIENT_REUSE_543.json) · [Frozen source](SOURCE_SNAPSHOT_543.json)
