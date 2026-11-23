# Source checkpoint 730

Vanishing Point can now apply a local correction with the default camera on a sparse 300,000 × 300,000 document. The editable archive and authenticated Photato API retain and replay the resolved focal length.

A 300,000 × 300,000 sparse document passed the native preview, Apply, archive reopen, HTTP archive download, and Undo. The API accepted the default camera and replayed the resolved 300,000-pixel focal length. The automatic and explicit camera controls produced the same local composite crop on both optimized slices and in Xcode Debug. Separate core tests cross the 100,000-pixel boundary in both document orientations and retain a calibrated 500,000-pixel focal length.

The automatic-camera edit produced a 2,048 × 2,048 preview in 104 ms on optimized Apple Silicon and 185 ms under Rosetta on this sparse fixture.

826 of 828 selected tests passed on each optimized architecture, with Intel tested under Rosetta. All three new cases passed on both. The existing layer-effect and color-profile fixtures repeated their earlier differences, and the paired color-profile outputs matched build 729 byte for byte. Xcode built the project, all 11 focused core tests passed, and both signed macOS 14+ slices opened offscreen.

The maximum-size fixture is sparse and the correction uses one tile. Editable archives with focal lengths above 100,000 pixels require build 730 or later. Photoshop 2026 opened the reference modal on the owned texture fixture. The app disappeared before a stamp could be applied, so Adobe pixel equivalence remains open. Adobe documents the PSB dimension limit separately from this native workflow. [Adobe’s PSB limits](https://helpx.adobe.com/photoshop/desktop/save-and-export/export-files-to-different-formats/image-file-formats-supported-in-photoshop.html)

Build inputs **9,423**. Source digest `793ac40c8b04d56dc08e4b15c5c2c1d07b6992b8ee8dcebace7d5f3fea62a7a8`. Local universal preview SHA-256 `b40b8bf78e68d922fa518aec302d9610263c399c90cd5a11b19b210dd628768d`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-730) · [Evidence hashes](SOURCE_PUBLICATION_730.json)
