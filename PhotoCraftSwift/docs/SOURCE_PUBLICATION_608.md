# Source checkpoint 608

Native Swift 0.3.0, build 608, 19 November 2026. Large sparse PSD and PSB saves can stream full-width raster edits through the existing row writer.

The 300,000 × 300,000 RGB8 PSB with paint across the first row saved in 9.20 s on Apple Silicon and 10.40 s under Rosetta. It reopened in 1.78 s and 2.86 s respectively. All authored raster bits matched.

An independent encoder matched all 8,445,600,024 bytes of RLE tables and payloads on each architecture. Separate Apple Silicon RGB16 and RGB32 checks preserved both raster layers and their mask.

All 941 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

Dense and ZIP maximum-size files, live Photoshop cross-open, and physical Intel and macOS 14 runtime remain open. [Adobe file format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-608) · [Validation data](WIDE_RASTER_EXPORT_608.json).
