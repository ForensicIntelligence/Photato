# Source checkpoint 562

Native Swift 0.3.0, build 562, 18 November 2026. Photato Actions can record Brush strokes on Smart Filter masks and saved alpha and spot channels. They also retain automatic pixel-layer creation when painting over a shape. The recipe stores the stroke samples, Brush settings, and portable target. Saved channels resolve by name and occurrence. Playback rejects a channel whose alpha or spot type differs from the original. [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html) · [Smart Filter masks](https://helpx.adobe.com/photoshop/desktop/effects-filters/smart-filters/mask-smart-filter-effects.html) · [Editing channels](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/manage-channels-in-the-channels-panel.html).

The desktop Brush and the existing `paint.stroke` and `paint.tool` API routes keep their original paint paths during replay. Playback uses the new document’s selection, mask placement, and channel interpretation. Each Action commits as one undoable edit. New records use Actions 68. Prior ordinary Brush, Pencil, and Paint Bucket steps retain their format requirements.

All 531 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 96 direct and prepared Brush output buffers and 12 older Action encodings matched build 561 byte for byte on each architecture. Both slices of the macOS 14+ universal archive passed offscreen checks.

The Photoshop reference desktop was locked. Live Adobe tool recording, byte equality, temporary Quick Mask Action playback, and process and ink-plate Brush Actions remain open.

[Development record](DEVLOG.md#dev-step-562) · [Validation evidence](TARGETED_BRUSH_ACTIONS_562.json) · [Frozen source](SOURCE_SNAPSHOT_562.json)
