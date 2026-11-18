# Source checkpoint 537

Native Swift 0.3.0, build 537, 17 November 2026. Pencil strokes can now be recorded and played in the Actions panel and over the automation API. Each step retains the exact samples, the brush settings, a portable target and the Auto Erase option. At playback, the same Pencil renderer checks the first point in the destination to choose the foreground or background color. Playback is one undoable transaction.

Version 62 is required for a file containing a Pencil step. Older files keep their original requirements. Supported destinations are pixels, layer masks, Smart Filter masks and saved alpha channels. Pencil on Quick Mask still needs visibility-aware playback. The existing API uses `actions.manage`, `paint.tool` and `actions.play`.

All 192 focused and seven retained compositing methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. The checks include Shift-click record and replay, native history, HTTP capture and replay, Auto Erase with different destination pixels, the version 62 file guard and resolving mask or saved-alpha targets in a different document. The two extracted executables passed the offscreen workspace check.

## Brush reference

The installed Photoshop 2026 app produced six isolated round dabs at each of four hardness settings. The test used the stock Hard Round preset, a transparent RGB8 layer, 100% zoom, Normal mode, 100% opacity and flow and 0% smoothing. Photato's aligned and nominal 8-bit alpha renders match across the two native architectures and against build 536. Photoshop alpha still differs. The 24 reference samples and their measured differences are in the evidence file. [Adobe Brush and Pencil workflow](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/brushes-presets/paint-with-brush-or-pencil-tool.html).

The following 0% hardness values compare the centered native output against a diagnostic Gaussian fit. Each 70 × 70 crop is compared with its saved Photoshop reference. The candidate uses the measured peak and one coefficient fitted to this sheet.

| Nominal diameter (px) | Native total alpha error | Gaussian total alpha error | Largest Gaussian error |
| ---: | ---: | ---: | ---: |
| 3 | 280 | 12 | 2 |
| 7 | 1,309 | 51 | 2 |
| 12 | 4,222 | 294 | 3 |
| 13 | 4,721 | 119 | 1 |
| 21 | 11,799 | 423 | 2 |
| 41 | 45,449 | 1,191 | 2 |

The curve is within one level at every sample in the two earlier 13 px soft dabs from checkpoint 536. Those two Photoshop dabs differ from each other at 137 samples after peak alignment. The earlier sheet supplies a second capture at one diameter. Exact input placement and the source of the one-level differences are unresolved. More holdout diameters, subpixel positioning and timed smoothing remain open. The diagnostic is outside the production brush renderer. Physical 60 fps, tablet response, interactive packaged launch, actual macOS 14 and physical Intel still need verification.

[Development record](DEVLOG.md#dev-step-537) · [Validation evidence](PENCIL_ACTIONS_537.json) · [Frozen source](SOURCE_SNAPSHOT_537.json)
