# Source checkpoint 725

Photato converts allocated tiles when a bounded sRGB raster changes to 8 or 16 bits per channel. Clone Stamp and Healing Brush use the faster conversion when preparing samples for a stroke. The desktop and authenticated Photato API share that conversion.

On the 2,096 × 2,592 portrait, the Apple Silicon depth conversion took 119 ms for RGB8 and 117 ms for RGB16. The former scalar loop took 194 and 193 ms. Every raw sample word matched at both depths on both optimized architectures. Each architecture matched all 12 build 724 PNGs across ordinary and cropped correction layers. Preview, commit, editable reopen and authenticated API pixels matched, with one Undo per stroke.

The ordinary New Layer first preview took 117–125 ms on optimized Apple Silicon after source selection. In the adjacent build 724 run it took 181–192 ms. A scripted 48-sample gesture produced 42 Clone Stamp and 41 Healing Brush software previews on an ordinary new layer. The cropped control produced 3 and 3, respectively.

795 of 797 selected tests passed on each optimized architecture, with Intel tested under Rosetta. The existing PSD layer-effect test repeated the same 118 assertions. The wider suite also surfaced a color-profile fixture failure. The retained build 723 bundles reproduced all 34 Apple Silicon and 294 translated Intel assertions. On each architecture the two builds also produced identical dense and paged color-profile output bytes. The new exact-storage regression passed on both architectures and among 23 focused Xcode Debug tests. Xcode successfully built the application, and both signed macOS 14+ preview slices opened offscreen. The SwiftPM Debug frontend trapped before the broad suite could run. Xcode Debug separately matched the benchmark sample words and the two tools’ selected native and API output for each layer geometry.

The timings measure software preparation and the first complete preview on one test host. Physical pointer-to-display cadence and direct Photoshop comparison remain open. The last Photoshop 27.2.0 workspace inspection at build 724 exposed no accessible editing window or menu bar.

Build inputs **9,423**. Source digest `2af2c939102c869c2cabea933dc54c44bead67b6462ccab326fb420c077e3865`. Local universal preview SHA-256 `879badf654242e2b45a90f0ead1c77dcc11f533ebcd54881c906a00706fe5ba3`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-725) · [Evidence hashes](SOURCE_PUBLICATION_725.json)
