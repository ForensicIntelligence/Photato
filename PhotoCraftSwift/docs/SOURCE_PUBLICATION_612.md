# Source checkpoint 612

Native Swift 0.3.0, build 612, 19 November 2026. Sparse PSD and PSB output reuses unchanged saved alpha, spot, and Quick Mask rows and retains the exact unchanged Float32 source words.

The file writer and reader round-tripped a 300,000 × 300,000 RGB8 PSB with an editable fill, a saved alpha, a spot channel and Quick Mask. All 15,360 stored alpha and spot samples matched. The 15.48 GB file took 6.95 seconds to write and 16.77 seconds to reopen in one Apple Silicon Debug run.

Independent executions saved the same 1,201 × 30,001 document on 611 and 612. All 7,924,054 output bytes matched. One Debug run took 38.41 seconds on 611 and 37.3 ms on 612.

All 960 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Two Debug offscreen tests passed on retry after the screenshot directory was restored. The binaries and all source inputs matched the first run. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The maximum-size round trip used synthetic RGB8 pixels and Photato file I/O. Live exchange with Photoshop and dense and deep maximum-size files remain open. [Adobe Large Document Format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-612) · [Validation data](PSD_SPARSE_AUXILIARY_OUTPUT_612.json).
