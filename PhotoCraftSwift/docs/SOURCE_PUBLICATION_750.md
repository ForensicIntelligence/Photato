# Source checkpoint 750

Floating Vanishing Point pastes now have side handles for changing width or height independently. The arrow keys move a selected paste by one pixel. Shift and an arrow move it by ten. The current handle and modifiers are reflected in the pointer.

The authenticated Photato API exposes the resulting position and dimensions through the existing paste operation and workspace state.

All 62 focused Debug tests passed. Each optimized architecture passed 876 of 878 selected tests, including the updated side-handle and nudge assertions. Intel ran under Rosetta. The two inherited failures repeated their earlier diagnostics. The replay image of a side stretch, nudge and undo/redo matched across Debug and both optimized builds.

An independent nine-impulse RGB8 donor showed that Photoshop’s plain, Flip and Flop results differ from exact donor mapping at 112, 2,432 and 2,436 pixels. All three preserved every pixel outside the patch. The reflected responses moved different distances at different locations and had fractional spill. Exact Photoshop raster parity remains open. [Adobe’s Vanishing Point reference](https://helpx.adobe.com/uk/photoshop/using/vanishing-point.html).

The extracted Universal app passed signature verification and offscreen launches on both architectures. The macOS 14+ ZIP is 77,808,062 bytes with SHA-256 `5612900a5d4df1cd9d427fb6aa2b2df8b5e28488e01b9efc98fc2c4dcf5033ff`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_750.json) · [Development record](DEVLOG.md#dev-step-750) · [API](AUTOMATION_API.md#vanishing-point-clipboard-placement).
