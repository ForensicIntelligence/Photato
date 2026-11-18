# Source checkpoint 544

Native Swift 0.3.0, build 544, 17 November 2026. The Brush prepares fixed rotation, projection, bitmap scale, centre alignment and falloff once per dab. The unrotated round-tip path identifies fully covered or empty tiles, with a half-pixel margin before falling back to the existing distance calculation. Primary and dual tips in the shared painting tools use the same prepared geometry. Native and HTTP commands share these raster operations. On a ready ordinary canvas the first Brush preview now submits within the pointer event, including wide tips that use the complete renderer. The command and file format stay compatible.

All 64 raw output buffers reproduced build 543 on both architectures. The comparison includes both retained and complete strokes, RGB8, RGB16, RGB32, linear storage, aliased and projected tips, and the Background Eraser, Color Replacement, Mixer Brush and Pattern Stamp routes. All 388 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. Both extracted universal executables passed the offscreen workspace check. The prior unsupported PSD shape fixture remains outside the selected suite.

## Hosted AppKit canvas

Each median uses two runs per build, with the order reversed for the second run. The fixture uses 240 generated points at 120 Hz on a 6,000 × 4,000 raster with two live adjustments, at 12.5% zoom. All 16 runs verify the final native command pixels, one commit and Undo.

| Diameter | 543 first draw | 544 first draw | 543 draws during input | 544 draws during input |
| --- | ---: | ---: | --- | --- |
| 64 px | 21 ms | 21 ms | 119, 119 | 119, 120 |
| 1,800 px | 473 ms | 483 ms | 2, 3 | 2, 3 |
| 2,500 px | 882 ms | 859 ms | 1, 1 | 1, 1 |
| 5,000 px | 2442 ms | 2343 ms | 0, 0 | 0, 0 |

Both 2,500 and 5,000 px cases now start the first worker with one input sample. The timing includes the worker, AppKit draw and generated input. Physical display presentation, physical tablet input and 60 fps with large tips remain open.

## Software brush rendering

Each median uses four complete renders from the actual optimized modules, after warmups. Every timed output matches build 543.

| Runtime | Operation | Build 543 | Build 544 |
| --- | --- | ---: | ---: |
| Apple Silicon | 64 px soft RGB8 | 0.1 ms | 0.1 ms |
| Apple Silicon | 1,800 px retained soft RGB8 | 79.0 ms | 62.5 ms |
| Apple Silicon | 2,500 px soft RGB8 | 148.9 ms | 117.1 ms |
| Apple Silicon | 5,000 px soft RGB8 | 586.4 ms | 441.9 ms |
| Apple Silicon | 2,500 px hard RGB8 | 139.2 ms | 99.3 ms |
| Apple Silicon | 1,800 px soft RGB8 stroke | 117.8 ms | 85.3 ms |
| Apple Silicon | 1,100 px rotated elliptical tip, Float32 | 34.3 ms | 33.1 ms |
| Apple Silicon | 900 px wet edges and noise, Float32 | 41.8 ms | 42.0 ms |
| Intel under Rosetta | 64 px soft RGB8 | 0.2 ms | 0.2 ms |
| Intel under Rosetta | 1,800 px retained soft RGB8 | 136.6 ms | 114.7 ms |
| Intel under Rosetta | 2,500 px soft RGB8 | 223.0 ms | 184.4 ms |
| Intel under Rosetta | 5,000 px soft RGB8 | 835.7 ms | 679.1 ms |
| Intel under Rosetta | 2,500 px hard RGB8 | 195.1 ms | 146.6 ms |
| Intel under Rosetta | 1,800 px soft RGB8 stroke | 164.4 ms | 123.8 ms |
| Intel under Rosetta | 1,100 px rotated elliptical tip, Float32 | 53.0 ms | 50.8 ms |
| Intel under Rosetta | 900 px wet edges and noise, Float32 | 65.2 ms | 63.1 ms |

An isolated first-dab run on the same 24 MP document measured 381 ms for painting, 1555 ms for layer composition and 344 ms for display image conversion at 5,000 px. These are median software timings of three runs.

[Development record](DEVLOG.md#dev-step-544) · [Validation evidence](WIDE_BRUSH_PREPARATION_544.json) · [Frozen source](SOURCE_SNAPSHOT_544.json)
