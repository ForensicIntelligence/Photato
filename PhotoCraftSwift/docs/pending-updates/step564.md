<a id="dev-step-564"></a>

## 2026-11-18 — Record Brush Actions for color channels

Photato Actions can record Brush strokes on process color components, Duotone gray, and Multichannel ink plates. Replaying the stroke on another file resolves the destination layer or ink plate and clips the stroke to that file’s selection. An Action can address several components or plates at once. Two plates with the same name are distinguished by their order among plates with that name.

Record, Play and the Photato API use the same stroke commands as direct painting. With an explicit color target selected, playback is limited to Actions whose enabled strokes all address that target. A mismatched mode, missing plate, or change to the captured target during playback prevents the edit. Unselected planes and layer alpha keep their stored samples. The replay adds one Undo step. The new operation requires Action version 70.

The implementation updates the portable Action model in `RecordedActions.swift`, editor admission in `ActionLibrary.swift`, and desktop and HTTP playback and commit checks. No additional API command was required. The new tests exercise all process modes and supported depths, cross-document ink replay, an incompatible mode, a disappearing plate, and a target change before commit.

All 583 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. On each architecture, 52 tested channel strokes replayed to the same samples as direct editing and matched build 563’s raw planes. Forty legacy Brush step encodings also matched. Both slices of the macOS 14+ validation archive passed offscreen checks.
The initial Debug run passed 582 of 583 methods. The new HTTP test omitted the required layer ID in its mode.channel.edit request and received HTTP 400. The corrected test supplies the layer ID; production code stayed unchanged between those runs. The first byte-comparison harness used an Imaging-only conversion helper with Core-only linkage. The corrected harness constructs the Duotone fixture directly from owned samples.

Raw output differs across Apple Silicon and Intel in 4,398 of 182,016 bytes, reproducing the same difference from build 563. A live Photoshop 2026 test accepted a Brush stroke in a scratch document with Red and Blue selected. The Photoshop Action recording sequence, its saved samples, and its playback controls still need comparison. [Adobe channel controls](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/manage-channels-in-the-channels-panel.html) · [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html). [Qualification](SOURCE_PUBLICATION_564.md).
