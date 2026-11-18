# Source checkpoint 558

Native Swift 0.3.0, build 558, 18 November 2026. Paint Bucket and Magic Wand page large color matches, including tested sparse selections and fills at 300,000 pixels per side. The matcher reads samples in bounded patches. Contiguous matching uses a paged bit plane and spillable worklist. The current Magic Wand API uses the same native command. [Adobe Magic Wand](https://helpx.adobe.com/ie/photoshop/desktop/make-selections/automatic-color-based-selections/select-areas-by-color-with-the-magic-wand-tool.html) · [Adobe Paint Bucket](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/fill-paint-bucket-tool.html).

The 300,000-square cases cover uniform full and empty coverage, sparse connected and disconnected foreground, implicit-background selection with holes, and local or full opaque Normal bucket fills. A hosted AppKit and HTTP test exercises native Wand and Paint Bucket, one Undo and exact native-to-HTTP Wand selection. A separate native save-and-reopen check preserves a maximum sparse selection, and an interrupted large nonuniform flood preserves the source and selection. The tests measure the existing Photato selection semantics, including mask sampling, transforms, hidden color and antialiasing.

All 481 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. On each architecture, 240 color-region masks and 18 bucket render buffers match build 557 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks. The first Debug run rejected an out-of-range translation in a new fixture. The corrected test uses a valid scale that still exercises inverse coordinates beyond the sample guard. Production source was unchanged by that repair.

Full dense maximum-size runtime and scratch pressure, Paint Bucket Clear, typed Bucket API, and exact Photoshop pixel output remain open. Large partial-opacity, pattern and nonuniform full-canvas writeback still need work.

[Development record](DEVLOG.md#dev-step-558) · [Validation evidence](PAGED_COLOR_REGION_558.json) · [Frozen source](SOURCE_SNAPSHOT_558.json)
