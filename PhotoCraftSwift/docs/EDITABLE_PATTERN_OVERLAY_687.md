# Keep Pattern Overlay editable in PSD and PSB

The Layer Style editor shows the actual pattern scale percentage and lets the user change angle and linkage. The PSD and PSB codec keeps the original layer reference point and rebases linked phase when exporting a moved overlay. Native editing and the existing local HTTP transfer use the same renderer. [Adobe Pattern Overlay controls](https://helpx.adobe.com/ie/photoshop/using/patterns-libraries-presets.html)

The Photoshop-authored document retained all 13 layers, six editable overlays, and all 196,608 merged RGB bytes in unchanged PSD and PSB exports. Changes to all six overlays reopened with their revised settings. The four exports were byte-identical across build configurations. A layer's generated vector-mask cache is removable only after it matches the existing alpha plane at every pixel and has the same bounds. This preserves the editable contours and the saved shape appearance. [Photoshop-authored fixture](https://github.com/psd-tools/psd-tools/blob/6a827c19543106cd83a50fd830b07312df950531/tests/psd_files/patterns.psd) · [Adobe file format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)

The shared reducer visits allocated tiles. The 4,000 × 4,000 sparse source at 25% now took 0.35 ms to prepare on the test Mac, compared with the prior 0.75 s measurement on the same fixture.

446 of 449 selected tests passed in each configuration, including Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three failures repeated on build 686 with the same assertions. Both signed macOS 14+ preview slices launched offscreen. Twelve earlier vector outputs, thirteen shape outputs and three canvas cutout files retained their established bytes.

The Photoshop color comparison covers the authored linked Normal overlays at 200% and 50% opacity. The existing style renderer still limits canvas area to 8,388,608 pixels. Other blend modes, rotated and fractional placement, and live Photoshop 2026 reopening require further comparison. [Qualification](SOURCE_PUBLICATION_687.md)
