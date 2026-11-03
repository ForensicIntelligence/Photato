# Next major function: C01 — Component visibility and edit targeting

Confirmed again by the maintainer on 3 November2026. Start after S05 is complete and tested. S05 is still the active major function; C01 is queued.

Retain the complete original scope: separate active editing channels from visible channels; grayscale/color display; temporary pixel/vector-mask rows; real painting/filter targets; eye gestures and Command2–5/other factory shortcuts. Include current color modes/depths, mask/Quick Mask transitions and unavailable-context validation. Do not turn a viewing control into an unrelated edit.

Use observed Photoshop2026 behavior, the factory shortcut catalogue and actual document outputs. Verify native controls, effective modifier cursors, cancel/Undo, document persistence and both API interfaces where applicable. Viewing/target changes should have the same history effects as Photoshop, and native/API edits must target the same channel values. Preserve every package acceptance criterion and keep broader output/platform gates explicit.

[Current work](WORKING_CHECKPOINT_370.json) · [Full package plan](FUNCTION_PHASES_370.json)

## Why this follows S05

The Channels panel already carries Quick Mask and saved selections. Completing component visibility and targeting turns that foundation into a usable professional channel-editing workflow: inspect a component, edit that component without changing its neighbours, then return to the composite. It also removes ambiguity about which pixels a brush or filter will change.

## Implementation sequence

1. Audit the existing visible-channel and edit-target state against Photoshop on owned RGB, CMYK, Lab and grayscale documents. Record current gaps rather than rebuilding working paths. Keep mode/depth restrictions explicit.
2. Complete native panel controls and canvas presentation: independent eyes and selection, grayscale/colour display, temporary mask rows, transitions back to the composite, and factory shortcuts. Verify modifier actions against the reference before assigning cursors.
3. Route supported painting and filtering through the selected numerical components or mask. Preserve other components, alpha and layer content. Include preview, cancel, one Undo step, redo and saved/reopened state where Photoshop retains it.
4. Expose identical state, availability and editing semantics through the Photato API. Add Adobe-compatible support only for operations actually defined by its public contract. Run focused native/API equivalence tests, independent owned-file comparisons and live UI checks; record architecture/runtime coverage and every remaining fidelity limitation.

The package's original acceptance criteria remain unchanged. Start this sequence after S05 is complete and tested. Do not count a visible menu, a partial target implementation or a passing round-trip test as complete Photoshop parity.

## Checkpoint369 audit

The initial C01 audit found a shared S05 prerequisite: the temporary Quick Mask eye exited the mode, and hidden-target brush behaviour needed direct verification. The owned Photoshop check confirms eye visibility and a separate hidden-brush rejection. Finish that native/API correction and its tests under S05 before starting the complete C01 package. All original C01 scope and acceptance criteria above remain.

## Checkpoint370 scheduling confirmation

The maintainer requested the next complete major feature again. C01 remains the choice because it completes the channel inspection and editing workflow built on S05. Source369 has now tested the shared Quick Mask eye and hidden-brush prerequisite. Remaining S05 contexts must be checked before switching packages. Complete the full C01 workflow and focused tests together; defer optional numerical refinements while major workflows are missing. No C01 completion is claimed by this scheduling entry.
