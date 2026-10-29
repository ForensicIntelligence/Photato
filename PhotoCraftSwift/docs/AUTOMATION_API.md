# Photato local automation API — v1 preview

## Frame animation to video Timeline (step245)

`animation.edit` accepts `{"operation":"toVideo","frameRate":30}` in the usual command/revision envelope. The frame animation becomes a video Timeline in one undoable transaction. The same command backs Timeline > Convert to Video Timeline. Rate is required, finite and1–240; unrelated fields reject400, stale/busy edits409, unsupported contexts or capacity limits422. Source pixels, layer tree, masks and shared editable content remain intact. Variable frame compositions become Hold Transform/Opacity/Style/Visibility tracks. Visibility only accepts Hold interpolation; new converted keys inherit the evaluated interpolation. Automatic capture edits the selected video time through normal layer controls.

Keys retain exact cumulative source delays using the existing20ms minimum for zero/short delays. Fixed-rate output samples that sequence and rounds total duration upward to a complete frame; a low rate can skip very short source compositions. The selected frame maps to its first available output sample. `finiteLoopCount` preserves positive total-pass counts from the selected frame; zero source loops become infinite. A subsequent `video.edit` loop toggle resets the finite count. Video work areas and both native playback clocks respect these limits. Converted placement keys carry `frameComposition:true` so evaluation changes placement without baking shared content/masks.

Readers accept native1–59. Converted keys, Visibility tracks and finite-loop metadata require native59; request `X-Photato-Archive-Version: 59`. Downgrades reject rather than strip state. The API exposes these values in `animation`, `video` and `keyframes` state/capability schemas; the existing command count remains172. The pinned Adobe v2 contract defines no Timeline conversion endpoint, so this remains a Photato extension. Reverse conversion, editable PSD/Actions animation interchange, exact Photoshop defaults/loop semantics and live/platform qualification remain open. Native controls initially suggest30fps; this default is not yet qualified against Photoshop.

## Trim document duration to the work area (step244)

`video.trimWorkArea` uses the same transaction as **Timeline > Work Area > Trim Document Duration To Work Area**. The typed command inventory is191. The operation takes no parameters beyond the ordinary revision-guarded command envelope:

```json
{"command":"video.trimWorkArea","revision":"<current revision>","parameters":{}}
```

The current work area becomes the full output duration, beginning at frame zero. Clip, soundtrack, keyframe and playhead times move by the work-area start. Wholly unused temporal layers/audio and unnecessary keyframes are removed; surviving layer content stays editable. Clipping bases, group ancestors and crossfade participants remain when needed. Original source frames/movie/audio bytes and bounding interpolation keys are retained as handles so cropping through a fade or crossfade does not restart its envelope. Undo restores the complete original; subsequent native saves retain the cropped output and surviving handles.

`video.timeline.trimmedToWorkArea:true` identifies this representation. Reported clip/audio/group start times and bounding keyframe times may be negative, or extend beyond the output duration. Ordinary editing retains the explicit cropped duration; changing duration/rate or inserting new video/audio can extend it. Clip/audio edge drags use the visible cropped boundary. The signed `startTime` field in `video.edit` and `audio.edit` permits editing retained pre-roll; ordinary untrimmed documents still reject negative placements. Video Group Start remains a nonnegative placement command. Source bounds and fades stay nonnegative. More complex grouped/ripple gestures and exact Photoshop handle-retention semantics remain unqualified.

Trimmed documents require native58; request `X-Photato-Archive-Version: 58` to download them. `nativeArchives.timelineTrimVersion` is58 and readers accept1–59. Earlier work-area/onion-only documents still have minimum version57. Downgrading trimmed documents rejects explicitly. Missing/unknown fields reject400; malformed ranges, locked affected layers or invalid timing reject422; busy/stale requests reject409. Full-range trimming is a content no-op; the native menu disables it. API state/capabilities expose the operation and signed timing schemas. No dedicated Adobe v2 Timeline trim endpoint exists in the pinned contract, so no Adobe route is added.

This supersedes earlier statements that work-area trimming is unavailable. Frame/video conversion, full PSD/Actions interchange, long media, exact Photoshop output/controls and supported-platform acceptance remain open. Qualification is recorded in the step244 development record; module tests do not establish complete Photoshop equivalence.

## Timeline workspace (step242)

`video.workArea` and `video.onionSkin` share the native Timeline model, Undo/Redo and persistence. At step242 the typed command inventory reached171. These are Photato extensions; the pinned Adobe v2 contract defines no corresponding dedicated routes.

```json
{"command":"video.workArea","revision":"<current revision>","parameters":{"operation":"set","startFrame":12,"endFrame":48}}
{"command":"video.onionSkin","revision":"<current revision>","parameters":{"settings":{"enabled":true,"framesBefore":1,"framesAfter":1,"spacing":1,"minimumOpacity":0.25,"maximumOpacity":0.5,"blendMode":"normal"}}}
```

The work area uses zero-based frames: start is inclusive, end exclusive. It must contain at least one frame inside the video Timeline. Other operations are `reset`, `startAtPlayhead` and `endAtPlayhead`, with no range fields. Reset follows the full Timeline duration. Setting the end at the playhead includes that frame. Playback and audio loop/stop inside the work area; a playhead outside starts at the area's beginning. Frame-rate edits preserve interval seconds with outward rounding; duration reductions clamp the range. Changing the work area does not remove any clip or keyframe.

Onion settings require all seven fields, or `settings:null` to reset. Before/after counts accept0–10 each, spacing1–100, and finite ordered opacity values0–1. Blend mode uses the published native blend-mode names. Default settings are disabled, one frame each side, spacing1, min0.25/max0.5, Multiply. These are provisional native defaults; exact Photoshop2026 defaults and overlapping blend behavior remain unqualified. Samples are processed far-to-near, before then after at each distance, without wrapping at Timeline edges. Opacity runs from maximum at the nearest configured distance to minimum at the furthest. Preview is bounded to20 neighbors and268,435,456 pixel visits.

`GET /v1/documents/{id}/onion-preview.png` returns the committed playhead's preview using saved settings, with the existing share/revision/source checks and preview limits. Ordinary `preview.png`, proof/channel output, editing pixels and image/movie exports exclude onion skins. Native canvas display includes them only in the full-composite editing view. No preview call changes history or content.

Both `sequence.export` and `video.render` accept optional `useWorkArea:true`. This requires a video Timeline and rejects explicit `firstFrame` or `lastFrame` fields, even if their values match the work area. The default remains full-range export. Export's first output frame corresponds to the work-area start; movie timestamps begin at zero and audio is mixed from the same source interval. Existing cancellation, transfer permission and snapshot/source-revision rules apply.

Settings are exposed in `video.timeline.workArea` and `video.timeline.onionSkin` (unset optional fields are omitted), with schemas/capabilities in the API. Work-area/onion metadata requires native57 and `X-Photato-Archive-Version: 57`; readers accept1–57. Older files remain readable, and clearing both settings restores the earlier minimum version if no other feature requires it. Invalid fields/types return400, invalid ranges/settings422, and stale/busy edits409, using the ordinary atomic history path.

Trim Document Duration To Work Area, conversion between animation modes, rich Timeline/PSD/Actions interchange, exact rendering/defaults and live/platform qualification remain open. This section supersedes earlier statements that work-area export and onion previews are unavailable; focused and full optimized tests pass; independent outputs are recorded in [workspace evidence](TIMELINE_WORKSPACE_REFERENCES.json).


## Timeline audio (step240)

Three additional typed commands bring the Photato inventory to167. Audio sources, native desktop controls, playback and API edits use the same Swift model/mixer and transaction/history engine. The pinned Adobe v2 contract has no dedicated Timeline audio endpoint; these are Photato extensions.

`POST /v1/documents/{id}/audio` imports an original audio container into an idle shared video Timeline. Bearer authentication, document transfers and a current `X-Photato-Revision` header are required. Accepted content types: `audio/wav`, `audio/x-wav`, `audio/aiff`, `audio/x-aiff`, `audio/mpeg`, `audio/mp4`, `audio/x-m4a`, `audio/aac`, `audio/x-caf`. Actual decoding depends on native AVFoundation codec support. The binary body must be nonempty and at most64MiB. Optional headers:

| Header | Meaning |
| --- | --- |
| `X-Photato-Audio-Track` | Existing track UUID; omission creates a new Audio Track. |
| `X-Photato-Audio-Name` | Percent-encoded UTF-8 clip name,1–256 characters; defaults to Audio. |
| `X-Photato-Audio-Start` | Finite Timeline seconds0–86,400; defaults to the playhead. |

A successful import returns200 document state, selects the new clip and adds one Undo entry. Original bytes remain inside the native document; no local filesystem path is exposed. Busy/stale/cancelled/revoked requests return409; transfers disabled403; unsupported content type415; empty/oversized body413; invalid media or model422. `audio.import.cancel` requires the matching active `operationID`. Cancellation is acknowledged before the worker has necessarily stopped; poll state for the cleared operation. Revoking sharing/transfers also cancels API-owned workers. Desktop import ownership is independent.

`audio.edit` requires exactly the parameters for its operation, plus the ordinary command envelope and current revision:

| Operation | Parameters |
| --- | --- |
| `newTrack` | `name` |
| `renameTrack` | `trackID`, `name` |
| `deleteTrack` | `trackID` |
| `muteTrack` | `trackID`, `muted` |
| `deleteClip` | `clipID` |
| `move` | `clipID`, `trackID`, `startTime` |
| `trim` | `clipID`, `startTime`, `sourceIn`, `sourceOut` |
| `clipSettings` | `clipID`, `volume`, `muted`, `fadeIn`, `fadeOut` |
| `movieSettings` | `layerID`, `volume`, `muted`, `fadeIn`, `fadeOut` |
| `split` | `clipID`, `seconds` |

Times are seconds; sourceOut is exclusive and must exceed sourceIn within the retained source. Gain is0–1, mute Boolean, fades0–86,400seconds. At most32 tracks and512 clips are admitted. Movie settings require an unlocked retained movie with audio. Splitting keeps original source bytes and moves exterior fade settings onto the corresponding halves; exact Photoshop split-envelope behavior is unqualified. Track overlap mixes additively. Each accepted edit is one native history transaction. Missing/irrelevant parameters reject400; invalid source bounds or model settings reject422. Stop playback before API edits.

`audio.view` accepts optional `trackID`/`clipID` (UUID or null) and `settingsVisible` (Boolean). A selected clip selects its owning track; explicitly contradictory track/clip IDs reject. View changes update the revision without content history. State exposes sanitized track/clip names, timings, settings, source duration/retained-byte count, movie settings, `preparing`, `playing`, `importOperationID`, selection and settings visibility. Raw source bytes are omitted from both audio state and the nested video Timeline state.

`GET /v1/documents/{id}/audio.wav` returns the full Timeline as stereo48kHz IEEEFloat32 WAVE using the native playback mixer. It is read-only and requires transfers. It returns422 if no audible clips exist,429 if another preview is busy, and409 if sources or authorization change. Request cancellation and share/transfer revocation cancel rendering. Each source is decoded at its native rate and linearly resampled once per mix, retaining complete duration; trims, speed, volume/mute and linear fades apply before summing/clamping to[-1,1]. API decoded sources and output each have a128MiB budget; desktop budgets are256MiB each. Silence fills uncovered intervals. Movie speed changes use linear resampling and change pitch. The audio clock drives visual preview frames; tests substitute a silent player and do not qualify physical output latency.

New soundtrack metadata or edited movie-audio settings require native56 and `X-Photato-Archive-Version: 56`; readers accept1–56. Older files remain readable. Long disk streaming, pitch-preserving speed, multichannel output, waveforms, full Render Video, PSD/Actions audio interchange and exact/live/platform parity remain open. Step239 and earlier sections below record their historical limits; this section supersedes their statements that audio is silent or unavailable.

## Graphical Timeline and transitions (step239)

The native Timeline now draws editable clip tracks, trim handles, transition regions and a draggable playhead. Horizontal dragging moves independent clips or reorders clips in a Video Group; vertical dragging moves a clip between tracks. Each completed drag is one content-history transaction; Escape cancels a pending gesture. Existing split/group and numeric controls remain available. Transition duration handles and a native popover edit retained transition objects. Preview, playback and image-sequence export share the transition renderer.

`video.edit` adds these operations, with exactly the listed fields:

| Operation | Required fields | Optional fields |
| --- | --- | --- |
| `trim` | `layerID`, `startTime`, `sourceIn`, `sourceOut` | None |
| `transition` | `layerID`, `kind`, `edge`, `duration` | `transitionID`, `previousLayerID`, `color` |
| `removeTransition` | `transitionID` | None |

`trim` applies to a retained movie/sequence clip. Source bounds use source-frame units, including fractional variable-frame-time boundaries; they can recover retained footage beyond previous trims. Grouped clips retain their sequential start. The existing `arrange` operation also accepts `startTime` when `groupID` is null, making detach-and-position a single transaction.

Transition `kind` is `fade`, `crossFade`, `black`, `white` or `color`; `edge` is `start` or `end`. Duration is positive seconds bounded by the affected clips. Omit `transitionID` to create an object, or pass its existing UUID to update it. `crossFade` requires `edge: "start"` and `previousLayerID` naming the preceding nonclipped sibling whose end equals the incoming clip's start. Its duration is centered on that shared boundary. Other kinds omit the partner. Only `color` accepts/requires `color`, an object with numeric r/g/b values in0…1 and a=1. Transitions on the same participant cannot overlap. Invalid values/boundaries, missing IDs and locked participants reject atomically; irrelevant fields reject as malformed requests. Existing authentication, sharing, stale revision and busy-operation guards apply.

The native renderer mixes premultiplied composed branches over the same backdrop, retaining masks, layer styles and current blend modes. Movie crossfades use retained media handles; unavailable handles hold the first/last source frame. Color fades retain the clip's rendered coverage. Split moves an outgoing edge transition to the right portion. Reorder/delete remove broken crossfade boundaries; shorter trims shorten effects. Duplicating a whole track remaps its contained transitions to independent IDs. All content changes participate in Undo/Redo.

`video.view` adds `pixelsPerSecond` (5…400), `transitionID` (existing UUID or null) and `transitionEditorVisible` (Boolean), alongside frame/playing/visible. View changes alter the exposed revision but add no content-history entries. State includes `video.pixelsPerSecond`, `video.selectedTransitionID`, `video.transitionEditorVisible` and `video.timeline.transitions`. The transition capability describes schemas, native behavior and remaining limits. Transition documents require native55 and `X-Photato-Archive-Version: 55` for native API downloads; earlier versions explicitly reject them. Older nontransition documents remain readable.

There is no dedicated Timeline transition endpoint in the pinned Adobe v2 contract, so no Adobe route is invented. Native semantics above are not a claim of exact Adobe output. Dragging a new effect directly from a transition palette, audio editing/playback, Render Video, automatic movie grouping, richer PSD/Actions animation interchange, factory-keyboard/default/preference equality, full accessibility, live acceptance and macOS/Intel qualification remain open.


## Video arrangement (step238)

`video.edit` now accepts five additional operations through the same native history path as the Timeline controls:

| Operation | Parameters besides `operation` | Result |
|---|---|---|
| `split` | `layerIDs` (nonempty distinct UUIDs) | Split selected clips at the current playhead. The right portions become independent editable layers; source frames and original movie bytes remain retained. |
| `group` | `name`, `layerIDs` (empty allowed) | Create a Video Group, optionally collecting selected sibling clips. Order follows the layer stack, bottom to top. |
| `arrange` | `layerID`, `groupID` (UUID or null), `position` | Move/reorder a clip on a video track; null places it on an independent root track. |
| `stillTiming` | `layerID`, `startTime`, `duration` | Set seconds of visibility for an editable still/type/shape/ordinary group. |
| `groupStart` | `layerID`, `startTime` | Move a video group's start and its sequential clips. |

A grouped clip’s `startTime` must retain its current value when trimming; use `groupStart` or `arrange` to move it. Group edits reflow following clips; moved animation keys retain their timing relative to the clip. Keys moved before zero preserve the evaluated boundary value. Split boundaries retain fractional source-frame units, including variable-frame-rate movie cuts. Ordinary painting of one split portion does not overwrite the other's source tiles. `video.clips` exposes numeric `sourceIn`/`sourceOut`; `video.arrangement` exposes `stills` intervals and `groups` with ordered clip UUIDs. Explicit source-frame trim changes reset only the affected exact boundary.

Native files containing arrangement metadata require `X-Photato-Archive-Version: 54`. Older download requests reject rather than lose timing. The archive reader accepts versions1–54. No new command name is added:164 typed commands remain. Missing/irrelevant parameters reject; standard stale, busy, locked and sharing guards apply. The pinned Adobe contract has no dedicated video arrangement endpoint; no Adobe route is invented. Transitions, audio, graphical Timeline bars/dragging, automatic movie grouping, full PSD/Actions and exact/live/platform qualification remain open. All 2,453 optimized tests and 13 final arrangement checks pass; independent PNG inspection verifies 576 analytic channel values. This does not establish Photoshop or live/platform equivalence.

**FOSS release policy (step237):** The optional API menu inventory no longer includes the removed Photato “Support Development…” command. There is no purchase operation or entitlement requirement. The 164 typed editing commands and Adobe v2 routes are unchanged.

### Editable video keyframes (step234)

`video.edit` now accepts `create` with `frameRate` (1–240) and `durationFrames` (1–20,736,001), `duration` with `durationFrames`, and `remove` with no extra parameters. Creation requires an RGB document without frame animation or artboards. Removing a Timeline first requires rasterizing its video clips; it freezes the current property values and removes keys, with Undo. Duration must include all clips and keys. Rate changes preserve duration in seconds and key times; loop changes retain the chosen duration.

`video.keyframe` uses the shared native history engine. All operations require `layerID`:

| Operation | Other parameters | Behavior |
|---|---|---|
| `enable` | `property` | Capture the current value at the playhead; subsequent property edits auto-key. |
| `disable` | `property` | Remove that property's keys while keeping its evaluated value. |
| `set` | `property`, optional `time` | Capture the current value at the requested time in seconds; default is the playhead. |
| `delete` | `keyframeID` | Remove an existing key; removing the last disables its track. |
| `move` | `keyframeID`, `time` | Move an existing key without changing its value; reject occupied times. |
| `interpolation` | `keyframeID`, `interpolation` | Set outgoing `linear` or `hold` interpolation. |

Properties are `position`, `opacity`, `transform` and `style`. Position and Transform are alternative geometry tracks: enabling one replaces the other. Time ranges from zero to 86,400 seconds. At most 4,096 keys per layer/65,536 per document and 64MiB metadata are allowed. New keys can extend the Timeline. Extra/missing/unknown parameters reject; stale/busy/playing requests return 409 without editing. Playback changes the exposed view revision even though it does not add history; clients must refresh it before editing. Locked layers reject. Geometry currently excludes groups, Smart Filters and Warp. Adjustment layers support opacity; style edits remain unsupported by the existing style engine.

To assign values, enable a track, use `video.view` to choose a frame, then use the normal `layer.move`, `layer.opacity`, `layer.transform` or `layer.style` command. Those edits capture or replace the enabled property's key at that time. The keyframe `set` operation captures the currently evaluated value; it does not accept arbitrary values hidden in the keyframe request. Seeking/playback creates no Undo entries. Geometry interpolates subpixel translation and decomposed affine rotation/scale/shear; reflection switches hold until the next key. Matching styles interpolate numeric/color fields; categorical, gradient/pattern and differing effect topology hold until the next key.

The document's `video.keyframes` state lists `{layerID, keys}`. Each key has `id`, `property`, `time`, `interpolation` and its relevant `geometry` (`x`, `y`, `affine`), `opacity` or optional `style`. The video capability publishes the complete schemas and limits. Native keyframe downloads require `X-Photato-Archive-Version: 53`; lower headers reject instead of discarding animation. Both movie/sequence clips and still layers can animate. Image-sequence export uses the same evaluated frames.

No dedicated Timeline/keyframe route exists in the pinned Adobe v2 contract; generic animation action descriptors remain open. Full Photoshop/live/platform and exact pixel equivalence are not established. [Current evidence and gaps](VIDEO_KEYFRAME_REFERENCES.json).



### PNG image-sequence export (step232)

`sequence.export` renders either frame animation or a video Timeline through the shared native PNG encoder. It requires document transfers enabled and the usual current revision:

```json
{"command":"sequence.export","revision":"<current revision>","parameters":{"format":"png","prefix":"shot_","firstFrame":0,"lastFrame":23,"startNumber":1,"digits":4}}
```

Only `format` is required. Defaults: prefix `frame`, firstFrame0, lastFrame equal to the last Timeline frame, startNumber0 and digits4. Frame bounds are zero-based and inclusive. Export allows1–4096 frames; numbering starts0–999999999 and must not overflow that limit. Digits1–9 specify minimum padding, not truncation. Prefixes allow letters, numbers, spaces, underscores and hyphens, with a64-byte UTF-8 limit. The export retains original dimensions and timing; it does not resample to a new rate. Revoking transfers or the shared document cancels the API-owned render worker promptly; ordinary desktop exports are independent.

The200 response is `application/zip`, at most128MiB, containing numbered PNGs in Timeline order and `sequence.json`. ZIP32 uses stored entries (PNG is already compressed), UTF-8 names, CRC32 and a fixed1980-01-01 timestamp for deterministic results. No executable or source document is included. PNG8/16 uses the existing native working-profile encoder and full alpha. HDR32 converts to SDR sRGB16; the source stays editable and unchanged.

The version1 manifest is a JSON object with these fields:

| Field | Value |
|---|---|
| format / version | `photato-image-sequence` / integer1 |
| sourceName / kind | Document name / `frameAnimation` or `video` |
| width / height | Source pixel dimensions |
| sourceDepth / pngBitsPerChannel | Native PixelDepth string / integer8 or16 |
| colorPolicy | Explicit working-profile retention or HDR-to-SDR conversion description |
| firstFrame / lastFrame | Exported inclusive zero-based source range |
| frameRate | Video Timeline rate, or null for frame animation |
| loopCount / videoLooping | Frame-animation passes or null / video preview-loop flag or null |
| frames | Ordered objects with `file` (basename), `sourceFrame` (zero-based integer), `time` (seconds from source Timeline start) and `duration` (seconds, including zero-delay animation frames) |

Document `sequenceExport.operationID` is non-null while rendering/archiving. `sequence.export.cancel` accepts that operationID and can run while the document is busy. A matching cancellation returns200 with `cancellationRequested:true`; the export returns409 without bytes. Missing operations return409. Invalid fields/types/formats return400; stale/busy/cancelled or revoked output409; disabled transfers403; unsupported source/range/prefix or resource limits422. After encoding, the API rechecks sharing, source/revision, transfer permission/generation and service identity before returning the archive. Export adds no Undo entry or dirty-state change.

Both native Timeline panels expose Export Image Sequence. Native frame controls use1-based first/last numbers, then convert to the same renderer's zero-based range. The native picker creates a new `<prefix>-sequence` subfolder in the chosen location. All files are staged before an exclusive folder rename; an existing destination rejects and stays unchanged. Cancellation/errors remove staging, and the source snapshot is rechecked before publication.

PNG is the initial sequence format. Alternate formats, export resizing/rate conversion, work-area selection, alpha modes, complete Render Video and exact Photoshop/live/platform qualification remain open. Native51/Actions20 are unchanged. The pinned Adobe v2 contract has no dedicated sequence route; generic video execute-actions descriptors remain unimplemented. [Sequence export evidence](IMAGE_SEQUENCE_EXPORT_REFERENCES.json).

### Video layers and PNG sequences (step231)

`video.sequence` creates a new shared RGB document with one editable video layer from ordered still documents. It requires document transfers enabled, 1–7 distinct shared source IDs with current revisions (including the command target), and a free output sharing slot:

```json
{"command":"video.sequence","revision":"<target revision>","parameters":{"name":"Image Sequence","frameRate":24,"sources":[{"id":"<shared source UUID>","revision":"<source revision>"}]}}
```

The201 response is the new shared document state. Sources must have equal dimensions and no video Timeline, frame animation or artboards. Each source is composited and converted into the first source's RGB working profile/depth; the originals and their history stay unchanged. The128MiB API frame budget and ordinary4MP/64-layer limits apply. Desktop Timeline > Import Image Sequence accepts1–512 PNG files, sorts filenames numerically and uses the same constructor with a1GiB decoded budget. Movie-file decoding is not yet implemented.

`videoSequenceCreation` state contains nullable `operationID` and `sourceIDs`. Use `video.sequence.cancel` with the active `operationID` on any participating shared document to cancel. Sources remain busy while rendering. Permission/sharing revocation, source revision changes, document open/close changes and cancellation prevent publication. Missing permission403, malformed parameters400, stale/busy/cancelled409, unsupported document context422 and sharing capacity429 are explicit; a missing shared source returns404.

`video.edit` goes through native Undo/Redo and accepts exactly the fields for its operation:

- `timing`: `layerID`, `startTime` (0–86400seconds), `inFrame` (inclusive, zero-based), `outFrame` (exclusive), and source `frameRate` (1–240). The trim must retain at least one source frame. Position-locked video layers reject timing edits.
- `frameRate`: Timeline `frameRate` (1–240), independent of each clip's source rate.
- `loop`: `looping` boolean for playback.

`video.view` accepts any nonempty combination of `frame` (zero-based Timeline frame), `playing` and `visible`. Seeking and playback use view state without content Undo entries. Painting through ordinary native/API raster commands changes the source frame at the playhead; other source frames retain their pixels. Painting outside a clip rejects. Timing and painting are transactional; native Rasterize Layer retains the currently selected frame as a still and Undo restores the video.

Document `video` state includes nullable `timeline` (`frameRate`, `currentFrame`, `durationFrames`, `looping`), nullable transient `previewFrame`, and `clips` metadata (`layerID`, `sourceFrames`, `sourceFrameRate`, `startTime`, `inFrame`, `outFrame`, `duration`). Existing `animation.playing`/`timelineVisible` indicate shared Timeline presentation. Native archive51 stores every video source frame and its timing; download requires `X-Photato-Archive-Version: 51`. `nativeArchives.videoVersion` is51 and `readVersions` includes1–51. Frame animation remains native50 and accepts download negotiation50 or51. Still copies contain the current frame; ordinary nonnative Save and editable PSD writes reject video loss.

These are Photato extensions. The pinned Adobe v2 contract has no dedicated video endpoint; generic execute-actions animation descriptors remain unimplemented. Sequence export, AVFoundation movie import, audio, keyframes/transitions, all-frame geometry/profile conversion, complete rich-layer contexts, editable PSD/Actions, live/platform checks and Photoshop pixel/byte identity remain open. Qualification is recorded in [video evidence](VIDEO_TIMELINE_REFERENCES.json).

### Animated GIF interchange (step230)

Opening a GIF through File > Open or `POST /v1/documents/import` (`Content-Type: image/gif`) now reconstructs all frames, including partial rectangles, transparency and disposal, as editable raster layers in the Timeline. The decoder retains unclamped delays and total-pass loop counts. A single-image GIF remains a still. Import permits at most256 frames and preflights tiled float storage plus frame metadata against1GiB on desktop or128MiB for API uploads; existing API4MP/64-layer limits also apply. Inputs beyond these limits reject instead of silently discarding frames.

`animation.export` uses the normal shared-document command envelope and requires document transfers enabled:

```json
{"command":"animation.export","revision":"<current revision>","parameters":{"format":"gif","alphaThreshold":0.5}}
```

The200 response body is `image/gif`, at most128MiB. Export renders all Timeline frames in order, converts to sRGB8, and uses the native ImageIO palette (up to256 colors). GIF alpha is binary: nonzero alpha greater than or equal to `alphaThreshold` is opaque; other pixels become transparent. The optional threshold ranges0–1 and defaults0.5. Delays round to the nearest centisecond; values above655.35seconds reject. Zero means forever for loop counts; positive values count total passes. Rendering preserves source layers, selected frame, native50 content and Undo/Redo history. Native Timeline > Export Animated GIF uses the same encoder and commits files atomically only after successful encoding.

While exporting, the animation state exposes `exportOperationID`. `animation.export.cancel` with that `operationID` cancels the matching worker; it is available while the ordinary edit preflight is busy. A cancelled export returns409 without output; HTTP task cancellation also cancels the worker. Other edits reject409 while export is active. Stale revision409, unavailable document transfers403, invalid parameters400 and unsupported context422 are explicit. Sharing, transfer permission/generation and source revision are rechecked before returning bytes. Native progress provides Cancel; failed/cancelled writes preserve an existing destination.

No dedicated GIF/animation endpoint exists in the pinned Adobe v2 contract, so these export/cancel commands remain Photato extensions. Generic Adobe animation descriptors, Photoshop Save for Web optimization/palette controls, exact output bytes, image sequences and video remain required work. Tests and platform/live qualification are recorded in [animation evidence](ANIMATION_REFERENCES.json).

### Video-to-frame conversion and source recovery (step246)

`animation.edit` now accepts `fromVideo` and `restoreVideoSource`, with no other parameters. Both use the same prepared Swift transaction and Undo as the native Timeline menus. Existing `toVideo` continues to require `frameRate` from1–240. Busy/stale requests return409, irrelevant fields400, and invalid context/capacity422. The qualified source/test record is in [conversion evidence](VIDEO_FRAME_CONVERSION_REFERENCES.json).

`fromVideo` samples every Timeline frame, up to512 frames/65,536 layer states, at the original rate. Layer types, composition, varying content/masks and sampled transition progress remain editable; source video/audio is retained in a recoverable original. Frame playback is silent. `toVideo` creates Hold property/content keys and sampled transition states. If frame order and delays remain unchanged, the current sampled soundtrack resumes, including movie source-rate timing and trimmed pre-roll. Reordered or retimed animations keep the original audio for explicit recovery; it is not silently resynchronized. `restoreVideoSource` restores original layers and Timeline, replacing conversion edits with Undo available. This is Photato's source-retention design, not a claim about Adobe internals.

Native60 archives preserve the new state. Ordinary JSON state exposes `retainedSource` metadata (rate, frame count, layer count, audio availability, retained byte count and restore operation), frame `sourceVideoFrame`, safe `sampledTimeline` rate/count/audio metadata, sampled `transitions`, layer `payloadSummary`, video `frameTransitionKeys` and key `contentSummary`. These contain no retained image/movie/audio byte payloads. Native document downloads remain gated by existing document-transfer permission and limits. Audio clip state reports effective `playbackRate`; Content keyframes use Hold and capture the current layer content through existing editing commands.

Positive video-derived frame delays retain rates above50fps. Ordinary frame animations retain their20ms preview minimum, and GIF format timing is still rounded to centiseconds. No new Photoshop v2 route is invented: the pinned published contract has no corresponding Timeline endpoint. Exact Photoshop conversion/default semantics, rich animation interchange, complete all-frame geometry/profile changes and live/platform qualification remain open.

### Frame animation and Timeline (step229)

Two Photato commands use the normal shared-document command envelope and revision guard. The same Swift layer state, transaction, rendering and history implementation serves the desktop. `animation.edit` changes one selected frame; `animation.view` selects a frame, shows the Timeline or controls temporary playback without adding content Undo entries.

| Command | Parameters |
| --- | --- |
| `animation.edit` | Required `operation`: `create`, `remove`, `fromVideo`, `restoreVideoSource`, `fromLayers`, `duplicate`, `delete` or `reverse` take no extra fields; `reorder` requires zero-based `index`; `delay` requires seconds0–3600; `loop` requires integer `count`0–65535; `toVideo` requires `frameRate`1–240; `tween` requires `count`1–100 and boolean `position`/`opacity`, at least one true. Irrelevant fields reject. |
| `animation.view` | At least one of `frameID` (existing UUID), `visible` (boolean), `playing` (boolean). Validation completes before any view change. No layer-content/history change. |

Document `animation` state includes `timelineVisible`, `playing`, nullable `previewFrameID` and nullable `animation`. The animation carries ordered `frames` (`id`, `delay`, per-layer composition states), `selectedFrameID` and `loopCount`. Each layer state retains `layerID`, visibility, opacity, x/y, optional affine transform and style. Pixels, text, masks, hierarchy and other layer content are shared; ordinary property changes update the selected frame. Layer insertion/deletion reconciles every frame. Native50/chunked archives and scratch history preserve the complete state. Native downloads require `X-Photato-Archive-Version: 50`; older requests reject instead of dropping animation.

Loop count0 repeats indefinitely; positive values count total passes, beginning at the selected frame. Playback uses a20ms minimum for zero-delay frames. Preview ticks do not invalidate the API revision; deliberate playback, visibility, selection and editing changes do. Stop via `animation.view` before sending editing commands while playback is active; those commands return409. Busy desktop gestures/drafts and stale revisions also return409. Invalid or irrelevant parameters return400; unsupported context or frame/storage limits return422. Limit512 frames,65,536 layer states and 64MiB animation metadata, within the existing document/history/HTTP budgets.

The first native Timeline supports thumbnails, creation, duplicate/delete, order, delay, basic loop options, position/opacity tween and playback. It is docked under the clipped canvas workspace. Still-image copies render the selected frame; ordinary nonnative Save and PSD animation writes reject unsupported animation loss. Advanced frame selection/unify/propagate, effect tween, onion skins, GIF/image-sequence/video/audio/keyframes, semantic Actions, editable PSD animation and exact/live/platform parity remain open. The pinned Adobe v2 contract has no matching Timeline endpoint; these commands are Photato extensions. [Evidence](ANIMATION_REFERENCES.json).

**In-progress step222:** 141 typed commands, native48 ink documents, clipboard envelopes1–2 and Actions20. Multichannel PSD/PSB native and both API file paths pass52 focused tests and2,316 full optimized tests; independent decoding confirms16 exports/768 exact samples. Installed/qualified221 remains the packaged baseline. See [ink evidence](INK_MODE_REFERENCES.json).

### Native ink documents (step222, in progress)

Native48 retains the Duotone gray source, ink curves/names/colors and overprint preview settings, or independent Multichannel8/16-bit ink plates/solidity. Ink documents require `X-Photato-Archive-Version: 48` for native downloads; omission or an older version returns422. Current unknown versions above51 return400. Native48 uploads restore the authoritative samples. `nativeArchives.inkModeVersion` is48; `readVersions` includes1–51. Existing Indexed/Bitmap documents may negotiate47 or48, and existing component documents may still negotiate46.

Document state reports `duotone`/`multichannel` and actual color-channel names. Existing `document.convertMode` converts an ink document into one of its four documented component modes; matching channel counts preserve numerical components, and Duotone-to-Grayscale recovers its original gray samples. Multichannel has no layerID until converted to a layered mode. Native/API history restores the complete original ink document.

Existing geometry commands transform ink samples, saved masks and selections together. Grid transforms retain exact8/16-bit sample bytes. Multichannel canvas extension accepts omitted/white/transparent fill as paper; arbitrary composite-color fill rejects. Duotone extension uses the supplied color's gray value over paper. Ink crop requires Delete Cropped Pixels and currently rejects content-aware fill. The8,388,608-pixel native ink limit and the smaller API resource limits both apply. See `geometry.inkModes`/`inkMaximumPixels` in capabilities.

`document.convertDuotone` accepts optional `settings` and `mergeVisible`. It creates Duotone from Grayscale8 or updates an existing Duotone's options without changing the gray samples. Settings contain one to four `inks` (`id`, `name`, opaque normalized `color:{r,g,b,a}`, and ordered `curve:[{input,output}]`) and `overprints:[{mask,color}]`. Curve inputs run from zero to one, have distinct increasing positions and include both endpoints. Overprint masks select at least two existing inks and change the preview only. Omitted ink IDs receive UUIDs; omitted curves are straight lines. Omitted settings retain an existing Duotone or select Monotone Black for new conversion. Unknown fields, duplicate IDs, invalid curves/colors and out-of-range combinations reject.

`document.convertMultichannel` accepts optional `mergeVisible` and `plateIDs`. Component8/16 and Duotone input produce independent printing channels. Omitted component plate IDs are generated once; explicit IDs must be unique and match the resulting channel count. Existing Duotone/Multichannel ink IDs are retained. Layer stacks that require merging reject until `mergeVisible:true`; hidden layers are then discarded while saved alpha channels remain. A successful conversion is one Undo transaction, with the same preview/commit result as the native dialog.

`ink.settings.read` returns `mode`, `depth`, `settings` (Duotone settings or null), `plates` (Multichannel metadata or an empty array), and `revision`. Each plate entry contains `id`, `name`, `color` and `solidity`. It does not return raw pixels or modify history. Native Load/Save Settings uses the complete Duotone settings JSON returned here; the API can restore it with `document.convertDuotone`. Adobe ADO presets are not supported yet.

All commands use the existing `/v1/documents/{id}/commands` envelope and require the current revision. Capabilities expose `inkModes`, strict parameter/result schemas and `stateSchemas.inkMode`; document state exposes ink conversion availability, merge requirement, open workspace, preview/commit activity and ink count. Busy/stale requests reject before mutation; revoked sharing during preparation prevents commit. Recorded ink conversions require Actions20, share the compositor playback engine and adapt Multichannel identities to each playback document.

Additional ink tools/clipboard/semantic channel Actions and Adobe ink descriptors remain unfinished. Ink PSD/PSB/TIFF output explicitly rejects to prevent silent RGB conversion; rendered PNG/JPEG exports flatten the printed preview. Preserve editable ink data in Photato format. Print separations, Adobe ADO/ATN and complete Photoshop ink-format/tool parity remain open.


### Ink channel editing (step222)

Six operations use the same authenticated command envelope and revision checks as other native edits. Targets are `"duotone"` for the sole gray source or a Multichannel plate UUID from `ink.settings.read`. Explicit API targets do not require changing the desktop selection. Ink writes require an ink editing context; finish any dialog/gesture and exit an alpha-mask target first. All successful changes use the shared prepared transaction and Undo/native48 path. View-only selection/visibility does not add history.

| Command | Parameters and behavior |
| --- | --- |
| `ink.channel.read` | `target`, optional `offset` (default0), `count` (default up to4096 remaining samples). Returns target, offset, normalized values, width, height, depth and revision. |
| `ink.channel.write` | `target`, optional `offset`, and1–4096 `values` in0…1. Replaces raw samples independently of the selection, preserving every other plate and untouched byte. |
| `ink.channel.edit` | Nonempty unique `targets` and `action`: `fill` (`value`, optional `opacity`); `stroke` (`points`, optional `brush`); `invert`; `filter` (`filter`); or `selection` (exactly one target, optional `mode` and `invert`). Irrelevant action fields reject. |
| `ink.channel.manage` | Multichannel only. `create`: name and optional newID/color/solidity/density. `delete`: plateID. `duplicate`: plateID and optional newID/name. `move`: plateID/index. `options`: plateID/name/color/solidity. |
| `ink.channel.select` | `targets`; an empty array selects all. Changes desktop editing targets and their initial visibility. |
| `ink.channel.visibility` | Nonempty `targets`; changes only the preview, independently of editing selection. |

Raw reads/writes retain Duotone gray (zero=black) or Multichannel density (zero=no ink). Fill/brush/filter use channel-view gray: zero means black/full ink, one means white/paper. Those edits honor the document selection and preserve other plate samples. Selection loading uses `mode` values `New` (default), `Add`, `Subtract` or `Intersect`; `invert` defaults false. New spot channels default to black, zero solidity and zero density. Names are nonempty and at most1024 UTF-8 bytes; colors are opaque normalized `{r,g,b,a}`. Optional newID provides deterministic create/duplicate identities. At least one plate must remain; at most56 total ink/alpha channels are allowed.

A single visible Multichannel plate displays numeric gray; multiple plates show their retained printing colors. Duotone keeps its printed composite and one gray channel. The native Channels panel exposes selection/visibility, spot options, create/duplicate/reorder/delete, selection loading and supported filters. Fill and Filter menus and Brush/Eraser share the same target path. Filters are the eight kinds listed by `inkChannels.filters`; unsupported kinds reject. Newly generated desktop brush seeds fit the API's exact53-bit integer range for reproducible replay.

Capabilities expose `inkChannels` with raw-page result schemas and limits. Document `inkMode` state adds `editingTargets`, `visibleTargets`, `channelEditingAvailable` and `channelOptionsOpen`; `/channel-preview.png` matches this ink visibility. There is no fabricated RGB layer in Multichannel. Complete ink-channel semantic Actions, other paint/clipboard contexts, ADO/ATN, Adobe ink actionJSON, editable Duotone PSD/PSB, ink TIFF and separation output remain open. Multichannel PSD/PSB transport is described below. Existing Actions20 conversion support does not imply channel-edit recording. No new Adobe route is claimed.


### Multichannel Photoshop files (step222)

Native Save/Open, `document.saveAs`, authenticated PSD/PSB downloads and imports, and both existing action-job routes share the native mode7 codec. `documentTransfers.multichannelPhotoshop` and `photoshopContainers.colorModes.multichannel` advertise 8- and 16-bit support. This extends existing file operations; it does not add a new typed command or invent an Adobe ink-editing descriptor.

The serializer preserves ink and alpha sample values exactly, supports Raw/RLE/ZIP/ZIP prediction in PSD and PSB, and retains Unicode channel names, display colors, opacity/solidity, resolution and supported saved paths. It emits ink planes followed by saved alpha masks, preserving order within each group. PSD encodes gray samples with the opposite polarity to native ink density; conversion uses integer inversion and byte swapping, without rendering or RGB reseparation. Alpha values keep their original polarity and display settings.

Modern DisplayInfo1077 uses a version word followed by13-byte channel records; old1007 has14-byte records. Supported imported RGB/HSB/CMYK/Lab/Gray color records are reused when their settings are unchanged. New/changed display colors use16-bit RGB and solidity/opacity rounds to the file format's whole percentages. Channel identities within a Photato session are not cross-file Photoshop identifiers. Obsolete channel identifiers/alternate-color metadata are removed on rewriting, preventing stale associations after edits or conversion.

Limits remain explicit: at most56 total channels,52 saved alpha masks,8,388,608 canvas pixels, the shared512MiB decompressed channel budget, and the lower existing HTTP/job budgets. Active Quick Mask, unknown color-book records, malformed/incomplete metadata, non-square resolution and unrepresented layer records reject. Duotone PSD/PSB and ink TIFF editing interchange remain unsupported; Save as Photato retains those structures. New Multichannel native Save shows only formats that retain inks. Live Photoshop interoperability and exact ink composite rendering are still unqualified.


### Semantic Actions playback (steps221–222)

Native `.photatoactions` versions1–20 remain readable. Ink conversion/settings steps require20. Color-mode conversion and clipboard steps require19; a file claiming an older version while containing those steps is rejected. Recording retains settings and portable layer targets. Clipboard images and converted document snapshots are not stored in these steps. Copy/Copy Merged and successful no-op Cut/Paste remain recordable without a new document-history entry. Conversions retain mode/depth/ICC/intent, explicit flatten/HDR clipping consent, Indexed/Bitmap settings, Color Table and explicit Previous palette data.

`actions.play` uses the normal authenticated shared-document command envelope, with required `actionID` and optional `clipboardPayloadBase64` and `sources`. The initial clipboard is a native envelope1/2 up to2MiB. It is required when an enabled Paste precedes any enabled Copy/Cut. Copy/Cut use the current playback pixels; later Paste uses the private playback clipboard. Each step validates document/clipboard extents and resource limits. The response is standard document state plus optional `clipboardPayloadBase64` when successful playback copies or cuts. Output above2MiB rejects before the document commits. The API never accesses the Mac clipboard. Parameter schemas are in command discovery; `actions.playback.resultSchema` describes the optional output field.

Additional master-palette sources use `[{"id":"shared UUID","revision":"current revision"}]`, up to7 distinct additional shares. The target is included automatically; additional sources require an enabled master-palette step. Full snapshot/revision/share/preflight checks apply again before commit. Desktop playback uses eligible open-document snapshots. Previous stores an explicit palette; the document session remembers the last accepted indexed/color-table palette from successful playback even if the action ends in RGB.

`actions.batch` also accepts optional `clipboardPayloadBase64`, reused as the initial private clipboard independently for each source. Internal Copy/Cut do not publish a system clipboard or an API clipboard result. Master palettes use frozen eligible Batch source snapshots, with an8,388,608-pixel/256MiB aggregate preparation limit plus normal per-step/API limits. Current source identity is excluded from its additional masters. Existing per-file atomic publication, cancellation, output-folder permission and source-revocation guards remain.

Native playback stages document and clipboard effects; failure, cancellation, changed master sources or a changed clipboard prevents the document transaction. One successful action makes one Undo entry when document content changes. Undo restores the document, not the clipboard. Recorded Paste retains its placement and optional document-pixel center. New from Clipboard, cross-document action lifecycle, broader unsupported command families, ATN, full Photoshop exactness and live/platform checks remain open. Existing Adobe component-mode actionJSON contracts are separate; this does not qualify new Adobe restricted-mode/clipboard descriptors or invent routes.

### Explicit clipboard transfers (step221)

Use the authenticated `POST /v1/documents/{sharedID}/commands` envelope with a current revision. These operations never read or write the Mac system clipboard. The returned payload can be sent to another shared document. `clipboard` capabilities include parameter/result schemas and limits; document state reports copy/cut/paste-target availability and current background color without exposing system clipboard contents.

| Command | Parameters and result |
|---|---|
| `clipboard.copy` | Optional `layerIDs` (default desktop layer selection) and `merged` (default false). Merged copies visible content regardless of layer selection. Returns `payloadBase64`, `sourceMode`, `kind`, `width`, `height`, `revision`. Read-only. |
| `clipboard.cut` | Optional `layerIDs` and `backgroundColor` (three RGB values 0–1; defaults to the current desktop background). Returns the same payload metadata plus updated `document` state. Actual changes create one Undo. |
| `clipboard.paste` | Required `payloadBase64`; optional `placement` (`centered`, `inPlace`, `into`, `outside`) and `center` (two document-pixel coordinates). Returns updated document state. |
| `clipboard.newDocument` | Required `payloadBase64`; optional `name`. Requires document transfers to be enabled. Returns201 with the newly shared document state; source/history stay unchanged. |

API payloads are native clipboard envelopes, limited to2MiB decoded bytes (2,796,204 base64 characters). Ordinary clipboard content still emits envelope1; retained Indexed/Bitmap samples use envelope2. A payload's document and bounds must also fit the4,194,304-pixel/64-layer/128MiB API limits before flattening or new-document creation. Native system clipboard operations retain their separate512MiB limit. Larger API resource/chunk transfer is not yet implemented.

Centered paste uses the selection center if present, otherwise the supplied center or canvas center. The desktop uses its viewport center for ordinary pixel paste. In Place retains copied coordinates. Into/Outside require a selection. Restricted-mode paste updates the existing flat layer; matching opaque full-coverage samples retain duplicate index identity, while other colors map to the destination table or one-bit output. Copy retains selection alpha separately. Exact New from Clipboard preserves mode; coverage that requires extra transparency produces RGB. Changed profiles invalidate direct index identity before native color conversion.

Cut prepares its bounded payload before changing the image. A payload limit failure returns413 without changing history. Bad request fields/base64 return400; invalid native payloads/context return422; stale, busy or revoked operations return409. New-document creation also checks transfer permission/capacity and lifecycle changes. A disconnected client cannot be guaranteed to receive a completed Cut response; Undo remains available. Adobe clipboard action descriptors are still unsupported; these are Photato commands.

```json
{"command":"clipboard.copy","revision":"<current revision>","parameters":{"merged":true}}
```

```json
{"command":"clipboard.paste","revision":"<destination revision>","parameters":{"payloadBase64":"<payload returned by Copy>","placement":"inPlace"}}
```

### Document geometry (step221)

These commands use the existing authenticated command envelope and current document revision. Results are the updated document state, including dimensions, resolution, mode and history. `geometry` in capabilities describes limits and sampling behavior.

| Command | Parameters |
|---|---|
| `document.resize` | Required integer `width`, `height` (1–32768); optional `resolution` (1–100000 ppi), `method` (`nearest`, `bilinear`, `bicubic`). Default method is nearest for Indexed/Bitmap and bicubic otherwise. Resolution defaults to the current value. |
| `document.canvasSize` | Required `width`, `height`; optional `anchor` (topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight; default center) and `fill` (four RGBA values 0–1). |
| `document.rotate` | Required `turn`: clockwise, counterclockwise, half, horizontal or vertical. |
| `document.resolution` | Required `resolution` in ppi; changes print sizing without resampling. |

Each operation is one prepared Undo/Redo transaction and rejects stale revisions, busy desktop edits and invalid parameters. Indexed/Bitmap output is limited to8,388,608 pixels. Exact grid transforms and nearest resampling preserve stored indices, including duplicate palette entries. Interpolation maps into the current palette or one-bit output. Bitmap extension defaults to white; Indexed extension uses its transparent entry if present, otherwise the nearest palette color to white. Canvas shrinking removes outside samples, recoverable through Undo. Component-mode Canvas Size retains existing off-canvas storage.

`document.crop` also supports these flat modes: require `deleteCroppedPixels=true`; new background/content-aware fill pixels map into the existing layer. Interior transparency and untouched indices remain. This does not qualify Photoshop interpolation or an Adobe action descriptor. The Adobe-compatible interface continues to reject unimplemented geometry actions explicitly.

```json
{"command":"document.resize","revision":"<current revision>","parameters":{"width":1024,"height":768,"method":"nearest"}}
```

### Indexed Color, Bitmap and Color Table (step221)

All commands use the existing authenticated `POST /v1/documents/{sharedID}/commands` envelope with `command`, current `revision` and `parameters`. `restrictedModes` advertises settings/result schemas and limits; `documentMode` reports source mode, actual bit depth, availability, palette count and preview/commit state.

| Command | Parameters and behavior |
|---|---|
| `document.convertIndexed` | Optional `settings`, `mergeVisible`, `sources`, `previousPalette`. Requires RGB/Grayscale8. Palette kind, count, forced colors, custom palette, transparency, matte, dither, amount and Preserve Exact use the native Indexed Color adapter. |
| `document.convertBitmap` | Optional `settings`, `mergeVisible`. Requires Grayscale8. Method, output resolution, frequency, angle, shape and optional grayscale threshold tile use the native Bitmap adapter. Output resolution defaults to the document resolution. |
| `indexed.colorTable.read` | No parameters. Returns RGB byte objects, transparent index (`-1` means none), ACT base64 and revision; no history mutation. |
| `indexed.colorTable.write` | Exactly one of `colors` (1–256 `{red,green,blue}` byte objects) or `actBase64` (768/772 decoded bytes). Optional `transparentIndex`, with `-1` removing transparency. Omission retains the current index for colors or reads it from ACT. Pixel indices, including duplicate-color identity, are preserved. |
| `indexed.indices.read` | Optional row-major `offset` and `count` (1–4096). Returns stored indices, offset, width, height and revision. |
| `indexed.indices.write` | `values` (1–4096 palette indices), optional `offset`. Bypasses selection, preserves the palette, rejects locked pixels and out-of-range entries; one Undo. |

Every edit is an atomic native transaction. Conversion requires `mergeVisible: true` when it would flatten multiple/transformed/effected layers or discard auxiliary channels. Busy desktop previews and stale revisions reject before mutation. Additional master-palette sources are distinct shared documents with `{id, revision}`; the target is included automatically. Every source is rechecked for sharing, revision and snapshot equality before commit. Sources are accepted only by master palette modes. `previousPalette` is explicit, so API requests never depend on desktop session history. Accepted Indexed/Color Table API edits update the desktop's Previous palette just like native edits.

Example parameters for `document.convertIndexed`: `{"settings":{"palette":"localSelective","colors":32,"dither":"diffusion","amount":0.75,"transparency":true},"mergeVisible":true}`. A custom Bitmap threshold tile uses `{"width":2,"height":2,"samples":"AP+AAA=="}`: base64 grayscale bytes in row-major order, dimensions1–1024. Ordinary document and combined-source pixel/memory limits still apply.

The six commands belong to Photato's API. Existing Adobe resource jobs retain restricted files, but restricted conversion action descriptors are still unqualified. UXP conversion-option documentation does not establish a Firefly action descriptor schema, and no Adobe route is invented. Actions19 covers mode conversion and clipboard playback; broader Actions, full Photoshop tool/mode behavior and byte-identical numerical results remain open.

### Restricted-mode file interchange (step221)

Native Open/Save/Save As/Copy and `/v1/documents/import`, `file.psd`, `file.psb`, `file.png` and `file.tiff` share codecs that preserve actual palette indices or packed monochrome samples. Duplicate palette entries and their indices are retained. Indexed transparency uses one transparent palette index; TIFF writes unassociated alpha samples plus Photoshop palette-count/transparent-index resources. PNG output is indexed8 or grayscale1;1/2/4/8-bit indexed PNG input is supported. TIFF accepts supported packed strips/tiles and both byte orders. `documentTransfers.restrictedFormats` records exact compression, sample, metadata and variant limits.

Restricted native download requires `X-Photato-Archive-Version: 47` on `file.photato` or `file.pcswift`; missing/older negotiation returns422 and unknown versions return400. `nativeArchives.readVersions` includes1–51, `restrictedModeVersion` is47, and native component documents can still negotiate46. Existing session/busy/stale revision and lower API memory/pixel limits remain. Uploaded native47 data restores authoritative palette/bit storage; RGB is only its derived display cache.

Ordinary TIFF Save defaults to flat output for these inherently flat modes. The native save accessory disables Layers; Bitmap PSD/PSB disables ZIP prediction. Explicit unsupported options reject. Ordinary JPEG Save rejects mode loss; Save a Copy remains an explicit rendered output. Saved paths require Photato, PSD/PSB or supported unrotated TIFF. Native47 is required for complete native structure.

Both `/v1/action-jobs` and `/v2/execute-actions` accept supported restricted PSD/PNG/TIFF resources and preserve their samples in PNG/TIFF/PSD outputs through the shared engine. Tests exercise the existing selectAllLayers action and36 output combinations; they do not establish every action's restricted-mode availability or Adobe numerical equivalence. No Adobe route, descriptor or request field was invented. Restricted conversion, Color Table editing, complete tool/Action context and broader file variants remain open.

**Historical step220 integration stage:** 118 typed Photato commands; native archives through46. Mode conversion, numerical component access, mode-aware Channels editing/viewing and raster/group/mask PSD/PSB/TIFF interchange have305 broader and126 final focused passing checks. Dedicated Adobe mode/channel integration, restricted modes and full parity are unfinished.219 remains the last fully qualified package. See [mode evidence](DOCUMENT_MODE_REFERENCES.json).

### Document color modes (step220, in progress)

`mode.channel.select` takes a unique array of zero-based `components`; an empty array restores the composite editing target. `mode.channel.visibility` takes a nonempty unique array and changes only the visible components. Both update the native Channels panel and revision without pixel/history changes. Native modes and high-depth RGB use these commands; legacy RGB8 retains its existing channel APIs. State exposes `documentMode.editingComponents`, `visibleComponents` and `componentEditingAvailable`; global `channelTarget`/`channelView` names follow the actual mode. `channel-preview.png` renders the committed mode view.

`mode.channel.edit` requires `layerID`, `components` and `action`. `fill` requires `value` in0...1 and optional `opacity` (default1); `stroke` requires1–4096 document-coordinate `points` and optional `brush` settings; `invert` takes no other fields; `filter` requires a native `filter` object of a kind listed in `documentModes.componentFilters`. Unknown/irrelevant fields and repeated/out-of-range indices reject. Brush erase paints the background gray. Edits respect the selection and layer transform, preserve other planes/alpha, and create one guarded Undo transaction. Selected native UI components must match explicit edit targets. Busy/stale/revoked requests retain the existing guards. View-gray0 is black/full CMYK ink; raw `mode.channel.read/write` values remain stored numerical ink. These are distinct semantics.

The native Channels panel has composite and mode-named rows, independent eyes, Shift selection, fill/brush/erase, an Invert context action and eight filter previews/Cancel/commit. Rich-effect channel previews separate the existing RGB composite; ordinary raster previews use retained planes. Mode-native blend fidelity, complete component tools/menu/shortcut qualification, semantic Actions and corresponding Adobe descriptors remain unfinished. No new Adobe route is invented.


Use the existing authenticated `/v1/documents/<shared-id>/commands` route with the current revision. `document.convertMode` requires `mode` (`rgb`, `grayscale`, `cmyk`, `lab`) and integer `depth` (8/16/32; CMYK/Lab support8/16). Optional `profileBase64` supplies a matching validated ICC; omission uses platform standard profiles. `intent` is perceptual, relativeColorimetric (default), saturation or absoluteColorimetric. `mergeVisible` and `clipHDR` default false. Rich layers/Smart Objects/Filters require explicit merging; hidden layers are then discarded and one visible composite replaces the stack. Artboard/frame merging remains unsupported. Reducing32-bit precision requires explicit HDR clipping; this operation does not perform automatic tone mapping. One conversion is one native Undo.

`mode.channel.read` requires raster `layerID` and zero-based color `component`; optional `offset` defaults0 and `count` defaults to the remaining samples capped at4096. Returns layerID, component, offset, numerical values, width, height and revision without changing history. `mode.channel.write` requires layerID, component and1–4096 `values`, with optional offset. Samples are row-major in layer-local coordinates. Integer samples must lie in0...1; floating-point color values may exceed that range. Component order is Red/Green/Blue, Gray, Cyan/Magenta/Yellow/Black, or Lightness/a/b; Lab uses the normalized retained sample representation. Alpha is preserved and not addressed by these operations. Writes bypass selection, preserve other planes and use one Undo; locked/Smart Object targets are rejected. Convert the document before using component access.

State exposes `documentMode`; capabilities expose `documentModes`, strict parameter/result/state schemas and limits. Invalid requests return400, missing layers404, stale/busy/revoked requests409, unsupported targets422 and resource-budget rejection413. Preview/Cancellation and API mutations use the existing shared transaction guards. Native46 download requires `X-Photato-Archive-Version: 46`; native46 import/reopen is tested. PSD/PSB downloads, native file saves and shared input parsers now retain Gray8/16/32, CMYK/Lab8/16 and RGB8/16/32 raster/group/mask component samples and profiles. Native RGB exports use its authoritative plane values; RGB imports retain the existing RGB working-profile representation. Unsupported non-RGB type/fill/adjustment/Smart Object records reject explicitly. `photoshopContainers.colorModes` advertises depths; native-mode geometry is bounded to8,388,608 pixels with the existing API budgets applied as well. TIFF import/output now retains Gray8/16/32, CMYK/Lab8/16 and nativeRGB output through existing save/download/job paths. `layeredTIFF.colorModes` advertises depths. Native Save defaults to layers; copy/download/Photato jobs use `tiffLayers=true` to preserve exact layer components. The Adobe TiffOutput contract remains flattened and does not accept that extension. Both job routes are tested with mode TIFF input/output. Flattened Lab16 chroma is quantized to the public TIFF signed1/256 scale (up to one native code step); embedded layer planes remain exact. Integer native samples, Float32 Gray HDR, ICC, alpha, orientation and lossless strip storage are supported. Native-mode tiled/JPEG TIFF, spot inks/extra channels and non-RGB rich layer records remain unsupported. PNG is rendered RGB. The merged mode preview is derived from the current RGB compositor, so exact native separation/blend behavior is still open. Adobe create-composite and Photato action jobs now accept the blank-document subset described below; complete Adobe channel descriptors and color/default equivalence remain open. Existing RGB blend/filter algorithms use the RGB cache; these APIs do not establish Photoshop numerical or full mode parity.

**Historical checkpoint219:** 112 typed Photato commands; native archives through45 and Actions through18. Five tone/color workflows add tone.apply and tone.statistics; see the step219 section below. Historical command totals describe their own milestones. The Adobe-compatible interface remains separately scoped and partial.

**Select People (step197;96 typed commands):** `selection.findPeople` runs the person-specific local Vision model and caches separate instances. Optional `refresh`, `includeMasks` and `includeThumbnails` are booleans; masks are full-canvas row-major UInt8 `coverageBase64`, thumbnails are PNG `pngBase64` at most96px per side. Responses expose `peopleSelection` and, when requested, `peopleMasks`/`peopleThumbnails`. A ready empty list means no person was detected. `selection.hoverPerson` accepts the current `cacheID` and an optional `instanceID` (omit to clear); `selection.selectPeople` requires that cache and1–64 unique `instanceIDs`, with optional `mode`/`hardEdge`. It selects the union through the same native history/Actions path as the picker. IDs expire on source/layer/sample/tool/refresh/cancel/close changes; stale/revoked requests reject. Detection/hover do not dirty the document. Step198 adds optional `features` to find/select and `feature` to hover. Values: `wholePerson`, `hair`, `bodySkin`, `faceSkin`, `clothes`, `accessories`; omitted values default to whole person. Find applies classes to optional exported masks; select intersects class confidence with each chosen person mask. Arrays must contain1–6 unique names (400 otherwise). Missing/failing optional native Core ML model preserves whole-person detection; unavailable classes return422. State exposes available `features`, `modelAvailable`, `featureError`, `hoveredFeature`, `selectedFeatures` and `selectedIDs`. Whole Person in a feature list selects the entire person. Eyebrows, eyes, lips, teeth, nose and beard labels remain unavailable. See [feature evidence](PEOPLE_FEATURE_REFERENCES.json). Bounds match Object Finder and shared-document limits; optional raw masks have a16MiB aggregate budget before base64. The corresponding desktop button lives in Object Selection options. No Adobe route is invented. See [evidence](PEOPLE_SELECTION_REFERENCES.json).


### Blank documents in both job interfaces

`POST /v2/create-composite` accepts `image` as published `ImageParameters` instead of an image source. `POST /v1/action-jobs` accepts the same creation parameters as a Photato extension and still requires its existing `options.actions` array. Adobe `POST /v2/execute-actions` continues to require `image.source.url`. Native File → New uses the same factory and exposes mode, depth, resolution, background and optional ICC selection.

```json
{
  "image": {
    "width": 1200,
    "height": 800,
    "name": "Print layout",
    "mode": "cmyk",
    "depth": 16,
    "resolution": {"unit": "density_unit", "value": 300},
    "fill": "transparent"
  },
  "outputs": [
    {"mediaType": "image/vnd.adobe.photoshop", "destination": {"validityPeriod": 3600}}
  ]
}
```

The asynchronous202/status/output flow and session resource-job permission are unchanged. Blank jobs fetch no image. A custom ICC source is fetched only when requested; revocation prevents late output publication. Jobs do not alter or automatically open desktop documents. Capability discovery includes `actionJobs.blankDocumentCreation.imageParametersSchema` and runtime limits.

Supported modes/depths are RGB and Grayscale8/16/32, CMYK and Lab8/16. Width/height are required integers1–32000, with a local4,194,304-pixel and128MiB document limit. `unit` supports `pixels_unit`; `pixelScaleFactor` supports1. Resolution uses `density_unit` and integer1–100000, default72pixels/inch. Defaults are RGB8, white and `Untitled-1`. `fill` accepts `white`, `transparent` or `background_color`; the last means white in isolated jobs. An empty document name is allowed; the maximum is255Unicode code points.

ICC may be omitted for the native platform default, or use `{"type":"standard","name":"sRGB IEC61966-2.1"}` (also Adobe RGB (1998), Gray Gamma2.2 spelled `Gray Gamma 2.2`). Named profiles must match the document mode and are linearized for32-bit storage. Custom profiles use `{"type":"custom","name":"My profile","source":{"url":"https://…/profile.icc"}}`, are bounded to4MiB and retained exactly after validation. If supplied, `imageMode` must match the document and the published profile variant. Custom32-bit ICC must already be linear; no silent profile replacement occurs. Platform CMYK/Lab profiles and rendering are not qualified as Photoshop working-profile equivalents.

PSD/PSB input admission now includes Gray8/16/32 and CMYK/Lab8/16. Applicable layer operations share the native engine. RGB channel descriptors reject non-RGB documents; matching Gray/CMYK/Lab descriptors are supported as described below. RGB PSD reopening retains the established Surface/embedded-profile representation; non-RGB files retain native planes. Restricted modes, nonpixel units, nonsquare scaling, other named profiles, the guide-only solidColor fill object, editable non-RGB rich layers, complete channel action variants and exact Adobe output remain open. The solidColor object appears in the prose guide but not the pinned string-only fill schema, so this adapter does not claim to support it.

### Color-mode actionJSON in both job interfaces

Both `POST /v1/action-jobs` and `POST /v2/execute-actions` interpret these descriptors through the same native engine used by the Channels panel and mode conversion workspace. Existing session authorization, URL input, isolated jobs, output encoding, status and error handling apply. Capability discovery exposes `actionJobs.colorModeActions`, including canonical conversion parameter and channel-name schemas. This actionJSON interface is separate from Photato's native recorded Actions format; native conversion/clipboard recording uses Actions19; other mode/channel operations still have separate recording gaps.

Select a component using an enumerated channel reference, then issue neutral Normal Fill, Invert or a supported component filter:

```json
[
  {"_obj":"select","_target":[{"_ref":"channel","_enum":"channel","_value":"black"}]},
  {"_obj":"fill","using":{"_enum":"fillContents","_value":"white"},"mode":{"_enum":"blendMode","_value":"normal"},"opacity":{"_unit":"percentUnit","_value":50}},
  {"_obj":"invert"},
  {"_obj":"average"}
]
```

Channel names are `red/green/blue` (RGB), `gray` (Grayscale), `cyan/magenta/yellow/black` (CMYK), and `lightness/a/b` (Lab). Composite selectors `RGB`, `CMYK` and `lab` clear the component target in their matching mode. Gray also accepts the installed `$Gry ` char-ID alias. Every target must exist in the current mode. RGB/Gray8/16/32 and CMYK/Lab8/16 are supported. Targets persist across separate inline action resources, clear on layer selection or mode conversion, and never authorize access to another document. Fill/Invert/filter require one active pixel layer; other targeted planes and alpha remain byte-preserved. CMYK uses channel-view gray, so black means full ink. Selection coverage and layer placement are respected. The qualified legacy RGB8 Fill path is retained; native-profile and higher-depth documents use their authoritative numerical components.

The eight component filters are Gaussian Blur, Box Blur, Motion Blur, Average, Unsharp Mask, High Pass, Add Noise and Mosaic, using their existing actionJSON descriptors. Composite Invert, other component filters/tools, arbitrary fill colors/blends, alpha/spot channels and selection modifiers remain unsupported in this adapter.

Mode conversion accepts the documented named form or installed public scripting class IDs:

```json
[
  {"_obj":"convertMode","to":{"_enum":"colorSpaceMode","_value":"grayscale"},"depth":16,"merge":false}
]
```

Modes are `rgb`, `grayscale`, `cmyk`, `lab`; `to` may instead be `{"_class":"$RGBM"}`, `$Grys`, `$CMYM` or `$LbCM`. Event `$CnvM` and keys `$T   ` (three trailing spaces), `$Dpth`, `$Mrge` are supported aliases. Supply at least mode or depth; duplicates and unknown parameters reject. Depth must be8/16/32 and valid for the mode. Depth-only conversion retains working-profile primaries and linearizes for32-bit storage. Reducing32-bit precision rejects until the image has been toned through an appropriate workflow; no implicit clipping is performed.

`merge:false` retains supported raster/group layers and their selection. Rich content requires explicit `merge:true`, which converts the visible composite and discards hidden layers, matching the native conversion option. Artboard/frame merge conversion remains unsupported. Later command failures discard the isolated result without publishing hosted outputs. Mode/channel descriptors use public interface evidence; the component names include a plugin author's primary observation on Adobe's developer forum, not a current Photoshop2026 recording. Pixel/default/ICC equivalence, full descriptor variants and complete hosted service conformance remain unqualified.

## Object Finder (step196)

The catalogue now contains93 typed commands. Object Finder uses one local Vision inference and cached per-instance masks. It keeps temporary detection/highlight state separate from document/history. Source edits, layer/tool switches, sample mode, refresh, cancellation and reload/close invalidate the cache; selection-only changes reuse it. The current state includes `objectFinder.available`, `enabled`, `busy`, `ready`, `cacheID`, `hoveredID`, `error`, `hardEdge`, `overlayColor`, and each detected object’s `instanceID` and bounds. Capability discovery includes strict parameter/result/state schemas.

| Command | Parameters and result |
| --- | --- |
| `selection.findObjects` | Optional `refresh:boolean` (false) and `includeMasks:boolean` (false). Detects the active source using current Sample All Layers configuration. Returns standard document state with cache/object IDs; optional `objectMasks` contains `instanceID`, `width`, `height`, and row-major UInt8 `coverageBase64`. Explicit API detection also works while the desktop Finder toggle is off. |
| `selection.hoverObject` | Required `cacheID`; optional `instanceID` highlights that instance, omission clears it. This uses the native temporary overlay. Canvas display additionally requires the enabled Object Selection tool. No document/history change. |
| `selection.selectFoundObject` | Required `cacheID` and integer `instanceID`; optional `mode` (replace/add/subtract/intersect) and `hardEdge:boolean`, defaulting to current tool settings. Uses the cached mask and one native Undo. |

`selection.configure` adds `objectFinderEnabled:boolean`, `hardEdge:boolean`, and `finderOverlayColor:{r,g,b,a}`. Existing `sampleAllLayers` selects active-layer versus composite sampling. `selection.object` adds optional `hardEdge` while preserving manual rectangle/lasso and the earlier direct point detector. Hard Edge uses a native128/255 threshold, with Adobe exactness still unqualified.

Normal revision/authentication/desktop-busy guards apply. Invalid types/fractional IDs return400, absent instances404, expired cache/stale/cancelled/revoked requests409 and unavailable/no-object results422. Source pixels remain unchanged. Native limits are8,388,608 pixels,6000 per side,64 instances and16,777,216 aggregate raw mask bytes with the conservative256MiB padded-tile bound; shared API limits additionally require4,194,304 pixels/64 layers/128MiB document data. `includeMasks` can produce about22.4MB of base64 plus JSON; omit it when IDs/bounds are sufficient. Native32 is unchanged; Actions4 records frozen selection coverage rather than re-running detection.

There is no dedicated desktop Object Finder endpoint in the pinned Adobe v2 contract; auto-crop bounding boxes are a different operation. This does not claim Adobe actionJSON/model equivalence. See [Object Finder evidence](OBJECT_FINDER_REFERENCES.json).


## Mask All Objects (step195)

The current catalogue contains90 typed commands. `layer.maskAllObjects` takes only `layerID` (a raster-layer UUID) through the usual authenticated shared-document command route with its current revision. It returns the standard updated document state plus `createdGroupIDs`, ordered bottom to top. `maskAllObjects` state reports desktop availability and geometry-busy status; capabilities expose parameter/result/state schemas and resource limits.

The native Vision adapter runs one local instance inference and creates a separate empty Pass Through masked group for each detected foreground object. Groups are placed above the source clipping family, inside its parent. The top group is selected. Add an adjustment inside a group to affect that object; the source layer, existing masks, pixels, clipping hierarchy and selection are retained. A locked source is allowed because it is unchanged; its parent must be unlocked. The requested layer is sampled in canvas coordinates with its mask/transform, without layer effects, through an SDR/sRGB proxy. The existing selection does not restrict analysis.

```json
{"command":"layer.maskAllObjects","revision":"<current revision>","parameters":{"layerID":"<pixel layer UUID>"}}
```

One successful request creates one Undo step. Invalid parameters return400, missing layer404, stale/busy/cancelled/revoked requests409, unsupported target/model/no-object cases422, and API post-edit document-budget failure413. All failures leave source/history unchanged. Native bounds are8,388,608 canvas pixels,6000 per side,64 instances,16,777,216 aggregate mask pixels and256MiB worst-case padded tile storage; shared API limits additionally require4,194,304 canvas pixels,64 layers and128MiB document data. Excess instances/work fail atomically rather than truncating results.

There is no dedicated Mask All Objects route in the pinned Adobe v2 contract. Auto-crop object bounding boxes are a different result; this does not add an Adobe mask-group endpoint. Mask All Objects actionJSON and recorded Actions remain explicitly unsupported. Native32 saves all editable mask groups. Apple model quality, semantic naming/order and full Photoshop parity remain unqualified. See [evidence and limitations](MASK_ALL_OBJECTS_REFERENCES.json).

## Actions and Batch (step182)

The API now advertises66 typed commands. `actions.manage` takes `operation` and the operation-specific fields below. Each request uses the usual shared-document command route, Bearer token, current revision and desktop-busy checks. Management responses contain `state` and the new `revision`; exports also contain `format`, `version` and base64 `data`. Full document state exposes `actions` and `batch`.

| Operation | Fields |
| --- | --- |
| list | none |
| record | name, optional set (default My Actions) |
| stop / cancel | none; stop saves the recorded action, cancel discards the recording |
| rename | actionID, name, set |
| delete | actionID |
| import | data: base64 native versions1–19 library JSON, at most60000 characters |
| export | optional actionID; omit to export the library |
| step.enable | actionID, stepID, enabled:boolean |
| step.delete | actionID, stepID |
| step.move | actionID, stepID, index:zero-based destination |

Library writes affect the same local library as the Actions panel. Imports create independent copies and preserve existing actions. Existing unreadable libraries cannot be overwritten through management. Native .photatoactions files support128 actions/512 entries each/16MiB; API requests retain their64KiB bound. Native files larger than the API import limit can be loaded through the panel. Recording tracks successful document commits, retained Undo/Redo transaction groups and layer selections. No-op document-only changes and failed/cancelled edits are omitted; successful Copy/Cut/Paste are retained semantically even when pixels do not change. Unsupported edits leave visible blocking entries. Stop before playing or changing the library. Library mutations and start/stop/cancel invalidate API revisions.

`actions.play` takes `actionID`. Active-layer references follow the target document's active layer; named references resolve name plus occurrence, independent of UUIDs. Pixel coordinates/dimensions are absolute; Move records a relative displacement. Playback is atomic, stops with an indexed error, and creates one undo step. Per-step API resource limits apply. Enabled unsupported steps fail explicitly; disabled steps are skipped. Native playback cancellation uses the existing geometry task.

`actions.batch` takes `actionID`, `sources:[{id,revision}]`, `format`, optional `options` (the shared encoding schema), optional `suffix` (default `-processed`) and optional `stopOnError` (default false). Include the command target once among1–8 unique shared sources. Enable **Allow local document saving** and choose the API save folder in the native API window first. No input/output paths are accepted. Batch reads independent snapshots, validates each action step, and writes numbered new copies such as `0001-Example-processed.png`. Existing output names fail; originals, open-document state and history remain unchanged. Outputs use the regular export codecs (PNG/JPEG flatten, Photato preserves native structure; PSD/PSB reject unsupported representation). The API response contains `operationID`, `completed`, `cancelled` and `results:[{source,output,error,cancelled}]`; output is a filename, never a private absolute path.

While the request is running, GET document state exposes `batch.active`, `operationID` and partial results. `actions.batch.cancel` takes that operationID from a participating source. Cancellation, stopped-on-error and revoked permissions preserve already published copies and mark remaining inputs unprocessed. Save permission/folder generation, sharing and source revision are checked before every file publication. Batch output is capped at128MiB per file; exclusive hard-link publication requires a supporting filesystem. No overwrite, Bridge, droplet, recursive scan or Open/Save override mode is implemented.

The existing Adobe `/v2/execute-actions` job adapter remains a separate, bounded descriptor interpreter with resource-based inputs/outputs. These desktop library/batch operations are Photato-specific; this increment does not invent an Adobe endpoint or add `.atn`/JavaScript support. See [evidence and remaining gaps](ACTIONS_BATCH_REFERENCES.json).

## Perspective Warp (step181)

Use `filter.apply` with `layerID` and `filter:{kind:"perspectiveWarp",perspective:{...}}`. Settings include up to16 `planes`, optional `locks`, `interpolation` (Nearest Neighbor/Bilinear/Bicubic; default Bicubic), and optional one-shot `straighten` (horizontal/vertical/auto). Each plane has four perimeter-ordered `source` points `{x,y}` in document pixels and optional corresponding `destination` points (default source). Points must be finite, bounded to±1,000,000 and form convex nondegenerate quads. Source corners within0.5px link and are canonicalized; destination corners in each linked group share one position. Projective horizons crossing a single-plane input reject.

Each lock is `{plane:0,edge:0,axis:"horizontal"}` or vertical, with zero-based plane/edge indices. Edge0 connects corners0–1, edge1 corners1–2, etc. Locks persist, and shared corners carry the constraint. `straighten` modifies canonical destination points once and is not stored as a repeated operation. Whole-layer transforms carry source/destination coordinates. Axis locks rotate between horizontal/vertical for axis-preserving transforms; arbitrary rotations/shears release them after preserving the effective warped geometry.

Example parameters: `{"layerID":"<uuid>","filter":{"kind":"perspectiveWarp","perspective":{"planes":[{"source":[{"x":10,"y":10},{"x":110,"y":10},{"x":110,"y":90},{"x":10,"y":90}],"destination":[{"x":20,"y":10},{"x":100,"y":15},{"x":110,"y":90},{"x":10,"y":90}]}]}}}`.

Ordinary layers bake one undoable edit. Smart Objects retain the program in `layers[].smartFilters`; update it with `smartFilter.set`, preserving filter IDs. Visibility/reordering/blend/opacity/mask controls remain shared. Empty programs are a no-op; identity planes may be retained for future Smart Object editing. Editable programs require `X-Photato-Archive-Version: 26` on downloads. State includes `perspectiveWarp.available/workspaceOpen/previewBusy`; filter capabilities publish schema/limits. Invalid settings return400, unsupported contexts422, stale revisions or busy desktop409. Alpha/Quick Mask targets reject without edits.

No dedicated Perspective Warp route exists in the pinned Firefly v2 contract. Unverified actionJSON and editable PSD/PSB descriptor transport reject explicitly. Use native26 or explicitly rasterize. No Adobe pixel equivalence is claimed; see [Perspective references](PERSPECTIVE_REFERENCES.json).

## Puppet Warp (step180)

Use `filter.apply` with `layerID` and `filter: {kind:"puppetWarp", puppet:{...}}`. `puppet` accepts `mode` (`rigid`, `normal`, `distort`), `density` (`fewer`, `normal`, `more`), `expansion` (−200…200 pixels), `interpolation` (`Nearest Neighbor`, `Bilinear`, `Bicubic`), and up to64 pins. Defaults are Normal mode/density,2px expansion and Bicubic. Each pin has `source:{x,y}`, optional `destination:{x,y}` (defaults to source), optional `rotation` in degrees (null/omitted means Auto), and integer `depth` (−1000…1000; higher draws later). Coordinates are document pixels, with finite magnitudes up to1,000,000. Duplicate source pins reject.

Example parameters: `{"layerID":"<uuid>","filter":{"kind":"puppetWarp","puppet":{"pins":[{"source":{"x":20,"y":30}},{"source":{"x":100,"y":60},"destination":{"x":110,"y":50},"rotation":12}]}}}`. Ordinary layers bake one undoable transaction. Smart Objects retain editable programs in `layers[].smartFilters`; modify existing entries with `smartFilter.set`, preserving their IDs. Existing visibility, blend/opacity, reordering and filter-mask operations apply. Layer moves/transforms carry retained pin coordinates. Empty programs are a no-op; stationary pins on Smart Objects can be retained for later editing.

State includes `puppetWarp.available/workspaceOpen/previewBusy`; filter capabilities expose the schema and limits. Native workspace drafts block API edits. Invalid parameters return400, unsupported contexts422, and stale revisions/busy desktop409. Unlocked RGB pixel/Smart Object targets without selections or vector masks are supported; convert other types to a Smart Object first. Source pixels and embedded Smart Object data remain retained. Downloads containing editable Puppet programs require `X-Photato-Archive-Version: 25`.

No dedicated Puppet route exists in the pinned Firefly contract. Unverified actionJSON descriptors and editable PSD/PSB transport reject explicitly; native25 or explicit rasterization remains available. This is native Rust-derived functionality, not a claim of Adobe pixel equivalence. See [Puppet references](PUPPET_REFERENCES.json).

## Warp (step179)

`layer.warp` takes `layerID` and `settings`. Settings include `style` (`none`, `custom`, or one of the fifteen preset identifiers in `capabilities.warp`), `bend`, `horizontalDistortion`, `verticalDistortion` (−100…100), `vertical` and `interpolation` (`Nearest Neighbor`, `Bilinear`, `Bicubic`). Defaults are None, zero amounts, horizontal orientation and Bicubic. `custom` requires `mesh: {us, vs, points}`. Knots ascend from0 to1; points are row-major `{x,y}` in unwarped source pixels, with `3*(us.count−1)+1` columns and analogous rows. Other styles reject a mesh.

Example parameters: `{"layerID":"<uuid>","settings":{"style":"arch","bend":50}}`. The operation replaces the instance warp on a Smart Object and retains source pixels; ordinary pixel layers bake it once. Both paths use the native prepared edit and Undo/Redo. `style:none` removes a retained warp. `layers[].warp` returns the retained definition. Preview state/availability appears at `warp`; native workspace drafts block API edits. Existing revision, busy, source-lock, cancellation, sharing and document-budget guards apply. Invalid settings return400; unsupported contexts return422.

This increment supports unlocked RGB pixel/Smart Object layers without selections or vector masks. Linked pixel masks follow; unlinked masks remain in document space. Native downloads of editable warps require `X-Photato-Archive-Version: 24`; older readers are rejected. PSD/PSB export requires explicit rasterization until editable descriptor transport is implemented. No standalone Warp route is defined in the pinned Firefly v2 contract, and an authenticated corresponding actionJSON descriptor is not implemented. The UXP desktop geometry interface does not establish a Firefly endpoint. See [Warp references](WARP_REFERENCES.json) for limits and remaining parity work.

## Merge to HDR Pro — step177

There are now58 typed commands. Enable document uploads/downloads and explicitly share2–7 source documents. Submit to `POST /v1/documents/{targetID}/commands`, including that target in the source list:

```json
{"command":"document.hdrMerge","revision":"TARGET_REVISION","parameters":{"sources":[{"id":"SHARED_ID_1","revision":"REVISION_1"},{"id":"SHARED_ID_2","revision":"REVISION_2"},{"id":"SHARED_ID_3","revision":"REVISION_3"}],"name":"HDR Scene","settings":{"exposureSource":"manual","exposureEV":[-2,0,2],"align":true,"removeGhosts":true,"ghostBase":1,"depth":"32 bit"}}}
```

`name` and `settings` are optional. Exposure source is `metadata` (default, complete EXIF exposure time/aperture/ISO required), `manual` (one EV per source,−20…20), or `estimate` (explicit native image-based estimation). `align` defaults true; `removeGhosts` false; `ghostBase` is an optional zero-based source index, otherwise automatically chosen. `depth` is `32 bit` (default), `16 bit`, or `8 bit`. Tone-mapped output supports `method`: `localAdaptation` (default), `exposureGamma`, `highlightCompression`, `equalizeHistogram`.

Tone fields: radius1…500(default7), strength0.1…4(default0.52), gamma0.1…4(default1), exposure−5…5(default0), detail−100…300(default30), shadows/highlights/vibrance−100…100(default0), saturation−100…100(default20). Unknown fields/types, invalid source counts and unsupported settings reject400; busy/stale requests409. Sources must have equal dimensions and be opaque camera/display-range exposures. Missing metadata requires manual values or explicit estimation. Extended-range HDR inputs reject; do not use merging as an existing-HDR tone command.

HTTP201 returns a new shared unsaved document and `hdrMergeResult`: relative `exposureEV`, `exposureSource`, integer `offsets`, selected `ghostBase`, `ghostFraction`, estimated `stops`, `responseCurve`(3×256) and `sourceCount`. Input documents/history stay unchanged. New-document saving/recovery and subsequent Undo use ordinary native paths.32-bit output retains linear radiance;16/8-bit output is tone mapped. All sources convert into sRGB; converted out-of-gamut camera colors clamp. Native limits16MP/source and32MP combined; API adds4MP/64layers/128MiB and eight total shared documents.

Participating document state exposes `hdrMerge.operationID`. Cancel with `document.hdrMerge.cancel`, current participating revision and `parameters:{"operationID":"UUID"}`. The acknowledgement requests cancellation; original work ends409 with no document publication. Revocation/API shutdown, source changes and opening/closing/recovery conflicts also prevent publication. Refresh revisions after cancellation. No transfer grant403; missing source404; busy/stale/lifecycle409; resource limit413; unsupported merge422; no share slot429. No local paths are accepted.

Global `hdrMergeState` reports native open/loading/rendering/ready, sourceCount, API creation state and previewExposure. The native32-bit preview exposure only changes the displayed image; it does not alter merged output. The pinned published Adobe v2 contract has no dedicated HDR route, and no authenticated HDR action descriptor is implemented. This orchestration is Photato-specific; existing Adobe-compatible interfaces remain available. [Evidence and limits](HDR_MERGE_REFERENCES.json).

## Photomerge — step176

There are now56 typed commands. Enable native document uploads/downloads, explicitly share2–7 source documents, and submit to `POST /v1/documents/{targetID}/commands`. Include the target among the ordered source IDs. Each source requires its current revision:

```json
{"command":"document.photomerge","revision":"TARGET_REVISION","parameters":{"sources":[{"id":"SHARED_ID_1","revision":"REVISION_1"},{"id":"SHARED_ID_2","revision":"REVISION_2"}],"name":"Panorama","settings":{"projection":"auto","blendImages":true,"fillTransparentAreas":false}}}
```

`name` and `settings` are optional. Projection choices match `photo.autoAlign`; defaults are Auto, blend=true and fill=false. Optional focalLengthPixels is10…1,000,000. Sources are flattened and converted into the first source's depth/working profile before alignment. The output canvas encloses all transformed sources; no silent crop is used to satisfy resource limits. Blending retains masked sources below a merged result. Fill also works without blending, adding only synthesized holes in a separate layer.

Success is HTTP201 with a new shared unsaved document state and `photomergeResult` (projection, matchedPoints, rmsPixels, sourceCount). Source documents and their history remain unchanged. The new document uses ordinary save/recovery/history for subsequent edits. Creation is cancellable and does not append an edit to an arbitrary source's history. Revalidate source revisions after any cancelled operation before retrying. Limits:16MP/source,32MP combined alignment;16MP expanded canvas;4MP blended/fill output and16MP combined blend grid; API4MP canvas/64layers/128MiB and8 total shared documents.

While running, participating document states expose `photomerge.operationID`; global capabilities expose native preview/loading and API creation state. Cancel from any participating source using its current revision:

```json
{"command":"document.photomerge.cancel","revision":"CURRENT_REVISION","parameters":{"operationID":"OPERATION_UUID"}}
```

Cancellation returns an acknowledgement; the original operation ends409 without publishing a document. Revoking document-transfer permission or stopping the API cancels the worker. Unknown fields/types, duplicate/missing inputs and invalid settings reject400; no permission403; unknown shared source404; stale/busy/revoked/lifecycle conflict409; output API limit413; unsupported geometry/matching422; no free share slot429. Inputs must already be explicitly shared; local filesystem paths are never accepted from the API. [Schemas, evidence and limits](PHOTOMERGE_REFERENCES.json).

The pinned [published Photoshop v2 contract](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/) contains no dedicated Photomerge operation. This orchestration is Photato-specific. The existing Adobe-compatible create-composite and execute-actions alignment/blend subsets remain available and are regression-tested; no `/v2/photomerge` route is invented. Exact proprietary behavior and complete endpoint conformance remain open.

## Auto-Align Layers — step175

There are now 54 typed commands. Submit `photo.autoAlign` with a current revision and two to16 unique layer UUIDs to `POST /v1/documents/{id}/commands`:

```json
{"command":"photo.autoAlign","revision":"CURRENT_REVISION","parameters":{"layerIDs":["LAYER_UUID_1","LAYER_UUID_2"],"settings":{"projection":"auto"}}}
```

`settings` is optional. `projection` is `auto` (default), `perspective`, `cylindrical`, `spherical`, `collage` or `reposition`. Optional `referenceLayerID` must be selected; optional `focalLengthPixels` is10…1,000,000. The default reference is the locked input if present, otherwise the first selected layer in document order. Unknown keys/types, invalid UUIDs/counts, duplicates or invalid settings reject400; stale/busy requests409; unsupported contexts/budgets422. Capabilities expose the complete settings schema/limits; state reports native preview availability/open/busy status. Results return the ordinary updated document state/revision.

Visible ordinary raster inputs must share a parent. Only a planar reference may be locked; unsupported Smart Objects/effects/vector masks/clipping reject explicitly. Matching uses a900px registration scale; full-resolution pixels and effective raster masks warp together. Limits are16MP per layer and32MP combined for source/output. Canvas and selection remain unchanged; off-canvas results are retained. Disconnected matches abort without partial edits. Native and API transactions share cancellation, source validation, Undo/Redo and supported native/PSD persistence. Use `photo.autoBlend` afterward for seams or focus stacking.

Both action-job interfaces accept the installed Photoshop content-alignment descriptor within their existing actionJSON envelope:

```json
[{"_obj":"selectAllLayers","_target":[{"_ref":"layer","_enum":"ordinal","_value":"targetEnum"}]},{"_obj":"$Algn","_target":[{"_ref":"$Lyr ","_enum":"$Ordn","_value":"$Trgt"}],"$Usng":{"_enum":"$ADSt","_value":"ADSContent"},"$Aply":{"_enum":"projection","_value":"$Auto"}}]
```

Supported projection enum values are `$Auto`, `$Prsp`, `cylindrical`, `spherical`, `sceneCollage` and `translation`. This does not add an Adobe route or claim other long-string aliases. The native implementation is shared by `POST /v1/action-jobs` and published `POST /v2/execute-actions`. Lens correction/vignette, exact Adobe pixels, difficult-image performance and live/platform qualification remain open. [Evidence and limits](PHOTO_ALIGN_REFERENCES.json).

## Auto-Blend Layers — step174

There are now 53 typed commands. Submit `photo.autoBlend` with current `revision`, two to16 unique `layerIDs` and optional `settings` to `POST /v1/documents/{id}/commands`:

```json
{"command":"photo.autoBlend","revision":"CURRENT_REVISION","parameters":{"layerIDs":["LAYER_UUID_1","LAYER_UUID_2"],"settings":{"method":"stack","seamlessTones":true,"fillTransparentAreas":false}}}
```

Method is `panorama` (minimum-cost seams) or `stack` (focus scoring). Defaults:panorama, seamlessTones=true, fillTransparentAreas=true. Unknown keys/types, duplicate IDs and invalid counts reject400; stale/busy requests409; unsupported contexts/budgets422. `capabilities.photoBlend` exposes settings/ranges, output construction and limitations. `state.photoBlend` reports native UI availability and preview state. The RAW `raw.develop` command schema has also been repaired to advertise the correct sensor settings.

Inputs should already be aligned, visible unlocked pixel layers sharing a parent, with Normal blend and full opacity. Smart Objects/effects/vector masks require rasterization. The clipped source bounding rectangle is limited to4MP; its pixel count times the number of inputs is limited to16MP. Existing selection is retained. New8-bit masks incorporate existing effective layer-mask coverage. Source pixel data stays unchanged. Seamless Tones and Colors applies multiband blending; optional transparent-area fill uses native content-aware synthesis. Either option produces a merged layer and hides its masked sources to avoid double alpha. With both options false, sources remain visible and selected with new masks. Existing native/PSD mask/layer persistence and one-step Undo/Redo apply; no new archive version is required.

The installed Photoshop2026 panorama descriptor is supported through both `POST /v1/action-jobs` and published `POST /v2/execute-actions`, in the existing options.actions/source.content actionJSON envelope:

```json
[{"_obj":"selectAllLayers","_target":[{"_ref":"layer","_enum":"ordinal","_value":"targetEnum"}]},{"_obj":"mergeAlignedLayers","$Aply":{"_enum":"autoBlendType","_value":"panorama"},"$ClrC":true,"autoTransparencyFill":false}]
```

The `$Aply` enum and both booleans are explicit. This bounded vocabulary comes from installed StackSupport.jsx; Stack Images descriptor variants/long-string aliases remain unsupported until verified. Native `photo.autoBlend` supports both blend methods. No new Adobe route is invented. Both job interfaces share native processing and existing async status/output conventions. Auto-Align, Photomerge, HDR/statistics, exact Adobe algorithms and live/platform qualification remain open. [Evidence and limits](PHOTO_BLEND_REFERENCES.json).

## RAW source development — step173

There are now 52 typed commands. `raw.inspect` and `raw.develop` require the current document `revision` and a RAW Smart Object `layerID`. Both use the same original-source decoder and document transaction as Edit Contents.

```json
{"command":"raw.develop","revision":"CURRENT_REVISION","parameters":{"layerID":"LAYER_UUID","settings":{"exposure":0.5,"temperature":5200,"adjustments":{"vibrance":20}},"allInstances":true}}
```

Submit to `POST /v1/documents/{id}/commands`. Omitted top-level settings retain the existing values. A supplied `adjustments` object replaces the RGB group, with omitted RGB fields returning to neutral defaults. Nullable temperature/tint/decoderVersion/lensCorrection/highlightRecovery reset to decoder defaults; allInstances defaults true. Setting it false creates an independent source identity for the target. `raw.inspect` is read-only and returns native dimensions, camera/decoder metadata, supported decoder versions and selected-decoder lens/highlight availability, saved settings and current revision. It exposes no source GPS/private metadata.

`capabilities.rawDevelopment` supplies the strict schema/ranges and limits. Sensor controls include exposure(-5…5), temperature(2000…50000), tint(-150…150), boost(0…1), shadowBoost(0…2), extendedRange(0…2), decoder version and supported lens/highlight booleans. The RGB `adjustments` group uses the Camera Raw schema below. Invalid settings/booleans return400; stale/busy requests409; unsupported sources/decoder/camera controls/locked targets422. Highlight recovery requires macOS26+ and decoder support. No network model or cloud fallback is used for source decoding.

Upload genuine RAW using `POST /v1/documents/import`, media type `image/x-camera-raw` or `image/x-adobe-dng`; optional `X-Photato-Open-Format: raw`. The existing API4MP and 64MiB limits apply. Desktop sensor decoding is bounded to36MP/64MiB. Import defaults to RGB16; redevelopment follows current document depth/profile. State includes `layers[].smartObject.rawDevelopment`; the existing `smart-objects/{layerID}/source` download returns exact original bytes. A source revision now includes its development settings. Native documents containing RAW sources require `X-Photato-Archive-Version: 22`; earlier requested versions reject. Native22 readers also accept1…21. Save native Photato to retain editability; editable PSD RAW descriptors explicitly reject.

The Adobe-compatible `POST /v2/edit` accepts supported RAW/DNG resources in the pinned `EditImageInput` contract, decodes sensors through the same native engine and applies supported LightroomEdits light/color/effects/detail fields. Existing async status/output conventions and PNG/JPEG output remain. DNG output, XMP, Adobe whiteBalance presets, proprietary pixel equality and all-camera support remain open. [Evidence and limitations](RAW_DEVELOPMENT_REFERENCES.json).

## Camera Raw Filter — step172

`filter.apply` accepts `{"kind":"cameraRaw","cameraRaw":{"exposure":0.5,"highlights":-25,"texture":15,"vibrance":20,"sharpenAmount":40,"vignetteAmount":-20}}` in its `filter` parameter, together with the target `layerID` and current document revision. Raster edits bake into the layer; Smart Objects append an editable filter. `smartFilter.set` edits/reorders/disables the same stored settings. There remain 50 typed commands; capability discovery exposes the new kind, complete strict settings schema and ranges under `filters.cameraRaw`.

Settings cover light, temperature/tint, vibrance/saturation, four parametric curve regions and four point curves, eight-band hue/saturation/luminance arrays, four grading wheels, texture/clarity/dehaze, sharpening/noise reduction, grain and vignette. Omitted fields use neutral defaults. Curves accept zero or 2–16 increasing points in 0–255; mixer arrays have eight values. Numeric booleans, unknown keys and invalid ranges reject before mutation. The settings object is bounded to32KiB. UI settings files use this same JSON object. Rendering is native Swift, supports RGB8/16/32 and preserves alpha. Maximum layer size is8,388,608 pixels; existing API limits also apply. Revision/busy/cancellation and history guards remain unchanged.

Download documents containing editable Camera Raw filters with `X-Photato-Archive-Version: 21`; earlier versions fail422, preserving editability. Native21 readers accept previous versions. PSD/PSB editable Camera Raw descriptor export and channel/mask filtering reject explicitly.

The published Adobe `POST /v2/edit` accepts `edits.light` (exposure, contrast, highlights, shadows, whites, blacks), `edits.color` (saturation, vibrance), `edits.effects` (texture, clarity, dehaze, vignette), `edits.noiseReduction` (luminance, color), `edits.sharpness`, and `edits.sharpen` (radius, detail, edgeMasking). Published ranges/types are validated. These use the same Camera Raw engine, flattened input lifecycle and existing PNG/JPEG output jobs/destinations. This changes the former color-only ClassicAdjustment approximation to Camera Raw rendering. AutoTone, autoStraighten, white-balance presets, XMP, Adobe presets, sensor RAW input and Camera Raw execute-actions descriptors remain unsupported. API contract support does not establish Adobe pixel equality. See [provenance and limits](CAMERA_RAW_REFERENCES.json).

## Select and Mask — step166

There are now **42 typed commands**. `selection.refine` runs the same Swift matting and prepared history path as the desktop workspace. Required parameter: `layerID` (ordinary raster layer UUID). Optional parameters: `settings`, `output`, `strokes`, `fromLayerMask` and `sampleAllLayers`. Example command body:

```json
{"command":"selection.refine","revision":"CURRENT_REVISION","parameters":{"layerID":"LAYER_UUID","settings":{"radius":4,"smartRadius":true,"feather":1.5,"shiftEdge":-10},"output":"newLayerWithMask"}}
```

Settings accept radius0–250px, smartRadius boolean, smooth0–100, feather0–1000px, contrast0–100%, shiftEdge−100–100%, decontaminate boolean and amount0–100%. Defaults are0/false except amount100. Output defaults to `selection`; choices are `selection`, `layerMask`, `newLayer`, `newLayerWithMask`, `newDocument`, `newDocumentWithMask`. Decontamination upgrades selection/layerMask to newLayerWithMask. Layer masks replace an existing pixel mask. New layers hide the original; new documents leave it untouched. Mask-free cutouts bake alpha; masked outputs retain editable coverage.

Input is the current selection, or empty when absent. `fromLayerMask:true` starts from the target's stored pixel-mask coverage (ignoring its density/feather display properties). `sampleAllLayers:true` uses the composite color guide. Brush entries take `points:[[x,y],...]` in canvas pixels, with optional `tool` (`add`, `subtract`, `refine`, `eraseRefinement`, `lassoAdd`, `lassoSubtract`), `size`1–5000px (default30), and `hardness`0–1 (default0.8). Limits:1024 strokes,16384 total points,4096 per stroke,250million brush-pixel visits. Canvas and source raster each support up to8,388,608 pixels; existing API document limits remain stricter. Command bodies retain the4MiB limit. Unknown keys, malformed types and out-of-range settings reject before mutation.

Ordinary outputs return200 and the existing document state, with one Undo transaction. New-document outputs require separately enabled document transfers and an available share slot, then return201 with the newly shared document state; the source revision/history is unchanged. Completion rechecks source revision, cancellation, sharing and lifecycle state. Errors retain the standard envelope:400 malformed,403 permission,409 stale/busy/revoked,413 resource limits,422 unsupported context,429 transfer/sharing capacity. `selectionRefinement.available` and `.workspaceOpen` expose desktop availability/draft state; the schema is recorded in [the refinement reference](SELECT_MASK_REFERENCES.json). Capabilities expose settings/stroke schemas and output values.

Adobe's pinned v2 contract has no dedicated refinement endpoint. Refinement action descriptors, proprietary Object Aware/Refine Hair models and exact Photoshop pixels remain unsupported/unqualified; this native command does not invent an Adobe route. All previously supported Adobe routes are retained.


## Native editable text — step162

There are37 typed Photato commands. `text.create` takes required `x`, `y` (integer pixels) and `text`, with optional `name`. `text.set` takes `layerID` and a complete replacement `text` description. Both share desktop history and retain type editability. Example parameters:

```json
{"x":20,"y":30,"name":"Caption","text":{"text":"Hello Photato","kind":"paragraph","width":500,"height":180,"style":{"font":"HelveticaNeue","size":36,"color":{"r":0.1,"g":0.2,"b":0.8,"a":1}},"paragraph":{"alignment":"center"}}}
```

The text object requires `text`; optional `kind` is `point` (default) or `paragraph` (requires width/height). `style` accepts font (installed PostScript name), size, sRGB color, tracking, baseline, leading (0 automatic), horizontalScale/verticalScale, underline and strikethrough. `paragraph` accepts alignment left/center/right/justified, direction natural/leftToRight/rightToLeft, firstIndent/startIndent/endIndent, spaceBefore/spaceAfter and hyphenation. `runs` is an optional complete UTF-16 partition: each element has positive `length`, `style` and optional `paragraph`; boundaries cannot split surrogate pairs. Omitted style fields inherit the top-level style. Empty runs apply the default style to the whole string. `antialias` is boolean. `text.set` replaces the whole description rather than patching omitted fields.

Font size, baseline, leading and paragraph distances use points at the document resolution. Tracking uses thousandths of an em; character scales are factors. Position/frame sizes use pixels. Maximums:100000 UTF-16 units,4096 runs,32768 pixels per frame dimension and16777216 rendered pixels. Existing HTTP transfer limits also apply. Missing fonts and oversized render frames explicitly fail. Read `layers[].text` and `capabilities.text.schema`. Native downloads containing rich text require `X-Photato-Archive-Version: 16`; older requested versions return422. Invalid payloads return400, missing layer404, stale/busy409, and unsupported/locked/render-limited operations422.

The published `POST /v2/create-composite` adapter adds `text_layer` add/edit operations. Example layer edit:

```json
{"type":"text_layer","operation":{"type":"add","placement":{"type":"top"}},"name":"Caption","text":{"content":"Hello Photato","frame":{"type":"area","bounds":{"left":20,"top":30,"right":520,"bottom":210}},"characterStyles":[{"characterStyle":{"font":{"postScriptName":"HelveticaNeue"},"fontSize":36,"autoLeading":true}}],"paragraphStyles":[{"paragraphStyle":{"alignment":"center"}}]}}
```

Submit this in `edits.layers`, with the existing `image.source.url` and `outputs` resource/job envelope. Edit an existing text layer with operation.type `edit` and exactly one name or PSD id. `apply:{"from":0,"to":4}` is inclusive; paragraph applies count paragraphs. Adobe font/spacing units are pixels and are converted to native points. Point-frame origins are baseline coordinates; Photato `text.create` coordinates describe its top-left local frame. The current adapter supports horizontal text, none/smooth AA, represented font/underline/alpha/leading/tracking and paragraph options, visibility/clipping and transformMode none. Root `fontOptions` supports installed defaultFontPostScriptName and missingFontStrategy fail/use_default. It never impersonates Adobe Fonts.

The pinned fontColor schema is opaque; custom Adobe fontColor and external fonts explicitly reject, as do synthetic/caps, vertical/path/warped text and unmapped transforms/placement/justification variants. Rich text native persistence supports more options than PSD; unsupported layered output rejects. Both API interfaces remain distinct, and Adobe endpoint support remains partial. [Provenance, tests and open scope](TYPE_EDITING_REFERENCES.json).

## Editable Smart Filters — step161

There are35 typed Photato commands. `filter.apply` appends an editable filter when the target is a Smart Object; ordinary raster targets keep their existing baked behavior. Use the current document revision for every edit. The same native transactions supply preview/commit, Undo/Redo and prepared-operation cancellation.

| Command | Parameters |
|---|---|
| `filter.apply` | Existing `layerID`, `filter:{kind,...parameters}`; Smart Objects append a filter |
| `smartFilter.set` | `layerID`, `stack:{enabled,filters,mask?}`; `stack:null` clears |
| `smartFilter.maskStroke` | `layerID`, `points:[{x,y,pressure?}]`, `size`, `hardness`, `opacity`, `value` |
| `smartFilter.maskFill` | `layerID`, grayscale `value` from0 to1; respects selection |

`filters` is bottom-first application order. Each entry requires `id` (UUID), `filter` (the existing kind-specific schema), `enabled`, `opacity` (0...1) and `blendMode` (a native blend-mode name). Read `layers[].smartFilters`, edit/reorder/remove those entries, then submit `enabled` and `filters` to `smartFilter.set`. Do not submit the read-only `hasMask` or `maskTransform` fields. A first filter creates a white mask, or a selection mask if a selection exists. `mask.operation` accepts `keep`, `reveal`, `hide`, `selection` and `delete`; optional `enabled`, `linked`, `density` (0...1) and `feather` (0...100 pixels) update its properties. Filter-stack edits preserve the embedded source and ordinary layer mask.

Stroke points use document coordinates within±1,000,000. Supply1...4096 points; optional pressure defaults to1. Brush size is0.5...2048 pixels; hardness/opacity/value are0...1. Black hides the filtered effect, white reveals it. Selection coverage also applies. Capabilities expose `smartFilters.stackSchema` and `smartFilters.layerStateSchema` plus limits and supported kinds. There are at most32 filters and8,388,608 pixels in the union of canvas and placed source bounds. Existing overall API document limits also apply. Invalid request shapes return400, missing layers404, stale/busy/cancelled requests409, and unsupported/locked/native-invalid operations422. No filter is silently skipped.

Source-bearing stacks require `X-Photato-Archive-Version: 15` on native downloads. Versions14 and below reject. Native15 preserves every supported filter and mask property. PSD/PSB supports Gaussian Blur, Box Blur, Motion Blur, Unsharp Mask, High Pass, Add Noise and Mosaic via editable `filterFX` and `FEid` records. Average, fractional Motion Blur angles and mask density/feather/inversion/fractional outside coverage remain native-only and reject layered PSD export. Raster exports render all supported native filters.

The published Adobe `POST /v2/execute-actions` workflow now accepts exact unique layer-name selection before a filter action on a prepared Smart Object PSD. Submit this actionJSON string in the existing `options.actions[].source.content` object with `contentType:"application/json"`:

```json
[{"_obj":"select","_target":[{"_ref":"layer","_name":"Artwork"}]},{"_obj":"gaussianBlur","radius":{"_unit":"pixelsUnit","_value":12}}]
```

Use the existing `image.source.url`, `outputs`, bearer token and asynchronous status/output lifecycle. The separate `/v1/action-jobs` interface continues to use the same interpreter. PSD/PSB output preserves supported editable filters; flattened raster output renders them. Unsupported actions, ambiguous layer names and unmapped PSD filter options fail explicitly. This remains a partial Adobe implementation; neither all Adobe filters nor exact Photoshop output is claimed. [Provenance, tests and open scope](SMART_FILTER_REFERENCES.json).

## Embedded Smart Objects — step160

The API now has32 typed commands. New commands use the same native source/cache and prepared history transactions as the desktop. `GET /v1/capabilities` publishes their parameter and result-state schemas under `commands` and `smartObjects`.

| Command | Parameters |
|---|---|
| `smartObject.convert` | `layerIDs`: one to64 distinct selected layer UUIDs in the same group |
| `smartObject.place` | `sourceDocumentID`, `sourceRevision`; optional `fit` (defaulttrue) |
| `smartObject.replace` | `layerID`, `sourceDocumentID`, `sourceRevision`; optional `preserveSize` and `allInstances` (both defaulttrue) |
| `smartObject.copy` | `layerID`; equivalent to New Smart Object via Copy |
| `smartObject.resetTransform` | `layerID`; source size/rotation restored at the current integer origin |
| `layer.rasterize` | `layerID`; discards editable source in the new state, recoverable with Undo |
| `layer.transform` | `layerID`, affine delta coefficients `a,b,c,d,tx,ty`; all finite within±1,000,000 with a nonsingular matrix |

Place/Replace take a snapshot of another explicitly shared document. Use existing document transfers or native Open to create that source, edit/share it, then supply its current revision. Authorization and source/target revisions are checked before publication. Ordinary duplicates share replacements; `allInstances:false` detaches the targeted instance. Source edits can use `preserveSize:false` to retain the placement transform when the source canvas changes. Smart Object transforms retain source pixels; ordinary raster transforms resample using bicubic interpolation.

```json
{"command":"smartObject.place","revision":"<target revision>","parameters":{"sourceDocumentID":"<shared source UUID>","sourceRevision":"<source revision>","fit":true}}
```

`GET /v1/documents/{documentID}/smart-objects/{layerID}/source` downloads the exact embedded bytes of an explicitly shared document. Layer state includes `kind`, full document-space `transform` and nullable `smartObject` metadata (`sourceID`, SHA256 `revision`, `fileName`, `mediaType`, `byteLength`, `width`, `height`, `resolution`, `embedded`). The download's media type identifies the original file. To edit contents through the API, download/upload the source as a new document, edit it, and replace the parent from its shared snapshot. Source-bearing native downloads require `X-Photato-Archive-Version: 14`.

Requests share desktop Undo/Redo and cancellation guards. Invalid parameters return400; missing/unshared layer or source404; busy/stale/cancelled/revoked409; unsupported/protected content422; overall API document-size violations413. Existing64-layer/128MiB API document bounds still apply. Embedded sources are limited to64MiB,8,388,608 canvas pixels,256MiB decoded content and eight nesting levels. These are bounded local capabilities, not full Photoshop limits.

The published `POST /v2/create-composite` route now accepts the following embedded Smart Object subset. Enable native resource jobs, use the local bearer token, poll the returned `statusUrl`, and fetch its authenticated output as for other Adobe-compatible jobs.

```json
{"image":{"source":{"url":"https://example.com/input.psd"}},"edits":{"layers":[{"name":"Product","type":"smart_object_layer","operation":{"type":"add","placement":{"type":"top"}},"smartObject":{"isLinked":false,"smartObjectFile":{"source":{"url":"https://example.com/product.png"}}},"transformMode":"fit"}]},"outputs":[{"mediaType":"image/vnd.adobe.photoshop","destination":{"validityPeriod":3600}}]}
```

For replacement use `operation:{"type":"edit"}`, identify one layer by name or signed32-bit PSD id, and supply `smartObject.smartObjectFile.source.url`. `smartObject.autoResize` defaults totrue, matching the old source canvas/dpi; false retains the new dimensions/dpi. Only the addressed Adobe instance changes. `transformMode` supports `none`, `fit`, `fill`; visibility/clipping and existing protection/dropShadow fields also work. Other placement types, custom `transform`, linked objects, SVG/PDF/AI sources, Smart Filters and warp reject explicitly. Native sources export to embedded PSB when their contents can be represented; unsupported rich content rejects rather than flattening. Exact Adobe hosted behavior and independent Photoshop interoperability remain unqualified. See [scope, provenance and evidence](SMART_OBJECT_REFERENCES.json).

## Subject selection and background removal — step159

At step159 there were25 typed Photato commands. `selection.subject` accepts required `layerID` (pixel layer UUID), optional `sampleAllLayers` (boolean, defaultfalse) and `mode` (`replace`, `add`, `subtract`, `intersect`; defaultreplace). `layer.removeBackground` accepts `layerID` and optional `sampleAllLayers`; it requires an unlocked pixel layer without an existing mask. Both run Apple Vision locally, preserve original pixels and commit one native Undo entry. Removal preserves the current selection. An existing mask must be applied or deleted explicitly first. Stale/busy/cancelled/revoked requests return 409 without committing; invalid parameters400, missing layer404, unsupported target/size/model/no subject422. Document state now reports selection bounds/coverage and subject availability; layers report mask presence, enablement, density and feather. Schemas and runtime limits are recorded in [subject references](SUBJECT_SELECTION_REFERENCES.json). An available command means a request may be attempted; it does not guarantee the system model can run on every Mac.

```json
{"command":"selection.subject","revision":"<current revision>","parameters":{"layerID":"<UUID>","sampleAllLayers":false,"mode":"replace"}}
```

`POST /v2/remove-background` implements a partial published Adobe contract using the same local detector. Enable resource jobs in the native API window and authenticate against the configured local base URL as for other jobs. The request uses singular `output`; it does not accept execute-actions `outputs`/`options` fields. Submit returns202 `jobId`/`statusUrl`; poll `/v2/status/{jobId}`, then fetch the authenticated hosted `result.outputs[].destination.url`.

```json
{"image":{"source":{"url":"https://example.org/photo.jpg"}},"mode":"cutout","output":{"mediaType":"image/png"},"trim":false,"colorDecontamination":1}
```

Modes: `cutout` (default), opaque grayscale `mask`, or editable foreground-mask `psd`. Optional `backgroundColor` requires numeric `red`/`green`/`blue` in0–255 and `alpha` in0–1. Optional `trim` defaultsfalse and crops to detected subject bounds. `colorDecontamination` ranges0–1/default1; this native local edge-unmix approximation is not Adobe's proprietary algorithm. Input is JPEG/PNG/TIFF/WebP within64MiB and6000pixels per side/8,388,608pixels total; decoded documents are limited to64layers/128MiB. Output is PNG/JPEG/PSD. WebP encoding explicitly rejects; TIFF/WebP input needs an explicit supported output. Omitted output retains PNG/JPEG input format; PSD mode infers PSD output. JPEG flattens transparency against the encoder's white matte. Hosted results expire after one hour. RGB8/16/32 editing pixels remain unchanged in desktop/Photato mask operations; detection uses an SDR ColorSync proxy and8-bit mask coverage.

Adobe coverage is four partial routes and four unimplemented routes. No Adobe service credentials, hosted model or byte-equivalence claim is implied. Older dated sections below describe their own checkpoint.

## Layer protection integration — step152 (qualified subset)

There are21 typed Photato commands. `layer.protection` replaces protection on1–64 unique layer UUIDs in one desktop/API history transaction. Required `protection` is `none` or `all` alone, or a nonempty unique combination of `transparency`, `composite` (image pixels), `position`, and `artboard_autonest`. Optional `includeDescendants` defaults false; when true it also replaces each descendant’s stored flags. Group flags otherwise apply through inheritance. Layer state exposes `protection`, `effectiveProtection`, `imageLocked`, `positionLocked`, and `transparencyLocked`; capability discovery includes the state schema. Busy/native sheets and stale revisions reject409; malformed input400, absent layer404, disallowed edit422. Changing protection is undoable and leaves pixels unchanged.

Partial protection requires native archive version12. Desktop Save/Copy/recovery chooses12 only when necessary; ordinary documents retain11. The legacy Core plist encoder uses12 only when necessary, otherwise10. Current readers accept older formats. Old readers reject12 rather than silently lose flags. Existing Photato downloads default to10 and accept explicit10/11 for compatible documents. A document requiring12 returns422 until the client supplies `X-Photato-Archive-Version: 12`; that option always returns chunked12. Both native filename aliases behave identically. No opt-in is needed to upload/open12.

`POST /v2/create-composite` now supports an explicitly limited published protection-edit subset: an existing `image.source.url`, optional `edits.layers` containing `operation: {"type":"edit"}`, one exact unique layer `name` or PSD numeric `id`, optional matching `type`, and `protection`. Adobe missing/null/empty protection leaves existing flags unchanged; `none` removes all. Group protection replaces descendant flags, as specified by Adobe. The pinned schema describes null semantics but lacks an explicit nullable type; the adapter follows the description and records the discrepancy. Output storage, authorization,202 job/status/download lifecycle and supported output formats share execute-actions. The native resource-job permission remains required. Blank canvases use the ImageParameters subset below. Other unimplemented layer properties, add/delete/move variants, scan and unsupported types/resources reject explicitly; this is not a complete create-composite implementation.

Adobe coverage is now three partial routes (create-composite, execute-actions, status) and five unimplemented routes. Photato and Adobe jobs use the same native protection transaction, with their separate shared-document/isolated-job lifecycles. Auto-nest flags survive files/APIs; artboard auto-nesting itself is still unavailable. Independent group/mask/type/shape, brush/eraser/high-depth Photoshop references, full menu contexts and platform qualification remain open. Earlier dated sections below describe their historical increments.


## Protection integration prerequisite (step151)

The isolated Adobe protection-field parser now follows the current pinned GA schema, including omitted/null/empty edits and exclusive none/all. It does not activate create-composite. Photato still exposes20 typed commands, with no protection mutation/state field yet. The next runtime increment must connect desktop, Photato schemas/state/commands and Adobe create-composite jobs through the same engine. No API coverage is claimed from an internal parser alone. See [protection evidence](LAYER_PROTECTION_REFERENCES.json).

## Source project reader prerequisite (step150)

The internal source graph and payload reader now preserves version1 `.pcraft` metadata and editing payloads from ZIP and directory bundles. Native Open and API import still reject `.pcraft`; no route, schema or capability is added until the native adapter can preserve supported editing semantics. Partial locks and sparse/default/profile behavior are next, with desktop and Photato API integration required together. Adobe compatibility remains separately tracked; no `.pcraft` route is invented. See [project evidence](PCRAFT_PROJECT_REFERENCES.json).

## Original PhotoCraft migration prerequisite (step149)

Internal bounded ZIP/Zstandard/BLAKE3 decoding is qualified. No new API route,parameter or executable import capability is exposed yet; `.pcraft` upload/open remains unsupported. The editable import increment must connect the same native decoder/model/history/persistence path to desktop and Photato API workflows,including schemas,state,errors,cancellation,busy/stale behavior and tests. No Adobe-specific `.pcraft` route is invented. See [container evidence](PCRAFT_CONTAINER_REFERENCES.json).

## JPEG Save/Copy and action output (step148)

Native Save/Save As/Save a Copy and Photato `document.save`/`document.saveAs`, `GET /v1/documents/{id}/file.jpeg` and action jobs share these strict encoding options:

| Field | Values | Behavior |
|---|---|---|
| `jpegQuality` | Integer0…12 | Maps locally to ImageIO quality/12; omitted retains0.95 |
| `jpegFormat` | `baseline`, `optimized`, `progressive` | Standard baseline, native Swift Huffman optimization, or ImageIO progressive schedule |
| `jpegMatte` | Three numbers0…1 | Opaque sRGB color behind transparency; omitted is white |
| `jpegEmbedProfile` | Boolean | True embeds the working ICC, false removes ICC APP2; omitted keeps platform profile signaling |

Use `options` for typed saves, `X-Photato-Export-Options` JSON for downloads, and `encodingOptions` on Photato action outputs. Example: `{"jpegQuality":8,"jpegFormat":"optimized","jpegMatte":[1,1,1],"jpegEmbedProfile":true}`. Wrong types/ranges/format return400; existing permission, busy and stale-state guards apply. Successful ordinary saves remember the selected options. Copy/download/job output leaves the shared document and remembered settings unchanged. Ordinary JPEG Save still requires one representable opaque8-bit raster; Copy/download/jobs flatten and convert to opaque8-bit, with SDR sRGB for32-bit input.

Both `/v1/action-jobs` and `/v2/execute-actions` accept `mediaType:"image/jpeg"` and the published `quality` enum: `very_poor`, `poor`, `low`, `medium`, `high`, `maximum`, `photoshop_max`. These map locally to0/2/4/6/8/10/12. Omitted action quality keeps the local0.95 behavior; Adobe does not guarantee an execute-actions default. Duplicate native/published quality choices reject. The Adobe route rejects Photato `encodingOptions` with422. Both execute-action adapters reject `scan` with400 because Adobe's operation-specific output contract excludes it. JPEG input to action jobs remains unsupported; existing PSD/PSB/TIFF/PNG input policy is unchanged.

Optimization changes only Huffman coding, including restart handling; quantized coefficients, sampling, quantization and other markers are retained. Explicit ICC removal leaves other metadata and entropy unchanged. The platform may describe sRGB through EXIF without embedding ICC when the option is omitted. Progressive output uses the platform scan schedule; Photoshop's3–5 scan choice is not exposed or claimed. Five live Photoshop quality8 references confirm different quantization/chroma sampling from the current ImageIO mapping. Its3/4/5 progressive choices produce7/10/14 SOS segments, with scan headers different from the platform schedule even when both have10 segments. Photoshop quantization, exact native dialogs/defaults and whole-file parity remain open. [JPEG evidence](JPEG_ENCODING_REFERENCES.json) records the qualification status.


## Rich TIFF records (step147)

Both byte orders now transport the represented Levels, point Curves, Hue/Saturation, Color Balance, Threshold, Posterize, Gradient Map and vector-mask records through the shared PSD implementation. The existing export restriction on editable Gradient Map layers at32-bit remains; their export coverage is8/16-bit. Retained global mask-display metadata (`LMsk`) survives native archives and TIFF/PSD/PSB output. Existing native Save/Copy and Photato upload/download/save/job interfaces expose the same behavior; both job interfaces retain rich TIFF input in supported PSD output. No routes, command names, permissions or Adobe output fields are added.

Little-endian fill descriptors (`SoCo`, `GdFl`, `PtFl`), saved-path descriptors (`pths`), embedded patterns and opaque metadata remain guarded. Independent synthetic payload/container tests establish the documented transport behavior, not Photoshop2026 rendering or whole-file parity. The live Adobe-produced rich TIFF comparison remains open.


## Editable layered TIFF (steps145–146)

Native Open, `POST /v1/documents/import`, `/v1/action-jobs` and `/v2/execute-actions` share Photoshop-style TIFF import. Uploads use `image/tiff` or `X-Photato-Open-Format: tiff`; job inputs retain the published image/source URL shape. Supported RGB8/16/32 layers, groups, masks, names and common attributes remain editable. Both endian orders and raw/RLE/ZIP/ZIP-predicted input streams are supported. Big-endian rich records share the PSD decoder. The distinct TIFF `MTrn` marker remains separate from PSD `Mtrn`. Saved alpha/spot channels, conflicting profiles/depths, malformed framing and unported records reject atomically instead of returning the preview.

Native Save/Save As and Photato `document.save`/`document.saveAs` now default to preserving supported TIFF layers. `effectiveSaveEncodingOptions.tiff.tiffLayers` reports this default; `saveEncodingOptions` retains requested choices. Explicit `tiffLayers:false` cannot flatten a layered document during ordinary Save. Save a Copy, downloads and resource-job TIFF outputs remain flattened by default; select Layers or provide `tiffLayers:true` to retain supported editable content. Successful saves remember their choices; Copy/download/failure/cancellation preserve document ownership and remembered settings.

| Photato option | Values | Behavior |
|---|---|---|
| `tiffLayers` | Boolean | Preserve supported editable TIFF content; ordinary Save defaults true, other output defaults false |
| `tiffLayerCompression` | `rle`, `zip` | Independent layer/mask compression, default ZIP; requires explicit `tiffLayers:true` |

These fields use the existing strict `options` schema for save commands (native Copy behavior is available through API downloads), `X-Photato-Export-Options` JSON for downloads, and `encodingOptions` for Photato jobs. For example, `{"tiffLayers":true,"tiffLayerCompression":"rle","tiffByteOrder":"littleEndian","tiffCompression":"zip"}` selects RLE layers with a ZIP TIFF composite. Omitted layered byte order is big endian, which supports the shared PSD rich records. Explicit little-endian output converts supported structures and preserves channel sample order; unqualified rich payloads fail before replacing files. Wrong types/enums/format or layer compression without explicit preservation returns400; unsupported representation returns422.

`documentTransfers.layeredTIFF` reports input/output support, separate input/output compression lists and bounds. No new route, permission or typed command is introduced. Both job interfaces can preserve TIFF input layers in PSD output. The pinned Adobe `TiffOutput` has no preservation or layer-compression field: its default TIFF output remains flattened, and Photato `encodingOptions` stays rejected422. Its inherited `layers` array selects export references; it is not a preservation boolean.

Classic TIFF output remains bounded to512MiB and1024 records including group markers. Existing upload/download/job budgets still apply. Little-endian rich adjustment/fill/vector/pattern/opaque blocks, PSB-style ImageSourceData, broader color modes/orientations, saved alpha/spot channels, re-emission of global user-mask display metadata (`LMsk`), Save Transparency/pyramids, Ask Before Saving Layered TIFF Files, exact Photoshop dialogs/defaults, full size/platform and Photoshop byte parity remain open. Synthetic independent fixtures and native round trips do not establish Photoshop2026 parity. See [layer evidence](TIFF_LAYER_REFERENCES.json).

## TIFF storage options (step144)

Native Save/Save As/Save a Copy and Photato save/download/action output share three additional TIFF fields. They are included in the same strict encoding schema, remembered per-document settings and capability/state descriptions as compression:

| Field | Values | Behavior |
|---|---|---|
| `tiffByteOrder` | `bigEndian`, `littleEndian` | Macintosh/IBM PC byte order for pixels and typed TIFF metadata |
| `tiffPixelOrder` | `interleaved`, `perChannel` | RGB(A) samples together or in separate channel strips |
| `tiffPredictor` | Boolean | `true` applies floating-point prediction to32-bit output with explicit `lzw` or `zip`; `false` disables it |

For example, `{"tiffCompression":"zip","tiffByteOrder":"littleEndian","tiffPixelOrder":"perChannel","tiffPredictor":true}` selects planar predicted Float32 TIFF. Wrong enum/type/format or prediction without LZW/ZIP returns400; a floating predictor on an integer document fails representation validation with422 without replacing a destination or adopting settings. TIFF fields cannot be applied to PNG/PSD/PSB/JPEG/native output. Omitted storage fields retain the established ImageIO encoder; requesting any storage field selects the shared native Swift strip writer, using None if compression is omitted. Options remain a complete set, not a patch. Successful ordinary saves remember them; Copy/download and failed/cancelled saves do not.

The strip writer preserves the existing integer associated-alpha and Float32 unassociated-alpha samples, ICC/XMP and supported typed metadata. Swift handles TIFF6 LZW, file/channel order and floating prediction; ZIP uses the macOS zlib library. Supported unassociated RGB/RGBA8/16/Float32 strips import directly when embedded and working RGB profiles match. Planar associated-alpha samples are assembled natively before the established CoreGraphics conversion; interleaved associated-alpha, tiled layouts and required profile conversion retain ImageIO/ColorSync handling. This repairs ImageIO’s observed NaN-alpha Float32 and fully opaque integer planar TIFF decoding for the supported same-profile paths.

`/v1/action-jobs` accepts these fields inside output `encodingOptions`. Adobe’s pinned `TiffOutput` has no equivalent storage fields: `/v2/execute-actions` rejects that Photato extension with422 and keeps its existing TIFF output behavior. Both interfaces still share the native editing/encoding engine, with two partial Adobe endpoints and six unimplemented endpoints. No new typed command or factory menu binding is claimed.

Historical step144 limits: RGB-only bounded flat TIFF,512MiB encoded input/output and existing document/API budgets. Layered TIFF, pyramids, JPEG-TIFF,16/24-bit floating point, broader alpha/color/profile coverage, full4GB and physical Intel/macOS14 qualification, Photoshop2026 dialogs/defaults and byte-identical Photoshop output remain open major requirements. Automated native controls and public Release callbacks do not establish live UI equivalence.

## Float32 TIFF preservation (step143)

TIFF saves, copies and document downloads now retain RGB32 linear floating-point pixels, transparency and the working RGB profile. The shared encoder supports None/LZW/ZIP without an SDR conversion. Native ordinary Save accepts a single representable full-canvas raster layer at RGB32; layered content still requires Save a Copy to flatten. Native controls show the supported depth and use the existing TIFF compression selector.

The existing `document.save`, `document.saveAs` and `GET /v1/documents/{id}/file.tiff` routes share that behavior and retain their permission/revision/busy/error contracts. Document uploads and native Open retain straight Float32 samples directly when the decoded colour space already matches the working space. Other source layouts and profile conversions use ColorSync. No new command, permission or request field is added; capabilities describe the expanded TIFF depth support.

Both `/v1/action-jobs` and `/v2/execute-actions` now accept `image/tiff` output from supported RGB32 PSD/PSB inputs. Adobe retains its pinned `TiffOutput` schema. Only Photato jobs accept `encodingOptions.tiffCompression`; desktop/shared-document output uses the same encoding options. Outputs remain isolated from open documents. PNG32 job output still rejects with an explicit PSD/TIFF alternative. Resource-job TIFF input remains unsupported; ordinary document uploads accept it.

Qualification covers finite HDR/negative/transparent samples, original Adobe linear and Apple linear RGB profiles, compression variants, independently constructed endian/orientation fixtures and real loopback API jobs. This is bounded sample/profile preservation, not complete Photoshop file-byte parity. At step143, layered TIFF and storage controls were still open; steps144–146 add the bounded support above. Broader alpha/layout/profile variants and full size/platform/live-UI qualification remain open. See [TIFF evidence](TIFF_FLOAT_REFERENCES.json).


## Recovery memory admission (step139)

Indexed recovery now checks estimated aggregate capacity before manifest reads, raster expansion and publication. This is an original Photato automatic-recovery policy: one quarter of physical RAM, clamped to256MiB–4GiB. It is not a Photoshop preference or a whole-process RSS limit. Existing open-document payload, resident history and conservative metadata/render allowances count toward the estimate; temporary workers, GPU allocations, drafts and general allocator overhead are not fully accounted. AppKit’s independent restoration and explicit Open/Open Copy retain their existing limits and are outside this admission policy.

`GET /v1/recovery` adds `lastDeferred`. Its nullable `operation` adds phase `accounting`, `memory` and `deferredByReason`. `memory` contains exactly `limitBytes`, `estimatedUsedBytes`, `availableBytes` and `metadataReadLimitBytes`. Reason counts contain exactly `aggregate`, `metadata`, `raster` and `workspaceGrowth`. These are the latest stable accounting snapshot and completed decisions, not a live process-memory monitor. Used capacity may exceed the automatic-recovery budget because already-open documents are retained. Responses expose counts and estimates without private names, file paths or contents.

Metadata reads are capped before allocation to the smaller of64MiB and one quarter of remaining capacity. Pre-decode allowance reserves four times the checked manifest size,64KiB of metadata overhead and a conservative canvas-render allowance; the remaining raster budget is capped at1GiB. Workspace/session signatures are checked after background accounting. Up to eight attempts, with cancellable20ms yields after changes, allow finite AppKit startup restoration to settle. Continued mutation returns409 without publishing stale accounting. A fresh post-decode estimate can defer an otherwise valid prepared document if capacity has changed.

Deferral preserves the complete recovery group, its registrations and backup bytes. It does not label a valid backup damaged or fall back to an older snapshot in that group. Smaller groups may still recover. Already-open groups are reported separately. The native results window and File Handling explain deferrals; close unneeded documents and retry, or use Review Backups for an individual independent copy.

`POST /v1/recovery/retry` still returns200 for a completed partial run: inspect `lastDeferred` and reason counts. Cancelled or unstable-workspace runs return409; revoked permission403. Existing operation cancellation, revision checks and separate recovery-management permission apply. No restored document is automatically shared. The existing routes and typed-command count are unchanged; Adobe v2 has no corresponding desktop recovery-admission endpoint. See [admission evidence](RECOVERY_MEMORY_ADMISSION_REFERENCES.json).


## Background indexed recovery (step138)

Indexed startup recovery and File Handling’s Retry Recovery now prepare complete snapshots off MainActor. Native progress shows records checked and offers Cancel. Documents already recovered remain open; cancellation leaves remaining backups registered for retry and resumes queued file-opening requests when recovery is idle, including immediately chained retries. Cancellation is cooperative and may wait for a decoder stage to finish. AppKit’s recovery factory still establishes document dirty/autosave state through a scoped prepared-read handoff.

Authenticated `GET /v1/recovery` adds nullable `operation`: `id`, `active`, `phase`, `totalEntries`, `completedEntries`, `cancellationRequested`, `canCancel`. Phases are `inspecting`, `decoding`, `publishing`, `completed`, `cancelled`, `failed`. Counters describe records checked, including failed/skipped entries; they are not a percentage of bytes decoded. No private document names, paths or contents are exposed.

`POST /v1/recovery/cancel` takes exactly `{"operationID":"<UUID>"}` with JSON Content-Type and **Allow recovery management**. It can cancel the active indexed recovery, including native startup. It returns200 with current state; `active` may remain true until the worker acknowledges. Unknown/inactive operation IDs return409; malformed bodies400, disabled permission403 and incorrect media type415. Authentication remains required.

`POST /v1/recovery/retry` retains its existing revision argument and waits for completion before returning200. Cancellation returns409; revocation returns403. Disabling recovery management cancels the retry owned by that API session; an unrelated native startup/manual recovery continues. Recovered documents are never automatically shared. State/capabilities expose the complete operation schema and limits.

Before publication, the coordinator rechecks snapshot context, archive identity, index bytes/revision, operation generation and permission. Source collisions and recovery groups are checked again after background work. Already-open groups are skipped; source collisions produce independent unsaved recovery copies. Missing files are rechecked before their records are pruned. Native saves/autosave/close and competing opening/maintenance are excluded while discovery runs. A document upload that spans a recovery generation cannot publish afterwards.

Full archive decoding, color validation, fingerprinting and source-format preparation are off MainActor. Bounded index metadata reads/writes, AppKit factory bookkeeping, document construction and window presentation still run on MainActor. Aggregate recovered-document memory and external AppKit restoration routes are not qualified by this increment. There is no corresponding Adobe v2 desktop recovery endpoint; no Adobe route is invented. See [background recovery evidence](BACKGROUND_RECOVERY_DISCOVERY_REFERENCES.json).


## Explicit recovery salvage (step137)

File Handling adds **Find Recovery Copies…**. This native Photato window scans the app’s private `Recovery/Archives` directory on demand, even if `Index.json` is unreadable. It never automatically adopts an unregistered or retired archive. A missing registration may represent deliberate cleanup. Scanning does not open documents, modify an archive or repair the index.

These routes use the existing separate, session-off **Allow recovery-backup access** permission, including GET. Every request also requires session authentication. They accept no arbitrary local paths and do not automatically share opened copies.

| Method and route | Exact JSON fields | Result |
| --- | --- | --- |
| `GET /v1/recovery/salvage` | None | Cached scan state |
| `POST /v1/recovery/salvage/scan` | `revision` |200, fresh scan state and new revision |
| `POST /v1/recovery/salvage/open-copy` | `revision`, `id` |201, fresh `documentID`, `shared:false` |
| `POST /v1/recovery/salvage/download` | `revision`, `id` |200, ordinary native11 file, at most128MiB |
| `POST /v1/recovery/salvage/reset-index` | `revision`, `confirmed:true` |200, state after preserving and resetting a damaged index |

POST requires `Content-Type: application/json` and exactly the listed fields. `revision` is this scan’s UUID, separate from the recovery index revision. `id` is an opaque scan-local item UUID; rescan before reusing an old item. Requests await completion. The capability object `recoverySalvage` includes complete request, result and state schemas, limits and error behavior.

State has exactly `revision`, `isBusy`, `isStale`, `canScan`, `canResetIndex`, `examinedEntries`, `maximumEntries`, nullable `lastError`, nullable `indexError`, and `items`. Item fields are `id`, `name`, `metadata`, `registration`, `bytes`, `canOpenCopy`, and `canDownload`. `metadata` is `current`, `legacy`, `none`, or `unverified`; it describes recovery metadata, not full image-data integrity. `registration` is `registered`, `retired`, `unregistered`, or `unknown` when the index is unreadable. Names are disclosed only with backup permission. Paths and bookmarks are not returned.

The worker enumerates immediate children only, with a limit of1024 total directory entries, including skipped files. Only regular `.photato` files within the native file-size limit are listed. Symlinks and subdirectories are not followed. Excess entries fail without publishing a partial scan. Root, archive-directory and index metadata must remain unchanged; file identity, size, mtime and ctime are checked around inspection/copy reads. External filesystem changes may only become visible in cached state when the next operation checks them. These checks do not provide filesystem compare-and-swap against non-cooperating writers.

Open Copy, native Save Copy and download fully decode the document in a background task. Current or legacy provenance is discarded; damaged recovery metadata can still yield a copy if the document data decodes correctly. Corrupt document data rejects. Open Copy assigns a fresh document ID while preserving layer/content values, marks it unsaved and adopts no source or recovery association. Save Copy and download use the same ordinary native11 serialization. The native save chooser refuses the private recovery folder, known original sources and open-document destinations.

**Reset Damaged Index** requires a fresh scan, all documents closed, and an unreadable regular index of at most2MiB. Its native confirmation or API `confirmed:true` authorizes preserving the exact old index under a unique name in the private recovery directory, then atomically writing an empty valid index. Backup archives and original files stay unchanged. Existing archives remain available as manual copies and are not re-registered. New automatic-recovery registrations can then proceed normally. An interruption before the new index commits leaves the old damaged index; after commit it leaves an empty index. A failed attempt may leave an additional preserved index copy. There is no registration Undo action. A valid, symlinked, missing or oversized index cannot be reset through this operation; oversized and symlinked indexes can still allow archive scanning.

The shared maintenance coordinator excludes competing native opening/closing, discovery, autosave and import publication. Scan revision, filesystem state, cancellation and API permission are rechecked before returning contents or creating documents. Disabling backup access while a read runs prevents publication. Reset has no suspension between its final validation and commit; once committed, the filesystem change is not rolled back by later permission changes.

Errors:400 malformed fields/UUID/confirmation;401 authentication;403 backup permission disabled/revoked;404 unknown item or route;409 busy/stale/cancelled, including open documents preventing reset;415 media type;422 scan/index/output limits, read/decode or reset failure. The twenty typed document commands remain unchanged. Adobe v2 has no corresponding desktop salvage route; its two partial and six unimplemented endpoints remain separately tracked.

This scan covers Photato’s current private Archives folder. Discovery in other legacy locations, fully responsive startup restoration, supported-platform/sandbox/power-loss qualification and live Photoshop/UI parity remain open. See [salvage evidence](RECOVERY_SALVAGE_REFERENCES.json).

## Recovery backup maintenance (step136)

File Handling now offers **Review Backups…**, opening a Photato-specific recovery window. It groups index entries by recovery document, shows availability and record capacity, and provides Open Copy, Save Copy, Move to Trash, Forget Record, and Remove Missing Records. This is a native recovery-management affordance; it is not a newly observed Photoshop factory menu command.

The existing recovery counts/retry permission remains unchanged. A separate **Allow recovery-backup access** toggle, off each API session, authorizes backup filenames/content, independent recovered copies and explicit cleanup. No route accepts arbitrary local paths. All routes require session authentication; GET also requires this new permission.

| Method and route | Exact JSON fields | Result |
| --- | --- | --- |
| `GET /v1/recovery/backups` | None | Cached inspection and current index capacity/state |
| `POST /v1/recovery/backups/inspect` | `revision` | Refresh metadata inspection; return state |
| `POST /v1/recovery/backups/open-copy` | `revision`, `id` |201 with a fresh `documentID` and `shared:false` |
| `POST /v1/recovery/backups/download` | `revision`, `id` |200 with an ordinary native11 document |
| `POST /v1/recovery/backups/trash` | `revision`, `id`, `confirmed:true` | State after retirement, native Trash and index cleanup |
| `POST /v1/recovery/backups/forget` | `revision`, `id`, `confirmed:true` | State after removing this group's registrations |
| `POST /v1/recovery/backups/remove-missing` | `revision` | State after reclaiming missing inactive registrations |

POST bodies use `Content-Type: application/json`; unknown fields reject. `revision` is the current recovery-index UUID; `id` is a known recovery-group UUID. These operations await their work before replying. Clients may read state concurrently, but another maintenance operation rejects while one is active.

State contains exactly `revision`, nullable `inspectedRevision`, `isPersistent`, `isBusy`, `isStale`, `canInspect`, `entryCount`, `maximumEntries`, `availableEntries`, nullable `lastError`, nullable `loadError`, and `items`. The index limit is512 entries; interrupted intents can temporarily occupy more than one entry for a group. Each item contains `id`, `snapshotID`, `name`, `registration` (`intent`, `ready`, `retired`), `status` (`available`, `missing`, `invalid`, `unavailable`), nullable `bytes`, nullable ISO8601 `modifiedAt`, `isOpen`, `canOpenCopy`, `canDownload`, `canTrash`, and `canForget`. Inspect after mutations or external changes when `isStale` is true. The `/v1/capabilities.recoveryBackups` object publishes complete schemas, routes, behavior and limits; `recoveryBackupsEnabled` reports the permission.

Inspection chooses a matching committed snapshot over a newer interrupted intent. **Available means matching metadata**, not proof that the entire document decodes. Open Copy and download fully decode off the main actor and recheck the index/session before returning content. Open Copy retains all layer/content values but assigns a fresh document ID, marks the copy unsaved, and adopts neither the original source association nor the backup's recovery registration. It does not share the document automatically. Native Save Copy and API download produce the same ordinary native11 serialization without private recovery context; download is limited to128MiB. Native Save Copy refuses the registered original and private recovery locations as destinations.

Trash requires an inactive group with matching archive identity and metadata. The app atomically retires the matching record before a coordinated `FileManager` move to Trash, then removes the registration. If a move fails or the process stops, a retired record/remaining archive or a missing retired record may remain. Startup discovery can prune the missing record; Refresh and Remove Missing Records also support review/cleanup. Once the move begins, registration cleanup finishes even if API permission ends; a revoked request then returns403 instead of exposing state. Completed filesystem effects are not rolled back. The native dialog explains the effect before confirmation.

Forget Record removes the group's index entries, stopping automatic recovery through that index, while leaving archive bytes untouched. It is useful for unrecognized or unavailable backups but has no registration Undo operation. It requires explicit confirmation in the native window or `confirmed:true` in the API. Remove Missing Records rechecks absence and removes only inactive groups without deleting a file. All cleanup protects groups still used by open documents. Maintenance excludes competing native opening/closing, recovery discovery, file commands and autosave writes.

Errors:400 malformed fields, UUID or confirmation;401 authentication;403 disabled/revoked backup access;404 unknown group/route;409 busy, stale or cancelled operations;415 media type;422 read/decode/output-limit/index/Trash failure. Errors expose no original paths or bookmarks. External index changes reject instead of overwriting them.

These six operations add application-level API routes; the20 typed document commands remain unchanged. Adobe's pinned v2 contract has no desktop backup-maintenance equivalent, so its two partial/six unimplemented endpoints remain independent. Index reconstruction, orphan/legacy migration, full startup responsiveness, filesystem compare-and-swap guarantees, supported-platform/sandbox/power-loss qualification and live Photoshop UI parity remain open. See [recovery maintenance evidence](RECOVERY_MAINTENANCE_REFERENCES.json).

## Recent documents (step135)

Native **File > Open Recent** lists successfully opened or saved local files, newest first, with **Clear Recent File List**. File Handling adds **Recent File List Contains**, accepting integers from0 through100. The current default20 is provisional pending live Photoshop2026 verification. Decreasing the limit trims the oldest records;0 clears history and stops recording. Clear removes references only and retains the limit. Failed/cancelled opens, unsaved API uploads, recovery-only opens and Save a Copy do not add records. Reopening an already-open source preserves its document identity and unsaved edits.

The optional API has a separate **Allow recent-file access** permission, off at every session start and revoked when the server stops. Even listing requires this permission because filenames may be private. No route accepts arbitrary local paths or exposes stored bookmarks. All routes also require the existing session authentication:

| Method and route | Exact JSON request | Result |
| --- | --- | --- |
| `GET /v1/recent-documents` | None | Current recent state |
| `POST /v1/recent-documents/limit` | `{"revision":"UUID","limit":20}` | State after atomic limit/history update |
| `POST /v1/recent-documents/clear` | `{"revision":"UUID"}` | State after clearing references |
| `POST /v1/recent-documents/open` | `{"revision":"UUID","id":"RECENT_ENTRY_UUID"}` |202 with `operationID`, `statusPath` and `shared:false` |

POST requests require `Content-Type: application/json`; unknown fields reject. State contains exactly `revision`, `limit`, `isPersistent`, `entries`, `canOpen`, `canManage`, nullable `loadError` and nullable `lastWriteError`. Each entry contains only `id` and `name`. Use the recent-list revision, which is separate from the recovery-preference revision. GET capabilities publishes the complete request/result/state schemas under `recentDocuments`, plus `recentFilesEnabled`.

Open resolves a known record and uses the shared native background coordinator. Poll `/v1/document-opening` for completion; an accepted202 may subsequently fail, for example when the source is missing. List revision, session and permission are rechecked before publication. Disabling recent-file access cancels that session's pending reopen; completed documents remain open. The opening cancel route accepts the active operation owned by this enabled recent-file session even without document-transfer permission. Reopening does **not** automatically share a document: clients must separately obtain ordinary document sharing to read or edit its content.

Errors are400 for malformed fields, UUIDs or limits;401 for authentication;403 for disabled permission;404 for missing IDs/routes;409 for busy/stale requests or externally changed settings;415 for media type;422 for unreadable settings, resolution or persistence failure. Opening failures after202 appear in the sanitized opening state. Busy checks include pending native opens, closing, recovery discovery and file operations.

The bounded atomic File Handling archive now writes version2 and reads versions1–2. Legacy version1 settings retain recovery values and gain empty recent history/default20. Older readers reject version2 rather than discard its new fields. Successful image operations remain successful if updating history fails; prior settings/history survive and `lastWriteError` reports the problem. External settings changes reject further writes; restart reloads that external state. Canonical URLs deduplicate records; bookmarks support relocation where macOS can resolve them. Sandbox, disconnected-volume and authorization changes can require reopening through File > Open.

These four application-level routes leave the20 typed document commands unchanged. Adobe's pinned v2 contract has no desktop recent-file/settings equivalent, so no Adobe route is invented; its coverage remains two partial and six unimplemented endpoints. Dock/system recent lists are not integrated by this change. Live menu/default/accessibility, full Finder behavior, sandbox and physical Intel/macOS14 qualification remain open. See [recent-document evidence](RECENT_DOCUMENTS_REFERENCES.json).

## Document opening (steps134–135)

File > Open now offers **Show: All Readable Documents / All Documents** and a supported **Format** selector. On macOS Adobe places format selection in Open; the separate Open As command is Windows-specific. The native worker reads and fingerprints each local file off the main actor. Actual native10/11, PSD/PSB and supported raster containers determine decoding independently of the filename. Explicit format mismatches reject instead of falling back. Already-open documents retain their identity and unsaved edits. Batches proceed after a per-file error; cancellation prevents the current read from publishing and leaves earlier successful documents open. A decoder may finish its current non-interruptible work before cancellation completes.

API uploads use the same format detector and validation before the existing shared decoder:

- `POST /v1/documents/import` accepts optional `X-Photato-Open-Format`: `automatic`, `photato`, `psd`, `psb`, `png`, `jpeg`, `tiff`, `heic`, `bmp`, `gif`.
- `application/octet-stream` is accepted only with that header. Existing supported Content-Types still work. Without the header, legacy Content-Type routing is unchanged. `automatic` detects the actual container; explicit formats validate it. Detection is only routing: full decoding and resource limits still apply.
- Unknown format values return400; mismatches or corrupt input return422; unsupported media types return415. A successful import returns201 and creates a shared, unsaved document. Native archives retain their stored identities/name; ordinary image decoding creates new identities. Existing transfer permission, session authentication, eight-share and input/memory limits remain.
- Uploads reject409 during a native opening or closing operation. Publication also rejects if either lifecycle operation started and finished during decoding, or if sharing/transfer/session permissions changed.

Authenticated `GET /v1/document-opening` returns exactly `active`, nullable `operationID`, `cancellationRequested`, `total`, `opened`, `alreadyOpen`, `failed`, `canCancel`, `queuedFiles` and nullable `lastError`. Batch counts/error concern the current or most recent native opening operation; `queuedFiles` counts pending requests behind it. Errors are sanitized. Status exposes no file names, paths or pixels; reading it requires no shared document.

`POST /v1/document-opening/cancel` requires `Content-Type: application/json`, exactly `{"operationID":"UUID"}`, and the native **Allow document transfers, Revert and opening cancellation** permission, or ownership of the active recent-file reopen under the separate enabled recent permission described above. Both permissions start disabled each API session. Transfer permission can cancel any active native opening operation, including unshared local files, but never closes documents already opened. Missing permission returns403, malformed fields400, stale/inactive IDs409, and wrong media type415. Success returns200 with updated state; `active` may remain true until the worker finishes. Cancellation does not revoke or stop an API upload; existing upload session/permission guards govern that separate operation.

Public AppKit Open calls, including document URLs delivered by LaunchServices, now queue behind startup recovery and active reads. Up to1000 requests may wait in the queue. Each request receives exactly one main-thread callback, including unstarted files in a cancelled batch. Later arriving batches have distinct operation IDs and survive cancellation of an earlier batch. Requests waiting for startup recovery do not yet have an active operation ID. Close/Quit and API uploads reject competing queued opens. Process checks cover three LaunchServices inputs after one recovered document, without an extra blank document; full live Finder/platform behavior remains unqualified.

`GET /v1/capabilities` publishes `documentOpening` with supported formats, upload-header/status/cancellation schemas, state effects and limits. These application-level routes do not add typed document commands; that count remains20. Adobe v2 has no corresponding live file-dialog/cancellation endpoint, so its resource-job contracts remain unchanged (two partial, six unimplemented endpoints).

Camera Raw/PDF/EPS/video import options, complete color-policy dialogs, and full sandbox/platform/live UI parity remain open. Native geometry and automated process probes are recorded separately from live verification. Independently decoded raster models can contain semantically equal ImageIO property lists with different binary dictionary ordering; pixel/model comparisons do not establish universal byte-identical outputs.

## Document closing and Quit (step133)

The native single-document, window, **Close All**, **Close Others** and Quit paths share one serial coordinator. Modified documents use Save, Don’t Save or Cancel, with Apply to All for a batch. Earlier accepted closes remain closed if a later document is cancelled. Save uses the existing native persistence path and format/source checks. Failed/cancelled saves keep the document open. Exact Photoshop prompt/layout parity remains unqualified.

The optional API adds application-level routes, distinct from the20 typed document commands:

- Authenticated `GET /v1/document-closing` returns `revision`, `openDocuments`, `enabled`, `canStart` and nullable `operation`.
- `POST /v1/document-closing` requires **Allow document closing and Quit** in the native API window, `Content-Type: application/json`, and exactly `revision`, `scope`, `mode`, plus `sharedDocumentID` when scope is `document` or `others`. Scope `all` or `quit` forbids that extra field.
- Modes are `review` (native prompts), `discard` (explicit loss of unsaved changes), and `save` (automatic saving). `save` additionally requires local document-saving permission and every modified target to be shared and already associated with an eligible existing source. Use `document.saveAs` first or choose `review` for unsaved/conflicted sources.
- A successful start returns202 with the queued operation. Work begins after successful response transmission. Failed transmission or revoked permission cancels queued work. Poll GET while the app runs; a successful Quit ends the API server. Only the latest operation is retained.
- `POST /v1/document-closing/cancel` accepts exactly `{"operationID":"UUID"}`. It can cancel only the currently active operation started by this API session. It dismisses its own prompt/save panel; an in-progress coordinated save finishes. Saved files and earlier closes are not rolled back.

`operation` contains `id`, `scope`, `mode`, `phase`, `total`, `closed`, `cancellationRequested`, nullable `error`, and `canCancel`. Phases are `queued`, `reviewing`, `saving`, `closing`, `completed`, `cancelled`, `failed`. Native window-close state can report scope `window`; API clients cannot request that scope. Shared document state adds nullable `closeOperationID`. Capabilities publish request/result schemas, behavior/limits and `documentClosingEnabled`.

This separate permission is application-wide: **all/others/quit can close unshared documents**, and discard can lose their unsaved changes. It starts off and is revoked when the API stops. Public status exposes counts, opaque revision/operation IDs and sanitized errors, without unshared names, paths or pixels. A revision binds the current document set and content/association state. Target mutations, new documents, source/save failures and revoked sharing/permissions stop remaining work. Concurrent close operations, recovery discovery and target API mutations are refused.

Errors:400 malformed fields;401 authentication;403 missing closing/saving permission or required sharing;404 missing shared document/route;409 busy/stale/unavailable or Save As required;415 wrong media type. Accepted operations report subsequent failures in their state. Adobe’s pinned v2 contract has no live-desktop Close/Close Others/Quit route; no Adobe route is invented. Its coverage remains two partial and six unimplemented operations.

## Independent recovery discovery (step132)

Production recovery snapshots now use a private `Application Support/Photato/Recovery/Archives` location independent of the original folder. An atomic bounded index registers an intent before writing the archive, then marks the snapshot ready. Each archive binds the recovery group, random snapshot token, document identity and source association. Startup supplements AppKit restoration by inspecting indexed archives, fully decoding valid candidates, and avoiding already-open recovery groups. When the original is already open, recovery creates a separate unsaved copy. Invalid/unavailable backups remain untouched; missing entries can be pruned. Normal Save/close retirement prevents intentional closures from reopening through the index. Legacy archives remain readable; ordinary saves/copies/downloads omit recovery context.

File Handling adds **Retry Recovery**, counters and sanitized errors. The optional API exposes the same discovery implementation:

- Authenticated `GET /v1/recovery` returns `revision`, `isPersistent`, `registeredCount`, `isDiscovering`, `canRetry`, nullable `operation` (step138), `lastDiscovered`, `lastAlreadyOpen`, `lastMissing`, `lastInvalid`, `lastUnavailable` and nullable `loadError`, `writeError`, `discoveryError`.
- `POST /v1/recovery/retry` requires JSON with exactly `{"revision":"<current UUID>"}` and the native **Allow recovery management** permission. This separate permission starts off and is revoked on stop/restart. Recovery opens native documents but does not share them with API clients.
- Invalid JSON/fields return400; authentication401; disabled/revoked permission403; busy/stale/external-index changes409; wrong content type415; recovery failures422. Permission and index generation are rechecked after asynchronous inspection. Retry completes discovery and full image decode; original-source verification may still report `checking`.
- Shared-document state adds `recoveryRegistration`: `status` (`none`, `intent`, `ready`, `retired`, `failed`), `isPersistent` and nullable `lastError`. The six-field `recovery` and four-field `recoverySource` objects remain unchanged. Capabilities include discovery request/state schemas and `stateSchemas.recoveryRegistration`.

The API reports counts and sanitized errors, without source paths, filenames, bookmarks or contents. Index limits are512 entries and2MiB; optional archive context stays bounded at128KiB. Desktop and API use the same native decoder and source-verification policy. Adobe v2 has no corresponding desktop recovery endpoint; its two partial/six unimplemented operations and the20 typed Photato document commands remain unchanged. Full platform, large-document, power-loss and live UI qualification remain open. [Step132 evidence](RECOVERY_DISCOVERY_REFERENCES.json) distinguishes automated tests and process interruption from live interaction.


## Recovery source identity (step131)

Native recovery archives now retain bounded local source information: original format, format-specific Save As review, volume/file identity, a SHA-256 content fingerprint and a bookmark when available. This optional field shares the native archive's manifest integrity check and atomic publication. It is absent from ordinary saves/copies and API downloads. Ordinary Open/uploads read the image but never adopt embedded source information as a file association.

Document state adds `recoverySource`: `status` (`none`, `checking`, `unchanged`, `moved`, `changed`, `replaced`, `missing`, `unavailable`, `unverified`), `isRecovered`, `hasRecord` and nullable `originalFormat`. No paths, bookmarks or hashes are exposed. The existing six-field `recovery` object is unchanged. `/v1/capabilities` includes the corresponding `stateSchemas.recoverySource` and `recoverySource` policy/limitations. No new command, route or permission is introduced.

Background verification initially blocks competing file commands/API mutations with409. A verified unchanged or moved original resumes ordinary Save unless its format already requires review. Save rechecks the recovered original after encoding and before handing the output to AppKit. Changed/replaced/missing/unavailable or unverifiable originals require explicit Save As; recovered source conflicts return409. Save/Save As and Revert refresh the local source record without adding an extra history edit. Existing sharing, revision, busy and permission guards remain in force.

Two limits are explicit: Foundation can resolve an occupied old path to its replacement, which the independent fingerprint refuses; automatic rediscovery of the moved original in that situation needs further work. In the owned crash probe, AppKit did not automatically enumerate the backup of a deleted original. Its archive remained recoverable through the explicit recovery factory, but automatic discovery/registration remains an open D02 requirement. These checks also do not provide a filesystem compare-and-swap guarantee. Large-document capture cost, sandbox entitlements, network/removable filesystems, physical Intel/macOS14 and live UI still need qualification.

Adobe v2 defines no corresponding live desktop recovery-source operation; its wire contracts and two-partial/six-unimplemented coverage remain unchanged. See [source recovery evidence](RECOVERY_SOURCE_REFERENCES.json).

## Atomic persistence (step130)

Native recovery, recovery-settings writes and local Save/Save As/Save a Copy now share the checked file writer. Raster output joins native/PSD/PSB output on this path. It retains the parent directory for relative staging, rename and cleanup, supports folders that grant traversal/write without listing, and checks destination/parent/staging identity before publication. Cancellation, short writes, interrupted system calls and storage failures use the existing error paths. Cleanup checks the private file’s inode and preserves an observed replacement at that name.

Before publication, the writer completes `fsync` and requests `F_FULLFSYNC`. If the latter is unsupported (`EINVAL`, `ENOTSUP` or `ENOSYS`), it retains the successful `fsync` result; actual I/O and space errors reject publication. This is a pre-publication file-flush policy, **not a guarantee that a directory entry or device survives power loss**. Filesystem identity checks are not compare-and-swap operations; full external coordination, network filesystems and supported-platform durability remain under qualification.

`GET /v1/capabilities` adds `atomicPersistence` with scope, publication/synchronization/cleanup/error policy, unsupported full-sync codes, the64KiB maximum write size and limits. Recovery and recovery-preference capabilities point to this shared policy. Existing routes, request/result schemas, document state,20 typed commands and permissions remain unchanged. Recovery errors still return422 and expose `lastWriteFailed`; prior backup/content/history survive pre-publication failures and a later retry can succeed. Settings-write failures preserve disk/model/revision/timer before publication. Neither API download bytes nor Adobe v2 wire contracts change; Adobe coverage remains two partial and six unimplemented endpoints.

Step155 adds `atomicPersistence.visibility`: `newFileHiddenFlag: false`, `preservesExistingHiddenFlag: true`, `preservesOtherStagingFlags: true`, and a textual `policy`. The writer normalizes macOS `UF_HIDDEN` through the retained staging descriptor before synchronization, preserving intentional destination visibility and unrelated staging flags. A dot-prefixed destination remains hidden by its filename. Interrupted flag updates retry; actual flag errors or observed visibility changes before publication reject without replacing the prior destination. External metadata changes after validation remain outside the guarantee. Native Save and Photato local save commands share this behavior. Downloaded image bytes and both action-job contracts remain unchanged; Adobe v2 has no host-file visibility parameter or new endpoint for this repair. Step155 qualification passes native/HTTP persistence and both existing action-job output regressions; see [visibility evidence](FILE_VISIBILITY_REFERENCES.json).

See [atomic persistence evidence](ATOMIC_PERSISTENCE_REFERENCES.json). Full Photoshop parity and D02 remain open.


## Recovery preferences (step129)

Photato > Settings… > File Handling… opens recovery settings with OK and Cancel. Recovery starts enabled at a ten-minute interval. The selector offers5,10,15,30 and60minutes; exact Photoshop2026 dropdown/layout/transition parity still needs live qualification. Settings persist separately from images in the app’s recovery-settings file. Committing updates the timer and asks AppKit to schedule already-dirty documents, without creating an image edit or Undo entry. Disabling blocks automatic recovery-save entries but keeps prior backups and explicit `document.autosave` available. Active file operations reject preference changes; read/write errors and external settings changes preserve current values and the existing file. Cancel discards the window draft, and a concurrent API change makes an older native draft stale.

Authenticated `GET /v1/preferences/recovery` returns application-wide state without requiring a shared document: `revision` (UUID), `enabled`, `intervalMinutes`, `effectiveIntervalSeconds`, `canUpdate`, `isBusy` and nullable `loadError`. The configured interval remains available while disabled, when the effective interval is0.

`POST /v1/preferences/recovery` uses `Content-Type: application/json` and exactly this body:

```json
{"revision":"CURRENT_PREFERENCES_UUID","enabled":true,"intervalMinutes":5}
```

The native API window’s **Allow recovery preference changes** permission must be enabled. It starts off and turns off whenever the API stops. This is separate from document-sharing and local-save permission because recovery settings affect all documents. Updates require the current preference revision; document revisions are independent. The response is the current preference state after successful persistence and scheduling. A no-op keeps the preference revision. No settings file path is accepted or exposed.

Errors:401 invalid/missing session token;403 preference-write permission off;400 malformed/unknown fields, invalid UUID, non-boolean enablement or an unsupported/non-integer interval;409 stale revision, external settings change or busy file operation;415 unsupported media type;422 unreadable settings or persistence failure. Existing same-origin/host/framing/body limits remain enforced. `/v1/capabilities.recoveryPreferences` publishes routes, request/result schemas, defaults and lifecycle/error policy; `preferenceChangesEnabled` reports the current session permission.

The20 typed document commands and six-field document `recovery` state remain compatible. This adds two HTTP methods on one application preference path, with no invented Adobe route. Adobe v2 still has two partial endpoints and six unimplemented endpoints. Exact supported-platform timing, live native/Photoshop settings UX, complete File Handling and other preference categories remain open. See [recovery preferences evidence](RECOVERY_PREFERENCES_REFERENCES.json).

## Background recovery writing (step128)

Recovery now captures an immutable document value on the main actor and writes its native version11 archive on AppKit’s background writer. The writer releases AppKit’s interaction block before serialization. Native edits can continue while a scheduled backup is writing; those edits are not part of the captured snapshot. Explicit generation accounting retains `hasUnautosavedChanges` when edits or Undo happen during writing, because this platform’s legacy autosave path resets its change count without invoking the change-token callbacks. A subsequent automatic backup captures the later committed content. Undo to a clean document can instead cause AppKit to remove an obsolete backup.

The same `document.autosave` command still waits for AppKit completion and returns current state. A successful response can contain `recovery.hasUnautosavedChanges: true` if later edits exist. `isWriting` remains true through AppKit completion. State GET requests remain available while serialization runs; API mutations and competing file operations reject while recovery is busy. Direct document replacement rejects, direct close is deferred until backup completion, and automatic backups defer during other file work. Sharing revocation prevents returning document data even if the already-started backup completes. Failure preserves prior backup bytes and current edits, exposes `lastWriteFailed`, and permits retry.

Capabilities add `backgroundWriting`, `concurrentEditing` and `fileLifecycle` descriptions. The six-field recovery state schema and all20 typed commands remain compatible. There is no new route or invented Adobe operation: the published Adobe v2 coverage remains two partial endpoints and six unimplemented endpoints. Desktop and HTTP share the native recovery implementation.

Focused regressions and disposable production-delegate processes qualify concurrent edits, follow-up backups, abnormal termination/relaunch, cleanup, busy/stale/revoked requests and injected out-of-space failure. The bounded Debug timing fixture is four1024×768 RGB32 layers (48MiB raw pixels); it is not a multi-GB, Release, physical Intel or peak-memory qualification. A repeat verification exposed metadata timestamp changes after saving. Native file reads now retry the entire read once with a fresh descriptor when only that timestamp changes; each attempt retains file-identity and archive-integrity validation. Replacement, size/modification changes, corrupt archives and repeated metadata churn still fail. This shared read behavior also applies to native desktop/API file import and recovery; it changes no API schema or error envelope. Full disk-full/interrupted-write/power-loss durability, original-file identity/bookmarks, recovered Undo history, window/tab layout and live Photoshop presentation remain open. Step129 above adds interval preferences; complete preference parity remains unqualified. See [background recovery evidence](BACKGROUND_RECOVERY_REFERENCES.json).

## Recovery autosave (step127)

The configured native document controller now schedules recovery every600seconds. AppKit owns scheduling and recovery registration; this is a minimum delay, not a guaranteed write deadline. Native version11 snapshots contain committed document content. They preserve the explicit Save source, modified state and current in-process history, and do not commit unfinished text/number fields. Recovery after relaunch restores content and modified state, **not Undo history**. AppKit may store snapshots beside a saved original or in its autosave directory.

The Photato registry now contains20 typed commands. An authenticated shared document can request the same snapshot path without authorizing arbitrary local file writes:

```json
{"command":"document.autosave","revision":"CURRENT_REVISION","parameters":{}}
```

Post to `/v1/documents/{id}/commands`. It waits for AppKit completion and returns current document state. An unchanged document may be a no-op. Existing session authentication, active sharing, revision and busy guards apply; unknown parameters400, missing share404, stale/busy/revoked409, shared-document limit413 and write failure422. Automatic recovery is available with the API off. Separate explicit-local-save permission is unnecessary for an AppKit-managed backup; no path is accepted or returned. A backup already underway may finish if sharing is revoked, but the request cannot return document data afterward.

State adds `recovery` with boolean `enabled`, numeric `intervalSeconds`, and booleans `hasSnapshot`, `hasUnautosavedChanges`, `isWriting`, `lastWriteFailed`. Capabilities publish `recovery` and `stateSchemas.recovery`. `hasSnapshot` reports AppKit’s registered URL, not an ongoing integrity scan. Source-associated recovered documents retain their format and require explicit Save As review before replacing an original, because the backup does not retain its pre-crash file identity. Missing originals remain recoverable.

The bounded process test proves automatic snapshot → abnormal termination → fresh-process reopening for unsaved/native/PSB fixtures, exact content, original-format association, cleanup on close and clean startup. It does not establish full power-loss/disk-full durability, every format/OS/session scenario, preserved window/tab layout, large-document responsiveness or Photoshop recovery UX/preferences parity. Interval preferences UI remains open. The synchronous serialization limitation recorded at step127 is addressed by the bounded step128 background-writing work above. Adobe’s pinned v2 contract has no corresponding live-desktop recovery endpoint, so no Adobe route is invented. See [recovery evidence](RECOVERY_REFERENCES.json).



## Cancellable history navigation (step126)

`history.undo` and `history.redo` retain their existing request envelopes. Both native and HTTP callers prepare a value-copy session off the main actor, then publish it only after cancellation, session-mutation, document-lifecycle, render-revision and API-sharing checks pass. HTTP waits for completion and returns the existing document state. At step126, the API advertised19 typed commands, including `history.cancel` with one required UUID parameter, `operationID`.

Document state adds `historyOperation` with `active`, nullable `id`, nullable `direction` (`undo`/`redo`) and `cancellationRequested`. To cancel, submit the current document revision and the active operation ID to the existing commands route. A200 response acknowledges the request; the operation stays active until its worker finishes. A malformed ID returns400; a stale revision, ended/different operation, cancellation or rejected stale completion returns409. Other edits return409 while history is busy. Empty-stack Undo/Redo remains a successful no-op. `canUndo`/`canRedo` describe stack availability; `historyOperation.active` describes whether navigation is currently in progress.

Native Cancel/Escape and the API cancellation command target the same worker. Revoking a share or stopping the API cancels history started through that share; native history is not cancelled merely because API access ends. Closing/replacing a document invalidates pending and queued native navigation. Failed/cancelled navigation does not change content, stacks, dirty state or revision. Native History-panel jumps perform individual Undo/Redo transitions; cancellation preserves transitions already completed. A client can use the same sequence of existing Undo/Redo commands.

While preparation is active, `historyStorage` reports the last committed accounting snapshot, avoiding the scratch-write lock. `/v1/capabilities` includes the operation schema and `historyNavigation` completion/cancellation/conflict/accounting policy. Progress is indeterminate; no byte-progress or timing guarantee is claimed. Core algorithms, pixel results, disk limits, archive versions and the Adobe-compatible endpoints remain unchanged. Snapshot final-release cleanup and rendering/active-document memory still need large-document qualification. Live factory-menu, progress-overlay and cancellation checks await an unlocked Mac.

### Native archive versions and streaming (step124)

Native desktop Save/Copy and autosave leaf writes use portable version11 with indexed, SHA256-checked raster/selection blobs. Open/Revert and extensionless recovery-file reads use a retained file descriptor with physical reads capped at64KiB. The manifest, selection and active document remain resident; full paging, multi-GB files and crash/relaunch recovery are still unqualified. Existing binary-plist archives1–10 continue to open. Older Photato versions cannot open version11 files; existing files change representation only on save with the new app.

Both `file.photato` and `file.pcswift` **continue to return identical version10 bytes by default** for existing clients. Set `X-Photato-Archive-Version: 11` on either native download route for the same version11 bytes as desktop Save a Copy. Explicit `10` is also supported. Invalid values, or this header on a non-native download, return400. Upload accepts both encodings without a new header. Existing authentication, transfer limits, revision/busy/stale guards and failure envelopes are unchanged. `documentTransfers.nativeArchives` publishes read/write versions, the default download version, header schema, integrity and limits; existing `float32Storage.nativeArchiveVersion` remains10 and additive `nativeArchiveWriteVersions` lists10/11.

The Adobe-compatible API retains its existing PSD contracts and shared Swift engine; no Adobe-native archive route is invented. See the [format specification](NATIVE_ARCHIVE_FORMAT_11.json) and [verification record](NATIVE_ARCHIVE_STREAMING_REFERENCES.json).

## History storage and failures (step123)

`history.undo` and `history.redo` retain their existing empty-parameter command contract and revision/busy checks. Desktop and HTTP navigate the same native history transaction. Old snapshots can spill to private, SHA256-checked scratch files rather than being silently dropped by the RAM payload limit. A failed spill or restore returns HTTP422 without changing document content, history stacks, revision or modified state; stale/busy remains409 and a restored document exceeding API limits remains413. HTTP failures do not open desktop error alerts.

Document state adds `historyStorage`: nonnegative integer `undoStates`, `redoStates`, `spilledStates`, `residentPayloadBytes`, `reusableCurrentRasterBytes`, `sharedScratchBytes`, `residentPayloadLimitBytes`, `scratchLimitBytes` and `cleanupFailures`. `/v1/capabilities` publishes their schema and the storage/failure/lifetime policy. Resident payload counts each shared raster Array once beyond the current document and conservatively estimates other payloads; it excludes index/allocator overhead and is not an RSS limit. Shared scratch bytes account for owned blob lengths across value-copy sessions, not filesystem block allocation. The current defaults remain40 history states,256MiB resident history payload and4GiB scratch; these are development limits, not a claim of Photoshop factory preference parity.

History restoration reuses verified tile arrays from the current restored document. `reusableCurrentRasterBytes` describes buffers already shared with current pixels, not extra history memory. The reuse index retains only the current restoration and is cleared by edits; subsequent restores still verify each owned scratch blob before reusing an array. `/v1/capabilities.historyStorage` advertises this policy. Value-copy sessions remain independent through native COW storage. Shared engine transactions release temporary Foundation coding objects at each edit/Undo/Redo boundary, including calls from API/jobs without an AppKit event-loop drain. This does not impose a process-RAM cap or make navigation asynchronous.

Scratch files are ephemeral, owned by live snapshots, and removed on normal last-owner release. They are neither recovery files nor portable native archives; abnormal process termination can leave private temporary storage. Current document pixels still reside in memory. Undo/Redo and scratch I/O remain synchronous; configurable drives, active-document paging, recovery, snapshots/nonlinear history/Fade/purge and full large-file qualification remain open.

Both Photato action jobs and Adobe-compatible `/v2/execute-actions` use the same `EditorSession` engine and retain their existing request/output contract and limits. This change creates no Adobe history endpoint or new supported action descriptor. [History storage evidence](HISTORY_SCRATCH_REFERENCES.json) records exact scope and qualification.

## Working colour profiles (step116)

Document state includes `workingProfile`: `name`, `embedded`, `sampleEncoding` (`profileRGB` or `linearRGB`), and nullable `iccSHA256`. The schema is exposed in capabilities. `embedded: false` means the historical implicit sRGB working space; it does not infer an interpretation from source metadata. Native archive version10 stores the actual working profile separately from source ICC provenance. Older archives retain their existing sRGB interpretation.

Desktop editing, document uploads/downloads/saving, Photato action jobs and Adobe execute-actions share this policy. PSD raster samples remain in their document RGB coordinates; RGB32 uses linear matrix profiles. Integer raster exports retain the RGB working profile. Float32 TIFF retains the linear working profile; HDR PNG/JPEG copies convert to SDR sRGB. Previews convert to sRGB; individual channel/mask views remain grayscale. Colour parameters are document-coordinate RGB values. Actual ICC bytes are available in the downloaded native/PSD/TIFF document; state carries a compact identity hash.

Profile assignment/conversion commands, complete Photoshop colour settings and exact colour-conversion parity remain outstanding. Cross-profile transfers of editable profile-dependent fills/adjustments require a separately qualified policy; raster transfer converts colours through native ColorSync. See [working-profile evidence and limits](WORKING_PROFILE_REFERENCES.json). Full Debug/Release and bounded final-package/native/Photoshop checks pass from the identical isolated source snapshot; coverage limits remain explicit.

Photato can serve a browser client and a versioned HTTP API while its native application is running. The server, document model, renderer and editing commands are Swift. The optional browser client uses HTML/CSS/JavaScript to call that native engine. The macOS editor remains AppKit/SwiftUI.

## Two maintained API interfaces

Maintain both interfaces as supported product APIs: the Photato API for native document automation and Photato-specific capabilities, and the Adobe Photoshop v2-compatible API for clients using the published contract. They share the native Swift engine; do not duplicate editing algorithms. Preserve the existing Photato /v1 routes and clients rather than replace or silently repurpose them. Every new capability must include Photato API coverage, schemas, documentation and tests; when Adobe defines the corresponding operation, include its compatible interface and conformance tests in the same increment. Keep Photato-only operations distinct rather than inventing Adobe routes. Test equivalent underlying operations across both interfaces and the desktop while respecting each contract’s document/job lifecycle. Report each interface’s actual coverage independently; support for one does not imply support for the other.

Current status (step115): eighteen typed document commands, optional resource action jobs, document uploads/downloads and native Save/Save As. `layer.merge` and Adobe action descriptors use the shared native merge transaction, including direct linear RGB32 storage. Full merge contexts, format/profile fidelity, six Adobe endpoints and complete Photoshop parity remain open.

## Layer merging (step115)

Post to `/v1/documents/{id}/commands` with the current revision:

```json
{"command":"layer.merge","revision":"CURRENT_REVISION","parameters":{"operation":"down","layerIDs":["TOP_LAYER_UUID"]}}
```

`operation` is `down`, `selected` or `visible`. `layerIDs` is a unique UUID array: exactly one for Down, at least two for selected, and empty for Visible (which uses the current active visible layer). At most64 IDs are accepted. The response is the current document state. Merging makes one shared Undo entry, sets the merged layer active/selected and marks the document modified. Failed requests leave document/history unchanged. State exposes `selectedLayerIDs` and `mergeAvailability` booleans (`down`, `selected`, `visible`) for the current native selection; custom API IDs, resource bounds and permissions are revalidated at execution.

The supported scope is unlocked root-level Normal pixel layers without masks, affine transforms, clipping or groups. Entirely transparent results remain unsupported. Down retains the immediate lower visible layer's identity/name; selected retains the top selected visible layer; Visible retains the active visible layer, preserves hidden layers and clips to the canvas. Down/selected keep off-canvas content. RGB32 merges retain linear Float32 storage. Imported profiles may already have been converted to the working profile: the Adobe linear-sRGB fixture currently changes RGB bytes during import, so these merges do not yet promise original-profile sample identity. The raw native merge kernel is independently qualified; complete profile-preserving import/export remains open. The merged allocation is limited to4,194,304 pixels before starting background work; existing shared-document limits also apply. Individual channels, mask/path targets and busy desktop interactions reject. Errors: malformed parameters400, missing layers404, busy/stale/revoked409, allocation/document limit413, unsupported contexts422. API work uses the same prepared transaction/history engine as the desktop with cancellation and revision/share/token checks before commit.

Both `/v1/action-jobs` and `/v2/execute-actions` accept the installed Photoshop merge event IDs via the documented `$` character-ID notation:

```json
[{"_obj":"$Mrg2","_options":{"dialogOptions":"dontDisplay"}}]
```

`$Mrg2` merges the current selected layers, or merges down when one layer is selected. `$MrgV` merges visible layers. Input starts with the decoder's active layer selected. To select all supported unlocked root layers before merging, use:

```json
[
  {"_obj":"selectAllLayers","_target":[{"_ref":"layer","_enum":"ordinal","_value":"targetEnum"}]},
  {"_obj":"$Mrg2"}
]
```

Selection carries across action resources in the same request. These action jobs are isolated; they do not modify open desktop documents/history. Unknown parameters, stamp/duplicate options, arbitrary layer references, groups/Background semantics and unsupported contexts reject explicitly. RGB8/16/32 PSD inputs share the merge engine; RGB32 output supports PSD and TIFF; PNG output remains unsupported. This expands two partial endpoints without adding routes or claiming full hosted Adobe compatibility. The descriptor provenance and independent output references are recorded in [merge evidence](LAYER_MERGE_REFERENCES.json).

## Save and Save As (step113)

**File → Save** (Command-S) writes the associated supported format; **Save As…** (Shift-Command-S) chooses a new name, format and association. Eligible formats are Photato, supported PSD, PSB (Large Document Format), PNG, JPEG and TIFF. Source associations use the actual image container, including common .jpg/.jpe/.tif aliases and misleading filename extensions. Ordinary Save keeps the associated filename; Save As chooses a canonical extension. The native selector shows only formats capable of preserving the model's supported editable structure; individual codec constraints can still reject the save. Layered documents use Photato or supported PSD/PSB; flattened conversions remain Save a Copy. PNG/TIFF persistence requires one full-canvas pixel layer with no mask, transform, path, reduced opacity or non-Normal blending, at8/16-bit depth for PNG or8/16/32-bit depth for TIFF. JPEG additionally requires opaque RGB8 and uses95% lossy encoding. Recovery autosaves always use Photato archives.

API saving requires **Allow local document saving** in the native API window, an active share and current revision. Save As additionally requires **Choose Save As Folder…**. Both permissions and the selected folder reset when the service stops. Commands accept no arbitrary local path:

```json
{"command":"document.save","revision":"CURRENT_REVISION","parameters":{}}
```

```json
{"command":"document.saveAs","revision":"CURRENT_REVISION","parameters":{"name":"Edited image","format":"photato","replace":false}}
```

Post to `/v1/documents/{id}/commands`. Save As requires all three parameters: a printable nonblank filename of at most200 UTF-8 bytes, format `photato|psd|psb|png|jpeg|tiff`, and boolean `replace`. Names cannot begin with a dot or contain slash, backslash or colon. The canonical extension is appended when absent; supply a bare basename or the matching extension. Only `replace:true` permits replacing an existing destination in the chosen folder. Symbolic-link destinations and files owned by another open document are refused. Ordinary Save requires an associated file whose modification date still matches the last open/save. Source and destination checks run before encoding and again before coordinated writing.

Successful saving returns current document state, clears `isModified`, and keeps Undo/Redo. Save As changes the document name, format and file association. Failed, cancelled, stale or revoked saves do not adopt a new file or clear the modified flag. `documentSaving` exposes format notices and error/availability policies; `documentSavesEnabled` and `saveAsFolderSelected` expose session availability without disclosing paths. State adds:

```json
{
  "persistenceFormat":"psd",
  "saveFormats":["photato","psd","psb"],
  "sourceSaveNeedsReview":false,
  "canSave":true,
  "canSaveAs":true
}
```

`canSave`/`canSaveAs` reflect permission, association/folder and current interaction state; execution still validates representation, revision, disk state and limits. Imported non-sRGB sources and RGB32 PSD/PSB sources currently require explicit Save As review before ordinary source replacement (`sourceSaveNeedsReview:true`); exact source-profile/float preservation remains unfinished. The format notice identifies conversion limits. Native archive saving retains the current editable model; it does not reconstruct import information already converted by a codec.

Errors: invalid parameters400, disabled saving/missing folder403, missing source/busy/stale/revoked/existing destination/changed file409, output larger than128MiB413, unsupported representation or I/O422. Existing authentication, share, command-body and decoded-document limits apply. Desktop and API use the same native encoder, NSDocument save operation and document history. There is no dedicated desktop Save/Save As endpoint in the pinned Adobe v2 contract; its two partial resource-job endpoints keep using the shared codecs.

## PSD and PSB compression choices (step141)

The shared encoding-options object additionally accepts `psdLayerCompression` and `psdCompositeCompression` for `psd` and `psb`. Each is an optional string: `raw`, `rle`, `zip` or `zipPrediction`. Layer compression includes raster masks. Composite compression applies to the complete merged image, which is always included. Omitting a choice preserves the existing encoder default: ZIP prediction for layers/masks and raw merged data. Explicit choices preserve the same sample encoding, profile, layer structure and metadata path.

The native Save As/Copy accessory exposes independent layer/composite choices and keeps separate PSD and PSB drafts. Successful Save/Save As remembers them per format; ordinary Save reuses those successful choices. Cancelling a later accessory draft, failed/stale saves and Save a Copy do not replace remembered settings. These are current Photato per-output controls, not a claim that Photoshop’s global Disable Compression or Maximize Compatibility preferences/dialogs have been completed.

The same two fields work in `document.save`, `document.saveAs`, the bounded `X-Photato-Export-Options` download header and `/v1/action-jobs` output `encodingOptions`. They appear in capability/parameter schemas and `saveEncodingOptions` state. Wrong enum/type/null, unknown keys or options for an unrelated format return400. The native API command/route count and permissions are unchanged. Options are a complete set, not a patch; `{}` selects defaults.

```json
{"command":"document.saveAs","revision":"CURRENT_REVISION","parameters":{"name":"Layered image","format":"psb","replace":false,"options":{"psdLayerCompression":"rle","psdCompositeCompression":"zipPrediction"}}}
```

PSD RLE row counts are16-bit; an encoded row exceeding65535 bytes is rejected before the destination is replaced. Choose PSB or another method. PSB uses32-bit row lengths. The writer streams rows and patches their length table through the existing bounded atomic output; Data and staged-file output use the same serializer. Existing512MiB decoded-channel/composite, format-dimension, overall output and smaller API resource limits still apply. Cancellation, errors and stale state retain the original file and prior Save settings.

Adobe’s pinned `PsdOutput` has no corresponding compression field. `/v2/execute-actions` therefore keeps its current default PSD encoding and rejects Photato `encodingOptions` with422. A PNG-style `compression` field on PSD is also unsupported. Both interfaces share the same native serializer and retain two partial/six unimplemented Adobe endpoints. No invented Adobe route or field is introduced.

Original Rust PackBits packet decisions are ported to Swift under MIT OR Apache-2.0; zlib remains the macOS system library. Qualification covers44 original-Rust packet cases, all96 depth/container/layer/composite export combinations and independent stream decoding. This establishes bounded format/output behavior, not byte-identical Photoshop rendering or the full file-handling workflow. Exact Photoshop compression defaults, global preferences, compatibility omission and live dialog sequencing remain open major requirements.

## Shared PNG and TIFF encoding options (step140)

Native Save As and Save a Copy expose PNG compression and interlacing and TIFF image compression. Ordinary Save reuses the last successful choices for that format in the open document. These choices are session state: they do not enter document content, Undo/Redo, recovery archives or persisted application preferences. A failed, cancelled or stale save does not adopt its choices; Copy and downloads never change remembered settings. The native controls are an initial format-options implementation; exact Photoshop dialog sequencing/defaults remain unqualified.

`document.save` and `document.saveAs` accept an optional `parameters.options` object. Its exact schema has no required fields and rejects additional properties:

| Field | Values | Applicable format |
|---|---|---|
| `pngCompression` | Integer0–9;0 stores without compression,9 requests strongest compression | `png` |
| `pngInterlaced` | Boolean;true selects Adam7 | `png` |
| `tiffCompression` | `none`, `lzw`, `zip` (TIFF tags1,5,8) | `tiff` |
| `tiffByteOrder` | `bigEndian`, `littleEndian` | `tiff` |
| `tiffLayers` | Boolean | `tiff` |
| `tiffLayerCompression` | `rle`, `zip`; requires `tiffLayers:true` | `tiff` |
| `tiffPixelOrder` | `interleaved`, `perChannel` | `tiff` |
| `tiffPredictor` | Boolean;true requires32-bit and explicit LZW/ZIP | `tiff` |

Omitting `options` in Save/Save As reuses that document's remembered options for the selected format, initially the existing encoder defaults. Supplying `{}` explicitly resets that format to encoder defaults after a successful save. Options are a complete choice set, not a patch: omitted fields within a supplied object use encoder defaults. Invalid types, fractional/out-of-range compression levels, unknown fields and format-mismatched choices return400. Existing permission403, busy/stale/revoked409, output-size413 and representation/I/O422 rules remain in force.

```json
{"command":"document.saveAs","revision":"CURRENT_REVISION","parameters":{"name":"Print image","format":"tiff","replace":false,"options":{"tiffCompression":"zip"}}}
```

`GET /v1/documents/{id}/file.{format}` accepts `X-Photato-Export-Options`, a JSON object with that same schema and a2048 UTF-8-byte limit. Omission or `{}` uses encoder defaults independently of remembered Save settings. For example, the header value `{"pngCompression":9,"pngInterlaced":true}` selects compressed Adam7 PNG. Downloads retain the existing permission, snapshot, size and cancellation guards and do not write a local file.

Document state includes `saveEncodingOptions`, an object keyed by all six supported formats (`photato`, `psd`, `psb`, `png`, `jpeg`, `tiff`). Each value contains the explicitly remembered fields or `{}`. `stateSchemas.saveEncodingOptions`, `documentSaving.encodingOptions`, `documentTransfers.encodingOptions` and action-job capability metadata describe the supported schema, defaults and limitations. The executable command count remains20.

Both `/v1/action-jobs` and `/v2/execute-actions` now support `image/tiff` output alongside PNG and PSD. PNG outputs accept Adobe's published `compression` field: `none`, `very_low`, `low`, `medium_low`, `medium`, `medium_high`, `default`, `high`, `very_high`, `maximum`, mapped to zlib levels0–9. Their output cache distinguishes format and choices. RGB32 PNG action output remains explicitly unsupported; TIFF32 is supported by step143 without silent depth reduction.

Only `/v1/action-jobs` additionally accepts output `encodingOptions` using the native schema. This allows PNG interlacing and TIFF compression/storage options in Photato jobs. The Adobe route rejects that extension with422; it has no TIFF-compression or PNG-interlace field in the pinned output contract. Supplying PNG compression through both fields is rejected with400. Adobe named compression on TIFF is rejected with422. Existing input/actions, destinations, authorization, job lifecycle and storage limits remain unchanged. This expands the tested subset of two partial endpoints; six other endpoints remain unimplemented.

Compression preserves the existing rendering/color/depth path. PNG recompression retains all non-IDAT chunks and the exact filtered sample stream; it streams through bounded buffers using the macOS zlib library. TIFF compression-only defaults use ImageIO; step144 adds native layout/prediction/LZW with system zlib for explicit TIFF storage options. JPEG Photoshop quality mapping and scan counts, full layered TIFF/pyramids, metadata/profile fidelity and complete Photoshop encoder-byte equivalence remain open major save/export requirements. The current authoritative Adobe contract fetch matches the pinned schema; native/API output equality is not evidence of Adobe service byte equivalence.

## File metadata preservation (step112)

Native Copy/download and both resource-job interfaces share the native metadata encoders. Raster imports retain ImageIO properties and XMP in `.photato` archives. Supported raster outputs preserve camera/descriptive/copyright/IPTC fields and custom XMP while updating orientation, dimensions, resolution and working-color fields. PSD copies retain opaque image-resource blocks, regenerate profile/resolution/path/XMP data and omit stale previews, layer-index/selection, version and recovery records. Opaque retention does not implement the Photoshop workflows those records may describe. Binary PSD EXIF remains opaque; full format metadata synchronization remains open.

`documentTransfers.metadata` exposes the retention policy:

```json
{
  "type": "object",
  "required": ["raster", "psd", "profiles", "metadataLimitBytes", "workingProfileLimitBytes", "workingProfileMaximumTags"],
  "properties": {
    "raster": {"type": "string"},
    "psd": {"type": "string"},
    "profiles": {"type": "string"},
    "metadataLimitBytes": {"type": "integer", "const": 16777216},
    "workingProfileLimitBytes": {"type": "integer", "const": 4194304},
    "workingProfileMaximumTags": {"type": "integer", "const": 4096}
  },
  "additionalProperties": false
}
```

The limit applies to each retained metadata payload (and the complete PSD image-resource section). Invalid or oversized stored metadata rejects encoding through existing error responses; failed output does not modify the shared document/history. Working/output pixels use the retained actual RGB working profile, with linear profiles for RGB32 PSD; source metadata remains separate. Complete profile conversion policy and Photoshop pixel/file equivalence remain open. See [metadata evidence and exact limits](SOURCE_METADATA_REFERENCES.json).

## Save a Copy and Revert (step110)

RGB32 storage preserves supported PSD raster sample bits and actual working profiles through native archive version10, metadata-only edits and straight PSD layer output. PSD merged RGB uses separately rounded white-distance matting, including opaque samples. Step117 adds a measured root untransformed Normal raster-stack path, with explicit finite-overflow errors. Native downloads/saves and both action-job interfaces use the same renderer/codecs. Qualification and remaining gaps are in [RGB32 composite evidence](RGB32_COMPOSITE_REFERENCES.json); groups, clipping, transforms, non-Normal blends, adjustments, arbitrary profiles and full HDR/file equivalence remain open. RGB32 source replacement still requires Save As review. Step118 exposes `float32Storage.normalHierarchyComposition` for the shared Normal raster hierarchy evaluator: Pass Through/isolated groups, group opacity/masks and default raster clipping chains. Independent clipping blending, clipped groups, other blends and transforms remain unqualified; current qualification is recorded in the development log.

`documentTransfers.float32Storage` retains `encoding`, `nativeArchiveVersion`, `preservation`, `limits` and `interfaces`, and adds `normalRasterComposition` with the following schema. This is additive capability metadata; command requests, binary response types and error envelopes remain unchanged. The existing413/422 resource/encoding failures and409 busy/stale/revoked handling apply; failed downloads/jobs do not mutate the shared document/history. Both `/v1/action-jobs` and `/v2/execute-actions` use this same output path; endpoint coverage is unchanged.

```json
{
  "type": "object",
  "required": ["scope", "mergedEncoding", "exactWholePSDFile"],
  "properties": {
    "scope": {"type": "string"},
    "mergedEncoding": {"type": "string"},
    "exactWholePSDFile": {"type": "boolean", "const": false}
  },
  "additionalProperties": false
}
```

Step119 adds `psb` to Photato format discovery, `document.saveAs`, associated `document.save`, and `GET /v1/documents/{id}/file.psb`. PSB transfers use `application/x-photoshop`, matching the installed Photoshop type declaration; import also examines the version2 container header. Native Open/Save/Copy and both APIs share the codec. `/v1/action-jobs` and `/v2/execute-actions` accept supported PSB resource input; their published `image/vnd.adobe.photoshop` output still means PSD, not a fabricated PSB contract extension. No command or endpoint count changes.

`documentTransfers.photoshopContainers` exposes `readVersions:[1,2]`, `writeFormats:["psd","psb"]`, `psbMediaType`, `maximumFileBytes:536870912`, `maximumDimension:32768`, `maximumPixels:36000000`, `streamingLargeFiles:false`, and textual `scope`, `adobeJobs`, `limits`. Existing64MiB/4MP transfer/job input and output/decoded budgets remain authoritative. Container framing supports64bit lengths and32bit RLE tables, but multi-gigabyte streaming,300000-pixel documents, all rich Photoshop content and live PSB qualification remain open. See [PSB evidence](PSB_REFERENCES.json). The additive `channelDecoding` object reports `rowBased:true`, `nestedSectionViews:true`, `zipInputChunkBytes:65536`, unused-merged-cache validation and the remaining input/metadata/tile/output constraints. Desktop Open, Photato imports and both job adapters use this same reader; the published Adobe routes and output contract are unchanged. Row decoding reduces temporary buffers but does not remove the advertised file, pixel or transfer limits. Step120 passes1077 Debug/1077 Release tests, universal packaging and Intel engine conformance; live qualification remains pending. See [decoder evidence](PSD_STREAMING_REFERENCES.json). The additive `fileInput` object reports `boundedReads:true`, `readWindowBytes:65536`, `maximumCacheBytes:524288` (cached page payload; row buffers, metadata and tiles are separate), the observed file-change rejection policy and the shared native/API scope. Native PSD/PSB files use a retained descriptor and bounded reads; uploaded/job resources remain Data-backed inputs to the same parser. Existing file/pixel/transfer budgets remain unchanged. Step121 passes final1084 Debug/1084 Release tests, universal packaging and Intel file-input checks; live qualification remains pending; see [file-input evidence](PSD_FILE_INPUT_REFERENCES.json).

**File → Save a Copy…** (Option-Command-S) writes a separate Photato, supported PSD/PSB, PNG, JPEG or TIFF copy. The API equivalent remains `GET /v1/documents/{id}/file.{format}`: the same snapshot and native encoders produce the output without changing the open document, filename, modified flag or Undo/Redo history. Downloads never choose a local save path. The native sheet explains flattening/depth conversions; format-specific compression, profile and metadata options remain incomplete. A native Save panel replacement confirmation can authorize overwriting an existing original; API downloads have no local overwrite operation; the separately enabled Save commands above can write associated files or files inside the approved folder.

**File → Revert** (F12) reloads the document’s associated local file. The Photato API exposes the same operation:

```json
{"command":"document.revert","revision":"CURRENT_REVISION","parameters":{}}
```

Post this to `/v1/documents/{id}/commands`. Revert requires native **Allow document transfers and Revert** enablement and an existing share. It reads only that document’s existing file association; client-supplied file paths are rejected. Upload-only/unsaved documents have no source until saved through the desktop or the separately enabled Save As command. Revert is one shared history edit, clears `isModified`, and can be undone/redone through either client. State adds `hasRevertSource`, `canRevert`, and `fileOperationBusy`; current interaction/revision checks remain authoritative at execution time. AppKit recovery autosaving preserves the last explicit save separately.

The persistence fields in the returned shared-document state follow this schema (other existing state fields remain present):

```json
{
  "type": "object",
  "required": ["isModified", "hasRevertSource", "canRevert", "fileOperationBusy"],
  "properties": {
    "isModified": {"type": "boolean"},
    "hasRevertSource": {"type": "boolean"},
    "canRevert": {"type": "boolean"},
    "fileOperationBusy": {"type": "boolean"}
  },
  "additionalProperties": true
}
```

Disabled permission returns403; missing saved source, busy/stale requests, concurrent edits or revoked access return409; resource limits413; unreadable/unsupported content422. The read uses the same64MiB input,4MP,64-layer and128MiB decoded-document limits as uploads. Failed/revoked/stale reads leave document content/history unchanged. Current native file lifecycle has no corresponding endpoint in the pinned Adobe v2 contract; existing action jobs remain separate and partially compatible.


**Current format policy:** `.photato` and legacy `.pcswift` downloads use Photato’s own archive; `.psd` uses the separate PSD codec. Full PSD support remains required and incomplete. The proposed PSD-backed `.photato` migration was withdrawn. See [format policy](DOCUMENT_FORMAT_POLICY.json).

## Document uploads and downloads (step109)

Start the API, then enable **Allow document transfers and Revert** in its native window. This is off each session and separate from resource action jobs. Uploads create a new unsaved document, open its native window and share it with the current API session. Downloads copy an explicitly shared document; they do not save to a local path, overwrite its source, mark it clean or change its undo history. Revoking a document share blocks its downloads. Disabling transfers or stopping the service invalidates in-flight results, including if transfers are enabled again before decoding completes. Already-created documents remain open; stopping the service revokes their shares.

| Operation | Request | Result |
| --- | --- | --- |
| Import | `POST /v1/documents/import` with raw file bytes | HTTP201 and new document state with `id` and `revision` |
| Download | `GET /v1/documents/{id}/file.{format}` | HTTP200 with a binary document snapshot |

Import Content-Type values are `application/vnd.photato.document`, `image/vnd.adobe.photoshop`, `image/png`, `image/jpeg`, `image/tiff`, `image/heic`, `image/bmp` and `image/gif`. The native archive type uses the native archive decoder; image types use the shared native image/PSD decoder and content identification. `X-Photato-Name` optionally supplies a nonblank printable ASCII name of at most256 characters; otherwise images use “Imported Image”. Native archives retain their stored name. Desktop file opening also retains its filename-derived name. Supported decoding does not imply complete metadata, profile, animation or format parity; Animated GIF input follows the Timeline decoder described above and retains all frames within its declared limits.

Download formats are `photato`, `psd`, `png`, `jpeg` and `tiff`. Photato archives preserve supported editable native structure. PSD output uses the existing supported editable-layer writer; unsupported structures can fail explicitly. Raster downloads flatten through the same native image exporter, with its current depth, profile and alpha limits. Supply `X-Photato-Revision` with the latest state revision to reject a stale download request. A document change, share revocation or session change during encoding also rejects the response. This custom header is a Photato revision token, not an HTTP entity tag. The old `file.pcswift` route remains an alias for `file.photato`, returning identical native archive bytes. Capability metadata advertises this under `documentTransfers.download.formatAliases`; the native MIME type and default version10 encoding remain unchanged. Both aliases also accept the version11 opt-in described above.

```sh
curl --fail -H "Authorization: Bearer $PHOTATO_TOKEN" \
  -H "Content-Type: image/png" -H "X-Photato-Name: Client image" \
  --data-binary @image.png "$PHOTATO_ENDPOINT/v1/documents/import"

curl --fail -H "Authorization: Bearer $PHOTATO_TOKEN" \
  -H "X-Photato-Revision: $PHOTATO_REVISION" \
  "$PHOTATO_ENDPOINT/v1/documents/$PHOTATO_DOCUMENT_ID/file.photato" \
  --output copy.photato
```

Step122 adds `documentTransfers.photoshopContainers.fileOutput`: `boundedWrites:true`, `maximumWriteBytes:65536`, `rowBasedCompression:true`, `checkedLengthBackpatching:true`, `atomicReplacement:true`, and a textual `scope`. Native PSD/PSB Save, Save As, Save a Copy and permitted API local saves stage private files and retain the existing snapshot/permission/state guards. File destinations use bounded writes and atomic replacement; API downloads and both job outputs still return bounded Data through the identical serializer. API local saves retain the128MiB output check before publishing. Renderer surfaces, metadata and native archives remain memory-resident; `streamingLargeFiles` remains false. No Adobe route or contract changes. Qualification is recorded in [output evidence](PSD_FILE_OUTPUT_REFERENCES.json).

Uploads are limited to64MiB,4,194,304 canvas pixels,64 layers and128MiB of decoded document data. Dimensions are checked before pixel decoding; native archive raster expansion also has an explicit128MiB budget. Downloads are limited to128MiB. Only one transfer runs at a time, and the existing eight-share session limit applies. The upload body limit applies only to the exact POST import route; document-command requests retain64KiB and isolated action submissions retain4MiB. Existing internal codec allocation limits still apply; large-document/scratch/streaming work remains open.

Errors distinguish invalid name400, authentication401, disabled403, missing share/route404, busy/stale/revoked409, resource limits413, unsupported Content-Type415, decode/encode/unsupported content422, and transfer/share capacity429. Complete capability metadata appears under `documentTransfers` and `documentTransfersEnabled`; document state adds `isModified` and `persistenceFormat` (`photato`, `psd`, `png`, `jpeg` or `tiff`). Uploading does not create a document until decoding, limits and session checks succeed. Local source-format save-back is not exposed by these routes.

Adobe v2 has no dedicated interactive desktop Open/Save endpoint. Its existing execute-actions input/output adapter remains a separate, limited action-job workflow using the same native RasterIO/PSDCodec implementation. No new Adobe endpoint or broader Adobe action input contract is claimed here. [Document workflow evidence](DOCUMENT_IO_REFERENCES.json) records tests and live scope.

## Adobe compatibility target

The maintainer requires compatibility with [Adobe Photoshop API v2 GA](https://developer.adobe.com/firefly-services/docs/photoshop/getting-started/v2-ga/) in Firefly Services. The `/v1` document routes below are Photato's own preview. The separate `/v2/execute-actions` and `/v2/status/{jobId}` routes implement a **limited Adobe-shaped subset**, not complete Adobe service compatibility. The existing version label does not refer to Adobe Photoshop API v1.

Add a Swift compatibility adapter alongside the maintained Photato API covering published routes, payloads, asset conventions, job submission/status and error behavior. Adobe's [status guide](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/status-migration) documents the job lifecycle; the [font workflow](https://developer.adobe.com/firefly-services/docs/photoshop/guides/fonts/) demonstrates asynchronous submission. Keep Photato-only extensions separate. New Adobe-covered functionality is incomplete until both its Photato API support and its compatible Adobe API path, documentation and conformance tests ship with it.

[The compatibility plan](ADOBE_API_COMPATIBILITY.json) records work packages and gaps. Step101 pins the authoritative [OpenAPI document](contracts/adobe-photoshop-v2.json) with [immutable provenance and endpoint inventory](contracts/adobe-photoshop-v2.provenance.json); all394 internal references resolve. Repository and service licenses are recorded separately. The contract uses jobId/statusUrl for submission and result/errorDetails for status. No live Adobe jobs or client interoperability are qualified. It has no dedicated desktop channel-view-state endpoint; its general actionJSON/ATN/UXP execution could express channel actions and is partially supported for the native RGB8 select/neutral Fill subset below. The view extensions below do not assert Adobe conformance.

## Native component editing and isolated action jobs (step106)

The Channels panel selects a real editing target; Command-2 selects RGB and Command-3/4/5 select Red/Green/Blue when the document canvas owns keyboard input. RGB8 Normal neutral Fill supports opacity and preserves other components and stored alpha. Geometric selections, shared Undo/Redo and layer metadata remain available. Other component tools, colored foreground conversion, RGB16/32 component writes and alpha/spot channels are still unimplemented; unsupported writers fail before a document/history mutation. Existing view-only API operations retain their meaning and never select an editing target.

Both job interfaces run the same native actionJSON/request/PSD/PNG/resource engine on isolated documents. They accept inline actionJSON resources selecting RGB/Red/Green/Blue and applying RGB8 Normal white/black/50%-gray Fill. RGB16/32 PSD input additionally supports composite RGB selection and PSD output preservation; individual-channel selection/writes still reject. PNG input remains RGB8; RGB32 PNG output rejects rather than converting depth. Composite RGB Fill, other actions, ATN/UXP/JavaScript execution, linked assets, fonts and generative actions are unsupported. Unknown options fail explicitly. Independent Photoshop comparisons cover five original single-layer RGB8 fixtures, not global byte equality, file identity or general imported active-layer semantics.

Start the API, then explicitly enable **Enable resource action jobs** in the native API window. This permits authenticated clients to fetch input URLs and upload results to requested destination URLs from this Mac. It does not grant access to unshared open documents or local filesystem paths. Disable the toggle to cancel/revoke jobs and hosted outputs. Stopping the service also revokes the token, document shares and jobs. Resource jobs are off after every start and launch; completed remote uploads cannot be rolled back by revocation.

Use the native window's loopback base URL and `Authorization: Bearer <session-token>` for both interfaces. Configure Adobe-oriented clients with this base URL and local token; Photato does not implement Adobe OAuth, subscriptions, client credentials or proprietary models. Resource URLs supply their own access (for example presigned URLs); the Photato token is never forwarded to a resource server. No Adobe credentials or external-service interoperability have been qualified.

| Method | Route | Result |
|---|---|---|
| POST | `/v1/action-jobs` | Photato isolated action job, using the typed action resource payload below; HTTP202 with jobId/statusUrl |
| GET | `/v1/action-jobs/{jobId}` | In-memory job status and results |
| GET | `/v1/action-assets/{assetId}` | Authenticated temporary PSD/PNG output |
| POST | `/v2/execute-actions` | Partial Adobe actionJSON adapter; HTTP202 with jobId/statusUrl |
| GET | `/v2/status/{jobId}` | Adobe-shaped not_started/running/succeeded/failed status; result.outputs or errorDetails |
| GET | `/v2/assets/{assetId}` | **Photato local extension**, not a published Adobe endpoint; authenticated temporary output |

POST bodies require Content-Type application/json and Content-Length. These two submission routes allow4MiB; existing document commands retain64KiB. A job accepts1–10 inline resources of at most51,200 Unicode scalars each and1–25 PNG/TIFF/PSD outputs. Limits include16 retained jobs, one running job,64MiB input,4,194,304 canvas pixels,64 layers,128MiB decoded document and128MiB hosted storage. Hosted outputs require destination.validityPeriod60–86400 seconds; completed jobs expire after24hours. Jobs are in-memory and lost on restart. Dropbox, resource redirects and Creative Cloud resources are unsupported. External HTTPS PUT destinations may specify Azure BlockBlob storage; overwrite prevention depends on destination HTTP preconditions. No real storage-provider upload is qualified.

Example submission payload for either job interface:

```json
{
  "image": {"source": {"url": "https://your-storage.example/input.psd"}},
  "options": {"actions": [{"source": {
    "contentType": "application/json",
    "content": "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"red\"}]},{\"_obj\":\"fill\",\"using\":{\"_enum\":\"fillContents\",\"_value\":\"white\"},\"opacity\":{\"_unit\":\"percentUnit\",\"_value\":50}}]"
  }}]},
  "outputs": [{"mediaType": "image/vnd.adobe.photoshop", "destination": {"validityPeriod": 60}}]
}
```

Poll the returned statusUrl using the same token. When succeeded, fetch result.outputs[].destination.url with that token for a local hosted output. A failed job returns errorDetails and no partial hosted output; earlier external PUTs may already have completed. Adobe routes use error_code/message for immediate errors; Photato routes retain error. The [pinned contract](contracts/adobe-photoshop-v2.json), [compatibility gaps](ADOBE_API_COMPATIBILITY.json) and [integration evidence](COMPONENT_EDITING_INTEGRATION_REFERENCES.json) distinguish the tested subset from complete conformance.

## Start and connect

1. Open **Help → Photato Automation API…** and click **Start API**.
2. Select an open Photato document and click **Share Current Document**. Sharing grants reading and editing access to clients holding this session's token.
3. Click **Copy Session Token**, then **Open Browser Client**. Paste into the browser's password field and click **Connect**.
4. Edit layer names, opacity, visibility, position or pixel fill; create layers and use shared Undo/Redo. The preview is rendered by Photato. Use **Refresh from Photato** after desktop changes.
5. Click **Revoke** for a document, or **Stop API** for the whole session. Closing the control window keeps the API running. Quitting Photato stops it. Every app launch starts with the API off.

The endpoint is an ephemeral `http://127.0.0.1:<port>` address shown in the native control window. No fixed port, DNS, account or external server is required. The browser demonstration is served at `/`. The token has 256 random bits, rotates on each start and is neither placed in a URL nor persisted by the client. Copying it puts it on the macOS clipboard; treat that clipboard content as a password. All authenticated clients have the same access to the session's shared documents. Previously received data cannot be recalled by revoking access.

## HTTP contract

All `/v1/` requests require `Authorization: Bearer <session-token>`. POST requests also require `Content-Type: application/json` and `Content-Length`. Use ordinary HTTP clients that supply the length automatically. The exact `Host` must match the numeric loopback endpoint. Browser requests must come from that same origin; there is no permissive CORS response, cookie authentication, remote listener or token query parameter.

| Method | Route | Result |
|---|---|---|
| GET | `/v1/capabilities` | API version, twenty executable commands, per-command JSON Schema, channel-view state schema, limits and the separate complete native menu inventory |
| GET | `/v1/documents` | State for explicitly shared open documents |
| GET | `/v1/documents/{id}` | Current document state and opaque revision |
| GET | `/v1/documents/{id}/preview.png` | Flattened native display PNG of the committed document; excludes desktop drafts, selection outlines and channel/mask viewing overlays |
| GET | `/v1/documents/{id}/channel-preview.png` | Committed native composite with current channel visibility; excludes drafts, selection outlines and mask overlays |
| POST | `/v1/documents/{id}/commands` | Execute one command and return updated document state |

Document state includes a session-specific share ID, display name, canvas size, depth, revision, active layer ID, layer IDs/names/opacity/visibility/positions and Undo/Redo availability, plus `channelTarget` (RGB/Red/Green/Blue) and `channelView` with `preview`, ordered `visible` components and `componentEditing` indicating an individual edit target. Preview remains independent of target selection. No filesystem path is returned. Share IDs become invalid after revocation, close, reload or server restart. Layer IDs identify the actual native document layers.

The command request is:

```json
{
  "command": "layer.opacity",
  "revision": "copy the exact revision from the latest document state",
  "parameters": {
    "layerID": "copy the target layer UUID from that state",
    "opacity": 0.75
  }
}
```

The revision is opaque and must not be synthesized or incremented by a client. Desktop edits and API edits use one history. Two changing commands with the same revision cannot both commit. A successful no-op can leave revision and history unchanged. Display updates can conservatively invalidate a revision even if pixels are unchanged. Undo/Redo validate the destination history document against API resource limits before restoring it.

A revision conflict requires refreshing and reviewing the current state, not blindly replaying the old edit. Network disconnection after sending a mutation can leave its outcome unknown; refresh before deciding whether to retry. v1 has no idempotency keys or atomic multi-command batches.

## Executable commands

All listed parameters are required; extra fields are rejected. Names are nonempty, at most 256 Swift characters, and cannot contain control characters. Numeric values must be finite. Selection coordinates are constrained further by the current document size. Capability schemas describe static constraints; document-dependent limits and native edit validation still apply.

| Command | Parameters | Native behavior |
|---|---|---|
| `view.channelPreview` | `channel` (RGB, Red, Green or Blue; exact case) | Select a display preview; exits mask viewing/editing without changing pixels or history |
| `view.channelVisibility` | `channel`, `visible` (boolean) | Change visible components without changing the selected preview; hiding the last component or composite is a no-op |
| `layer.rename` | `layerID`, `name` | Rename the target layer |
| `layer.opacity` | `layerID`, `opacity` (0–1) | Set layer opacity |
| `layer.visibility` | `layerID`, `visible` (boolean) | Set visibility |
| `layer.move` | `layerID`, integer `x`, `y` (±1,000,000) | Absolute position in document pixels, including native group movement semantics |
| `layer.new` | `name` | Transparent pixel layer above the native active layer |
| `layer.fill` | `layerID`, `r`, `g`, `b`, `a` (0–1) | Native pixel-layer RGBA fill, honoring the document selection; masks are not targets |
| `selection.rectangle` | integer `x`, `y`, `width`, `height` | Replace selection with a rectangle contained in the canvas |
| `selection.clear` | none | Deselect |
| `document.revert` | none | Restore the associated saved file as one undoable edit; requires native transfer permission |
| `document.autosave` | none | Write committed content to AppKit recovery storage; preserves dirty state, source and history |
| `document.save` | optional `options` | Save the associated format/file; requires separate native local-save permission |
| `document.saveAs` | `name`, `format`, `replace`; optional `options` | Save inside the native-selected folder and adopt that file; requires local-save permission |
| `history.undo` | none | Undo the latest document edit from either client |
| `history.redo` | none | Redo the latest undone document edit |

Fill values use the native engine's pixel representation. The browser color picker is a demonstration, not a qualified color-managed web editing workflow. Native layer/group locks apply. API errors do not open desktop alerts. Commands are rejected while desktop numeric/text naming edits, geometry/adjustment dialogs, AI interactions, modal sheets, coalesced edits or pointer interactions in the active shared document window could conflict. Mouse buttons held in another application or unrelated document do not by themselves block automation; document gesture/draft guards still apply after focus changes.

The menu inventory reports paths, node kinds and base key characters; complete modifier bindings remain in the native shortcut reference and are not a web shortcut implementation.

The browser demonstrates eight commands directly. Rectangular selection, deselection and both channel-view operations are available to API clients; their browser controls are future additions. Menu inventory entries are reference/discovery data, including unavailable commands and submenus. Their presence does **not** make them callable. Only `commands` in the capability response identifies executable API commands.

## Error handling and limits

Errors return JSON with an `error` string. Common status codes: 400 malformed request/parameters; 401 missing or expired token; 403 Host/Origin rejected; 404 unshared document/layer/route; 409 stale revision or desktop interaction conflict; 411 missing length; 413 resource limit; 415 unsupported body type; 422 unsupported command or native validation failure; 429 preview/share limit; 503 stopped/cancelled session. Connections over the concurrency limit are closed before request handling.

v1 limits: 16 KiB headers, 64 KiB JSON body, eight connections, 15-second connection lifetime, eight shared documents, one concurrent PNG render, 4,194,304 canvas pixels, 64 layers and 128 MiB estimated document data. Adding a layer uses a conservative worst-case allocation check. HTTP/1.1 only, one request per connection, no chunked bodies or pipelining. Preview generation rechecks the document revision and share/session lifetime before returning data. Core rendering cancellation is bounded by completion of the current native render stage, not guaranteed instantaneous.

## Feature completion requirement

Every new or expanded capability must be reflected in the optional API in the same implementation increment. API coverage is part of feature completion, not deferred follow-up work. Add or update the typed operations, observable state/capabilities, parameter and result schemas, availability/error behavior, usage documentation and relevant API tests. Use the same native Swift implementation and transaction/history path as the desktop, with matching results, validation, undo/redo and document-state effects where applicable. Test desktop/API equivalence and invalid/busy/stale-request behavior as relevant to the feature. For presentation-only changes, explicitly record their API impact and update exposed state or metadata where applicable; do not silently omit the API review. Keep executable capabilities distinct from the reference menu inventory. Existing API coverage gaps remain tracked separately and must not be represented as already implemented.

Channel view state is per open document and is not saved into document archives or history. Selecting RGB restores all components. Selecting a component from RGB, or selecting a hidden component, isolates it; selecting an already-visible component from a component preview preserves the custom visible combination. A single visible component appears grayscale; multiple components keep their colors. Eye visibility never changes the selected preview. `stateSchemas.channelView` in capabilities describes the result object. Mask viewing/editing returns422 for visibility changes; selecting a preview exits it. Ordinary busy/stale requests still return409. Changes invalidate revisions; a no-op does not. Neither operation enables channel-targeted painting. The existing `preview.png` always returns the committed full composite; use `channel-preview.png` to reproduce this view state.

For example, send `view.channelPreview` with `{ "channel": "Red" }`, then use the returned revision to send `view.channelVisibility` with `{ "channel": "Green", "visible": true }`. The resulting state has `preview: "Red"` and `visible: ["Red", "Green"]`; the channel-preview PNG matches the native canvas in the qualified fixture. Authentication and shared-document requirements apply to both PNG routes.

## Next stages

Use the pinned Adobe v2 contract to implement the native adapter, then expand the compatible command coverage alongside tested native features, then add selection/brush gestures, thumbnails and delta updates, asynchronous jobs, explicit import/export permissions, streaming preview updates, client SDKs, action recording and richer machine-readable schemas. A complete web workspace also needs the desktop's panels, tools, keyboard behavior, color management, large-document rendering and accessibility.

LAN/internet hosting is a separate product increment: TLS, user identity, per-client/document permissions, pairing/revocation UI, quotas, deployment and threat testing. This preview must not be exposed by a reverse proxy or tunnel. App Store sandbox distribution will also need the incoming-network entitlement and sandboxed network tests. No server entitlement or public hosting was enabled in this increment. The optional API does not complete Photoshop scripting/UXP compatibility or the Photoshop-parity backlog.

See [current status](STATUS.md), [step091 development record](DEVLOG.md#dev-step-091), and [API qualification evidence](AUTOMATION_API_REFERENCES.json).

Component editing integration (step106): the earlier step102 core foundation is now exposed through native channel targeting/Fill, the Photato channel.target and channel.fill commands, and both isolated job interfaces described above. That step’s executable document registry contained fourteen operations; step110 adds document.revert, step113 adds document.save/document.saveAs, and step115 adds layer.merge. Existing view.channelPreview and view.channelVisibility operations still affect display only. See [integration evidence](COMPONENT_EDITING_INTEGRATION_REFERENCES.json) for measured scope and remaining gaps.

## Component document commands

`channel.target` requires `{ "channel": "Red" }` (or RGB/Green/Blue). It updates document-local target and preview state without adding document history. A target change invalidates the revision even if its preview already matches. `channel.fill` requires `{ "value": 1, "opacity": 0.5 }`; both numbers must be finite in0–1. It fills the active RGB8 pixel layer's selected component using the shared native transaction. Select an individual target first. Invalid parameters return400; busy or stale requests409; unsupported target/depth/locked/writer contexts422. Undo/Redo uses the existing shared history commands. These operations add to the original twelve document commands; they do not reinterpret layer.fill or the two view-only commands.

## Photoshop file compression preferences (step142)

Authenticated `GET /v1/preferences/photoshop-file-handling` reads `revision`,
`disablePSDCompression`, `isPersistent`, `canUpdate`, `isBusy` and `loadError`.
`POST` to the same path requires the separate native **Allow Photoshop file
preference changes** permission and exactly this JSON object:

```json
{"revision":"<current File Handling revision UUID>","disablePSDCompression":true}
```

The permission resets whenever the API starts or stops. Recovery-preference and
recent-file permissions do not grant this write access. Native File Handling
OK/Cancel and this endpoint use the same atomic settings transaction. Invalid
fields/types return400, authentication401, missing permission403, stale or busy
state409, wrong media type415, and settings load/write failure422. Reads remain
available while an operation is busy; responses never expose the settings path.

When enabled, omitted layer or merged-image compression choices become `raw`
for16/32-bit PSD and PSB native Save/Save As/Copy and shared-document downloads.
RGB8 and other formats retain their existing defaults. Explicit per-output
Photato options override each component independently. These overrides are a
Photato extension; exact Photoshop dialog/default equivalence remains open.
`saveEncodingOptions` preserves the requested choices, including omitted fields.
The new `effectiveSaveEncodingOptions` state applies current application defaults.
Thus a later preference change affects future ordinary Saves using defaults.
Each output operation snapshots its preference before background encoding;
already-running downloads retain that snapshot. Native save/recovery operations
and document sheets reject settings changes while busy.

The version3 File Handling archive preserves recovery intervals and recent files.
Versions1/2 load with `disablePSDCompression:false`; older readers reject version3.
Native settings errors, stale drafts and failed writes preserve previous bytes and
values. Preference changes do not edit documents, change Undo history, modify
existing image files, or change recovery snapshot contents.

Stateless Photato `/v1/action-jobs` and Adobe `/v2/execute-actions` retain their
own output contracts and do not inherit desktop preferences. There is no Adobe
application-preferences endpoint in the pinned v2 contract. No Adobe route or
field is added. `Maximize PSD and PSB File Compatibility` and its output framing
remain outstanding. Current guidance is recorded in the [Adobe performance
reference](https://helpx.adobe.com/photoshop/desktop/troubleshoot/performance-stability-issues/fine-tune-photoshop-features-for-performance.html).


### Original PhotoCraft project input (step153, qualified subset)

Photato adds `pcraft` to `X-Photato-Open-Format` and accepts original PhotoCraft v1 ZIP bytes with `Content-Type: application/vnd.photocraft.project` on `POST /v1/documents/import`. The registered native Open type is `org.photocraft.project`; the MIME/type names describe this local adapter, not a published Adobe format. Format recognition inspects the container/manifest instead of trusting its extension. Upload limits remain64MiB,4,194,304 canvas pixels and128MiB native document memory. Native Open additionally reads stable directory projects; choose **PhotoCraft Project** in the format selector to select a directory.

The shared Swift adapter retains supported RGB8/16/32 raster layers, nested groups, visibility, opacity, blend/clipping settings, protection, color labels, independent grayscale masks, vector masks, saved/work paths, GRAY8 selections and RGB profiles. Pixel tiles retain off-canvas data and hidden RGB. Float32 samples remain linear and retain their bits. IDs map deterministically from exact source UInt64 IDs; `pcraft.manifest` in native source metadata is original provenance, never current editable state. Imported documents have no writable source association: Save As creates a Photato document and leaves the original project unchanged. Existing editing commands, undo/redo and native downloads operate on the imported model. Partial protection requires explicit native archive version12 for API downloads.

`POST /v1/action-jobs` accepts the same ZIP subset as a resource input and produces its existing output formats through the same engine. Existing action, canvas,64-layer,64MiB resource and128MiB model limits still apply. `/v2/execute-actions` and `/v2/create-composite` retain Adobe input policy and reject `.pcraft`; no Adobe route or field was invented. `documentOpening.pcraft` and `actionJobs.photatoAdditionalInput` report the separate scopes.

Unknown fields or unrepresented features reject the entire import with the existing decode/job error envelope. This includes non-RGB modes, nonzero unbounded raster defaults, explicit empty/off-canvas/high-precision selections, fill opacity, fill/adjustment/type/shape/Smart Object content, effects, artboards, auxiliary channels, guides, patterns, comps, timeline and unsupported metadata. No preview is flattened as a substitute. Native editable import is bounded to512layers,1,025surfaces,16MiBmanifest,4MiBprofile blobs and512MiBsource payloads; caller raster limits further bound decoding and allocation. This is a migration subset, not complete PhotoCraft or Photoshop parity.


### Off-canvas raster-mask feather boundaries (step154, qualified boundary repair)

The shared native mask sampler uses outside-mask coverage at a canvas edge when the raster layer extends beyond that edge. Canvas-contained raster controls retain the prior edge-extension behavior. This correction applies to desktop preview, Apply Mask and exports, Photato imports/previews/downloads, and output from both Photato and Adobe-compatible action jobs. It adds no routes, commands or schema fields. Permission, validation and isolated-job lifecycle rules are unchanged.

The new Photoshop reference controls qualify this boundary condition only. The Gaussian feather kernel, vector edge coverage and broader Photoshop byte equivalence remain open; see the step154 development record. Scaled/rotated raster and group/other-content boundary behavior requires further independent qualification.

## Native raster filters (step157)

`filter.apply` adds a prepared, undoable command on an existing shared pixel layer:

```json
{"command":"filter.apply","revision":"<current revision>","parameters":{"layerID":"<layer UUID>","filter":{"kind":"unsharpMask","amount":100,"radius":2,"threshold":3}}}
```

Filter kinds: `gaussianBlur`, `boxBlur`, `motionBlur`, `unsharpMask`, `highPass`, `addNoise`, `mosaic`, `average`. `/v1/capabilities` exposes `filters` with a strict per-kind schema, targets and limits. All parameters besides `kind` are optional and use the native dialog defaults. Unknown parameters, wrong types and out-of-range values reject without editing. RGB8/16 operate on encoded samples; RGB32 operates on linear samples. Pixel selections use document coordinates; masks and layer composition metadata remain intact. Transparency protection preserves alpha. Composite component/mask targets are unavailable. Existing API sharing, revision, busy, cancellation and resource limits still apply. The filter engine caps raster layers at8,388,608 pixels; API document/job limits may be smaller.

| Kind | Parameters (default) |
|---|---|
| gaussianBlur / highPass | radius0.1–1000 (5) |
| boxBlur | integer radius1–1000 (5) |
| motionBlur | angle−360–360 (0), integer distance1–2000 (10) |
| unsharpMask | amount1–500% (50), radius0.1–1000 (1), integer threshold0–255 (0) |
| addNoise | amount0.1–400% (10), distribution uniform/gaussian (uniform), monochromatic boolean (true), UInt32 seed (1) |
| mosaic | integer cellSize2–200 (10) |
| average | no parameters; averages selected raster samples |

The existing `/v1/action-jobs` and Adobe-compatible `/v2/execute-actions` use the same engine. Inline actionJSON uses `$Avrg` for Average, `boxblur` for Box Blur, and the other kind names as action events (the local aliases `average` and `boxBlur` also work). Explicit parameters: pixel quantities as `{"_unit":"pixelsUnit","_value":5}`, angle as `angleUnit`, amounts as `percentUnit`, numeric threshold, and noise distribution `{"_enum":"distribution","_value":"uniformDistribution"}` or `gaussianDistribution`. Noise requires boolean `monochromatic`; the local Adobe adapter uses seed1 and does not invent an Adobe seed field. Generic action options remain supported as before. These are raster edits with existing native/PSD/PSB/TIFF persistence, not Smart Filters. Gaussian uses three running-box passes, Motion Blur at most257 line samples, and Photoshop numerical equality is unqualified. Full endpoint conformance is still partial.


## Editable layer styles (step158)

`layer.style` replaces the entire style for one to64 unique `layerIDs` in one native Undo transaction. `style: null` clears it. Omitted style fields use native defaults; unknown fields and invalid values reject. Read `layers[].style` to copy a complete style, including complex gradient/pattern definitions. Capability discovery includes `layerStyles.schema`, kinds, bounds and limitations. Full locks, busy drafts and stale revisions use the existing shared edit guards. Styles are independent of the pixel selection.

```json
{"command":"layer.style","revision":"CURRENT_REVISION","parameters":{"layerIDs":["LAYER_UUID"],"style":{"effects":[{"kind":"dropShadow","opacity":0.6,"size":12,"distance":18},{"kind":"stroke","size":3,"color":{"r":1,"g":1,"b":1,"a":1}}]}}}
```

Kinds: `bevelEmboss`, `stroke`, `innerShadow`, `innerGlow`, `satin`, `colorOverlay`, `gradientOverlay`, `patternOverlay`, `outerGlow`, `dropShadow`. The native engine currently supports32 effects and8,388,608 canvas pixels. Colors are SDR RGBA0...1, blend names are the native display names. Gradient/Pattern Overlay require the corresponding native `GradientFill`/`PatternFill` object; pattern IDs must exist in the document. Exact source schemas are in `LayerStyle.swift`, `GradientFill.swift`, `Gradient.swift` and `PatternFill.swift`, and complete objects are observable in state.

Native downloads of styled documents require `X-Photato-Archive-Version: 13`; desktop Save automatically selects13. Older version requests reject with422 instead of losing effects. PSD/PSB retain the represented shadows,glows,solid strokes and color overlays. The remaining four effects require a native original or explicitly flattened raster output. Styled merge and unsupported PSD/TIFF descriptor variants reject. Style rendering is approximate; per-style shared light, simple Inner Bevel and bounded canvas sampling are not full Photoshop semantics.

The existing Adobe `POST /v2/create-composite` edit subset now accepts published `layerEffects.dropShadow` arrays (1–10) for an existing unique name/PSD id. Native distance supports the published0...30000 integer range; size0...250,opacity/spread0...100 and local angle−180...180. `color` uses `{"rgb":{"red":255,"green":0,"blue":0}}`. Other defined but unrepresented contour/noise/knockout variants return explicit unsupported errors. Effects on groups are unsupported in this adapter. Adobe group-protection behavior is unchanged; no custom Adobe route or Photato-only JSON property is invented. Hosted defaults, model execution and exact Adobe pixel results remain unqualified. There are now23 executable Photato typed commands; three Adobe routes remain partial and five remain unimplemented.

## Classic adjustments (step163)

There are40 typed commands. `adjustment.create` takes `adjustment` plus an optional `name`, creates an editable layer and builds its mask from the selection. `adjustment.set` takes `layerID` and a complete `adjustment` description of the existing kind; omitted settings use defaults. `adjustment.apply` takes `layerID` and `adjustment`, bakes an ordinary RGB pixel layer within the selection and commits one native Undo edit. Smart Object/component/mask targets reject. Creation and editing retain native layer history, masks, opacity and blending.

Example parameter object: `{"adjustment":{"kind":"vibrance","vibrance":40,"saturation":-10}}`. Kinds are `vibrance`, `blackWhite`, `photoFilter`, `channelMixer`, `selectiveColor`. Discover strict per-kind schemas/defaults/limits in `capabilities.classicAdjustments`; read `layers[].classicAdjustment` for current values. Unknown/wrong-typed/out-of-range fields reject before mutation. All three commands use the prepared native transaction, reject component/mask targets and validate candidate layer/memory limits before commit. Standard revision/busy/permission/resource guards apply. Native downloads retaining these layers require `X-Photato-Archive-Version: 17`; older versions return422. The minimum stays unchanged for older content.

Percentages are integers. Black & White `weights` has six entries: Reds,Yellows,Greens,Cyans,Blues,Magentas (−200...300), with optional `tint` RGBA or null. Photo Filter takes opaque normalized `color`, `density`0...100 and `preserveLuminosity`. Channel Mixer `matrix` has three output rows (RGB), each with four source percentages (RGB plus Constant, −200...200); `monochrome` uses row0 for gray. Selective Color `adjustments` has nine CMYK rows (Reds,Yellows,Greens,Cyans,Blues,Magentas,Whites,Neutrals,Blacks), −100...100, and `relative` boolean. RGBA colors require alpha1. These are bounded PhotoCraft approximations, not qualified Photoshop-exact results.

Adobe `POST /v2/edit` now accepts the pinned `EditRequest` subset: URL image input, optional `edits.color.vibrance` and `.saturation` (integers −100...100), and one to25 PNG/JPEG outputs with a destination and optional corresponding compression/quality. It edits the input composite in an isolated native document, then uses the existing202/status/job/asset lifecycle. Other Lightroom options, RAW/XMP, presets, white balance and Creative Cloud resources return explicit unsupported errors. Input support is local PNG/JPEG and represented PSD/PSB/TIFF, with existing bounds. No Adobe Camera Raw numerical equivalence is claimed.

The execute-actions route additionally recognizes `vibrance`, `blackAndWhite`, `photoFilter`, `channelMixer` and `selectiveColor` actionJSON subsets. Colors use `RGBColor` with `red`, `grain` and `blue`; unsupported descriptors and contexts fail explicitly. Current coverage is five partial and three unimplemented published routes. Request schema and native job behavior are tested; independent Photoshop action captures and output fidelity remain open. See [evidence](CLASSIC_ADJUSTMENT_REFERENCES.json).

## Color Lookup LUT grading (step164)

The existing40 typed commands now include Color Lookup in `adjustment.create`, `adjustment.set` and `adjustment.apply`. `{"kind":"colorLookup","preset":"warm","dither":false}` selects a generated Photato look. Use `lutID` instead of `preset` for an uploaded table; omit both for identity. `interpolation` is `trilinear` (default) or `tetrahedral`; `dither` defaults to true. Set replaces the settings. Native selection masks, locks, one-step history and stale/busy guards apply.

With document uploads/downloads enabled, `POST /v1/luts` accepts raw `application/octet-stream` data and `X-Photato-LUT-Name` containing a percent-encoded basename ending in `.cube`, `.3dl` or `.look`. The201 response has `lutID` and `lut` metadata. Uploads allow64MiB per file,16 cached tables and 64MiB total retained cache memory. `GET /v1/luts` lists the session cache; `POST /v1/luts/clear` with an empty body clears it. Stop or disabling transfers also clears the cache; tables already assigned to layers remain embedded.

`GET /v1/documents/{shareID}/layers/{layerID}/lut` downloads the original imported bytes or a generated Cube. Optional `X-Photato-Revision` prevents stale exports; revocation and concurrent edits are checked again after encoding. Read the filename and table metadata from `layers[].colorLookup.lut`; the state also includes interpolation/dither. No arbitrary filesystem paths are accepted. Discover the detailed schemas/routes/limits in `capabilities.colorLookup`. Editable native output requires `X-Photato-Archive-Version: 18`; older explicit versions reject. Blank and Tetrahedral LUT layers require native saving; PSD/PSB supports loaded Trilinear tables within its16MiB descriptor bound. Little-endian layered TIFF clrL, ICC abstract/device-link and CSP are not yet supported.

Adobe and Photato action jobs accept a bounded `colorLookup` descriptor with `lookupType` enum `colorLookupType/3DLUT`, `LUTFormat` enum `LUTFormatType/LUTFormatCUBE` (or3DL/LOOK), `dataOrder` enum `colorLookupOrder/rgbOrder`, `tableOrder` enum `colorLookupOrder/bgrOrder`, `LUT3DFileName`, `LUT3DFileData:{"_rawData":"base64","_data":"…"}` and optional boolean `dither`. Put the descriptor array string in the existing `options.actions[].source.content` with `contentType:application/json`. The51,200-character inline-program limit still applies; use the Photato upload route for ordinary large LUTs. Arbitrary local paths, abstract/device-link profiles and unsupported descriptors reject. The create-composite contract has no corresponding LUT adjustment entry, so no Adobe extension route was invented. Exact Photoshop action/rendering qualification remains open. [Provenance and test evidence](COLOR_LOOKUP_REFERENCES.json).


## Liquify (step165)

Use `filter.apply` with `filter: {"kind":"liquify","liquify":{...}}`. Pixel layers bake the result; Smart Objects append an editable filter, and `smartFilter.set` replaces its settings in the same native history path. State returns the full program. Native downloads of editable Liquify require `X-Photato-Archive-Version: 19`. Unsupported PSD/PSB mesh interchange fails explicitly; flatten/rasterize deliberately or save native to retain editability.

A minimal program is `{"width":640,"height":480,"strokes":[{"tool":"forwardWarp","size":100,"points":[[200,200],[240,210]]}]}`. Coordinates are target pixels, y down, with optional third-component pressure0…1. Zero/omitted width and height use the current target; saved dimensions scale the mesh on another target. Smart Objects use the placed filter canvas. Brush defaults are size100, density50, pressure100 and rate80. Supported tools and face parameter names/ranges are advertised in `filters.liquify`; unknown keys/invalid values reject atomically. Limits:8,388,608 pixels,2,048 strokes,32,768 total points,16 faces and250million visited mesh nodes. POST document command bodies allow4MiB; other route limits are unchanged.

`liquify.faces` takes a `layerID` and optional existing `filterID`, with the normal current revision. It returns `{revision,width,height,faces}` from local Apple Vision without editing the document or history. Each face contains normalized `[x,y,width,height]` bounds for `bounds,leftEye,rightEye,nose,mouth`. Supply these as `faces:[{"geometry":...,"parameters":{"smile":30}}]` in the Liquify program. Parameters default to0 and range−100…100. Detection can return an empty list or fail if the local model is unavailable. Concurrent/stale/revoked sharing rejects the result. Freeze masks protect face warps as well as brush deformations.

Mesh import/export uses UTF-8 JSON `{"format":"PhotatoLiquify","version":1,"settings":...}` in `.photatoliquify` files (maximum4MiB), the same settings used by the UI and API. Local workspace Undo, zoom/pan and overlays are presentation state; API clients manage their own preview presentation and can use normal document preview after an undoable edit. Shared-mask/blending effects apply through the existing Smart Filter pipeline.

Adobe's published execute-actions envelope remains supported for the previously documented action subset. Adobe Liquify mesh descriptors, Photoshop `.msh` files and exact proprietary face deformation are **unsupported**, with explicit errors rather than invented compatible JSON. These open gaps do not remove existing Adobe routes. See [Liquify references and limits](LIQUIFY_REFERENCES.json).


### Alpha channels and Quick Mask (step167)

`channel.edit` adds shared native history transactions for create/delete/duplicate/rename/move, saveSelection/loadSelection, quickMask, options, stroke/fill/invert and filter. `channel.view` selects an alpha UUID, `quickMask` or `RGB`, with an optional overlay flag. Read `/v1/capabilities` for parameter schemas and action names. Parameter names not applicable to an action are rejected; revision, busy, share revocation and resource limits apply. Channel state includes IDs, names and overlay settings; `channel-preview.png` uses the shared channel view and `preview.png` stays the image composite.

Example parameters for `channel.edit`: `{"action":"saveSelection","name":"Subject"}`; then `{"action":"loadSelection","target":"<channel UUID>","mode":"replace","invert":false}`. Quick Mask uses `{"action":"quickMask","enabled":true}`; painting uses `{"action":"stroke","target":"quickMask","points":[{"x":20,"y":30}],"size":20,"value":0}`. Black protects, white selects. `options` accepts `overlayColor` (three RGB numbers), `opacity` and `indicates` (`maskedAreas`/`selectedAreas`). `fill` requires value0–1; stroke also accepts hardness/opacity0–1 and pressure0–1. All coordinates are document pixels. The channel engine keeps layer pixels unchanged.

Native downloads containing channels require `X-Photato-Archive-Version: 20`. Alpha planes retain document8/16/32-bit depth; loaded selections currently use GRAY8. PSD/PSB channel export is explicitly unsupported; preserve edits in Photato. Flat image exports contain the composite. Dedicated published Adobe endpoints do not cover these operations; Adobe channel actionJSON descriptors remain unsupported. This increment raises typed Photato commands42→44 without changing existing clients. See [channel evidence](ALPHA_CHANNEL_REFERENCES.json).


### Content-Aware Fill (step168)

`contentAware.fill` fills the current selection on an ordinary raster layer using the same native synthesis and prepared history edit as the desktop workspace. Supply `layerID`; `output` is `current`, `new` (default), or `duplicate`. Settings and strokes are optional. Read `/v1/capabilities` for the settings/stroke schemas and limits. Document state reports availability and whether the workspace is open. A desktop workspace blocks concurrent API document editing; stale revisions, invalid settings and sharing revocation cannot publish an edit.

Example parameters:

```json
{
  "layerID": "<layer UUID>",
  "output": "new",
  "settings": {
    "sampling": "auto",
    "colorAdaptation": "default",
    "rotation": "none",
    "scale": false,
    "mirror": false,
    "sampleAllLayers": false,
    "seed": 1
  }
}
```

Sampling accepts `auto`, `rectangular` (with `margin`, default 64), and `custom`. Custom sampling starts from an optional `samplingChannelID` or an empty source region; add sampling strokes when no saved alpha channel is supplied. `strokes` contain `target` (`sampling` or `selection`), `kind` (`brush` or `lasso`), `add`, `size` and `points` as `[x,y]` document coordinates. Selection strokes run first, then sampling strokes; the resulting selection is retained in the output. Source sampling excludes the fill area and transparent pixels. Color adaptation accepts `none`, `default`, `high`, `veryHigh`; rotation accepts `none`, `low`, `medium`, `high`, `full`. Scale and mirror permit transformed source patches. An unchanged seed produces deterministic output for identical inputs.

The canvas/source budget is 16,777,216 pixels. The synthesis region, including transformed sampling variants, is limited to 4,194,304 pixels. At most 256 strokes and 16,384 total stroke points are accepted. Unknown settings, invalid ranges and a source region with no usable pixels fail explicitly. Output preserves the document depth/profile; RGB32 retains HDR values. One native transaction covers the output and selection, including Undo/Redo. No archive version change is required by this operation.

There is no dedicated CAF endpoint in the pinned Adobe Photoshop v2 contract. Content-aware actionJSON descriptors remain unsupported; Photato does not invent an Adobe route or claim Adobe model/pixel equivalence. The typed Photato catalogue increases from 44 to 45 operations. See [fill evidence](CONTENT_AWARE_FILL_REFERENCES.json).


### Content-Aware Scale (step169)

`contentAware.scale` resizes an ordinary raster layer or its selected pixels with the same native seam-carving and history edit used by the canvas transform. Required parameters are `layerID`, `width` and `height` (integer output pixels). Optional integer `x`/`y` set the output top-left in document coordinates; omitted coordinates retain the original region center, rounded down to an integer origin. `amount` is0–100 (default100); zero uses ordinary bilinear scaling. `protectChannelID` names a saved alpha channel; `protectSkinTones` enables the native RGB skin heuristic. Both protection sources can be combined.

Example parameters:

```json
{
  "layerID": "<layer UUID>",
  "width": 1200,
  "height": 800,
  "amount": 100,
  "protectChannelID": "<alpha channel UUID>",
  "protectSkinTones": true
}
```

The selected region is its nonzero coverage bounds; otherwise the operation uses the whole transformed layer, including off-canvas storage. Selection coverage follows the same seams as the image and moves to the output. The layer name, effects, depth and working profile are retained. Whole-layer masks use geometric linked/unlinked mapping; selected-pixel edits preserve mask positions. Nonlinear seam deformation of masks is not yet qualified. No archive schema change is required.

The maximum dimensions are60,000 pixels per side, with16,777,216 pixels per source/output/intermediate buffer and a500,000,000 estimated seam-pixel processing budget. The latter limits the total requested change as well as image size. Image, position and transparency locks must be clear. Schema/type errors, invalid ranges, unavailable protection channels and processing limits fail explicitly. The desktop preview is cancellable and cannot be overwritten by a stale request. Both desktop and API commits use one undo transaction; busy/stale/revoked API edits cannot publish results.

State exposes transform availability, preview activity and errors; `/v1/capabilities` describes bounds and semantics. This raises the Photato typed catalogue from45 to46 operations. Adobe's pinned v2 contract has no dedicated content-aware-scale endpoint; its actionJSON descriptor remains unsupported. Exact Photoshop pixels and live interaction remain unqualified. See [scale evidence](CONTENT_AWARE_SCALE_REFERENCES.json).


### Crop, straighten and edge fill (step170)

`document.crop` accepts integer `x`, `y`, `width` and `height` in original document pixels. The rectangle can extend outside the old canvas. Optional `angle` is the clockwise crop-frame angle in degrees; the output applies its inverse rotation to straighten the image. The canvas becomes `width`×`height` without resampling to a different resolution. Original working profile, depth and resolution are retained.

```json
{
  "x": -100,
  "y": -60,
  "width": 1400,
  "height": 960,
  "angle": 2,
  "deleteCroppedPixels": false,
  "fill": "contentAware",
  "seed": 1
}
```

`deleteCroppedPixels` defaults to true and trims ordinary raster image storage. False retains off-canvas raster content with editable affine geometry. Smart Object source documents, vector/type data and masks remain editable. Saved alpha channels and paths follow the canvas transform; the active selection is cleared. The desktop's preview/commit/cancel and API use one shared prepared edit and Undo/Redo transaction.

`fill` accepts `transparent` (default), `background` and `contentAware`. Background uses optional `backgroundColor` as three0–1 RGB values, default white. Fill targets gaps exposed outside the original canvas; interior transparency remains untouched. Existing retained off-canvas pixels are reused. Fill output is an additional editable raster layer. `seed` is an optional unsigned32-bit deterministic variation seed.

Dimensions are1–60,000 pixels per side, limited to16,777,216 source/output canvas pixels. Deleting cropped pixels has a64MP total raster processing budget. Content-aware fill currently allows up to4,194,304 output pixels. Invalid types/ranges, missing source samples and exceeded budgets fail explicitly. Desktop draft state blocks API mutation; stale revisions, cancellation and sharing revocation cannot publish partial results. State exposes crop availability and preview activity/error; `/v1/capabilities` describes current limits.

The Photato catalogue now contains47 typed operations. Adobe's `/v1/auto-crop` in the v2 GA contract is a separate automatic detection workflow; this manual crop operation does not implement it. Manual crop actionJSON remains unsupported. See [crop evidence](CROP_WORKFLOW_REFERENCES.json) for pending Photoshop fidelity and advanced options.


### Patch, Content-Aware Move and Red Eye (step171)

All three operations use the same prepared Swift edit as the desktop, with revision validation, busy-state rejection, cancellation on revoked sharing and one history transaction. They require an unlocked ordinary raster layer. Results preserve depth, layer/mask placement and transparency protection; RGB image targets are supported. The catalogue now has 50 typed operations. `state.regionRetouch` reports availability, selection presence and preview state; `capabilities.regionRetouch` describes limits.

- `retouch.patch`: required `layerID`, integer `dx`, `dy`. Optional `mode` (`source` or `destination`), `type` (`normal` or `contentAware`), `diffusion` (1–7, default 5), `transparent` (false), `structure` (1–7, default 4), `color` (0–10, default 0), `sampleAllLayers` (false), `seed` (UInt32, default 1). Source repairs the current selection using the dragged-to region; Destination repairs the dragged-to region using the selected pixels. Both regions must remain inside the canvas.
- `retouch.move`: required `layerID`, `dx`, `dy` in document pixels. Optional `mode` (`move` or `extend`), `scaleX`/`scaleY` (1–1000%, default 100), `angle` (−360…360°, default 0), `structure`, `color`, `sampleAllLayers`, `seed`. Transform centers on the selection; Move fills its vacated area, while Extend retains it. The result selection follows the destination.
- `retouch.redEye`: required `layerID`, integer `x`, `y`, `width`, `height`. Optional `pupilSize` (1–100%, default 50) and `darken` (0–100%, default 50). This is a bounded red-dominance correction, preserving neutral highlights, alpha and selection clipping.

The canvas budget is 16MP and the temporary retouch/solve region budget is 4MP. API-wide transfer/document limits also apply. Invalid parameters return 400; stale or busy edits return 409. Settings and availability are discoverable through the typed schemas. Pattern Patch, mask/channel targets, exact Adobe output and complete preference persistence remain open. No dedicated Adobe v2 endpoint corresponds to these tools; the generic execute-actions descriptors remain unsupported rather than being silently approximated or assigned invented routes.


## Image stacks (step178)

`document.imageStack` creates a new shared unsaved document from `sources:[{"id":"shared UUID","revision":"current revision"},…]` with optional `name` and `settings:{"align":false,"createSmartObject":true,"mode":"median"}`. Two to seven unique sources must include the command target; enable document transfers and leave one sharing slot. No local paths are accepted. `createSmartObject` defaults false, `align` false, `mode` none. A statistical mode requires `createSmartObject:true`. Source files/documents/history remain unchanged. Each input composite becomes a retained photo layer in the first input's working profile/depth, with maximum input width/height as canvas. Optional shared Auto alignment retains that canvas.

Modes: `none`, `entropy`, `kurtosis`, `maximum`, `mean`, `median`, `minimum`, `range`, `skewness`, `standardDeviation`, `summation`, `variance`. Change an existing instance with `smartObject.stackMode`, `parameters:{"layerID":"UUID","mode":"mean"}`. This is one ordinary Undo transaction. Source replacement/edited-content saving preserves each instance's own mode and re-renders its cache, retaining outer transforms, masks and Smart Filters. Removing a mode restores ordinary compositing. RAW source replacement rejects when it cannot retain a statistical mode.

Creation returns HTTP201 document state plus `imageStackResult:{sourceCount,aligned,mode,smartObject}`. Participating sources expose `imageStack.operationID`; `document.imageStack.cancel` with that UUID requests cancellation. No publication occurs after cancellation, revoked permissions/shares, stale source revisions or conflicting lifecycle work. Refresh revisions after cancellation. Invalid request400, missing permission403/source404, stale/busy409, limits413, unsupported processing422 and share capacity429 use the existing envelope. Global `imageStackState` exposes native open/loading/rendering/sourceCount/ready and API creation state. Layer Smart Object state includes its mode and revision. Mode changes apply only to the addressed instance; edited source contents still update ordinary shared instances.

Native23 retains editable statistical metadata. Native downloads require `X-Photato-Archive-Version: 23` for these documents; lower declarations reject. PSD/PSB statistical export rejects explicitly, so use native files for editable stacks or flattened raster exports. Native supports2–16 sources,8MP per canvas and16MP combined sample grid; existing Smart Object64MiB source/256MiB decoded and API4MP/64layers/128MiB caps apply. Population variance and normalized entropy/skewness/kurtosis follow PhotoCraft.8/16-bit samples clamp/quantize;32-bit sums preserve HDR range. These are documented working conventions, not Photoshop byte-equivalence claims.

The published Adobe `/v2/execute-actions` and existing `/v1/action-jobs` accept the installed `applyImageStackPluginRenderer` action with `imageStackPlugin:{"_class":"$medn"}` on the active RGB Smart Object. Class mappings are `$avrg` mean, `$summ` sum, `$minn` minimum, `$maxx` maximum, `$medn` median, `$vari` variance, `$stdv` standard deviation, `$skew` skewness, `$kurt` kurtosis, `$rang` range and `$entr` entropy. Optional `name`/`$Nm  ` is descriptive text. Unknown fields/classes reject; this does not run plugins. Use flattened PNG/TIFF output until editable PSD transport is supported. No dedicated Adobe source-loading endpoint is invented. [Evidence and limits](IMAGE_STACK_REFERENCES.json).

## Artboards (step183)

`artboard.edit` uses the normal command envelope and current revision. `operation` is `create`, `convert`, `configure`, `duplicate`, `guides.clear` or `ungroup` (removes board metadata while retaining the group). Create requires `name` and `bounds`, with optional top-level `layerIDs` and `background`. Convert requires `layerID` and `bounds`, with optional background. Configure requires `layerID` and bounds, with optional name/background/guides/moveContents (default true). Duplicate requires layerID and destination bounds of the unchanged source size, with optional name. Clear/ungroup require only layerID. Irrelevant parameters reject.

Bounds contain integer x/y/width/height in logical pixels. Negative coordinates expand/rebase the physical canvas without resampling; document state exposes originX/originY. Background is RGBA0–1; guides are axis horizontal/vertical and finite local pixel position, at most512. Native schema discovery describes limits. Each edit is one native prepared transaction with matching Undo/Redo, lock/selection/structure validation and stale/busy/revocation guards. Layers expose dimensions/background/preset/guides. Presentation-only names/guides visibility is observable state.

`artboard.export` requires `layerIDs` and `format` (`png`, `jpeg`, `tiff`, `photato`, `pdf`), document transfers enabled and the current revision. Image/native formats require one board; PDF accepts multiple distinct board IDs in output order. It returns binary bytes with the matching Content-Type and preserves document/history. Output is capped at128MiB and stale/revoked results are discarded. Native artboard downloads through the ordinary file route require `X-Photato-Archive-Version: 27`; per-board `photato` exports explicitly use the current native format.

`POST /v2/create-artboard` follows the pinned Adobe request envelope with1–25 `images` (URL source, optional1–255-character name), optional integer `artboardSpacing` (local subset0–32768; default50), and1–25 outputs. The shared engine arranges source composites horizontally as raster children in real native artboards. Existing resource-job authentication/enablement,202 response/status polling, hosted expiry and HTTPS PUT transport apply. PNG/JPEG/TIFF and a document/layer/artboard JSON manifest subset are supported. Cloud/embedded storage, PSD/PSDC artboards, output resizing/JPEG scan, full descriptor manifests and exact Adobe image results remain unsupported and reject explicitly. See [evidence and limitations](ARTBOARD_REFERENCES.json).

## Frames (step184)

`frame.edit` uses the normal revision-checked command envelope. Operations and parameters:

- `create`: name, bounds `{x,y,width,height}`, definition; optional layerIDs. Creates an empty frame or groups existing layers.
- `fromLayers`: name and layerIDs; computes their union bounds and preserves editable children.
- `convert`: layerID of a shape/type layer; captures its outline as an empty frame.
- `configure`: layerID and complete definition (required width/height, optional shape/sides/customPath/strokeWidth/strokeColor/strokeAlignment).
- `transform`: layerID, transform `{a,b,c,d,tx,ty}`, optional contents (default true). Applies an affine delta in physical document coordinates; false changes only the frame boundary.
- `contents.transform`: layerID and transform; retains the frame boundary and embedded sources.
- `fit`: layerID, optional fit (`fill`, `fit`, `original`; default fill); requires one image child.
- `clear`: layerID; removes contents while retaining the frame.

Shapes are rectangle/ellipse/triangle/polygon/custom. Custom geometry uses the exposed VectorPath schema, normalized to the dimensions, with closed contours, fill rule and bounded knots. Stroke width is0–1000 document pixels; alignment inside/center/outside and RGBA color. Unsupported/irrelevant fields reject. Existing API canvas/layer/byte budgets and locks apply. Frame definitions and availability/target/shape/sides are visible in state; target and tool options describe desktop presentation. Content operations are independent of that transient desktop target.

`frame.place` takes layerID, sourceDocumentID, sourceRevision and optional fit. It replaces all frame descendants with one editable embedded Smart Object snapshot. Sources must be explicitly shared; source/target revisions, sharing, busy state and cancellation are checked before commit. Each operation shares the native prepared transaction and Undo/Redo. Source bytes survive fit and content transforms. Ordinary native file downloads containing frames require `X-Photato-Archive-Version: 28`; earlier archives reject. Rendered export is supported; editable PSD/PSB frame interchange rejects.

The pinned Adobe v2 contract has no dedicated image-frame operation; its TextFrame schema describes text layout. No Adobe route has been invented. Existing supported Adobe Smart Object commands retain their separate contract, and linked/generative/PSD frame support remains open. [Frame evidence](FRAME_REFERENCES.json).

## Blur Gallery (step185)

Use `filter.apply` with `filter: {"kind":"blurGallery","gallery":{...}}`, or the same filter object in `smartFilter.set`. `gallery.enabled` contains distinct `field`, `iris`, `tiltShift`, `path`, `spin` values. Enabled effects run in that fixed order. Empty enablement is identity. Default settings and strict bounded schemas are published in `filters.blurGallery`; unknown fields reject. The normal layerID/current revision envelope, prepared transaction, locks, cancellation and Undo/Redo apply.

`field`, `iris`, `tiltShift` and `spin` are arrays of at most64 pin records. x/y are normalized source coordinates; blur is source pixels. Iris/spin radiusX/Y and tilt focus/transition are fractions of the shorter source edge. angle/blurAngle are degrees. Iris uses feather/roundness; tilt uses focus/transition; spin uses blurAngle/feather. A common stored Pin schema retains the remaining tool defaults. `paths` has at most16 objects with2–32 normalized points, speed pixels, taper percent, curved and centered flags. Curved paths use Catmull–Rom interpolation.

Bokeh uses lightBokeh/bokehColor0–100 and lightMin/lightMax0–1. Noise uses uniform/gaussian/grain, noiseAmount/noiseRoughness/noiseColor/noiseHighlights0–100, noiseSize0.1–10 and a deterministic UInt32 seed. Spin strobeStrength0–100, strobeFlashes1–30 and strobeDuration0–360 degrees describe bounded explicit exposures. Settings persist with Smart Filters; masks, visibility, blend/opacity and reordering use the existing stack API. Raw raster application bakes one undoable edit; source Smart Objects remain intact.

Editable gallery downloads require native archive29. PSD/PSB gallery descriptor interchange and Adobe blurGallery actionJSON are not qualified and reject explicitly. There is no dedicated route in the pinned Adobe v2 contract, so no route was invented. Raster output continues through supported rendered export paths. Current source limit is8,388,608 pixels; API sharing retains its4MP/64-layer/128MiB limits. Exact Adobe results, full path/motion controls, mask visualization and other limitations remain in [the reference record](BLUR_GALLERY_REFERENCES.json).

## Lens Correction (step186)

Use `filter.apply` with `filter: {"kind":"lensCorrection","lens":{...}}`, or the same object in `smartFilter.set`. Standard layerID/revision, busy/stale guards, selection/locks and one prepared undoable transaction apply. No correction is applied by default. Parameters and defaults appear in `filters.lensCorrection`.

Manual controls are distortion/redCyan/blueYellow/vignetteAmount/vertical/horizontal −100…100, vignetteMidpoint0…100, angle−360…360 degrees and scale5…800 percent. `autoScale` samples all three colour-coordinate borders and searches up to800%; failure to cover rejects. `edge` is transparency/edgeExtension/black/white/color; custom `edgeColor` has four normalized RGBA values. Optional `straighten` contains two distinct normalized `{x,y}` points and adds the nearest horizontal/vertical correction to angle. Smart Object normalization uses its actual filter input after placement and preceding filters.

Provide either an explicit `profile` or `genericFocalLength`12…200mm (35mm equivalent), never both. The generic estimate is the same native lookup as the desktop button and is not manufacturer calibration. Profile fields are name, radial k1/k2, tangential p1/p2, three vignette coefficients and caRed/caBlue radial colour offsets. Profile component toggles are correctDistortion/correctVignette/correctCA. Strict schemas reject unknown/out-of-range/type-invalid fields. Saving/loading desktop settings uses this same JSON representation. Active workspace state includes its settings/tool/preview/grid/zoom/effective scale/history; document edits remain blocked while its desktop draft is open.

The existing Actions API can store/replay the typed filter; `actions.batch` uses the same engine for shared source snapshots, with output-folder permission/revision checks and atomic new-file publication. Native Actions/Batch can also process files. Originals remain untouched. The dedicated File > Automate > Lens Correction dialog remains unavailable.

Editable saving requires native archive30. Editable PSD/PSB lens descriptors and unqualified Adobe lensCorrection actionJSON reject explicitly; no dedicated route exists in the pinned Adobe contract. Rendered exports use existing paths. Source processing retains the8,388,608-pixel limit and API sharing keeps its separate4MP/64-layer/128MiB bounds. Manufacturer profiles, exact Adobe output and other gaps are recorded in [Lens evidence](LENS_CORRECTION_REFERENCES.json).

## Adaptive Wide Angle (step187)

Use `filter.apply` with `filter: {"kind":"adaptiveWideAngle","wideAngle":{...}}`, or the same filter in `smartFilter.set` and recorded Actions/Batch. LayerID/revision, busy/stale guards, locks/selection and one undoable transaction apply. `filters.adaptiveWideAngle` exposes schema/defaults/limitations. No constraints with scale100 is byte-preserving identity.

Settings: model auto/fisheye/perspective/panorama/fullSpherical; focalLength0…200mm (0 uses default); cropFactor0.1…10; scale5…400 percent; interpolation Nearest Neighbor/Bilinear/Bicubic. Auto chooses Full Spherical for an approximately2:1 image, Fisheye for positive equivalent focal length below17mm, otherwise Perspective. Fisheye defaults12mm, other projections24mm. Panorama is cylindrical. This is not camera/manufacturer/Photomerge calibration.

`constraints` contains at most64 objects and128 total segments. Each has `points` (2…32 normalized `{x,y}` source points), optional `closed` (closed polygons need3points), `orientations` and `angles`. Arrays are empty (free/0 defaults) or have one entry per segment. Orientations are free/horizontal/vertical/angle; angles are clockwise degrees from horizontal, −360…360. Consecutive endpoints must differ. Source normalization uses actual filter input after Smart Object placement and preceding filters. Antipodal/horizon-crossing camera curves reject. The same settings JSON can be saved/loaded in the native workspace.

Document state exposes active workspace settings, preview/rendering, tool, zoom, overlays, selected constraint/edge, pending polygon count, resolved model and local history availability. The native draft blocks external document edits. API clients render their own interaction layer while using the shared correction engine. Editable native downloads require X-Photato-Archive-Version:31; old archive negotiation rejects instead of dropping settings. Editable PSD/PSB and unqualified Adobe actionJSON remain unsupported. No corresponding Adobe operation has been invented. Rendered exports continue through existing routes. Limits and unqualified parity are in [Wide Angle evidence](WIDE_ANGLE_REFERENCES.json).

## Vanishing Point (step188)

`filter.vanishingPoint` takes required `layerID` and optional `settings`, `operations`, `newLayer` (false). Omitting settings reuses saved document planes; an empty operations array saves or clears plane metadata without painting. Each request is one cancellable native transaction with existing revision, stale, busy and sharing guards. Desktop drafts block concurrent document edits.

Settings contain `planes` (up to32), `focalLength`0…100000 pixels (0 infers from the first plane, otherwise the longer canvas axis), and optional `{x,y}` `center`. A root plane has four convex `corners` in document pixels. A related plane has an earlier `parent` index, empty corners, `edge` top/right/bottom/left, `angle`0…180 (default90) and `depth`0.05…20 (default1). Resolved scene corners and metric dimensions are exposed in document and workspace state. Invalid geometry rejects before mutation.

Every operation has `kind`, optional `plane` (0), `opacity`0…100 (100) and `clip` (true). Additional fields are:

- `paste`: required `sourceLayerID` referencing a raw raster layer in the original document; optional `at:{x,y}` in plane UV coordinates (0.25,0.25), `width`0.001…20 as a fraction of metric plane width (0.5), `angle`−360…360 clockwise about the paste origin (0). Source aspect is retained in plane metric space.
- `brush`: required `points:[{x,y}]` in document pixels; optional `diameter`1…2000 (40), `hardness`0…100 (50), `color:{r,g,b,a}` with numeric channels0…1 (opaque black).
- `clone`: required `points` and `sourcePoint` in document pixels; optional diameter/hardness as above. Each stroke freezes its visible source including earlier draft operations. The native aligned-source toggle resolves the source point before calling this same engine.

Example parameters, using existing layer UUIDs:

```json
{
  "layerID": "TARGET-UUID",
  "settings": {"planes": [{"corners": [{"x":40,"y":40},{"x":400,"y":70},{"x":360,"y":300},{"x":70,"y":320}]}]},
  "operations": [{"kind":"paste","sourceLayerID":"SOURCE-UUID","at":{"x":0.1,"y":0.1},"width":0.6}],
  "newLayer": true
}
```

Current-layer output preserves placement/masks and applies document selection and transparency/image locks. New-layer output retains the original layer. Smart Object targets require explicit rasterization. Limits are32 planes,256 operations,16,384 points total/4,096 per stroke,128MiB embedded paste sources,8,388,608 canvas/target pixels and134,217,728 raster visits; existing API sharing limits apply as well. Unknown, irrelevant, malformed and out-of-range fields reject.

Native downloads containing saved planes require `X-Photato-Archive-Version:32`; older negotiation and editable PSD/PSB saves reject rather than discard metadata. Raster exports remain available. No dedicated Adobe v2 route exists in the pinned contract; no new route is invented. Unqualified Adobe actionJSON and recorded Actions remain explicitly unsupported. Additional gaps are recorded in [Vanishing Point evidence](VANISHING_POINT_REFERENCES.json).

## Brush Settings and presets (step189)

All three commands use the normal shared-document command envelope and revision. `brush.configure` accepts a `brush` object that recursively patches the current tool without changing document pixels. Its schema in capabilities covers diameter/hardness/opacity/color/backgroundColor/erase and all extended `settings`: tip/spacing/angle/roundness/flips, flow/mode, shape/scatter/texture/dual/color/transfer/pose, smoothing/symmetry, noise/wetEdges/buildUp/protectTexture/locks/seed/zoom. Unspecified fields retain current values. Unknown nested keys, incorrect primitive types, invalid enums and out-of-range values reject. Optional tip bitmaps accept null to clear; each bitmap has required width,height and base64 bytes with exactly one coverage byte per pixel.

`brush.presets` requires an `operation`:

- `list`: return current tool and preset metadata.
- `select`: required presetID; apply capture choices and current section locks.
- `save`: required name; optional group and includeSize/includeToolSettings/includeColor (true,true,false).
- `define`: required name, optional group; capture the visible selected area (or canvas) as inverse-luminance coverage, with cancellation and sharing/state admission before saving the preset.
- `rename`: presetID and name, optional group. `delete`: presetID. `move`: presetID and destination index.
- `import`: data in base64, optional format photatobrushes (default) or abr. Creates independent preset IDs and returns unsupported-ABR warnings.
- `export`: optional presetID (otherwise whole library) and format. Returns base64 data. ABR rejects native color/size capture choices, symmetry and custom airbrush rates it cannot preserve; the native format is lossless for supported native settings.

`paint.stroke` requires `points:[{x,y}]`. Optional sample fields are pressure0…1 (default1), tiltX/tiltY−90…90 degrees, rotation−360…360 degrees, wheel0…1, and monotonic time0…3600000 milliseconds since stroke start. Optional brush recursively overrides the current settings; presetID applies a preset first. Optional target defaults to pixels; layerID defaults to the active layer. layerMask and smartFilterMask require the corresponding existing mask. alpha requires channelID; quickMask requires an active Quick Mask. Irrelevant target fields reject. Each stroke uses a frozen seed/settings snapshot and is one undoable native command. The native canvas routes the same implementation through its selected target.

Example paint parameters:

```json
{"points":[{"x":30,"y":50,"pressure":0.4,"time":0},{"x":130,"y":80,"pressure":1,"time":200}],"brush":{"size":32,"color":{"r":0.2,"g":0.4,"b":1,"a":1},"settings":{"flow":0.4,"seed":12,"shape":{"enabled":true,"size":{"control":"penPressure"}}}}}
```

The body limit is4MiB, inline preset import is at most3000000 base64 characters, and API strokes have1–4096 samples. Desktop files/strokes have higher bounded limits; see capabilities. Native preset files are version1. Actions containing extended brush/tablet data require action-library version2; old version1 actions retain their painter. Painted document pixels need no archive migration (current native32).

The published Adobe execute-actions `options.brushes` resource path and corresponding paint/path descriptors remain explicitly unsupported. No new Adobe route is invented, and ABR interoperability is not Firefly compatibility. Exact Adobe pixels, full ABR fields, physical bristles and live tablet/platform qualification remain open. See [brush evidence](BRUSH_REFERENCES.json).

## Painting and eraser tools (step190)

**Mode storage update (step221):** Native prepared painting and `paint.tool` now reconcile authoritative RGB/Grayscale/CMYK/Lab components, Indexed palette indices and Bitmap bits before returning previews or committing edits. Native reopen restores the same samples. Untouched component bytes and duplicate palette indices remain unchanged; indexed erasure uses the existing transparent entry when present. Automatic Brush/Pencil layers acquire native components where the mode supports layers. Indexed and Bitmap remain flat. `painting.modeStorage` in capabilities describes this behavior; existing command/parameter contracts are unchanged. All supported mode/depth combinations are covered by focused native and HTTP regressions. Exact Photoshop mode-specific availability, color algorithms and Adobe painting descriptors remain unqualified.

`paint.configure` requires `tool` and `options`. It patches the session settings for that tool without painting or adding history. `paint.tool` requires `tool` and `points`; tool is brush, pencil, colorReplacement, mixerBrush, patternStamp, backgroundEraser or magicEraser. Optional brush/presetID and pixel/layerMask/smartFilterMask/alpha/quickMask targets follow `paint.stroke`; optional options patch the selected tool's settings for this stroke. Each successful stroke is one atomic undoable edit, including any automatic layer creation. Failed, cancelled and stale preparation never changes document pixels or consumes Mixer paint. Magic Eraser requires exactly one point.

The options schema is specific to the tool; unknown or irrelevant fields reject. All fractional values below use0…1:

| Tool | Options |
| --- | --- |
| Pencil | autoErase |
| Color Replacement | sampling: continuous/once/backgroundSwatch; limits: discontiguous/contiguous/findEdges; tolerance; replacementMode: Hue/Saturation/Color/Luminosity; antiAlias |
| Mixer Brush | wet, load, mix, flow; sampleAllLayers; loadAfterStroke; cleanAfterStroke; loadSolidColorOnly |
| Pattern Stamp | aligned; impressionist; placement with scale1…1000 percent, angle in degrees and phaseX/phaseY in document pixels |
| Background Eraser | sampling; limits; tolerance; protectForeground |
| Magic Eraser | tolerance; contiguous; antiAlias; sampleAllLayers |
| Brush | Empty options; use the existing brush settings object |

`patternID` is only accepted for Pattern Stamp and must resolve to a document or library pattern. Without it, the selected library pattern is used. Aligned mode retains the previous stroke phase for the same pattern; unaligned starts at each stroke's first point. Explicit placement.phaseX/phaseY overrides that phase. Available pattern IDs are in painting state. Example parameters:

```json
{"tool":"pencil","points":[{"x":20,"y":30},{"x":90,"y":30}],"options":{"autoErase":true},"brush":{"size":6,"color":{"r":1,"g":0,"b":0,"a":1}}}
```

`paint.mixer` changes session paint without document history. `operation:load` accepts optional color (otherwise foreground); `operation:clean` accepts no other fields. `operation:sample` requires x,y and accepts size,layerID,allLayers,solid. Defaults are current brush size, active layer and Mixer sampling settings. Sampling is asynchronous with normal sharing/revision/cancellation admission. A varied load retains at most256×256 source samples; a solid load uses the hotspot color. Native Option-click uses the same preparation. State exposes reservoir, pickup, remaining amount and tip dimensions. Stroke commit applies configured automatic cleaning/loading; cancelled preview leaves those wells untouched.

Color Replacement and the two new erasers require ordinary pixel-layer targets. Other tools can paint grayscale masks/channels; Sample All Layers on those targets rejects. Brush and Pencil create a transparent layer above nonraster content automatically. Background Eraser converts the recognized native Background representation to an ordinary layer and otherwise rejects locked transparency; Magic Eraser paints background color when transparency stays locked. Selection, inherited protection and target transforms are respected. Body limit4MiB, API points1–4096, generated dabs200000, raster visits134217728, individual footprint and Magic canvas16MP. Request bounds fail explicitly.

The new prepared painting operations are not yet replayable recorded Actions; the recorder preserves them as unsupported steps. Tool-specific options/Mixer reservoir are not stored by the existing brush preset format. Adobe execute-actions brush resources and tool descriptors remain an explicit compatibility gap; no new Adobe HTTP route is claimed. Native archive version remains32. See [painting evidence](PAINT_TOOL_REFERENCES.json).


## Adjustment Brush — step191

The native Adjustment Brush is available through four commands on the existing shared-document command endpoint. All use the normal authentication, current revision, busy and lifecycle guards. Editing responses return the refreshed document state; configuration returns session state without changing document history. Discovery exposes `adjustmentBrush` capabilities and each kind's settings schema/defaults. Native UI and API use the same Swift transaction and Undo path.

| Command | Required | Optional |
| --- | --- | --- |
| `adjustmentBrush.configure` | None | `kind`, `subtract`, `newLayer`, `applyToObject`, `overlay`, `brush` |
| `adjustmentBrush.stroke` | `points` | `kind`, `settings`, `brush`, `layerID`, `newLayer`, `newLayerID`, `subtract` |
| `adjustmentBrush.object` | `x`, `y` | Same optional fields as stroke |
| `adjustmentBrush.edit` | `operation` (`new`, `replace`, `invert`, `mask`) | `layerID`, `kind`, `settings`, `density`, `feather` where applicable |

Kinds are `brightnessContrast`, `levels`, `curves`, `exposure`, `vibrance`, `hueSaturation`, `colorBalance`, `blackWhite`, `photoFilter`, `channelMixer`, `selectiveColor`, `invert`, `posterize`, `threshold`, `gradientMap`. `settings` patches the same-kind existing values or native defaults when changing type. Typed schema/default objects are returned per kind; unknown keys, booleans as numbers and invalid ranges reject. Gradient Map colors accept resolved RGB, HSB or grayscale values.

`configure.kind` sets the default for a new adjustment; use `edit` with `operation:replace` to change an existing layer. Configure toggles object-click mode for the native tool and overlay visibility. `newLayer:true` starts a masked adjustment; it cannot accompany `layerID`. Optional `newLayerID` supplies a UUID only for a newly created layer. Otherwise the current masked adjustment is used, or a new one is created. Subtracting before creating a target rejects. Points use ordinary brush coordinates and sample fields; a partial `brush` overrides the current brush. Mask painting ignores foreground/erase/RGB color dynamics and uses additive or subtractive grayscale coverage.

Example command body (replace the revision with the current shared revision):

```json
{"command":"adjustmentBrush.stroke","revision":"CURRENT-REVISION","parameters":{"kind":"exposure","settings":{"exposure":0.7},"newLayer":true,"points":[{"x":100,"y":100},{"x":180,"y":120}],"brush":{"size":60,"hardness":0.3,"opacity":0.5}}}
```

`object` uses top-left document coordinates and the current visible composite. Apple's local Vision foreground instance at that point supplies coverage, intersected with the current selection. A background/outside point or unavailable model fails explicitly. It does not fall back to cloud processing. Brush opacity does not attenuate the detected object mask; use layer opacity/mask density afterward. Existing masks retain coordinate transforms, density and feather. Locked or disabled masks reject. New adjustment/source pixels remain editable and unflattened.

`edit.new` takes no other parameters and changes the next-stroke session mode. `edit.replace` accepts a kind and partial settings. `edit.invert` accepts only an optional target layer. `edit.mask` takes `density`0…1 and/or `feather`0…100, retaining other mask properties. Irrelevant parameters reject. Each committed stroke/object/replacement/inversion is undoable; cancelled/revoked/stale work leaves the document unchanged. Invalid schemas return400, stale/busy/revoked requests409, unavailable/unsupported editing results retain the existing engine error mapping (for example an out-of-canvas object point422).

State exposes kind/settings, target layer UUID or null, mask density/feather/enabled/inverted or null, `newLayer`, `subtract`, `applyToObject`, `overlay`, and `available`. Limits: request4MiB;1–4096 stroke points and ordinary brush work bounds; object detection8,388,608 canvas pixels/6000 per side; stored object-mask raster16MP. Native archive stays32. Recorded Actions now support library versions1,2,3; version3 stores Adjustment Brush requests and replacement operations with semantic layer targets. Saved object coverage replays without invoking detection again. Existing library limits remain16MiB for native files and60000 base64 characters for API imports; larger recordings can be saved natively but may exceed the API import limit.

No dedicated Adobe Adjustment Brush HTTP route is claimed. The existing Adobe color-adjustment subsets remain supported; masked freehand tool/actionJSON compatibility is still open. Photoshop defaults, complete presets and exact pixel/model parity are unqualified. See [Adjustment Brush evidence](ADJUSTMENT_BRUSH_REFERENCES.json).


## Selection tools — step192

Four commands use the existing authenticated shared-document command endpoint and current revision. Configuration changes tool-session settings without a history entry; editing commands use the desktop's native prepared selection transaction and return updated document state. Discovery includes parameter schemas, `selectionTools` state/result schemas, algorithms, availability and limits. The command catalogue now contains85 operations.

| Command | Required | Optional |
| --- | --- | --- |
| `selection.configure` | None | `mode`, `objectMode`, `sampleAllLayers`, `enhanceEdge`, `overlayColor`, `brush` |
| `selection.quick` | `points` | `brush`, `mode`, `layerID`, `sampleAllLayers`, `enhanceEdge` |
| `selection.object` | `region` | `mode`, `layerID`, `sampleAllLayers`, `enhanceEdge` |
| `selection.brush` | `points` | `brush`, `mode` |

Selection `mode` is `replace`, `add`, `subtract` or `intersect`. Configuration applies an explicit mode to both object and painting defaults. Omitted editing modes use the matching native default. `objectMode` is `Rectangle`, `Lasso` or `Object Click`; it configures the desktop interaction, while API regions are explicit. Configuration does not select a toolbar tool. `brush` partially overrides native Brush Settings. Points use ordinary stroke coordinates/pressure fields, with1–4096 samples. Unknown keys, boolean numbers, nonfinite/out-of-range values and malformed region alternatives reject.

Object `region` must contain exactly one of `point`, `rectangle`, or `polygon`:

```json
{"command":"selection.object","revision":"CURRENT-REVISION","parameters":{"region":{"rectangle":{"x":40,"y":30,"width":280,"height":200}},"mode":"replace","sampleAllLayers":true}}
```

A point is `{"point":{"x":120,"y":90}}`; a polygon is `{"polygon":[{"x":20,"y":20},{"x":160,"y":20},{"x":100,"y":120}]}` with3–4096 vertices. Coordinates use the canvas's top-left origin. Rectangle/lasso initialization runs native iterative color-model graph cut. A point uses Apple's local Vision foreground instance at that location; background/outside/unavailable inference fails explicitly without cloud fallback.

```json
{"command":"selection.quick","revision":"CURRENT-REVISION","parameters":{"points":[{"x":100,"y":100},{"x":180,"y":120}],"brush":{"size":32},"mode":"add","enhanceEdge":true}}
```

Quick Selection follows image edges from the stroke using native seeded graph cut and boundary refinement. `enhanceEdge` applies the shared native matting refinement. Sampling uses the selected raster with placement/masks, or visible composite when requested or the source is nonraster. Locked layers may be sampled. An explicit unknown layer rejects. Original image pixels are unchanged.

Selection Brush paints grayscale soft coverage using brush size/hardness/opacity and other applicable native brush settings; foreground color, erase mode and RGB color dynamics are ignored. Add/Subtract accumulate coverage, Replace starts fresh and Intersect combines the painted coverage. Native overlay color defaults to translucent red. Selection mode modifiers and preview cancellation use the existing canvas lifecycle.

State includes `available`, `objectMode`, `objectSelectionMode`, `paintSelectionMode`, `sampleAllLayers`, `enhanceEdge`, `overlayColor` and `previewActive`, plus the existing selection bounds/soft-coverage state. Each editing operation is undoable. Invalid schema requests return400; stale/busy/revoked requests return 409; engine-unavailable or invalid editing contexts retain the existing error mapping. Cancellation does not commit partial coverage.

The API retains its shared-document4,194,304-pixel ceiling and4MiB request limit. Native selection tools allow16MP; Enhance Edge and point inference allow8,388,608 pixels, with point inference also limited to6000 pixels per side. Graphs use at most160000 working pixels before full-resolution boundary refinement. Native brush size is1–2048. RGB-document analysis uses SDR/sRGB proxies; channel/component-specific detection is unsupported.

Native archives remain version32. Action libraries1–4 are readable; version4 saves resulting coverage with original canvas dimensions, so replay does not silently rerun detection. Existing library/import size limits still apply. No dedicated Adobe selection-tool HTTP route is claimed, and corresponding actionJSON descriptors remain unqualified. See [selection-tool evidence](SELECTION_TOOL_REFERENCES.json).


## Sky workflows — step193

Three commands use the authenticated shared-document command endpoint and a current revision. The catalogue now contains88 commands. `selection.sky` and `sky.replace` use the same Swift preparation, validation and Undo transaction as the desktop. `sky.library` manages the same optional persistent user library without editing document pixels or adding document history. Capability discovery includes selection/settings/stroke schemas, `sky` state, result/library-result schemas, defaults and limits.

| Command | Required | Optional |
| --- | --- | --- |
| `selection.sky` | None | `layerID`, `sampleAllLayers`, `settings`, `mode` |
| `sky.replace` | Exactly one of `skyID`, `sourceLayerID` | `settings`, `strokes`, `useSelection` |
| `sky.library` | `operation` | Operation-specific `skyID`, `name`, `data` |

`selection.sky` defaults to composite sampling, replace mode and threshold/softness50. `mode` accepts lowercase `replace`, `add`, `subtract`, `intersect`. `settings` accepts threshold/softness0–100. If detection finds no sky, it returns an error without changing selection/history. Sampling an existing layer follows the native selection preparation. This is a classical source-derived detector running entirely in Swift; it does not invoke cloud AI or download model weights.

```json
{"command":"selection.sky","revision":"CURRENT-REVISION","parameters":{"mode":"replace","sampleAllLayers":true,"settings":{"threshold":50,"softness":50}}}
```

`sky.library` operations are `list`, `import`, `rename`, `delete`, `export`. Import requires `name` plus base64 `data` containing a supported raster image. Rename requires `skyID` and `name`; delete/export require `skyID`; list takes neither. Unknown or irrelevant fields reject. Import validates dimensions before decoding, then validates the decoded document. Export returns the original image bytes as base64. Results include `revision`, `state` and, when relevant, `skyID`/`data`. Updates are atomic and a corrupt persisted library cannot be silently overwritten. Library changes alter API revision, including changes made from the desktop. User images are stored in Application Support/Photato/Skies.photatoskies; tests use isolated libraries.

`sky.replace` uses either an imported library `skyID` or an existing raster `sourceLayerID`; the latter reads its raw source pixels, independent of its visibility/placement. `useSelection:true` starts from current document coverage instead of automatic detection and requires a selection. The source photo and current selection remain retained. Settings are partial overrides of discoverable defaults:

| Setting | Range/default |
| --- | --- |
| `selection` | `{threshold:50, softness:50}`, each0–100 |
| `shiftEdge`, `brightness`, `temperature` | -100–100; each0 |
| `fadeEdge` | 0–100;50 |
| `scale` | 10–500 percent;100 |
| `offsetX`, `offsetY` | Canvas pixels, ±1000000;0 |
| `flip` | Boolean;false |
| `lightingMode` | `multiply` or `screen`;`multiply` |
| `foregroundLighting`, `edgeLighting`, `colorAdjustment` | 0–100;50,0,35 |
| `output` | `layers` or `duplicate`;`layers` |

```json
{"command":"sky.replace","revision":"CURRENT-REVISION","parameters":{"skyID":"IMPORTED-SKY-UUID","settings":{"scale":115,"flip":true,"temperature":12,"output":"layers"},"strokes":[{"points":[{"x":120,"y":80},{"x":140,"y":90}],"size":30,"hardness":0.6,"opacity":1,"add":false}]}}
```

Optional strokes refine the initial mask. Each needs1–4096 canvas-coordinate points and may specify size1–2048(default40), hardness0–1(default0.5), opacity0–1(default1) and add(defaulttrue). Up to128 strokes are accepted, bounded additionally by134217728 cumulative mask-pixel visits. Controls use native mask painting, shift/feather and sky placement. Layer output adds a group with retained sky raster/affine transform, an unlinked canvas mask, clipped sky brightness/temperature and masked foreground/edge adjustments. Duplicate output appends a merged raster result. Both commit once and preserve the original layers. Saved layers remain independently editable; reopening the original replacement dialog settings from output is not implemented.

`sky` state reports availability, workspace/preview activity, current settings/source IDs/manual-selection flag/stroke count and library metadata/revision/error. Invalid schemas return400; stale/busy/revoked requests409; unavailable or invalid editing contexts use existing422 mapping. Async preparation and import check cancellation, document revisions and sharing before mutation. Preview cancellation, document reload and close leave no late output.

Native Select Sky permits16MP; replacement/sky images permit8,388,608 pixels. API sharing remains limited to4,194,304 canvas pixels,64 layers and128MiB; requests remain4MiB. Library import additionally caps base64 at3000000 characters, whereas native files permit16MiB. Library capacity is64 entries/48MiB image payloads/64MiB file. No proprietary bundled skies are shipped.

Native archive version remains32. Select Sky Actions store coverage in Actions4; replacement recording explicitly remains unsupported. No dedicated Adobe v2 sky route or sky actionJSON conformance is claimed. Float32 duplicate recomposition has an open exact-byte gate (observed maximum2.98e-8 on the opaque synthetic fixture); bounded functional tests do not establish Adobe pixel/model parity. See [sky provenance and qualification](SKY_REFERENCES.json).


## Focus Area — step194

`selection.focus` uses the normal authenticated shared-document command endpoint and current revision. It shares the desktop detector, manual brush processing, six output paths and history. The catalogue now has89 commands. Capability discovery includes settings/stroke/output schemas, `focusArea` state and document-result schema.

Required: `layerID` identifying an ordinary raster layer. Optional: `settings`, `output`, `strokes`, `sampleAllLayers` (defaultfalse). With current-layer sampling, placement is respected and its mask/style are removed from the analysis guide. Composite sampling uses the visible document. The existing selection does not constrain detection. Pixel sources remain retained; analysis uses an SDR/sRGB proxy.

```json
{"command":"selection.focus","revision":"CURRENT-REVISION","parameters":{"layerID":"PIXEL-LAYER-UUID","settings":{"autoRange":false,"range":4,"autoNoise":true,"softenEdge":true},"output":"newLayerWithMask","strokes":[{"tool":"subtract","size":30,"hardness":0.8,"points":[[120,80],[140,90]]}]}}
```

Settings partially override these native defaults:

| Setting | Values/default |
| --- | --- |
| `range` | 0–10;5 |
| `noise` | 0–1;0 |
| `autoRange` | Boolean;true |
| `autoNoise` | Boolean;true |
| `softenEdge` | Boolean;false |

Manual range0 selects the entire image. Increasing range selects only sharper regions. Auto overrides its corresponding manual value; disable Auto to apply an explicit value. Native Auto uses an Otsu threshold on normalized local Laplacian energy and a conservative high-frequency noise floor. Exact Photoshop thresholds, numeric ranges and factory defaults remain unqualified. An image with no sharp area yields empty coverage, which can be corrected with Add brushes. There is no cloud or downloaded model dependency.

`strokes` accepts Add/Subtract corrections: `tool` is `add` (default) or `subtract`; `size`1–5000(default30), `hardness`0–1(default0.8), and required `points` as canvas-coordinate `[x,y]` pairs. Refine-edge/lasso tools belong to the separate `selection.refine` operation and reject here. Unknown keys, boolean numeric values, malformed points and invalid enums/ranges reject. Native UI provides a Select and Mask handoff that retains current coverage/output without committing an intermediate document change; subsequent cancellation leaves the source unchanged. API clients can explicitly apply `selection.refine` to focus coverage as a subsequent operation.

`output` supports `selection` (default), `layerMask`, `newLayer`, `newLayerWithMask`, `newDocument`, `newDocumentWithMask`. The first four return200 and one native Undo transaction. New-document outputs return201 with the newly shared document state, require document-transfer permission and available sharing capacity, and leave source pixels/history unchanged. Layer outputs preserve original pixels and geometry; mask output replaces the target pixel mask. Existing lock, layer-count, size and prepared-operation guards apply. New-document processing retains token/revision/permission/sharing/lifecycle checks before publication.

`focusArea` state includes `available`, `workspaceOpen`, `previewBusy`, nullable requested/effective settings, `strokeCount`, `output` and `previewError`. Effective estimates are visible while the desktop Focus workspace is open; API execution itself does not open that workspace. `selectionRefinement.workspaceOpen` now identifies the separate Select and Mask mode. Invalid requests return400, stale/busy/revoked work409, unavailable targets422, and disabled new-document transfers403.

Native analysis/output supports8,388,608 canvas and source pixels, using at most1MP working resolution. API sharing remains4,194,304 canvas pixels/64 layers/128MiB; requests4MiB. Corrections permit1024 strokes,4096 points per stroke,16384 total points and250000000 raster visits. Whole-image detection is cancellable and document close/reload cannot commit late results.

Native archive32 remains unchanged. Focus selection output records explicit coverage in Actions4; mask/layer outputs remain visibly unsupported for recording. The pinned Adobe v2 contract has no dedicated Focus Area endpoint; actionJSON descriptors are unqualified. Native tests and offscreen synthetic UI do not prove Photoshop pixel/model/live/platform parity. See [Focus Area evidence](FOCUS_AREA_REFERENCES.json).

## Live shapes (step199)

`shape.edit` shares native desktop preparation and history. Operations are `create` (definition plus optional name, mode, transform and layerID), `configure` (layerID and definition), and `append` (layerID and component). Modes are `shape`, `path` and `pixels`; Pixels requires an unlocked raster target and respects selection/transparency locks. Path creates/replaces the native Work Path. Components retain primitive geometry, local affine transforms and combine/subtract/intersect/exclude operations. `transform` places the shape's logical origin in document pixels; stored raster bounds may extend outside that origin to retain strokes.

`shape.configure` sets the single-component drawing template, mode, combine operation (null means new layer), and optional presetID. It changes session state/revision without document history. `shape.library` lists, defines from selected path/shape, imports/exports base64 `.photatoshapes`, renames and deletes presets. Import preserves existing preset identities by assigning new IDs on collision. Library changes persist atomically and do not alter document history. A damaged saved library is preserved and blocks writes.

`GET /v1/commands` exposes `shapes` defaults, strict definition/component/paint schemas, result/state schemas, bounds and qualification. Start from `shapes.defaults` and alter the required complete component object; top-level omitted definition fields use native defaults. Solid, none, captured gradients and patterns are supported for fill and stroke. Gradients use native encoded stop colors (`{"rgb":{"_0":{"r":1,"g":0,"b":0,"a":1}}}`), placements and methods. Pattern IDs resolve in the document or native pattern library; new resources are embedded in the same edit. Dash/gap lengths and phase are local pixels. Unknown fields, invalid geometry, missing resources and incompatible targets fail atomically.

Document state exposes `shapes` tool/library availability and each layer's `shape` definition and `shapeTransform`. Revision includes shape tool and preset changes. Existing busy, stale revision, sharing revocation, cancellation and size gates apply. Live shape documents require `X-Photato-Archive-Version: 33`; versions below33 are rejected for these documents. Native Actions5 records shape creation/configuration/components and paint resources; path/pixel mode retains native Undo but broader action recording remains separately qualified.

Limits:64 components,8,388,608 shape rasterization pixels,128 native presets/16MiB file,3,000,000 base64 input characters through the API. Shared document4MP/64 layers/128MiB and request4MiB limits remain. Editable PSD shapes, Adobe `.csh`, exact pixels/defaults and live/platform qualification remain open. The pinned Adobe v2 contract defines no dedicated shape route; proprietary actionJSON shape descriptors are not claimed. Existing Adobe routes remain independently supported.

## Pen and Paths (step200)

Five commands share native geometry/history: `path.configure` sets Pen/Freeform/Curvature/direct/component selection, Curve Fit and component operation; `path.draw` fits freehand samples or interpolates curvature anchors into a saved/work path; `path.edit` saves full cubic geometry, deletes a path, loads a selection or creates a vector mask; `path.trace` converts the current selection into a work path; `path.paint` fills with the current foreground color/opacity or strokes with the current Brush (optional pressure simulation).

`path.draw` requires document-coordinate `points`; `method` is `freeform` (default) or `curvature`. Freeform supports `tolerance`0.5–10; Curvature accepts zero-based `corners`. `closed` defaults false. `pathID` replaces an existing saved path; omitted ID creates/replaces the Work Path, unless `workPath:false` creates a named path. `path.edit` requires `operation`: `save` also requires `path`; `delete` requires `pathID`; `vectorMask` requires `layerID`; `selection` accepts `selectionMode`, `feather`, `antiAlias`. Omitted pathID for paint/conversion uses the desktop-selected saved path/vector mask. `path.paint` takes `stroke:true` for brush painting; `simulatePressure` is rejected for fills. Optional `brush` follows the existing brush schema.

Document `paths` state includes retained saved geometry, selected ID/target/geometry, tool, operation, tolerance, gesture status and editability. `/v1/capabilities` publishes complete path/parameter/result/state schemas. Coordinates use pixels with positive Y downward; anchors and both handles remain editable. Invalid/irrelevant fields reject without edits. Native limits4096 knots/256 components/100000 samples; API draws4096 samples, trace/painting16MP plus existing stricter sharing/body limits. Native drawing cancels on Escape; API preflight rejects active gestures. Prepared edits retain stale-generation/sharing-revocation protection.

This adds no Adobe-only route. The pinned v2 contract has no dedicated Pen/Paths endpoint; unsupported execute-actions descriptors continue to reject explicitly. Exact Adobe curve/brush kernels, magnetic pen, multi-anchor editing, clipping-path export and advanced Fill/Stroke dialog options remain open.


## Advanced typography — step201

`text.create` and `text.set` accept `orientation: "horizontal" | "vertical"`. Styles accept `fontOptions` with `features: [{"tag":"liga","value":0}]`, `variations: [{"axis":2003265652,"value":1}]` and an optional language tag. Axis IDs/ranges come from the installed font; the example is not portable to every font. `font.inspect` takes `font` (PostScript name), optional `start` and `count` and returns supported tags, axes, bounded glyph data and glyphCount. It uses the normal settled-document/revision contract.

`text.glyph` takes `layerID`, `font`, `glyphID`, optional UTF-16 `location` and replacement `length`; defaults append without replacement. It shares native glyph construction and document Undo with the desktop. Unicode scalar splits, invalid glyphs/axes and unknown fields reject before mutation. The full returned type description retains explicit glyph identity. Native downloads containing these fields require `X-Photato-Archive-Version: 34`; Actions containing advanced type creation require version6.

The existing Adobe `/v2/create-composite` text_layer adapter now accepts vertical orientation and normal/small caps through the published fields. Arbitrary features/axes/glyphs/language remain native API extensions. Editable PSD supports a bounded vertical/OpenType subset; axes, glyph overrides and other unrepresented metadata reject. See [advanced typography references](ADVANCED_TYPOGRAPHY_REFERENCES.json) for qualification and remaining gaps.

## Editable shaped text (step202)

`text.layout` takes `layerID` and `settings`; `enabled: false` removes the layout without settings. Modes are `warp`, `path`, `inside`, `block`, `circle`, `arch`, and `bow`. The same geometry object is available in `text.create`, `text.set`, `layers[].text.geometry`, and `capabilities.text.layout`. The registered native command count is107.

```json
{"command":"text.layout","revision":"<current revision>","parameters":{"layerID":"<type layer UUID>","settings":{"mode":"circle","width":300,"height":200,"fit":true,"start":0,"end":1}}}
```

`pathID` copies a saved document path into logical type coordinates for `path` or `inside`; a full local `path` may be supplied in settings instead. Width/height, spacing and baseline offset are pixels before the layer affine transform; start/end are fractions of path length. Preset `warp` takes style, bend, horizontalDistortion, verticalDistortion and vertical axis. Settings replace the layout, defaulting omitted fields. Type remains editable, the logical anchor/mask placement is preserved, and one command creates one Undo transaction. Expensive type edits use the cancellable prepared-operation path. Input errors400, stale/busy409, locks and existing share/budget/revocation guards apply.

Native35 retains geometry and requires `X-Photato-Archive-Version: 35` for downloads; type creation in an action requires Actions7. The pinned Adobe contract has no dedicated shaped-type field or route; editable shaped PSD output rejects explicitly. Vertical/bitmap-glyph layouts, exact Adobe fit/warps, live curved carets/delimiter gestures and independent/platform qualification remain open. [Evidence and limits](SHAPED_TEXT_REFERENCES.json).

## Filter Gallery (step203)

`filter.apply` accepts `filter: {"kind":"filterGallery","artistic":{"effects":[{"filter":"cutout","values":{"numberOfLevels":5}},{"filter":"glowingEdges","visible":true,"values":{"edgeWidth":2}}]}}`. The first effect runs first; the native stack displays that effect at the bottom. `smartFilter.set` edits the same saved stack. Hidden entries retain their settings.

`capabilities.filters.filterGallery` lists all47 effects, six categories, per-effect schema/defaults/choices, work limits and qualification. `values` contains integer numeric controls; choices use zero-based indices and boolean controls use0/1. `visible` is a JSON Boolean. Optional foreground/background/glowColor are explicit RGBA objects in0...1; defaults are black/white/blue, while the desktop captures the current paint colors. Preview/workspace state includes current settings, category, selection, zoom and local Undo availability.

Ordinary raster layers bake pixels; Smart Objects retain editable effects and source pixels. The native/API command uses the same selection, protection, prepared cancellation and document Undo path. Maximum32 effects,8,388,608 source pixels and67,108,864 active effect-pixels. Processing uses encoded RGB and bounds output to0...1, preserving source alpha;32-bit storage is linear. Component/channel targets and external texture files are unsupported.

Gallery Smart Filters require native36 (`X-Photato-Archive-Version: 36` for downloads); Actions carrying them require8. Older formats reject instead of dropping metadata. The published Adobe execute-actions workflow covers gallery families, but exact descriptors and editable PSD/PSB mappings remain unqualified and explicitly unsupported. No Adobe route or descriptor is invented. The47 Rust-reference matches are source-port evidence, not Photoshop pixel-equivalence evidence. [Scope and qualification](FILTER_GALLERY_REFERENCES.json).

## Smart Sharpen and Reduce Noise (step206)

`filter.apply` accepts `{"kind":"smartSharpen","sharpen":{"amount":100,"radius":2,"reduceNoise":10,"remove":"motion","angle":30,"shadows":{"fadeAmount":20,"tonalWidth":50,"radius":1},"highlights":{"fadeAmount":0}}}` in its `filter` parameter. Removal values are `gaussian`, `lens`, and `motion`. Amount0 is identity. `capabilities.filters.smartSharpen` describes the full schema and native algorithm qualification.

For noise reduction, use `{"kind":"reduceNoise","denoise":{"strength":6,"preserveDetails":60,"reduceColorNoise":45,"sharpenDetails":25,"removeJpegArtifact":true,"perChannel":{"blue":{"strength":4,"preserveDetails":30}}}}`. Optional `perChannel` entries are `red`, `green`, and `blue`; each applies additional smoothing after the overall pass. Omitted channels have zero additional strength. `capabilities.filters.reduceNoise` provides complete numeric ranges and defaults. Unknown fields, nonnumeric values and invalid ranges reject.

Both use the desktop native engine, selection/protection rules and single history transaction. `smartFilter.set` re-edits the same settings. Document state exposes `photoDetail` availability and native preview/zoom/channel/local-history state. Stale and busy edits return409; invalid filter parameters return400. RGB8/16 process encoded samples, RGB32 processes linear unclipped samples. Alpha and zero-alpha hidden pixels are preserved. JPEG grid coordinates follow the layer transform. Maximum8,388,608 layer pixels; mask/component/auxiliary channel targets remain unsupported.

Editable settings require native37 (`X-Photato-Archive-Version: 37`) and Actions9; older formats reject instead of dropping settings. Photoshop Smart Sharpen is listed in Adobe's execute-actions workflow, but its exact action descriptors and editable PSD mappings are not yet independently qualified. These two descriptor families explicitly reject in the Adobe adapter. Native APIs do not establish Adobe or pixel parity. [Evidence and remaining scope](PHOTO_DETAIL_REFERENCES.json).

## Lens Blur (step207)

Use `filter.apply` with `filter: {"kind":"lensBlur","lensBlur":{"radius":15,"blades":6,"depthSource":"none"}}`. The same settings work in `smartFilter.set`; capability discovery includes the strict schema and parameter ranges. RGB8/16 supports iris curvature/rotation, focal distance/invert, highlight brightness/threshold and deterministic uniform/Gaussian noise with monochrome/color controls. Native preview and API edits use the same command and history path.

`depthSource` accepts `none`, `transparency`, `layerMask` or `alphaChannel`. The last requires `depthChannelID` from the document's channels. Mask/channel depth stays live; edits are reflected in later renders. Layer-mask depth uses raw grayscale with its transform, independent of display feather/density/inversion/visibility. Transparency samples the current filter input. Referenced masks/channels cannot be removed until filters change their source; a Smart Filter mask remains independent. UUID references replay only in documents containing those channels.

The `lensBlur` state reports availability, workspace/preview status, current parameters and available depth sources. The native preview's focus picker sets `focalDistance` (0–255), which API clients can set directly. Editable saving requires native38 (`X-Photato-Archive-Version: 38`); Actions10 retains settings. Older archive requests reject. RGB32, auxiliary targets, invalid sources, stale revisions and concurrent modal edits reject without committing a change.

This adds no unverified Adobe descriptor. Lens Blur Photoshop actionJSON and editable PSD/PSB remain unsupported; exact Photoshop output, live/platform behavior and cross-document source mapping remain open. [Evidence](LENS_BLUR_REFERENCES.json).

Editable Lens Blur on Smart Objects is a Photato extension: [Adobe explicitly excludes Lens Blur from Photoshop Smart Filters](https://helpx.adobe.com/photoshop/desktop/effects-filters/smart-filters/apply-and-manage-smart-filters.html). This extension does not establish Photoshop context or file-format parity.

## Document presentation (step208)

Document state now includes `windowTitle`, formatted as `Photato - <display name>`. The `name` field remains the document name without branding. Desktop title updates share this computation; this presentation metadata adds no editing command or Adobe API field. Canvas containment changes only drawing and child-view clipping; pixel coordinates, editing operations, saved output and history are unchanged.

## Distortion workflows (step212)

`filter.apply` and `smartFilter.set` accept nine kinds: `displace`, `shear`, `wave`, `pinch`, `spherize`, `twirl`, `ripple`, `polarCoordinates`, and `zigzag`. Supply settings in the `distortion` object, for example `{"kind":"twirl","distortion":{"angle":75}}`. The factory Filter > Distort menus use the same Swift commands. Preview Cancel discards changes; OK commits one history step. Smart Filters retain editable settings and original source pixels.

| Kind | Settings |
| --- | --- |
| `displace` | Integer `horizontalScale`/`verticalScale` −999…999; `fit`: `stretchToFit` or `tile`; `edge`: `repeatEdge` or `wrapAround`; required `map`. |
| `shear` | 2–64 `points`, each with `position` 0…1 and `offset` −1…1 in half-widths. Positions strictly increase, with endpoints at 0 and 1. `edge`: `repeatEdge` or `wrapAround`. |
| `wave` | Integer `generators` 1…999, `wavelengthMin`/`wavelengthMax` and `amplitudeMin`/`amplitudeMax` 1…999, each minimum below maximum; horizontal/vertical scales 1…100; `waveType`: `sine`, `triangle`, `square`; unsigned 32-bit `seed`; `edge`. All generators are evaluated. |
| `pinch` | Integer `amount` −100…100. |
| `spherize` | Integer `amount` −100…100; `sphereMode`: `normal`, `horizontalOnly`, `verticalOnly`. |
| `twirl` | Integer `angle` −999…999. |
| `ripple` | Integer `amount` −999…999; `rippleSize`: `small`, `medium`, `large`. |
| `polarCoordinates` | `polarMode`: `rectangularToPolar` or `polarToRectangular`. |
| `zigzag` | Integer `amount` −100…100 and `ridges` 0…20; `zigzagStyle`: `aroundCenter`, `outFromCenter`, `pondRipples`. |

A displacement map is immutable embedded data: `{"width":1,"height":1,"channels":1,"samples":"gA==","name":"Neutral map"}`. Samples are base64 row-major interleaved 8-bit bytes, with an exact width × height × channels length and at most 1,048,576 pixels. The first channel drives horizontal displacement; the second drives vertical displacement, or the first is reused for monochrome maps. Byte128 is neutral. Desktop import reads grayscale or red/green samples from a local image; the API accepts samples, never arbitrary filesystem paths. Map names are limited to256 UTF-8 bytes.

Discovery publishes parameter schemas, defaults and `capabilities.filters.distortion`; document state exposes distortion workspace availability, preview/settings and local-history state. Unknown fields, invalid enums/ranges, fractional integer settings, missing maps and malformed samples reject without changing history. Stale revisions and busy modal work reject409. Supported targets are RGB8/16/32 pixel layers and editable Smart Filters, up to8,388,608 layer pixels, with selection/protection rules. RGB8/16 samples are encoded; RGB32 samples are linear and unclipped. Premultiplied interpolation avoids hidden-color fringes. Auxiliary/component/mask targets remain unsupported.

Editable documents require native39 (`X-Photato-Archive-Version: 39`); recorded settings require Actions11. Older versions reject instead of silently losing settings. Native HTTP, desktop, undo/redo, source/mask retention and both archive encodings have focused regression coverage. These settings are not Adobe actionJSON descriptors: the Adobe adapter and editable PSD mappings explicitly reject these nine unqualified filter families. No Adobe route is invented. Exact Photoshop pixels and physical platform/live interaction qualification remain open. [Evidence](DISTORTION_REFERENCES.json).

## Pixelate workflows (step213)

`filter.apply` and `smartFilter.set` accept `colorHalftone`, `crystallize`, `facet`, `fragment`, `mezzotint` and `pointillize`. Configurable kinds take a `pixelate` object. For example, the filter value `{"kind":"colorHalftone","pixelate":{"maxRadius":8,"angles":[108,162,90,45]}}` uses the same native engine as Filter > Pixelate. Facet and Fragment apply immediately from the menu; the other four open a native preview workspace. Cancel discards the draft; OK creates one document Undo step. Smart Filters retain editable settings and source pixels.

| Kind | Settings and native defaults |
| --- | --- |
| `colorHalftone` | Integer `maxRadius` 4–127 (default 8); exactly four integer `angles` −360–360 (default `[108,162,90,45]`). RGB uses the first three angles; the fourth is retained. |
| `crystallize` | Integer `cellSize` 3–300 (default 10); unsigned 32-bit `seed` (default 0). |
| `pointillize` | Integer `cellSize` 3–300 (default 5); unsigned 32-bit `seed` (default 0); `background` with all four normalized `r`, `g`, `b`, `a` components. API default is opaque white; the desktop snapshots the current background color. |
| `mezzotint` | `pattern`: `fineDots`, `mediumDots`, `grainyDots`, `coarseDots`, `shortLines`, `mediumLines`, `longLines`, `shortStrokes`, `mediumStrokes`, `longStrokes` (default `fineDots`); unsigned 32-bit `seed` (default 0). |
| `facet`, `fragment` | No options: use `{"kind":"facet"}` or `{"kind":"fragment"}`. |

Discovery publishes strict schemas and `capabilities.filters.pixelate`, including kinds, patterns, archive requirements and algorithm limitations. Document state exposes Pixelate availability and active workspace settings, preview and local history. Unknown keys, wrong types, fractional integer values and invalid ranges reject with400; stale revisions and busy documents reject409. Rejected operations do not change pixels or history. Processing is cancellable and limited to8,388,608 layer pixels. RGB8/16 use encoded values; RGB32 uses linear values. Native cell origins are layer-local and edges clamp. Selection, transforms and transparency protection use the shared filter command path; auxiliary/component/mask targets remain unsupported.

Editable Pixelate Smart Filters require native archive40; native downloads must opt in with `X-Photato-Archive-Version: 40`. Older requests reject422 instead of flattening or losing settings. Recorded operations require Actions12. Both native archive encodings, source/mask retention, replay, desktop/HTTP equivalence and invalid/busy/stale behavior have focused coverage. Eighteen synthetic RGB8 fixtures match the licensed original Rust implementation byte-for-byte; this does not establish Photoshop pixel equivalence.

Adobe lists these filters in its [published Smart Filters workflow](https://developer.adobe.com/firefly-services/docs/photoshop/guides/workflows/smart_filters/) and requires recorded actionJSON descriptors. Those descriptors and editable PSD mappings are not yet qualified here; the Adobe adapter explicitly rejects these six filter families. Their Adobe-compatible interface remains an open feature-completion requirement. Exact Photoshop defaults, supported depths, pixels and live/platform qualification also remain open. [Evidence](PIXELATE_REFERENCES.json).

## Stylize workflows (step214)

`filter.apply` and `smartFilter.set` accept `diffuse`, `emboss`, `extrude`, `findEdges`, `oilPaint`, `solarize`, `tiles`, `traceContour` and `wind`. Configurable filters use a `stylize` object, for example `{"kind":"emboss","stylize":{"angle":135,"height":3,"amount":100}}`. Find Edges and Solarize accept only their `kind` and apply immediately from the factory menu. The other seven open native settings/preview workspaces. The desktop and API share rendering, selection/protection handling and document Undo; Smart Filters retain editable settings and source pixels.

| Kind | Settings and native defaults |
| --- | --- |
| `diffuse` | `mode`: `normal`, `darkenOnly`, `lightenOnly`, `anisotropic` (default `normal`); unsigned32-bit `seed` (default0). |
| `emboss` | Integer `angle` −180–180 (135), `height`1–100 (3) and `amount`1–500 (100). |
| `extrude` | `type`: `blocks` or `pyramids`; integer `size`2–255 (30), `depth`1–255 (30); `depthMode`: `random` or `levelBased`; booleans `solidFrontFaces`/`maskIncompleteBlocks` (false); unsigned32-bit `seed` (0). Solid fronts apply to blocks. |
| `oilPaint` | `stylization`0–10 (4), `cleanliness`0–10 (5), `scale`0–10 (1), `bristleDetail`0–10 (5), `shine`0–10 (1); boolean `lighting` (true); integer `angle` −360–360 (−60). The source algorithm retains an internal0.1 floor for stroke stylization/scale. |
| `tiles` | Integer `count`1–99 (10), `maxOffset`1–99 (10); `fill`: `background`, `foreground`, `inverse`, `unaltered`; normalized RGBA `foreground`/`background`; unsigned32-bit `seed` (0). API colors default to opaque black/white; desktop snapshots current colors. |
| `traceContour` | Integer `level`0–255 (128); `edge`: `lower` or `upper` (default `lower`). |
| `wind` | `method`: `wind`, `blast`, `stagger`; `direction`: `fromRight` or `fromLeft`; unsigned32-bit `seed` (0). Defaults: Wind, From the Right. |
| `findEdges`, `solarize` | No settings object or adjustable parameters. |

Discovery exposes strict schemas, `capabilities.filters.stylize`, archive requirements and the active workspace settings/preview/local-history state. Unknown keys, wrong types, fractional integer settings and invalid ranges reject400. Busy documents and stale revisions reject409. Invalid operations do not change history. Cancel closes the preview without edits; OK records one document transaction. Auxiliary/component/mask targets remain unsupported. Native processing supports RGB8/16 encoded and RGB32 linear samples, up to8,388,608 layer pixels, with cancellation. Exact Photoshop depth availability and defaults are not qualified by this broader native support.

Native archive41 preserves editable Stylize filters; downloads require `X-Photato-Archive-Version: 41` and older requested versions reject422. Recorded operations require Actions13. Oil Paint processes256-pixel tiles with source-equivalent halos to bound working buffers. Its original Rust implementation has a small whole-image versus tiled floating-point difference; the wide reference uses the original app's default tiling. This is recorded separately from exact Photoshop matching.

Emboss editable PSD/PSB mapping follows the upstream `Embs` descriptor with integer `Angl`, `Hght` and `Amnt`; current source round trips do not prove live Photoshop interoperability. Other Stylize PSD descriptors and all nine Adobe actionJSON mappings remain unqualified and explicitly reject. Adobe lists these filters for [execute-actions](https://developer.adobe.com/firefly-services/docs/photoshop/guides/workflows/smart_filters/), so their compatible-interface completion gate remains open until the actual descriptors and job behavior are verified. [Evidence](STYLIZE_REFERENCES.json).

## Procedural Render filters (step215)

`filter.apply` and `smartFilter.set` accept `clouds`, `differenceClouds`, `fibers` and `lensFlare`, with settings in `render`. For example, `{"kind":"fibers","render":{"variance":16,"strength":4,"seed":42}}` uses the same native command as Filter > Render > Fibers. Clouds and Difference Clouds apply immediately from the desktop menu. Fibers and Lens Flare open native previews with Cancel, local Undo and a single document Undo on commit. The flare center can be dragged in the preview or entered numerically. Existing Smart Filters can be reopened to edit their retained settings.

| Kind | Native settings and API defaults |
| --- | --- |
| `clouds`, `differenceClouds` | Unsigned32-bit `seed` (0); normalized RGBA `foreground` (opaque black) and `background` (opaque white), each containing exactly `r`, `g`, `b`, `a`. |
| `fibers` | `variance`1–64 (16), `strength`1–64 (4); the same seed and color fields as Clouds. |
| `lensFlare` | `brightness`10–300 (100); `centerX`/`centerY` −0.5–1.5 (0.5), normalized against document width/height; `lens`: `zoom`, `prime35`, `prime105`, `moviePrime` (default `zoom`). |

Desktop generation captures the current foreground/background and a new random seed. API defaults are deterministic; clients can supply a seed, and Actions/Smart Filters retain it for reproducible replay. Clouds and Fibers generate opaque color before selection/transparency clipping, irrespective of the supplied color alpha. Difference Clouds and Lens Flare retain the original alpha. RGB8/16 processing uses encoded samples; RGB32 uses linear samples with color conversion and finite HDR support. These native settings do not claim Adobe depth, modifier-key or exact-pixel equivalence.

Clouds, Difference Clouds and Fibers operate in document coordinates over the selected canvas area, expanding cropped or empty raster storage as needed. Existing pixels outside the affected area, off-canvas storage, transforms, mask placement and transparency locks are retained. Layer/canvas/expanded-target budgets are8,388,608 pixels; cancellation and failures leave the document transaction unchanged. Component, auxiliary-channel and mask targets remain unsupported. Smart Filters retain original source pixels and their captured settings.

Discovery publishes strict per-kind schemas, `capabilities.filters.render`, format requirements and workspace settings/preview/local-history state. Unknown fields, wrong types, invalid colors/enums and out-of-range numbers reject400; busy/stale edits reject409. Editable Render filters require native42; downloads use `X-Photato-Archive-Version: 42`, with older requests rejecting422. Recorded operations require Actions14. Existing native1–41 and Actions1–13 remain readable.

The native normalized center fields are **not** Adobe's pixel-coordinate descriptor. Adobe's public UXP documentation describes Clouds, Difference Clouds and Lens Flare; its Firefly tested Smart Filter list includes those three. Exact actionJSON and editable PSD/PSB mappings are not yet verified and explicitly reject. No unsupported Adobe route or Fibers service claim is invented. These compatible-interface, exact-output, live and physical-platform gates remain open. [Render evidence](RENDER_REFERENCES.json).

## Flame, Tree and Picture Frame (step216)

`render.flame`, `render.tree` and `render.pictureFrame` generate raster pixels through the same native command as their Filter > Render dialogs. All accept optional `settings`, `layerID` and `newLayer` (default `false`). Omitting `layerID` uses the active layer. An ordinary raster target is required unless `newLayer` is true. Layer and ancestor locks, selection coverage, transparency locks, cropped storage, masks and transforms use the shared paint transaction. Successful edits create one Undo entry. Preview controls and local history do not change the document until OK; Cancel discards them.

Flame additionally accepts `pathID`, referring to a saved document path. Path resolution is explicit `pathID`, the desktop-selected path, Work Path, then the first saved path. A missing path rejects; Photato does not silently generate a fallback arc. Native curves are flattened at half-pixel tolerance. The dialog can choose among existing paths. Tree position is adjustable numerically or by dragging its base in the preview.

| Command | Settings and native defaults |
| --- | --- |
| `render.flame` | `flameType`: `oneFlameAlongPath` (default), `multipleFlamesAlongPath`, `multipleFlamesPathDirections`, `multipleFlamesVariousLength`, `candleLight`, `multipleFlamesOneDirection`; `length`, `width`, `interval` 1–1000 (150,40,60); `angle` −180–180 (0); `turbulent`, `jag`, `opacity`, `flameBottomAlignment` 0–100 (25,25,75,20); `flameLines` 1–100 (20); integer `quality` 0–4 (2); `flameStyle`: `normal`, `violent`, `flat`; `flameShape`: `parallel`, `toCenter`, `spread`, `oval`, `pointed`. Booleans: `randomizeLength`, `useCustomColor`, `randomizeShapes` false; `adjustIntervalForLoops` true. `color` defaults to RGBA `[1,0.5,0.1,1]`. |
| `render.tree` | Integer `baseTreeType` 1–34 (1), with names in discovery; integer `lightDirection` 1–5 (3); `leavesAmount` 0–100 (50), `leavesSize` 0–200 (100), `branchesHeight` 50–300 (100), `branchesThickness` 50–200 (100); normalized base `x`,`y` 0–1 (0.5,0.95); `size` 0.05–2 (0.8). `defaultLeaves` true; `customBranchColor` and `flatShading` false. `leavesColor` defaults to `[0.24,0.52,0.16,1]`, `branchesColor` to `[0.36,0.25,0.16,1]`. |
| `render.pictureFrame` | Integer `frame` 1–16 (1), with style names in discovery; integer `lines` 1–5 (1); `margin` 0–30 (4); `size`, `arrangement`, `thickness` 1–100 (50,50,30); `fade` 0–100 (0). `vineColor` defaults to `[0.25,0.4,0.15,1]`, `flowerColor` to `[0.9,0.3,0.45,1]`, `leafColor` to `[0.3,0.6,0.2,1]`. |

Every settings object accepts unsigned32-bit `seed`, default0. Desktop and API defaults are deterministic; the dialog's Randomize button captures a fresh seed. Colors are objects with normalized `r`, `g`, `b`, `a` fields; arrays above describe defaults, not the request syntax. Partial settings merge over the documented defaults, while unknown fields, incorrect types, fractional integer values and out-of-range numbers reject400. Unknown layer/path IDs reject404; busy documents and stale revisions reject409. Invalid operations leave pixels and history unchanged.

`capabilities.proceduralRender` publishes settings schemas/defaults, tree/frame names, limits and format requirements. Document state `proceduralRender` reports per-kind availability, open workspace, preview/commit activity, current settings, path presence, new-layer choice, zoom, preview and local history. Rendering supports RGB8/16 and linear-storage RGB32, with encoded-RGB source-over compositing. Canvas/expanded storage is limited to8,388,608 pixels, generated geometry to200,000 primitives and coverage work to268,435,456 samples. These explicit limits do not establish Photoshop large-document or depth parity.

Results use existing raster persistence, including native archives and PSD/PSB output; this increment does not introduce native version43. Recorded operations require Actions15 and retain settings, a portable layer target and the actual Flame path geometry. Actions1–14 remain readable. The discovery state's `supportedVersions` is authoritative; a legacy description for the `actions.manage` data parameter still mentions an older subset and is tracked for correction.

Adobe's [Smart Filter guide](https://helpx.adobe.com/photoshop/desktop/effects-filters/smart-filters/apply-and-manage-smart-filters.html) excludes these three generators from that mode. Their native commands therefore generate raster pixels. The public Firefly [execute-actions guide](https://developer.adobe.com/firefly-services/docs/photoshop/guides/workflows/smart_filters/) does not supply their raster ActionJSON descriptors. Those descriptors and Adobe `.atn` compatibility remain unqualified and reject explicitly; no route is invented. Seventy original-Rust RGB8 cases match exactly after preserving its floating-point PI constant. That is source-reference evidence, not Photoshop output proof. Exact Photoshop settings, output, platform and live interaction qualification remain open. [Evidence](PROCEDURAL_RENDER_REFERENCES.json).


## Other and Video filters — step217

The existing `filter.apply` and `smartFilter.set` operations accept seven additional filter kinds. They share native desktop commands, prepared transactions, selection/transparency checks, document Undo and Smart Filter source retention. Discovery includes `filters.otherVideo`; document state reports availability, workspace presence, preview busy state and current workspace parameters/history. The typed-command total remains110. Native editable output requires archive43; Actions export uses16 when these operations are recorded. Older native/Actions versions remain supported for older content. The Actions import-description hint now matches supported versions1–16.

Supply `otherVideo` with kind-specific fields; omitted fields use the listed defaults. Unknown fields, wrong types, nonfinite numbers and out-of-range values fail validation. Busy/stale requests retain409 behavior, missing targets404, invalid parameters400; execution/storage/size limitations remain explicit errors.

| Kind | Settings and defaults |
|---|---|
| `customFilter` | `kernel`:25 integer row-major coefficients−999…999, center1/rest0; `scale`:1…9999 default1; `offset`:−9999…9999 default0. Scale/offset accept finite numbers. Alpha is preserved. Original-source all-zero kernel is a no-op. |
| `hsbHsl` | `inputMode`:rgb/hsb/hsl default rgb; `outputMode`:rgb/hsb/hsl default hsb. Reinterprets the three channels and retains alpha. Input channels clamp0…1 as in the licensed source. |
| `maximum`, `minimum` | `radius`:1…500 integer with `preserve:squareness` (default radius1);0.2…500 with `preserve:roundness`. Original-source disc below one pixel is a no-op; exact Adobe fractional morphology remains unqualified. |
| `offset` | `horizontal`, `vertical`:whole document pixels, default0, bounded to±2×document width/height (schema hard cap±600000). `undefinedAreas`:wrap(default),repeatEdge,transparent. Wrap/repeat use current selection bounds or canvas. |
| `deInterlace` | `eliminate`:odd(default)/even; `createBy`:interpolation(default)/duplication. Counts one-based lines from the selection/canvas top. Interpolation uses premultiplied samples; boundary rows use the available neighbor. |
| `ntscColors` | No settings. Restricts YIQ chroma to the original-source composite-signal bounds, retaining alpha. |

Example:

```json
{"command":"filter.apply","revision":"<current revision>","parameters":{"layerID":"<layer UUID>","filter":{"kind":"offset","otherVideo":{"horizontal":24,"vertical":-12,"undefinedAreas":"wrap"}}}}
```

Custom Save/Load uses a UTF-8 `.json` object containing `kind:"customFilter"` and the `otherVideo` settings object. That is exactly the `filter` payload accepted by this API; preserve/reuse it directly. Files are limited to16KiB and25 coefficients. This is Photato preset transport; Adobe `.acf` compatibility remains open. No API filesystem paths are accepted.

Processing supports RGB8/16 encoded samples and RGB32 linear samples, with an8,388,608-pixel canvas/expanded-target limit. Disc extrema additionally limit width×height×(2×floor(radius)+1) to268,435,456 row-window samples. Original off-canvas pixels and layer-mask placement are retained; raster storage expands for shifted/generated coverage. Component/Quick Mask targets remain unavailable for this family.

Adobe's [published Smart Filter workflow](https://developer.adobe.com/firefly-services/docs/photoshop/guides/workflows/smart_filters/) lists Maximum, Minimum, Offset and De-Interlace through execute-actions and directs clients to record the exact Photoshop descriptor. Corresponding ActionJSON/ATN and editable PSD/PSB mappings are not yet qualified here; they remain explicit unsupported paths. Rasterized PSD results can be saved, and native43 retains editability. The44 original-Rust RGB8 fixtures are source-port evidence, not Photoshop parity proof. See `OTHER_VIDEO_REFERENCES.json` for current validation status and limits.

## Remaining Blur, Noise and Sharpen workflows (step218)

`filter.apply` and `smartFilter.set` now accept twelve additional kinds through `classicDetail` settings. Desktop and API share the native transaction, selection/transparency handling, document Undo and Smart Filter source retention. Six immediate desktop commands still use those same filter payloads. The typed-command total stays110. Editable documents require native archive44; recorded filters/stacks require Actions17. Earlier document/action versions remain available for older content.

| Kinds | Settings and defaults |
| --- | --- |
| `blur`, `blurMore`, `despeckle`, `sharpen`, `sharpenEdges`, `sharpenMore` | No settings; send an empty `classicDetail` object or omit it. Each uses its fixed source settings and distinct history label. |
| `radialBlur` | `amount` integer1–100(default10); `method:spin/zoom`(spin); `radialQuality:draft/good/best`(good); `centerX`, `centerY` normalized0–1(default0.5 each). Desktop preview dragging changes the same center coordinates. |
| `shapeBlur` | `radius` integer5–1000(default10); `shape:circle/ring/square/diamond/triangle/hexagon/star/heart/cross`(circle). Imported Photoshop shape presets remain unsupported. |
| `smartBlur` | `radius` and `threshold` number0.1–100(default3 and25); `quality:low/medium/high`(high); `mode:normal/edgeOnly/overlayEdge`(normal). |
| `surfaceBlur` | `radius` integer1–100(default5); `threshold` integer2–255(default15). |
| `median` | `radius` integer1–500(default1). |
| `dustAndScratches` | `radius` integer1–100(default1); `threshold` integer0–255(default0). |

Example:

```json
{"command":"filter.apply","revision":"CURRENT-REVISION","parameters":{"layerID":"LAYER-UUID","filter":{"kind":"radialBlur","classicDetail":{"amount":30,"method":"zoom","radialQuality":"best","centerX":0.3,"centerY":0.6}}}}
```

Discovery exposes `filters.classicDetail`, strict per-kind schemas/defaults and `depthsByKind`. Document state exposes `classicDetail.available`, `availableKinds`, `workspaceOpen`, `previewBusy` and the workspace settings/history state. Smart Blur acceptsRGB8. Despeckle, Dust & Scratches, Median and Sharpen Edges acceptRGB8/16. The remaining operations support nativeRGB8/16/32; their exact Photoshop depth contexts remain unqualified. Component/mask targeting rejects. Unknown or inappropriate fields, invalid enums and fractional integer controls return400. Unsupported depth/context or processing bounds use422; stale/busy/revoked edits use409 without mutation.

Radial center uses the selected bounds or canvas. Neighborhood filters can sample across the selection boundary and apply the resulting pixels through selection coverage. Cropped pixel storage can expand without moving masks; transparency locks preserve alpha. RGB32 calculations use linear samples. The native limit is8,388,608 pixels and268,435,456 estimated neighborhood visits; shared API document limits also apply. Large kernels can fail explicitly before document mutation. Cancellation leaves no partial command/history entry.

These are licensed PhotoCraft algorithms, with native running-rank/prefix optimizations. Radial Best retains the original sample cap; Good and Draft use lower native caps. Exact Photoshop kernels, quality/default behavior, imported Shape presets and Adobe ActionJSON/ATN/editable PSD descriptors remain unqualified. No corresponding Adobe route or descriptor support is claimed. See [current evidence](CLASSIC_DETAIL_REFERENCES.json).


## Classic tone and color adjustments (step219)

The Photato interface adds `tone.apply` and `tone.statistics` through the existing authenticated `POST /v1/documents/{sharedID}/commands` route. Both require the current `revision` and idle desktop state. Capability discovery lists every control, range and default under `classicTone`; new work uses the same Swift transaction path as the desktop.

`tone.apply` takes `kind` (`shadowsHighlights`, `hdrToning`, `matchColor`, `replaceColor` or `equalize`), optional `settings`, and optional target `layerID`. Omit `layerID` for HDR Toning, which composites visible content over white into one background, clears the pixel selection, and restores all original layers through one Undo. Other operations edit the chosen pixel layer; Shadows/Highlights can instead append an editable Smart Filter on a Smart Object. `filter.apply` / `smartFilter.set` also accept `shadowsHighlights` with a `tone` settings object. These editable filters require native archive45; the other raster edits use existing native/raster PSD persistence. Ordinary tone operations and Shadows/Highlights filters require Actions18; semantic HDR Toning action playback is explicitly unsupported.

For Match Color, submit `tone.statistics` to the **source's shared document route**, optionally selecting `layerID` (omitted: Merged) and `useSelection` (default false). It returns `statistics` (`mean` and `standardDeviation`, three Lab components each), `revision`, and `sourceDepth`. Put those statistics in the target's `tone.apply` settings as `sourceStatistics`. There is no implicit access to an unshared source document. Statistics are frozen, portable values. The operation weights samples by alpha and optional selection, does not change history, and rejects empty samples. Cancellation, changed revisions, service restart or revoked sharing reject publication. A concurrent preview/statistics job returns429.

Example target parameters: `{"kind":"matchColor","settings":{"sourceStatistics":{"mean":[55,12,-8],"standardDeviation":[18,15,22]},"luminance":100,"intensity":100,"fade":0,"neutralize":false,"useSelectionInTarget":true,"ignoreSelection":false}}`.

Replace Color accepts one to64 `samples`, each with opaque RGBA `color`, optional normalized `point`, and `subtract` boolean. At least one additive sample is required. Controls include `fuzziness`, `hue`, `saturation`, `lightness`, `localized` and pixel `localRadius`. Equalize's `equalizeEntireImage` applies the histogram derived from the current selection to the whole target; false confines application to the selection. HDR methods are Local Adaptation, Exposure and Gamma, Highlight Compression, and Equalize Histogram; a sorted two-to32 point `curve` is optional for Local Adaptation. Native JSON presets preserve these settings; Adobe STA and preset formats are not accepted as equivalent.

Unknown/irrelevant fields, malformed samples/curves, invalid ranges and an HDR layer target return400. Missing requested layers return404; stale or busy documents return409; unsupported targets, empty statistics and resource limits return422. Native RGB8/16/32 and up to8,388,608 pixels are supported; Photoshop depth/default/output and ICC-specific tone behavior remain unqualified. State reports availability, active preview, commit progress and local history. Adobe v2 endpoint coverage is unchanged: unqualified ActionJSON/ATN/editable PSD descriptors are explicitly unsupported, and no replacement Adobe route is invented.


## Restricted-mode foundation (step221, in progress)

Native47 files can retain Indexed Color indices/palettes and packed1-bit Bitmap data. Document mode state can report `indexed` or `bitmap`; Bitmap reports depth1. The earlier storage-only stage is superseded by the restricted-mode and geometry commands documented above. `document.convertMode`, File New and Adobe creation remain limited to component modes; use the explicit restricted conversion commands where available. Adobe restricted conversion descriptors and full workflow qualification remain open. See [working evidence](RESTRICTED_MODE_REFERENCES.json).


## Proof display (step223)

`proof.configure` accepts a required `settings` object, merged strictly with committed per-document proof settings. `proof.settings.read` returns the committed settings and current revision. Both use the ordinary authenticated share, revision and desktop-interaction checks. Changes advance the view revision without changing pixels, document Undo, dirty state or saved output. Unknown properties, malformed profiles, mismatched plate/profile modes and incompatible Preserve Numbers requests reject atomically.

Settings are `enabled`, `gamutWarning`, `device` (`workingCMYK`, `sRGB`, `custom`), optional base64 ICC `profile`, `profileName`, `intent` (the four mode intents), `blackPointCompensation`, `preserveNumbers`, `simulatePaper`, `simulateBlack`, `plate` (`composite`, `cyan`, `magenta`, `yellow`, `black`, `cmy`), `warningColor` (opaque RGBA), `warningOpacity` (0–1) and `gamutThreshold` (0.01–100 DeltaE76, default4). Complete machine schemas, result/state schemas and limits are in capabilities.proofing. Existing request-body limits also apply to embedded profiles. System Generic CMYK is the current workingCMYK default. Custom device profiles are retained exactly; no Adobe ICC assets are bundled.

`GET /v1/documents/{id}/proof-preview.png` returns a color-managed SDR PNG from committed pixels and committed proof settings. It excludes uncommitted sheets and channel visibility. Concurrent work, stale state and share revocation use the same preview guards as other preview routes. Ordinary `preview.png`, channel preview and native/PSD/TIFF exports keep their existing contracts. An invalid proof after later editing yields an explicit proof-export error; the desktop retains the current ordinary canvas and exposes `proofing.displayError` instead of freezing the old image.

Preserve Numbers bypasses source-to-output conversion and requires matching modes; non-RGB or native-mode RGB currently needs a flat retained native raster. Rendering uses per-operation ColorSync transforms with separately retained alpha. Gamut warnings use a relative-colorimetric device round trip and Lab D50 DeltaE76; this is not a Photoshop byte-equivalence claim. Proof settings are view state, with native JSON Save/Load presets, not document editing Actions or archive data. The published Adobe v2 schema has no corresponding display-proof endpoint; no route is invented. Printing/HDR/global preferences, Adobe PSF and full exact/live/platform parity remain open.


## Native printing and hard proofs (step224)

`print.configure` merges a `settings` object atomically. `print.settings.read` returns the committed settings and last print operation. Both return `printing` and `revision`; the document GET includes the same state. These settings do not change pixels, undo/redo, native archives or the modified flag. The capability response documents the settings/state/result schemas.

`GET /v1/documents/{id}/print.pdf` prepares the committed document, print settings and proof condition. It excludes uncommitted desktop drafts and screen gamut warnings. It uses the same layout, ICC transforms, marks and separation images as native printing. PDF output requires an authenticated shared document, but no printer permission; stale or revoked output is rejected. Concurrent preview/PDF preparation returns429. Copies affect printer submission, not PDF page count.

- All physical measurements are points,72 per inch. Paper/orientation, custom portrait media, printable margins, centering, scale/fit, top/left, selected-area bounds, border and bleed are configurable. Centering uses the printable area; top/left measure from the paper’s top-left.
- `content` is `document`, `hardProof` or `separations`. `colorHandling` is `printerManages` or `photatoManages`. Photato-managed composite/proof output requires a base64 RGB/CMYK/gray ICC `profile`, with `profileName`, `intent`, `blackPointCompensation` and optional `sixteenBit`. A document command accepts the4 MiB ICC maximum after base64 expansion plus bounded JSON overhead; unrelated generic routes retain their64 KiB limit.
- Hard proofs use the committed Proof Setup profile/intent/preserved numbers and print-specific `simulatePaper`/`simulateBlack`. The printer profile is a separate output condition. Disable additional correction in the driver when Photato manages color.
- Separations support retained flat CMYK, Duotone or Multichannel ink densities, with one grayscale image/page per plate. General layered component separations/DeviceN/overprint are unfinished. Selected area prints its rectangular bounds, without multiplying a soft selection mask.
- Preparation is bounded to8,388,608 source pixels and256 MiB prepared images; PDF output is bounded to128 MiB.32-bit source content is converted to bounded8/16-bit printing.

Enable **Allow printing** in the native Automation window to permit `print.present` or `print.submit`. Capabilities then expose installed `printers`; `printingEnabled` reports the current permission. `print.present` opens native controls. `print.submit` starts asynchronous preparation and explicitly submits the committed job to AppKit. Read document `printing.status`/`operationID`/`error` to follow it. Printer names are checked at submission, and selected-device printable bounds constrain the layout; disconnected printers do not prevent PDF previews.

`print.cancel` takes `operationID` and cancels preparation owned by the current API session. Revoking sharing or disabling printing also cancels preparation. Once submitted, manage cancellation in the macOS print queue. `completed` means AppKit completed its operation, not independently verified paper delivery; cancellation or native failure may report `cancelledOrFailed`. Stopping the API resets printing permission. Native commands and tests share the engine; tests inject a transport or force an owned PDF file and never spool a physical job.

No printer endpoint is defined in the pinned Adobe Photoshop v2 contract, so these are Photato-specific interfaces. Complete driver/page-range/print Actions/persistence, color-font/mark output, physical-device and live/platform/Photoshop-equivalence acceptance remain open. See [printing evidence](PRINTING_REFERENCES.json).

## Assign and convert color profiles (step225)

`document.assignProfile` takes `profileBase64` for an ICC profile matching the current RGB, CMYK, grayscale or Lab mode. It changes interpretation while retaining numerical component samples. Alternatively, pass `removeProfile: true` and omit `profileBase64`: the document uses the platform standard interpretation and omits color profile tags on supported exports. Native saving then requires archive49; older API download versions reject rather than silently dropping the untagged state.

`document.convertProfile` requires `profileBase64` and accepts `intent` (`perceptual`, `relativeColorimetric`, `saturation`, `absoluteColorimetric`), `blackPointCompensation` (defaulttrue), and `mergeVisible` (defaultfalse). The native Apple ColorSync transform preserves independent alpha and transparent colors. Precision remains unchanged;32-bit ICC must already be linear, while the native ICC chooser can explicitly linearize a selected profile. RGB/gray32 retain negative and HDR values. Unsupported destination/depth combinations reject. Ordinary RGB raster/group, text, solid fill and simple solid shape layers stay editable; other profile-dependent stacks require explicit merging. Merging replaces the stack with its visible composite and removes hidden layers. All document edits use one shared prepared native history transaction with busy, revision, source, cancellation and authorization checks.

`document.profile.read` returns `profileBase64`, `name`, `untagged` and `revision`. The profile is the effective numerical interpretation even when untagged. The ordinary document response includes `colorProfile` availability, preview and commit state. These operations are limited to8,388,608 canvas pixels and4MiB ICC data. Indexed/Bitmap/ink profiles, semantic Actions, dither, DeviceLink/abstract profiles, full rich-layer conversions, working Color Settings/policies and complete Photoshop byte identity remain open. Capability schemas describe actual support.

The Adobe-compatible job output adapter now accepts the published `outputs[].iccProfile`. Standard profiles currently include `sRGB IEC61966-2.1`, `Adobe RGB (1998)` and `Gray Gamma 2.2`. Custom profiles use `{ "type": "custom", "name": "Profile name", "source": { "url": "https://example.test/profile.icc" }, "imageMode": "rgb" }`; `imageMode` is optional and, when present, must match RGB/gray/CMYK data. URL resources share existing job authentication, aggregate bounds and revocation checks; ICC itself is at most4MiB. Each output converts independently before any output is published, and encoding caches include profile identity. Non-RGB output ICC currently requires PSD/TIFF. Raster output may flatten supported profile-dependent stacks; PSD preserves supported editable layers and rejects conversions requiring unrequested destructive flattening. Other predefined profiles, Creative Cloud source variants, proprietary ACE behavior and full Adobe API equivalence remain unsupported or unqualified. No desktop preference route is invented in the Adobe interface.

## Working Color Settings (step226)

Authenticated `GET /v1/preferences/color-settings` returns `revision`, `settings`, `isPersistent`, `canUpdate` and `loadError`. The settings object always has `workingRGB`, `workingCMYK`, `workingGray` (ICC base64 or null for Photato’s default), `intent` (`perceptual`, `relativeColorimetric`, `saturation`, `absoluteColorimetric`) and `blackPointCompensation` (boolean). Profiles are limited to4MiB each and validated against their mode. Null resolves to sRGB, Generic CMYK or Gray Gamma2.2; supported32-bit operations linearize their working profiles.

Enable **Allow Color Settings changes** in the native API window before POST. It is separate from recovery and file-handling permissions and resets when the API stops. POST exactly `{"revision":"<current UUID>","settings":{"workingRGB":null,"workingCMYK":null,"workingGray":null,"intent":"relativeColorimetric","blackPointCompensation":true}}`. The five original settings fields remain required. Step227 adds optional policy/alert fields described below; omitted new fields retain their current values. Unknown fields and invalid types reject400. Authentication401, disabled permission403, stale revision/external edit409, oversized body413, content type415 and unreadable/failed settings storage422 leave current settings and documents unchanged. The request cap is3×base64(4MiB)+16KiB for this route only. Capability discovery supplies strict request/state schemas and runtime permission state.

Settings writes do not modify document content or Undo. Each native dialog/shared-document API operation captures a value snapshot. File New uses working spaces unless the user selects an explicit profile. `document.convertMode` uses the destination working profile and intent for omitted values; precision-only changes retain the document ICC. `document.assignProfile` with `removeProfile:true` retains numbers under the working-space interpretation. `document.convertProfile` still requires an explicit target ICC; omitted intent/BPC use the captured settings. Explicit command parameters override defaults.

Photato and Adobe resource jobs keep their own contract defaults. The published Adobe v2 API has no application Color Settings endpoint; no Adobe route is invented. Step227 adds opening/paste policies and captures actual working-CMYK proof profiles. CSF presets, Spot dot gain, dither and advanced blending remain open. Image Mode uses its existing engine; BPC applies to Convert to Profile.


## Color policies and profile review (step227)

Color Settings now also returns `rgbPolicy`, `cmykPolicy`, `grayPolicy` (`preserveEmbedded`, `convertToWorking`, `off`) and boolean `askMismatchOpening`, `askMismatchPasting`, `askMissingOpening`. Factory Photato values preserve embedded profiles with all alerts off. Any subset of these six fields can accompany the five required original fields in POST; omitted new fields preserve their existing values. The disk archive writes version2 and reads version1 with defaults; old version1-only readers reject the new archive rather than silently dropping its policies.

External document imports snapshot settings before decoding. Tagged files preserve, convert to the working profile, or become untagged according to their mode policy. Untagged files retain numeric samples under the captured working interpretation by default. Policy Off makes new documents untagged unless an explicit ICC is supplied. Native Photato archives retain their saved interpretation; an opening-policy override on a native import rejects400.

If an enabled alert requires a decision, binary document import returns HTTP409 before publishing a document. Its JSON includes `colorProfileReview` with `kind`, `source`, `destination`, `choices`, `importHeader` and `pasteParameter`. Retry the same payload with `X-Photato-Color-Decision` set to one of the returned choices: `preserveEmbedded`, `convertToWorking`, `discard`, `leaveUntagged`, or `assignWorking` as applicable. No native dialog opens for an API request. Invalid/unsupported decisions leave document state unchanged. The native missing-profile dialog also accepts a custom ICC; atomic custom-ICC binary import is still unsupported. Use `leaveUntagged` followed by `document.assignProfile` with `profileBase64`, or configure the working profile and choose `assignWorking`.

`clipboard.paste` accepts optional `colorDecision`: `convertAppearance` or `preserveNumbers`. An enabled mismatch alert returns the same409 review shape before editing. Without an explicit decision, the captured mode policy applies; numeric preservation is used for compatible untagged/Off destinations, otherwise content converts to destination appearance. Numeric preservation requires matching component modes and float-versus-integer storage. Native component Paste Into/Outside does not support this choice. Float32 source content copied into integer-only CMYK/Lab reduces precision on its private copy before conversion; the clipboard original remains unchanged. Native paste also rejects a changed clipboard or destination after review. Accepted paste creates one undoable history transaction.

Working CMYK proof setup captures the currently selected working ICC; stored proof presets retain their captured profile. Explicitly selecting `device:"workingCMYK"` through `proof.configure` refreshes that snapshot. Proof settings and application preference changes do not change image pixels or Undo. Adobe and Photato stateless resource jobs remain independent of desktop policies. No Adobe desktop preference/review route is invented.

ICC identity is currently byte-based, so metadata-only differences can prompt review. Rich unsupported conversions reject without implicit flattening. Restricted/ink clipboard contexts retain their existing behavior; drag/drop and additional import contexts need further integration. Placed Smart Objects retain their own embedded profiles. See [policy evidence](COLOR_POLICY_REFERENCES.json) for focused/full qualification and remaining limits.


## Native movie import and video placement (step233)

`POST /v1/documents/import` accepts `video/quicktime`, `video/mp4` and `video/x-m4v` (optional `X-Photato-Open-Format: movie`). It shares File/Open's native AVFoundation decoder and returns a newly shared document with one editable video layer. Original container bytes, including audio, and exact rational frame presentation timestamps are retained in native52. Variable frame timing is used during playback, trim and export. Frames are currently converted to SDR sRGB16; native audio playback/editing and HDR preservation remain open.

To add the imported clip to another shared document, send `video.place` with `sourceDocumentID` and `sourceRevision` to the target's commands endpoint, including the target revision. Placement converts every frame to the target RGB profile/depth, centers the layer and starts it at the current playhead. One Undo removes the new layer; the shared source remains unchanged. Source/target revisions and transfer permission are rechecked before commit. `video.place.cancel` takes the active `operationID` exposed as `video.placementOperationID`. Busy/stale/revoked operations return409, disabled transfers403, invalid parameters400, unsupported input/context422 and ordinary sharing-capacity limits remain in force.

Each clip's optional `movie` state contains `retainedBytes`, `audioTracks`, `audioPlayback:false`, `originalFrameRate`, `presentationTimes` and `endTime`. Times are objects containing integer `value` and positive integer `timescale`. Native downloads containing movie sources require `X-Photato-Archive-Version: 52`. Sequence-only archives remain51.

Admission limits: one unprotected video track; native host-supported MOV/MP4 codecs;64MiB source;512 frames; desktop1GiB/API128MiB retained frame/source budget, with the existing API4,194,304-pixel/64-layer cap. No partial imports and no external referenced media. The source's audio is preserved but currently silent, with an explicit Timeline indication. Longer disk-backed footage, keyframes/transitions, audio, full Render Video and independent Photoshop equality are still required. The pinned Adobe v2 contract has no dedicated movie import endpoint; these Photato operations do not invent Adobe routes.

Validation: 62 focused and 2,435 full optimized tests pass; independent lossless movie comparison matches 6,144 RGBA8 channel values. This does not establish Photoshop, arbitrary codec/HDR, live UI or universal runtime equality. See [movie import evidence](MOVIE_IMPORT_REFERENCES.json).

Keyframe validation (step234): Native video Timeline creation and Position/Opacity/Transform/Style keyframes, automatic capture, Linear/Hold interpolation, native53 and shared API editing pass 65 focused and 2,450 full optimized tests on 2,302 unchanged inputs. Independent PNG checks match 1,920 analytic RGBA8 channel values. Clip groups/splitting, transitions, audio, Render Video and full exact/live/platform parity remain open. Installed build221 and private universal build232 are unchanged. See [keyframe evidence](VIDEO_KEYFRAME_REFERENCES.json).

### Render Video (step241)

`video.render` renders frame animation or a video Timeline through the same native
Swift compositor, ColorSync conversion, audio mixer and AVFoundation encoder as
**File > Export > Render Video…**. Document transfers must be enabled, the current
revision must match, and playback/editing must be idle. The source document,
playhead, history and saved project remain unchanged.

```json
{"command":"video.render","revision":"<current revision>","parameters":{"codec":"h264","width":1920,"height":1080,"frameRate":30,"firstFrame":0,"lastFrame":119,"includeAudio":true}}
```

The required `codec` is `h264`, `hevc`, `proRes422`, `proRes4444` or `uncompressed`.
Successful output is binary MP4 (`video/mp4`) for H.264/HEVC, or QuickTime
(`video/quicktime`) for ProRes/uncompressed. Optional width/height default to the
source size; rate defaults to the video Timeline or 30 fps for frame animation.
Source frame ranges are zero-based and inclusive; the native dialog labels them
from 1. Optional H.264/HEVC `bitRate` is 100,000–200,000,000 bits/sec; other codecs
reject that option. `includeAudio` defaults true. `preserveAlpha` defaults false
and requires ProRes 4444 or uncompressed. Unsupported codec/hardware settings
fail explicitly instead of silently substituting another format.

Output uses square pixels and SDR Rec.709, converted from the document working
ICC profile. The encoder receives 8-bit BGRA. Transparency is composited on black
unless preservation is requested. H.264/HEVC require even dimensions. Maximum
size is 8192 per dimension and 33,554,432 pixels, with at most 100,000 output
frames. API output is bounded to 128 MiB; desktop output is bounded to 2 GiB.
Decoded audio sources and the mix each have a separate 128 MiB API budget.

Keyframes/transitions evaluate at each output timestamp. Range duration rounds
up to the next output frame, holding the final image and padding audio with
silence where needed. Frame-animation delays use the playback minimum of 0.02
seconds. Export produces one pass; document loop settings are not movie flags.
Audio is mixed to 48 kHz stereo: MP4 uses 192 kbps AAC, QuickTime uses Float32 PCM.
There is no audio track if no audible source clips exist.

`videoRender.operationID` exposes the active encoder. Send
`video.render.cancel` with that `operationID` to cancel while rendering. Closing
the document, cancellation, source/revision changes, or revoking its share or
transfer permission prevents delivery. Native publication stages the completed
movie and replaces the selected destination only after validation.

DPX, HDR, non-square pixel aspect ratios, work-area controls, complete Adobe
presets/action descriptors and exact Photoshop/runtime/platform qualification
remain open. Native encoder output is not claimed byte-identical to Adobe's. Uncompressed QuickTime stores row-stride metadata; the installed FFmpeg6.1 reader ignores it for nonaligned BGRA widths. Apple native decoding and direct packet checks preserve the pixels, but general raw-movie reader interoperability remains unqualified.
The pinned Adobe v2 contract has no dedicated Render Video endpoint; this is a
Photato extension, with no invented Adobe route.


## Variables and Data Sets — step247

The optional Photato API now registers twelve `variables.*` commands. The qualified native checkpoint passes80 focused and2,588 full optimized tests; see [Variables evidence](VARIABLES_REFERENCES.json). This is not complete Photoshop Variables parity. These operations use the same native variable engine and prepared Undo transaction as Image > Variables. The pinned Adobe v2 contract has no dedicated Variables route; corresponding Photoshop Actions descriptors are not yet qualified.

- `variables.preview`: render draft `definitions`, `dataSets` and optional `dataSetID` to a PNG without changing the template, history or revision. Existing embedded images are available to the draft. Sharing/source changes prevent preview delivery.
- `variables.define`: replace `definitions`, each with `name`, `layerID`, `kind` (`visibility`, `textReplacement`, `pixelReplacement`), optional `id` and pixel-only `pixelOptions`. Identical names link layers of the same kind. Pixel options support `fit`, `fill`, `asIs`, `conform`, nine canvas anchors and `clipToBounds`. Retaining an existing binding ID preserves its original image rectangle.
- `variables.configure`: atomically replace `definitions` and `dataSets`, optionally apply `dataSetID`. Existing uploaded image assets are retained.
- `variables.rename`: rename `oldName` to `newName` across bindings and row values.
- `variables.dataSets`: replace or append (`append: true`) typed named rows. Each row has optional `id`, `name`, and a `values` array. Each value has `variable`, `kind`, and exactly one of `visible`, `text`, or `imageID`. A null imageID means Do Not Replace. An omitted variable leaves that layer property unchanged.
- `variables.image`: import still-image base64 `data` with a display `name`; optional `imageID` replaces that asset ID. Images are decoded and converted to the current working profile, then embedded. `variables.image.remove` removes an unused `imageID`.
- `variables.import`: parse decoded CSV/TSV `text`, optional `delimiter` (`comma`/`tab`), `firstColumnNames`, `replaceExisting` (default true) and `imageReferences` entries `{reference,imageID}`. Every variable must occur in the header. Image references map only to embedded assets; the API never reads server-local paths or URLs from CSV. Quoted multiline text is supported. Imports fail atomically on malformed data or missing assets.
- `variables.apply`: apply `dataSetID` as one undoable transaction. `variables.clear` removes definitions, rows and assets while preserving the current artwork.
- `variables.export`: requires enabled document transfers and `format` (`photato`, `psd`, `psb`, `png`, `tiff`, `jpeg`); optional `prefix` and `dataSetIDs` select output. Returns `application/zip` containing numbered variations and `data-sets.json`. Every row starts from the same original template. Native output retains variables; rendered non-native outputs omit template metadata. Export does not edit the source or its history.
- `variables.export.cancel`: cancel the current `operationID`, obtained from `variables.exportOperationID` in document state. Transfer/share revocation and source changes prevent output delivery.

All commands retain the ordinary `{command,revision,parameters}` envelope and busy/stale revision guards. `variables` in document state exposes definitions, placement frames, typed rows, image metadata, active row and export ID. Pixel data are not exposed in state. Capability discovery includes parameter/state schemas and limits. Imports allow up to3,000,000 base64/text characters within the4MiB command-body bound; native template budgets are1,536 bindings,1,000 rows,256 images,16MiB metadata and512MiB assets. Output is bounded to128MiB.

Save templates as native archive61, and explicitly request `X-Photato-Archive-Version: 61` on native downloads. Direct PSD template save rejects unsupported variable metadata rather than silently dropping it. Photoshop Variables XML/interchange, Actions descriptors, broader mode/depth lifecycle, main-canvas preview, exact output/UI behavior and live/platform qualification remain open.

RGB Assign/Convert Profile now updates embedded variable replacement assets through the existing native color-management path, preserving IDs, row references, alpha and hidden RGB. The artwork’s numeric samples remain unchanged on assignment; assets for future placement retain managed appearance. Both profile APIs use the same atomic transaction and Undo. Broader mode/depth and Photoshop-exact conversion behavior remain open.

## Contact Sheet II — step248

`document.contactSheet` generates all pages through the same native Swift engine as File > Automate > Contact Sheet II. Send `sources` as one to seven objects containing an explicitly shared document `id` and its current `revision`; the command target must be among them. Optional `name` sets the page prefix (default ContactSheet). Each source is a still document. Source documents and their history remain unchanged; new pages are unsaved, independently editable documents.

Optional `settings` supports units (`inches`, `cm`, `mm`, `pixels`), width/height, resolution in pixels/inch, columns/rows, placeAcrossFirst, autoSpacing, horizontal/vertical gaps in page units, rotateForBestFit, caption, font (installed PostScript name), fontSize in points and flatten. Color settings are mode (`rgb`, `grayscale`, `cmyk`, `lab`), depth (`8 bit`, `16 bit`, `32 bit`, where supported), and optional base64 ICC profile. Unknown fields, invalid types/UUIDs/profile data and impossible layouts reject. Omitted settings use the native defaults. The full default 8×10-inch/300ppi page exceeds the API's existing4MP sharing limit; lower resolution or dimensions explicitly for API output.

HTTP201 returns `documents` (an array of ordinary shared document states), `pages`, `images`, and `placements` (zero-based source/page/column/row, pixel x/y/width/height and rotated). Document uploads/downloads must be enabled. Every output must fit the existing shared-document4MP/64layer/128MiB limits and the eight-document sharing pool must have room for all pages. No page is published if any page fails. Native preparation additionally limits256 sources,32 pages,64MP combined page area,8MP per page and512MiB source/output storage. The API has no arbitrary local filesystem input; desktop source selection uses explicit user file/folder access.

`document.contactSheet.cancel` takes the operationID exposed in a participating source's contactSheet state. Transfer disablement, source revocation, stale revisions or interrupted document lifecycle discard unpublished results. Settings/source schemas and limits are advertised under contactSheet capabilities; native workspace state reports open/loading/rendering/ready/sourceCount separately from API operation activity.

Example parameters: `{"sources":[{"id":"<shared UUID>","revision":"<current revision>"}],"settings":{"units":"pixels","width":1200,"height":1500,"resolution":150,"columns":5,"rows":6,"caption":true,"flatten":true}}`.

The pinned published Adobe Photoshop v2 contract has no dedicated contact-sheet endpoint. An Execute Actions descriptor is not yet qualified. Photoshop exact spacing/resampling, caption truncation and font defaults, Bridge integration, folder grouping and full supported-platform acceptance remain open. The qualified native increment passes38 focused and2,599 full optimized tests; see [Contact Sheet evidence](CONTACT_SHEET_REFERENCES.json). Full Photoshop equivalence remains open.

After a Contact Sheet preparation is cancelled or rejected, refresh all source document states before retrying: resuming source rendering can invalidate their revision tokens even though document contents and history remain unchanged. Missing caption fonts reject before publication, including layered output.

## Crop and Straighten Photos — step249

`document.cropStraighten.detect` returns detected photo rectangles without creating documents. `document.cropStraighten` uses the same native engine as **File > Automate > Crop and Straighten Photos** to create separate unsaved documents. Both accept optional `layerID` (defaults to the active layer) and `forceSingle` (defaults to false, matching the native Option modifier). The document’s current selection limits detection. Ordinary revision-guarded command envelopes apply.

Detection returns HTTP200 with `photos` (centerX, centerY, width, height, angle and area), `layerID`, `region` and `preservesNativeComponents`. Coordinates are document pixels; angle is degrees. An empty scan returns an empty photos array. Extraction returns HTTP201 with those fields plus `count` and `documents` containing shared document states. No-photo extraction fails with422. Creation prepares every output before publishing any; the source and its history stay unchanged. Output names are `<source> copy <N>` with one Background layer, retained depth/profile/resolution and transparency/position protection.

Detection requires an explicitly shared source. Creation also requires native document-transfer permission and a free sharing slot for every output. The8-document sharing limit and4MP/64-layer/128MiB API document limits apply. Native extraction supports8MP sources and individual photos,64 detections,32MP combined outputs and512MiB budgets. Still component-mode RGB/Grayscale/CMYK/Lab documents are supported; artboards, frames, animation, palette/bit and ink modes remain unsupported.

Use `document.cropStraighten.cancel` with the active `operationID` from the source’s `cropStraighten` state. Cancellation, source changes, close/recovery interruptions and revoked sharing prevent publication. Invalid parameters return400, disabled transfers403, stale/busy state409, invalid scan content422 and insufficient sharing capacity429.

Ordinary native-mode pixel scans retain numerical component planes. Complex non-RGB compositions use the existing RGB compositor and profile conversion, disclosed as `preservesNativeComponents: false`. Detection derives from licensed PhotoCraft source; exact Photoshop segmentation, resampling and complex-mode composition remain unqualified. The pinned Adobe contract defines smart auto-crop/subject bounds, not multi-photo scan extraction. No Adobe route is repurposed; Execute Actions descriptors remain open. The qualified native increment passes19 focused and2612 full optimized tests; see [Scan extraction evidence](SCAN_CROP_REFERENCES.json). Full Photoshop equivalence remains open.

## Image Processor — step250

`document.imageProcessor` exports shared still images through the same native engine as **File > Scripts > Image Processor**. It requires document-transfer permission and `sources` containing1–8 unique shared UUID/current-revision pairs, including the command target. Optional `settings` uses the same JSON object as the native Load/Save controls. Source pixels, metadata and history remain unchanged. The response is HTTP200 `application/zip` containing JPEG, PSD and TIFF folders, plus `image-processor.json` records with source, file, width, height and format. All outputs prepare before any archive is returned.

Each of `jpeg`, `psd` and `tiff` has `enabled`, `resize`, `width` and `height` fields. Dimensions are1–30,000 pixels, preserving aspect ratio when resize is enabled. Other fields are `jpegQuality` (0–12), `convertJPEGToSRGB`, `includeICC`, `tiffLZW`, `maximizeCompatibility`, `dontEnlarge`, `copyright` (up to4096 UTF-8 bytes), optional loaded `actionID`, and `useFirstImageProfile`. Unspecified values use the native settings defaults. `maximizeCompatibility` must currently be true: standalone PSD output includes its rendered composite. First-profile reuse converts other source profiles; it does not present Camera Raw’s interactive first-image settings. Actions requiring initial clipboard or a master palette are unsupported in this workflow.

`document.imageProcessor.cancel` accepts the current operation UUID exposed in each participating source’s `imageProcessor` state. Stale revisions or busy work reject with409; invalid settings/sources with400; disabled transfers with403; unsupported source/codec/action data with422. Revocation, cancellation and source changes return no archive. Each source is bounded to8MP/512MiB; the whole output ZIP is limited to128MiB. Native file/folder processing supports256 sources and stages all output before publishing unique filenames, without overwriting existing files or following symlinked format folders.

The qualified native increment passes 26 focused and 2623 full optimized tests; see [Image Processor evidence](IMAGE_PROCESSOR_REFERENCES.json). Exact Photoshop encoder/resampling/defaults, all Actions/format contexts, same-source-folder orchestration and interactive first-image raw settings remain open. The pinned Adobe contract has no dedicated Image Processor route; existing edit/execute-actions interfaces remain distinct.

## Video Frames to Layers — step251

POST movie bytes to `/v1/documents/import` with a supported MOV/MP4 Content-Type and optional `X-Photato-Movie-Frames` JSON. Omit the header for the existing one-video-layer import. Include `{}` to create editable raster layers and frame animation using all frames. Fields are `selectedRange` (default false), `start` and `end` in seconds (defaults0 and1), `every` (integer1–10000, default1), and `makeAnimation` (default true). Selected timestamps lie in `[start,end)`; every-N sampling starts at the first eligible frame. Frame delays cover the intervals between retained samples and the selected end. Filtering precedes output allocation, so a short subset of a longer movie can fit within output limits.

The native File > Import > Video Frames to Layers workflow uses the same decoder and options. The response is HTTP201 new shared unsaved document state. Each frame has its own editable raster layer; optional frame animation changes visibility with precise delays. Other documents, history and source bytes remain untouched. The decoder creates SDR sRGB16 layers; omit `X-Photato-Color-Decision` here. Source audio belongs to the ordinary movie/Timeline workflow and is not imported into frame animation.

`GET /v1/capabilities` exposes `movieFramesImportState` with native dialog/loading/importing state and the active `uploadOperationID`. Cancel an upload with `POST /v1/documents/import/movie-frames/cancel` and JSON `{"operationID":"<uuid>"}`. Cancellation, transfer permission revocation, service stop or lifecycle conflicts publish no new document. Existing bearer, transfer permission, share capacity and document lifecycle guards apply. Invalid options return400, disabled permission403, cancelled/conflicting operations409, unsupported media415/422, and capacity/resource limits429/413 or decoder422.

Source containers remain limited to64MiB. Native decoded storage is limited to1GiB with512 layers or256 animation layers; API output remains4MP/64layers/128MiB. Larger/HDR media, exact Photoshop range/default/depth/codec behavior and live/platform qualification remain open. The existing191 typed document commands are unchanged: this operation extends the separately described binary-upload API. No corresponding dedicated endpoint exists in the pinned Adobe v2 contract, and none was invented. The native increment passes 16 focused and 2632 full optimized tests; see [Movie frame import evidence](MOVIE_FRAMES_REFERENCES.json).

## Generic PDF page import — step252

PDF pages use the same native CoreGraphics renderer in File > Open and the optional API. All routes require a current bearer token and document-transfer permission. The existing `/v1/documents/import` single-document result is unchanged; PDF selection has a separate multi-document route. Native page import, HTTP/native output equality, cancellation, permission revocation and invalid/busy/stale behavior pass automated integration checks. The final source passes29 focused and2648 full optimized tests; Photoshop-exact/live/platform qualification remains open.

| Operation | Request | Result |
|---|---|---|
| Inspect | `POST /v1/pdf/inspect`, binary `application/pdf` | Page numbers, rotations, oriented media/crop/bleed/trim/art sizes in PDF points, encrypted flag and optional PNG thumbnails. |
| Import selected pages | `POST /v1/documents/import/pdf`, binary `application/pdf` | HTTP201 `{documents:[shared document state,...],count:N}`. Every selected page becomes a new dirty unsaved document. |
| Cancel | `POST /v1/documents/import/pdf/cancel`, JSON `{"operationID":"uuid"}` | Requests cancellation of the active PDF inspect/import worker; stale IDs return409. |

Optional headers:

- `X-Photato-PDF-Options`: at most4KiB JSON; import only. Supported fields: `pages`(distinct1-based integers), `crop`(`bounding`,`media`,`crop`,`bleed`,`trim`,`art`), `resolution`(1–10000ppi), optional positive integer pixel `width`/`height`(or null), `constrainProportions`, `antialias`, `mode`(`rgb`,`grayscale`,`cmyk`,`lab`) and `depth`(`8 bit`,`16 bit`,`32 bit`). CMYK/Lab32 reject. Unknown fields and invalid types reject400.
- `X-Photato-PDF-Thumbnails`: inspection only; a JSON array of up to32 distinct page numbers. Returned PNGs fit160×160, encoded as base64 in the `thumbnails` object keyed by page number. Omit for metadata only.
- `X-Photato-PDF-Password`: base64-encoded UTF-8, at most1024 decoded bytes. It is not returned in state or persisted in a document/source association. Incorrect or missing required passwords return422.
- `X-Photato-Name`:1–240 printable ASCII characters. Default `Imported PDF`; multiple documents append their source page number.

Defaults are first page, bounding crop,300ppi, constrained proportions, antialiasing and RGB8; exact Photoshop defaults remain unqualified. Without explicit dimensions, pages keep their individual physical size at the chosen resolution. With constrained dimensions, one shared scale fits selected pages into the maximum requested bounds. Unconstrained explicit dimensions stretch each page. Bounding currently uses raster alpha within Trim Box at requested resolution; blank pages retain Trim Box.

The source PDF is limited to64MiB and4096 pages. Native selection supports32 outputs; API output additionally needs one of eight sharing slots per page,4,194,304 pixels/page and128MiB combined output/render memory. Input validation and all page rendering complete before publication. Cancellation, transfer revocation or lifecycle changes publish no documents. CoreGraphics rendering itself can finish its current page before cancellation is observed. Existing documents and source bytes are unchanged. No PDF is silently associated for Save/Revert; choose Save As for the imported pages.

`GET /v1/capabilities` exposes `pdfImport` settings/result schemas and `pdfImportState` (native open/loading/rendering and API `uploadOperationID`). API errors include400 invalid settings,401 authentication,403 disabled permission,409 busy/stale/cancelled,413 source size,415 content type,422 decode/render/password/resource limits and429 share capacity. Full native/API pixel equality is tested on owned fixtures; that does not establish Photoshop byte equality.

Embedded-image extraction, PDF-backed vector Smart Objects, editable Photoshop PDF data, custom import profiles, comprehensive metadata/annotations/forms/large files and exact/live/platform qualification remain open. The pinned Adobe v2 contract has no corresponding desktop PDF-selection endpoint; no Adobe route has been added. [Working evidence](PDF_IMPORT_REFERENCES.json).

## Embedded PDF images — step253

`POST /v1/pdf/images` accepts the same binary PDF/password/name/thumbnail headers as page inspection and returns `{images:[{number,page,width,height,bitsPerComponent,imageMask,colorSpace}],thumbnails:{...}}`. Image IDs are1-based in painted page/Form order; reused XObjects are deduplicated and inline images have separate IDs. Masks attached to an image and unpainted resources are not separate entries. A document without images returns an empty list. This ordering is not yet qualified against Photoshop.

`POST /v1/documents/import/pdf/images` uses `X-Photato-PDF-Options` with `images`(up to32 distinct IDs), `resolution`(1–10000ppi), `mode` and `depth`. Defaults are image1,72ppi,RGB8. Resolution changes print size; intrinsic pixel dimensions are retained. Page crop/size fields and unknown settings reject400. The result and atomic new-document publication match page import. Every image uses the same Swift/CoreGraphics extraction and conversion path as the native Images selector.

Both routes share the existing PDF cancel endpoint, token/transfer permission, busy/stale/lifecycle guards, errors,64MiB input,8 API sharing slots,4MP/API image and128MiB API decoded/output budget. Native rendering uses512MiB; each extracted in-memory image PDF is capped at64MiB. The image graph copier preserves supported palettes, Decode arrays, profiles and mask streams. CoreGraphics stream decoding/rendering cannot be interrupted inside a single framework call; guards check before/after and between scanner callbacks.

`pdfImport.images` exposes endpoint/settings/result discovery, while `pdfImportState.content` reports `pages`, `images` or null for the native chooser. The191 typed document commands and existing Adobe routes are unchanged: the pinned Adobe contract has no corresponding embedded-image extraction endpoint. The final candidate passes40 focused and2660 full optimized tests, including actual native/HTTP matching image output and cancellation/revocation/lifecycle guards. Exact Photoshop image order/dedup/defaults, color/mask/depth semantics, pattern/annotation images, retained-vector Smart Objects, Photoshop editing data and live/platform parity remain open.

Step253 rendering correction: shared page/image rasterization uses a16-bit intermediate before converting to the requested editing depth. Owned probes reveal incorrect image scaling in CoreGraphics Float32 PDF bitmap contexts on this platform. This preserves tested source geometry but leaves Float32 PDF/HDR precision and Adobe-exact rasterization unqualified.


## Retained PDF Smart Objects — step255

`POST /v1/documents/{id}/smart-objects/pdf` accepts an `application/pdf` body for an explicitly shared RGB document, with transfers enabled and required `X-Photato-Revision`. `X-Photato-PDF-Options` is a strict JSON object: `page` (1…4096, default1), `crop` (bounding/media/crop/bleed/trim/art), `resolution` (1…10000, default72), `antialias` (defaulttrue). Placement allows `fit` (defaulttrue). Replacement instead supplies `layerID`, with `preserveSize` and `allInstances` (both defaulttrue). Invalid/irrelevant options reject. `X-Photato-Name` supplies a printable ASCII filename without path separators, up to240 bytes; default Contents.pdf. Success returns HTTP200 target state and one native Undo transaction.

Select an embedded image with `image` (1…4096) instead of `page`/`crop`; combining those selectors rejects with400. Images retain intrinsic dimensions and the original whole PDF. Optional placement-only `transform: {a,b,c,d,tx,ty}` applies a document-coordinate delta after centering/fit, in the same Undo transaction. Singular/invalid transforms reject. Per-document `pdfPlacement` reports native chooser/preparing/transform/committing/idle state; mutating API requests reject while a native draft is open.

The original PDF, selected page or image and fixed point-space crop are retained. Layer state includes `smartObject.pdfSource`; source download returns the original whole PDF. Native downloads must negotiate `X-Photato-Archive-Version: 62`. The shared native/API Rasterize operation bakes the enlarged PDF result without losing its document geometry or mask coordinates.

`GET /v1/capabilities` exposes `pdfSmartObjectOperations`, keyed by shared-document UUID. Cancel with `POST /v1/documents/{id}/smart-objects/pdf/cancel` and `{"operationID":"..."}`. Preparation uses existing document/share/token/revision guards and checks transfer permission again before commit. Actual HTTP busy, wrong-operation cancellation, cancellation and transfer-permission revocation checks pass without publishing document/history changes.

The Adobe-compatible Smart Object resource adapter accepts PDF through existing create-composite/edit file inputs. `autoResize:true` matches the original source dimensions/resolution; false retains the selected default PDF source size. No Adobe route or page-selection field is invented. The actual create-composite PNG resource job matches the native engine output; editable PDF-backed PSD/PSB output currently rejects explicitly.

Native Place PDF selection, Page/Image previews, Return/Cancel, Replace Contents and frame placement are implemented and tested, including failed-transform recovery and in-flight cancellation. Source editing, linked files, PDF Warp, editable PSD/PDF interchange and live/exact/platform qualification remain pending. Native source/render limit is8MP and original PDF limit64MiB; shared-document limits apply before publication. Encrypted originals reject; passwords are not persisted. CoreGraphics uses the existing16-bit intermediate, so Float32/HDR precision and byte-identical Photoshop behavior remain unqualified. See `PDF_SMART_OBJECT_REFERENCES.json` for the current test scope.
