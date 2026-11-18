# Source checkpoint 564

Native Swift 0.3.0, build 564, 18 November 2026. Photato Actions can record Brush strokes on process color components, Duotone gray, and Multichannel ink plates.

Process strokes retain the layer reference, color mode and selected components. Duotone strokes retain the gray source. Multichannel strokes address plates by name and occurrence, so they can replay on another document with different plate IDs. Playback uses the destination selection and one Undo. While an explicit channel target is selected, Play admits enabled Brush steps that all address that target. Composite playback can apply mixed steps. New color-channel Brush steps require Action version 70. Older files retain their existing version requirements.

All 583 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. On each architecture, 52 tested channel strokes replayed to the same samples as direct editing and matched build 563’s raw planes. Forty legacy Brush step encodings also matched. Both slices of the macOS 14+ validation archive passed offscreen checks.

Raw output differs across Apple Silicon and Intel in 4,398 of 182,016 bytes, reproducing the same difference from build 563. A live Photoshop 2026 test accepted a Brush stroke in a scratch document with Red and Blue selected. The Photoshop Action recording sequence, its saved samples, and its playback controls still need comparison. [Adobe channel controls](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/manage-channels-in-the-channels-panel.html) · [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html).

[Development record](DEVLOG.md#dev-step-564) · [Validation evidence](COLOR_CHANNEL_ACTIONS_564.json) · [Frozen source](SOURCE_SNAPSHOT_564.json)
