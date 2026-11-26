# Source checkpoint 754

The Vanishing Point preview and raster grid now use the same plane scale as the Measure tool when you enter Grid Size manually. Keeping a manual size and linking a measurement of the same size now produces the same grid.

The authenticated Photato API reports the same projected intervals in scene state. Grid Size retains its existing value and file format.

All 69 focused Debug tests passed. Both optimized architectures passed 883 of 885 selected tests, including the new grid-spacing regression. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics.

The corrected tilted rectangle grid matches all 51,233 marked RGBA samples in the equivalent measurement-linked control. All 105,704 marked samples on the straight-on control remain exact, as do its complete PSD and PNG files. Photoshop’s preview spacing on the tilted reference agrees with the corrected geometry at the observed zoom. An independent Photoshop grid raster is still needed to qualify the exact coordinates, color and alpha. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/define-perspective-planes-in-vanishing-point.html).

The extracted Universal app passed signature verification and offscreen launches on both architectures. The macOS 14+ ZIP is 77,837,980 bytes with SHA-256 `6aebb7fec8caff9c78d78e830dd2ccbdfe416bed8c15d4e230ac65fd0bfab70c`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_754.json) · [Development record](DEVLOG.md#dev-step-754).
