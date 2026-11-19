# Source checkpoint 609

Native Swift 0.3.0, build 609, 19 November 2026. File Handling, Image Processor and Photato API output can omit the merged preview for eligible RGB8 PSD and PSB files.

Always includes a merged preview. Ask prompts during eligible desktop saves. Never skips the preview for RGB8 documents without saved channels. Unattended Ask saves include the preview by default.

All 1,974 PSD and 1,732 PSB placeholder bytes matched across five Adobe controls. Native saves, copy and cancellation passed, along with loopback API saves and downloads for all three settings.

All 954 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

Higher bit depths, saved channels, Photoshop factory preferences, exact dialog timing, live Photoshop cross-open, and physical Intel and macOS 14 runtime remain open. [Adobe file format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-609) · [Validation data](PSD_COMPATIBILITY_609.json).
