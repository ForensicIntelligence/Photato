# Source checkpoint 663

Native Swift 0.3.0, build 663, 20 November 2026.

The Adobe-compatible manifest reports Photoshop document and layer metadata. Use the returned layer IDs to edit the same PSD or PSB through create-composite.

1,498 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional masked RGB32 test passed on Apple Silicon. On Intel, eight PSD composites matched the previous build byte for byte and reproduced its existing differences from the Photoshop fixtures. Both slices of the signed macOS 14+ universal preview launched offscreen.

An authenticated manifest-to-edit round trip reopened the edited PSD and retained the original and fallback layer IDs. The tests also checked XMP opt-in, layer hierarchy, mask and blend state, destination equality and rejection of unauthorized downloads.

Layer thumbnails, original Smart Object extraction, full layer descriptors and comparisons with Adobe's hosted results remain open. Intel tests ran under Rosetta. The preview binaries declare macOS 14.0 as the minimum system version.

[Development record](ADOBE_DOCUMENT_MANIFEST_663.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_663.json)
