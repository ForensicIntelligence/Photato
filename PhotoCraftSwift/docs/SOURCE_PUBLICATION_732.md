# Source checkpoint 732

Vanishing Point can now apply Brush, Stamp and pasted repairs to an existing cropped pixel layer. The layer grows where needed and keeps its identity, original pixels and mask position. The native editor and authenticated Photato API use the same edit.

On the 1,600 × 1,200 owned layered PSD, Heal On extends the 1 × 1 Repair raster inside the selection. The existing-layer and separate-layer renders match across the full composite. The selected crop hashes match in Xcode Debug and both optimized architectures. The native editor and authenticated API retain the existing layer ID, its two underlying layers, the protected swatch, the archive and Undo. PNG export retains the tested repair sample.

833 of 835 selected tests passed on each optimized architecture, with Intel tested under Rosetta. All three new cases passed on both. The existing layer-effect and color-profile fixtures repeated their earlier differences. The paired color-profile outputs matched build 731 byte for byte. Xcode built the project. All 16 focused core cases and the cropped-layer application test passed in Debug. The signed macOS 14+ preview opened both architectures offscreen.

The saved Photoshop Off-mode fixture preserves the repaired layer and its perspective data. The corresponding Photato crop still differs at 455 of 901 pixels, by a mean 0.71 RGB8 levels per channel. Both outputs preserve the protected swatch. Photato preserved the imported Photoshop plane record byte for byte through a native archive and PSD re-export. Editable PSD exchange of the perspective planes remains open. The actual Photoshop 27.2.0 PSD saved its perspective rays in image resource 4000 with the `tNaF203` marker. The published format describes the older version-101 record. [Adobe’s Photoshop file format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)

Build inputs **9,423**. Source digest `943125c29ffcc93582c70de01d1aaaaaf18ebfa22fd90ba050ea4b3999f05e86`. Local universal preview SHA-256 `45c1e318ae75d450d4da82177c38e41f2c3512b1c20b415c9c63caaac4b44126`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-732) · [Evidence hashes](SOURCE_PUBLICATION_732.json)
