# Source checkpoint 795

The native Camera Raw panel applies five RGB color profiles, 8- or 16-bit output, independent PPI, and six aspect-ratio-preserving resize modes. The defaults preserve the source interpretation. The selected settings are saved for later opens.

Adobe Camera Raw 18.1.1 exposed those resize modes and separate resolution, color space and depth controls. The signed Photato app took the same 3,008 × 2,000 Nikon source to 1,504 × 1,000, RGB8 Display P3 and 300 ppi. Image Size confirmed 300 ppi in the opened copy. The original NEF and directory contents stayed intact.

The locally authenticated RAW import route accepts `X-Photato-Raw-Workflow` containing base64-encoded JSON. It can select an output profile, `"8 bit"` or `"16 bit"`, `pixelsPerInch`, and resize. The revisioned Camera Raw preference endpoint includes a separate `workflow` object for desktop defaults. Uploads without the header keep their existing defaults.

Xcode built the app and four new focused Debug tests passed, along with the five earlier opening tests. Both optimized architectures passed all 365 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The recorded checks cover the resulting geometry, profile, depth and PPI. Output sharpening, installed and non-RGB ICC profiles, and byte-identical Adobe output remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,679,198 bytes with SHA-256 `a83e81a326ad33f23e0e88e95c61626e4af751b3f4626f19c2b32db91f003452`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_795.json) · [Development record](DEVLOG.md#dev-step-795).
