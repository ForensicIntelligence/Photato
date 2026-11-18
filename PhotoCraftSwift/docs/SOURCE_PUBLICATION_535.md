# Source checkpoint 535

Native Swift 0.3.0, build 535, 17 November 2026. The ordinary Brush now starts at 10% smoothing. The installed Photoshop control was observed in step 533, and Adobe also documents 10% smoothing and 25% round-brush spacing. Photato already used 25% spacing. [Adobe painting performance](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/brushes-presets/optimize-painting-and-cloning-using-brush-settings.html).

The ordinary Brush amount persists when changing tools or switching document tabs. The other painting tools use their separate amount and keep their previous initial value. The existing options bar and Brush Settings controls reflect the active amount. The current-brush API uses the active settings and the explicitly named paint, selection and adjustment operations resolve their own smoothing amount. The capability response records the default. Explicit 0%, tip-only presets and old Actions keep their existing meanings.

All 160 focused methods and seven retained Photoshop-reference methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. The corner stroke at 10% produces exact native pixel equality between desktop and HTTP. Explicit zero produces its own matching stroke. The old Action with absent brush settings and the newly recorded Action both replay to their own expected pixels. Three explicitly configured corner-stroke vectors match the retained build 534 Core bit for bit on both optimized architectures. The retained Photoshop methods cover 20 RGB32 compositing examples. Live Photoshop smoothing output bytes and other factory settings remain open.

## 24 MP Brush timing

Three runs at each setting use the same optimized build 535 AppKit workspace, an independently scheduled 120 Hz feed, 240 points and two tone adjustments. Each run checks the held preview, the full commit and Undo. The hosted workspace capture at 10% records the native toolbar. The timing reports software drawing.

| Stage | Explicit 0% | Factory 10% |
| --- | ---: | ---: |
| Median first input to AppKit draw | 26.38 ms | 23.85 ms |
| Continuous input-to-draw p95 | 17.20 ms | 18.44 ms |

Both extracted executable slices pass the signed package's built-in offscreen workspace check. Physical 60 fps, stylus timing, normal interactive bundle launch, actual macOS 14 and physical Intel remain unverified.

[Development record](DEVLOG.md#dev-step-535) · [Validation evidence](BRUSH_FACTORY_535.json) · [Frozen source](SOURCE_SNAPSHOT_535.json)
