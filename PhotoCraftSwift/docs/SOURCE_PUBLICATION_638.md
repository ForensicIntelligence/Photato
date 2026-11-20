# Source checkpoint 638

Native Swift 0.3.0, build 638, 19 November 2026.

Native documents retain committed print settings and hard-proof conditions. Editable PSD and PSB update supported Photoshop Print Information and Print Style fields.

All 1,171 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

An independent parser verified seven supported print values and all 22 other retained fields in both Photoshop formats. The original Debug run returned one unexpected AppKit modal conflict. A second run stalled in an implicit autosave error alert. The same Debug binaries then passed the full test inventory in fresh XCTest processes. Live Photoshop and physical print comparison remain open.

[Development record](DEVLOG.md#dev-step-638) · [Validation data](SOURCE_PUBLICATION_638.json)
