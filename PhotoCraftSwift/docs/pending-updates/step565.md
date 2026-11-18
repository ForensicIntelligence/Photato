<a id="dev-step-565"></a>

## 2026-11-18 — Add Allow Tool Recording to Actions

The Actions menu now controls whether a new recording captures Brush and other supported painting and retouching gestures. The default is off. A recording reads the setting when it starts, and the next recording uses any newly saved value.

Swift’s transaction layer still applies an omitted stroke and adds its normal history entry. The setting governs capture for Brush and Eraser, prepared paint tools, Adjustment Brush, retouch strokes, Paint Bucket and raster gradients, including supported channel and mask destinations. Older saved strokes still play. The new state and the existing `actions.manage` command share the preference used by the native Actions panel.

The implementation updates `ActionLibrary.swift`, `ActionsPanel.swift`, `Engine.swift`, and the automation schema and handler. Existing tests that expect tool steps explicitly enable capture before recording. Three additional tests cover persistence and session scope, native Brush capture and replay, and the HTTP preference and a process-channel stroke.

The installed Photoshop 2026 Actions panel showed Allow Tool Recording unchecked. Adobe documents enabling the switch before recording to capture interactive strokes. [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html). The exact extracted build opened a new Photato document, and Option-F9 opened its native Actions floating window. The desktop state changed before the checkbox could be exercised by hand. Automated desktop and HTTP tests cover the on and off behavior.

The GitHub README now links to a compact Developer Diary page with the ten most recent entries and access to the full history. A repository check compares the page, both source diary indexes, and the current build number on pushes and pull requests to main.

All 608 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. In 52 channel-stroke sequences, both recording settings produced the same raw samples as direct editing and the same per-architecture output as build 564. Forty older Brush step encodings also matched. Both universal slices passed offscreen checks.
The first Debug build caught a fixture calling the opt-in on its store factory instead of the shared document store. The corrected fixture calls the actual document store. No production behavior changed between those attempts.
The broader runs exposed two older assertions that expected 267 typed API commands. The same assertions also failed on the retained build 564 binary. Both tests now use the existing shared expected command count of 272. Their behavior assertions stayed unchanged.

The same 4,398 raw-byte differences between Apple Silicon and Intel from build 564 remain in RGB32 and Gray32. Of those offsets, 4,397 already differ in the converted input planes before painting. A standalone ColorSync probe returned the same initial sample words as each architecture. Photoshop’s channel-selection Action steps, percentage-based stroke coordinates, and byte-level output comparison remain open. [Qualification](SOURCE_PUBLICATION_565.md).
