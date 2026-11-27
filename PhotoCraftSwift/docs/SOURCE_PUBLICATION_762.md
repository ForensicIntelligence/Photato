# Source checkpoint 762

Saving an eligible layered Grayscale PNG now blends the retained gray and opacity samples directly. The 16-bit calculation promotes layer opacity before composing. Transparent pixels within the visible bounds retain the bottom layer’s gray, and pixels outside those bounds use transparent white.

Desktop Save and the authenticated Photato download use the same encoder. The HTTP regression uploads a layered PSD and compares its PNG with Desktop Save. Existing Adobe-compatible routes retain their current operation and format limits.

All 28 focused imaging tests and nine app and HTTP tests passed in Xcode Debug. Both optimized architectures passed all 215 selected tests. Intel ran under Rosetta.

Photoshop 27.2.0 opened four owned three-layer PSDs and saved PNG copies at 8 and 16 bits, each with opaque and transparent base cases. An independent reader compared all 16,384 gray and alpha pairs across standard and Adam7 Photato exports. All pairs matched, including hidden gray. The four noninterlaced exports also matched Photoshop’s filtered scanlines byte for byte. A fifth 16-bit reference distinguished the two half-tie rounding orders at 32 positions. All 128 gray and alpha pairs across its ordinary and Adam7 exports matched.

A separate sparse 36-megapixel Debug export saved and reopened, preserving the six tested gray and opacity pairs.

Complete PNG files differ. Photoshop’s observed profile setting left the reference untagged and the exported files also differ in metadata and compressed IDAT bytes. The numerical check covers aligned Normal layers with a shared profile. Masked or transformed stacks, other blend modes, TIFF and Photoshop merged previews still need separate verification.

The signed Universal ZIP targets macOS 14 and later. Both extracted architectures rendered offscreen. The 77,945,124-byte ZIP has SHA-256 `46f89e8fc0fea2ff0b4cf97ae0ecbeaadd203f6d41d483ee7d3f6b100e0a9841`.

[Adobe XMP media management fields](https://developer.adobe.com/xmp/docs/xmp-namespaces/xmp-mm/).

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_762.json) · [Development record](DEVLOG.md#dev-step-762).
