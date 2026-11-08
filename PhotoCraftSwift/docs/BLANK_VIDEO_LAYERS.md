# Blank video layers

Use **Layer > Video Layers > New Blank Video Layer**, or the same command in the Timeline menu, to add transparent drawing footage. Create a video Timeline first and select the composite RGB target. The command adds one layer and one Undo step. Its initial dimensions, frame rate and visible span follow the current document Timeline.

Move the playhead and paint. Each source frame keeps its own pixels; painting one frame leaves its neighbours transparent. The existing brush preview, Cancel, commit, Undo/Redo, timing, masks, layer blending and rendering paths remain in use. Video groups sequence their children; use a separate track outside a sequential group when an overlay is needed. Photoshop’s exact naming, initial span and group insertion defaults still need direct qualification.

The frame store retains one transparent prototype plus only edited frames. It can index long blank footage without allocating a full image per frame. Existing movie and image-sequence decode limits are separate. Ordinary imported clips keep their legacy array encoding. Native version90 stores sparse footage and retained conversion sources; reopening does not require external media or a model.

A blank source initially contains the current Timeline’s frames. Extending that source, inserting/deleting/restoring frames and the remaining specialist video commands are still open. The existing one-day clip bound and normal memory, scratch, archive, transfer and export budgets continue to apply. The logical Timeline limit is 20,736,001 positions; decoded movie/image-sequence sources remain limited to 512 frames. Sparse storage is not proof that every tool or export supports the largest logical document.

## Optional API

Send `video.edit` with `{"operation":"blankLayer"}` and the current document revision. There are no extra parameters. It uses the same Core command as the native menu. State includes `video.canCreateBlankLayer`; each clip reports logical `sourceFrames`, `storedFrames` and `sparseFrames`. Timing schemas cover the logical range while the engine validates the actual clip.

Busy, stale, non-composite/mask targets and unavailable Timelines are rejected without an edit. Creation and painting share normal history. Existing `video.view`, `paint.stroke`, timing and file-transfer commands operate on the new clip.

Native downloads containing sparse footage require `X-Photato-Archive-Version:90`. Missing or older acknowledgements return 422 rather than silently dropping frames. The API advertises90 as the latest supported archive version while preserving legacy default output and older supported versions. No corresponding dedicated video endpoint is defined in the pinned Firefly v2 contract, and no unqualified Adobe animation ActionJSON binding is invented.

## Verification

All 111 selected Debug methods and the same111 optimized methods on Apple Silicon and translated Intel pass, including 13 new methods. Tests cover copy-on-write frame isolation, legacy bytes, malformed sparse data, all RGB depths, preview/Cancel/commit/history, file/conversion recovery, API equality/permissions/revisions/strict parameters, native90acknowledgement, existing video/rendering, factory menus/cursors and independent RGB32 regressions.

A 300,000 × 300,000 canvas and a 24-hour 240 fps Timeline retain one empty stored frame and stay below the tested 64 KiB document-storage and 128 KiB archive bounds. These are owned synthetic tests. They do not establish physical memory usage, dense maximum capacity, Photoshop video output/defaults, native live UI, supported physical platforms or 60 fps performance. Full SP01 and earlier failures remain open.

[Evidence](BLANK_VIDEO_LAYERS_476.json) · [Developer record](DEVLOG.md#dev-step-476)
