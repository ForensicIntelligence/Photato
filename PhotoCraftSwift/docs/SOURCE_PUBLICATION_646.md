# Source checkpoint 646

Native Swift 0.3.0, build 646, 19 November 2026.

The 9-megapixel editable Smart Filter test dropped from 164.4 to 7.2 seconds on optimized Apple Silicon. Three PSD and PSB exports matched the previous Photato codec byte for byte.

All 1,357 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed offscreen launch checks.

The large-file byte comparison references the earlier Photato codec. Photoshop-authored large Smart Filter output and physical Intel hardware remain open.

[Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_646.json)
