# Source checkpoint 787

Camera Raw can export a DNG copy with supported adjustments embedded as XMP. The copy retains original sensor bytes, and the source stays unchanged.

Camera Raw 18.1.1 opened the Photato copy with Exposure +1.50, Contrast +21, Highlights −17 and Vibrance +9. All 393,216 sensor bytes matched the original and the Adobe-saved file. The sandboxed Photato export matched the tested copy byte for byte.

The authenticated `GET /v1/documents/{id}/smart-objects/{layerID}/source.dng` downloads a copy using the retained DNG and current committed settings. It requires native document transfers, supports the optional `X-Photato-Revision` header, and shares the native writer. The original source download stays byte-exact. The API reports a stale revision or revoked transfer without changing the document.

Xcode built the app. Three focused imaging tests and one real authenticated HTTP test passed. Both optimized architectures passed all 336 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

In-place Done, importing sidecar-only metadata into edited DNGs, general RAW-to-DNG conversion, preview regeneration, Apple-only sensor controls in XMP and exact Photoshop pixel rendering remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,327,625 bytes with SHA-256 `255d235efd263b4654cea4cd3755c3336c3e8f489797f497eba7f9b8eef0bec1`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_787.json) · [Development record](DEVLOG.md#dev-step-787).
