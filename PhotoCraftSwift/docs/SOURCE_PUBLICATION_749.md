# Source checkpoint 749

Clipboard images pasted into Vanishing Point now start at the upper-left of the document at their original pixel size. They can be placed before any plane exists. Dragging the paste onto a fitted face preserves the grabbed point as the image adopts perspective.

The authenticated Photato API accepts a `canvasPaste` object as an alternative to plane coordinates. It uses the same renderer and document undo as the clipboard workflow.

All 62 focused Debug tests passed. Each optimized build passed 876 of 878 selected tests, including both new cases. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics. The replay PNG matched byte for byte across Debug and both optimized builds.

The direct 96 × 48 Flip comparison matched Photoshop at 1,789 pixels and differed at 2,819. All pixels outside the patch were preserved. Paste origin and dimensions now match the Photoshop control. Photoshop’s resampling still needs separate qualification. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/uk/photoshop/using/vanishing-point.html).

The extracted Universal app passed signature verification and offscreen launches on both architectures. The macOS 14+ ZIP is 77,804,243 bytes with SHA-256 `50f00a58c7998ca7d8513e793dc7dfabcde021b9e5a2db7b47dbdd15d4e9bc5c`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_749.json) · [Development record](DEVLOG.md#dev-step-749) · [API](AUTOMATION_API.md#vanishing-point-clipboard-placement).
