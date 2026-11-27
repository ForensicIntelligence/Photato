# Source checkpoint 761

Open retains Grayscale PNG as an editable gray plane with straight opacity. Packed 2-bit and 4-bit values expand to 8-bit. Eligible flat 8-bit and 16-bit Save output retains the exact gray and opacity samples, including hidden gray, along with embedded profiles and declared gamma.

Native Open and Save and authenticated Photato import/download share the codec. The Adobe-compatible action resource reader uses the same implementation within its existing local 8-bit PNG limit. Command and request schemas stay the same.

All 36 focused Xcode Debug tests passed. Both optimized architectures passed all 214 selected tests, including the three new Grayscale PNG regressions. Intel ran under Rosetta.

Six independently generated files matched all 1,122 gray/alpha pairs on import. All 2,244 pairs in twelve standard and Adam7 exports matched. A 36-megapixel sparse control preserved the six sampled pairs through PNG and native archive round trips. Candidate 01 discarded declared gamma. The corrected reader retains the color interpretation of all three tested gamma values and the embedded gray ICC control. Layered grayscale still goes through the RGB composite. Its output differs from a diagnostic based on the measured RGB Normal model. Independent Photoshop Grayscale output and complete file equality remain open.

The Vanishing Point save replay wrote identical complete PSD and PNG files with both overlays shown, hidden or restored. The offscreen preview still differed at 16 pixels by one code value after restoration. The independent Photoshop grid raster and live shortcut remain open.

The signed Universal ZIP targets macOS 14+ and both extracted slices rendered offscreen. The 77,937,429-byte archive has SHA-256 `abe8259220d74a741bdd508f54e4554258f760060b822032b9a0a2ba3179aabc`.

[PNG sample and color-space specification](https://www.w3.org/TR/png/)

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_761.json) · [Development record](DEVLOG.md#dev-step-761).
