<a id="dev-step-562"></a>

## 2026-11-18 — Record Brush Actions for masks and channels

Brush strokes on a Smart Filter mask or a saved alpha or spot channel now make a playable step while an Action is recording. Replay keeps the Brush settings and input samples. It locates saved channels by name and occurrence and checks whether the destination is an alpha or spot channel. [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html) · [Smart Filter masks](https://helpx.adobe.com/photoshop/desktop/effects-filters/smart-filters/mask-smart-filter-effects.html) · [Editing channels](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/manage-channels-in-the-channels-panel.html).

The desktop Brush and the `paint.stroke` and `paint.tool` commands use their existing paint paths on playback. This matters because the two paths prepare masks and invert channel samples differently. Playback applies the saved stroke through the current selection. A prepared Brush stroke over a shape still creates an ordinary pixel layer above it. Undo removes that layer and the rest of the Action in one step.

Tests cover a shifted Smart Filter mask, soft selection coverage, duplicate saved names, a saved spot channel, and rollback if the matching channel type is missing. The new steps use Action version 68. The Photoshop reference desktop was locked. Live Adobe tool recording, byte equality, temporary Quick Mask Action playback, and process and ink-plate Brush Actions remain open.

All 531 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 96 direct and prepared Brush output buffers and 12 older Action encodings matched build 561 byte for byte on each architecture. Both slices of the macOS 14+ universal archive passed offscreen checks. [Qualification](SOURCE_PUBLICATION_562.md).
