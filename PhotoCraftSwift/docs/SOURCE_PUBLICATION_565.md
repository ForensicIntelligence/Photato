# Source checkpoint 565

Native Swift 0.3.0, build 565, 18 November 2026. The Actions menu now controls whether a new recording captures Brush and other supported painting and retouching gestures.

Allow Tool Recording starts unchecked and saves its value for future recordings. Each active recording retains the value it started with. With the switch off, a supported tool gesture still edits the document and creates its normal Undo entry. Menu commands and dialog settings retain their existing recording behavior. Saved actions can play with either setting. Existing Action files keep their format requirements.

The installed Photoshop 2026 Actions panel showed Allow Tool Recording unchecked. Adobe documents enabling the switch before recording to capture interactive strokes. [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html).

All 608 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. In 52 channel-stroke sequences, both recording settings produced the same raw samples as direct editing and the same per-architecture output as build 564. Forty older Brush step encodings also matched. Both universal slices passed offscreen checks. The exact extracted build opened a new Photato document, and Option-F9 opened its native Actions floating window. The desktop state changed before the checkbox could be exercised by hand. Automated desktop and HTTP tests cover the on and off behavior.

The same 4,398 raw-byte differences between Apple Silicon and Intel from build 564 remain in RGB32 and Gray32. Of those offsets, 4,397 already differ in the converted input planes before painting. A standalone ColorSync probe returned the same initial sample words as each architecture. Photoshop’s channel-selection Action steps, percentage-based stroke coordinates, and byte-level output comparison remain open.

[Development record](DEVLOG.md#dev-step-565) · [Validation evidence](TOOL_RECORDING_565.json) · [Frozen source](SOURCE_SNAPSHOT_565.json)
