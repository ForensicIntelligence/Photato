**Scheduling update402:** C01 is included in the major quick-win sweep, followed by its remaining implementation during major stillneeded and fidelity/qualification during major cleanup. It no longer waits for full S05 closure. The historical sequencing statements below are superseded; all C01 scope and acceptance remain. First overall quick win is L01/AUT02 Delete All Empty Layers. [Current order](CURRENT_WORK_ORDER.md).

# Next major function: C01 — Component visibility and edit targeting

Confirmed again by the maintainer on 3 November2026. Start after S05 is complete and tested. S05 is still the active major function; C01 is queued.

Retain the complete original scope: separate active editing channels from visible channels; grayscale/color display; temporary pixel/vector-mask rows; real painting/filter targets; eye gestures and Command2–5/other factory shortcuts. Include current color modes/depths, mask/Quick Mask transitions and unavailable-context validation. Do not turn a viewing control into an unrelated edit.

Use observed Photoshop2026 behavior, the factory shortcut catalogue and actual document outputs. Verify native controls, effective modifier cursors, cancel/Undo, document persistence and both API interfaces where applicable. Viewing/target changes should have the same history effects as Photoshop, and native/API edits must target the same channel values. Preserve every package acceptance criterion and keep broader output/platform gates explicit.

[Current work](WORKING_CHECKPOINT_376.json) · [Full package plan](FUNCTION_PHASES_376.json)

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

## Checkpoint371 integration notes

Current hidden Quick Mask Fill/Invert/modern painting and permitted Gaussian are tested natively/API. Independent pixel Invert menu/API outputs match the owned RGB8 reference. C01 still needs the complete independent component/mask visibility and edit-target workflow, remaining channel-specific filter availability, target wording and transition qualification. Retain all original scope. S05 remains in progress; do not infer closure from this increment.

## Checkpoint372 scheduling confirmation

The maintainer again asked for the next complete major feature. C01 remains selected, with its entire original scope and acceptance criteria. Current Photoshop confirms independent editing targets while the temporary Quick Mask remains present; the shared S05 target-transition dependency is now tested. Finish S05 before starting C01. C01 must still complete independent component/auxiliary eyes, grayscale/color display, temporary pixel/vector-mask rows, real painting/filter targets, eye gestures, factory shortcuts and native/API workflow tests. No package is closed by this scheduling entry.

## Checkpoint373 audit

C01 remains next, with its original full scope. The shared S05 auxiliary paint-color context is tested. The complete S05 audit retains a real large-selection file gap: auxiliary-only Multichannel PSD/PSB decoding still uses the dense ink-plane limit. Finish that workflow and remaining S05 requirements before switching packages; retain general palette/output/platform/performance gates. [S05 audit](S05_ACCEPTANCE_373.json).

## Checkpoint374 scheduling confirmation

C01, Component visibility and edit targeting, remains the next complete major feature. It completes the professional workflow of inspecting a color component, editing only that component and returning to the composite. The shared S05 large-selection file gap now has native/API, independent numerical and owned Photoshop reference tests. Finish the remaining full S05 requirements before switching; retain every original C01 scope and acceptance criterion. [Current S05 audit](S05_ACCEPTANCE_374.json).

## Checkpoint375

C01 remains next with its entire original scope. The current S05 large-selection file handoff is checked after correcting PSB wide tagged-block framing. Shared paint palettes and remaining S05 requirements stay open; complete them before starting C01. [S05 audit](S05_ACCEPTANCE_375.json).

## Checkpoint376

C01 remains next with its entire original scope. The S05 shared-palette prerequisite now has native/API, revision, history, persistence and live two-document tests. Consolidate the retained S05 acceptance evidence and remaining functional requirements before switching packages; preserve full custom-gray/profile/mask/component and final platform/output gates. [S05 audit](S05_ACCEPTANCE_376.json).


Checkpoint379 closes the unsupported8/16-bit Multichannel Quick Mask file path within focused scope. Full S05 remains in progress; the next concrete target-context audit is layer-mask/smart-filter-mask palette switching (currently keyed only to editingChannel). C01 stays next after complete and tested S05; no original C01 scope is removed. See [379 evidence](MULTICHANNEL_QUICK_MASK_379.json).


Checkpoint380 implements the separate shared layer/Smart Filter mask palette and API target selection, preserving independently selected masks when Q is removed. It does not close C01 temporary rows, visibility, filter targets or full S05. The current compiled live check awaits unlock; next audit checks mask/component target cleanup. [Evidence](MASK_PAINT_PALETTES_380.json).


Checkpoint381 repairs the shared nil-mask-owner lifecycle so leaving Smart Filter masks restores image operations through native/API paths. Focused regression tests include actual merge and Undo. Current native acceptance awaits unlock; full S05 and C01 scope remain unchanged. [Evidence](MASK_TARGET_LIFECYCLE_381.json).


Checkpoint382 executes the full current3,845-case inventory on both architectures, with failures retained. No C01 scope/status change or product version change. Repair current lifecycle/API/fixture failures and finish S05 live acceptance before switching packages. [Inventory](CURRENT_TEST_INVENTORY_382.json).


Checkpoint383 repairs shared lifecycle test setup and current-protocol expectations. All740affected cases pass per architecture;43old full-baseline failures now pass within this focused run. The full inventory was not rerun. Current S05 live acceptance and original C01 scope remain open. [Evidence](LIFECYCLE_REGRESSION_REPAIRS_383.json).
