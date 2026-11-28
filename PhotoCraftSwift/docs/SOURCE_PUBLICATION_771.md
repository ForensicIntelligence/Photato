# Source checkpoint 771

Large layered RGB8 TIFFs now keep named selections alongside editable layers, layer masks and composite opacity. A saved channel can be loaded as a selection after reopening the file.

Photato reopened an 11,000 × 10,000, 660 MB TIFF with both named selections, their channel IDs, two editable layers and a local layer mask. An independent parser checked all 220 million saved-selection bytes and all 110 million opacity bytes. In two Photoshop captures, all 6,144 authored selection samples matched, with and without a separate opacity sample.

The authenticated Photato TIFF download preserves the saved channels, and the Adobe-compatible action resource decoder restores them from the exported bytes. Both interfaces use the native TIFF codec. HTTP transfer limits still apply.

Xcode built the native app. All 10 focused imaging and 6 app and HTTP tests passed. Both optimized architectures passed all 245 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

The new evidence covers classic stripped RGB8 TIFFs with named non-spot channels. Larger embedded layer payloads, additional channel types and depths, tile layouts, JPEG-in-TIFF and BigTIFF still need qualification.

The Universal ZIP targets macOS 14 and later. It contains 78,071,791 bytes with SHA-256 `4615c284cebeb1e2b55c284216b3e6a8d2691ddbf14325ff52db32a12e14ac95`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_771.json) · [Development record](DEVLOG.md#dev-step-771).
