# Source checkpoint 665

Native Swift 0.3.0, build 665, 20 November 2026.

Embedded Smart Objects with perspective placement keep their original bytes and editable corners in PSD and PSB. Free Transform starts from the saved artwork frame.

1,507 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen.

The four new tests exercised editable PSD and PSB output, original source bytes, mask position, cached render, malformed corners, hit-testing and repeat Distort. A separate reader checked six files and the raw double-precision corner records.

Live Photoshop document scripting timed out after the read-only version query. Projective linked files, projective PDFs and editable non-identity Warp still need Photoshop-file coverage. Intel tests ran under Rosetta.

[Development record](PROJECTIVE_SMART_OBJECT_ROUNDTRIP_665.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_665.json)
