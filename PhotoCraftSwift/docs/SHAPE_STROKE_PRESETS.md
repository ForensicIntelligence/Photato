# Shape stroke presets

Choose a shape tool and open Tool Settings, or select a live shape layer and open Properties. Set a stroke paint other than None to show the stroke controls. Stroke Preset offers Solid, Dashed and Dotted. Custom identifies retained or manually edited dash values; opening the sheet does not replace them. Dash/gap, phase, cap and width-relative controls remain available.

Solid clears dash and phase. Dashed uses width-relative `[3,3]` with butt caps. Dotted uses width-relative `[0,2]` with round caps. Phase resets to zero. Paint, width, alignment, join, miter, opacity, path mode, geometry and placement are retained. These are Photato convenience values. Exact Photoshop spacing, defaults and output are not yet qualified.

Editing a layer previews without changing the document. Cancel discards the preview; Apply makes one existing shape edit with Undo/Redo. Tool Settings updates the template without adding a document edit. A drawing gesture captures its starting definition.

The existing optional API command envelope supports the same values:

```json
{"command":"shape.edit","revision":"<current revision>","parameters":{"operation":"configure","layerID":"<shape UUID>","strokePreset":"dotted"}}
```

Existing-layer configure accepts the preset alone or with a complete definition. Creation still requires a definition. Existing `shape.configure` changes the tool template with the optional preset, while retaining unrelated values. Full-definition clients remain supported. `shapes.templateStrokePreset` and `shapes.activeStrokePreset` report the derived classification; `shapes.strokePresets` publishes convenience values, behavior and limits. A missing active shape reports null. Custom is a state classification and is rejected as a preset request.

Usual authentication/sharing, revision, busy, target and shape validation apply. Malformed or unknown preset requests reject without document/history changes; the existing native shape command performs accepted edits. The typed catalog remains243, native archive86 and Actions maximum46. There is no new Adobe endpoint or new serialized preset field.

Public [Adobe stroke guidance](https://helpx.adobe.com/photoshop/desktop/draw-shapes-paths/create-shapes/set-and-manage-shape-stroke-options.html) describes the three choices. Our focused tests check native/API byte equality, rendering, history, cancellation, persistence and guards; these are distinct from independent Photoshop equivalence. Full G03 and all original acceptance remain open. See [the current evidence](SHAPE_STROKE_PRESETS_408.json) for attempts and remaining qualifications.

Normal optimized qualification passes156 identical ordered affected cases per architecture, including24 new cases across increments406–408 and all eight new stroke-preset cases. The isolated universal package passes strict signing, both macOS 14 targets and ZIP extraction checks. The live408 native control/drawing/history/Quit check awaits Mac unlock. Earlier Debug curved-stroke comparison and signal10 failures remain recorded; this is not a full-current-suite pass.
