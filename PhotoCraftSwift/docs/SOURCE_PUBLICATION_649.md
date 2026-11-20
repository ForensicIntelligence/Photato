# Source checkpoint 649

Native Swift 0.3.0, build 649, 19 November 2026.

PSD, PSB and chunked native Smart Object sources have a local 256 MiB budget. The two previously rejected PSBs retained exact bytes and editable contents, and a 262.5 MB reference passed native and PSB round trips.

All 1,372 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed an offscreen launch. The Debug save-sheet check passed on an isolated rerun after the sheet missed the suite's deadline.

Live Photoshop acceptance and physical Intel testing remain open.

[Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_649.json)
