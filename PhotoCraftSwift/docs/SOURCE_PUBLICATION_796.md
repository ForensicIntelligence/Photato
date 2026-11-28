# Source checkpoint 796

Photato packs the same opaque RGB input for ColorSync without copying the source raster tile by tile. Hidden RGB and source alpha survive conversion. Opaque output avoids a second pass to restore alpha.

The full Nikon RGB8 Display P3 conversion took 5.71 seconds, down from 11.91 seconds in three alternating arm64 Debug trials. The stored samples and RGBA8 bytes matched the prior Photato path.

Twelve lossless Adobe Camera Raw TIFFs captured the nine synthetic sharpening variants, their baseline, and a separate Nikon pair. An independent TIFF reader found 16,562,956 changed RGB samples in Adobe’s Nikon Screen Standard export. The unsharpened Photato and Adobe Nikon exports differed at 18,044,936 of 18,048,000 RGB samples with the same visible sRGB16, 300 ppi and sizing choices.

The same conversion code serves the desktop and existing Photato and Adobe-compatible output paths. The change retains their existing profile, alpha and encoding settings.

Xcode built the app and two focused imaging tests passed, covering historical samples, signed float values, and hidden color. Four workflow and five opening regressions also passed. Both optimized architectures passed all 367 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The timing covers profile conversion in Debug. The Adobe comparison leaves sensor development, sharpening and file-byte equivalence open.

The Universal ZIP targets macOS 14 and later. It contains 78,684,484 bytes with SHA-256 `dee650ce0ad2ad751096df519929c2fadad209141e0d43069117aa275292a487`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_796.json) · [Development record](DEVLOG.md#dev-step-796).
