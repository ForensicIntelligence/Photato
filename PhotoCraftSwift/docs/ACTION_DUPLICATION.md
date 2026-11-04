# Duplicate saved actions

Open Window > Actions, select a saved action and choose Duplicate from the panel menu. The new copy is selected. Its action and step IDs are new; ordered commands, names, enabled flags and operation payloads are retained. Editing or deleting the copy leaves the source unchanged. Duplication changes the saved library and its revision, without adding a document pixel edit, dirty state or Undo entry. Playing the copy uses the existing action transaction and one Undo.

The current default name appends copy, then numbered suffixes unique within the destination set. The source stem is shortened by whole characters to keep the name within 256 UTF-8 bytes. The copy is inserted after its source. Exact Photoshop naming/order remains unqualified. The current library limits remain 128 actions, 512 steps per action and 16 MiB. Invalid/full/corrupt libraries and failed saves retain the prior library through the existing atomic save path.

The Duplicate item applies to a whole saved action. It is disabled without a selected action, while a command is selected, during recording or an active edit, and for unavailable libraries. Command/set duplication, Option-drag and the full Actions hierarchy remain open. No global shortcut is invented. Existing step Up/Down controls and `step.move` continue to work.

The existing optional API uses the usual POST `/v1/documents/{id}/commands` envelope:

```json
{"command":"actions.manage","revision":"<current revision>","parameters":{"operation":"duplicate","actionID":"<source action UUID>"}}
```

Optional `name` and `set` override the copy only. The result contains `state`, `revision`, `sourceActionID` and copied `action` information. Availability is `actions.canDuplicate`; `actions.duplication` publishes the behavior and result schema. Library revision changes invalidate stale clients, and existing authentication/share/busy/revision guards apply. Missing/irrelevant or malformed parameters reject; unknown sources and library validation failures retain the existing action-library error behavior. There is no new typed command or Adobe route. The catalog remains 243; native archive 86 and Actions maximum version 46 are unchanged. Photato action files are not Adobe ATN files.

All 34 focused arm64 Debug tests pass, including eight new cases. Tests cover independent identities/payloads/editing, Unicode names, persistence/reopen/import/export, limits/corruption/write rollback, native/API state and guards, and source/copy playback producing identical native document bytes with one Undo. These are focused tests; the full current suite is not claimed to pass. Earlier Debug failures remain recorded. Normal optimized universal qualification is deferred to a stable breadth batch.

The actual native sandboxed app recorded an owned Invert, duplicated it through the panel menu, selected and played the copy, and returned to the clean source with two Undos. An independent JSON check proves fresh action/step IDs, unchanged source and equal operation payloads in the saved sandbox library. Duplicate is observed disabled without action/with command selection. The app quit normally. The shared existing library's hash is unchanged. This sandbox check is separate from production signing/archive or full supported-platform validation.

Public [Adobe workflow guidance](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/manage-actions-and-action-sets.html) supports the panel command. Exact live Photoshop behavior remains unqualified. See [the evidence record](ACTION_DUPLICATION_407.json) for retained source, binaries, commands, captures and remaining scope.

Qualification update at checkpoint 408: the cumulative normal optimized batch passes all 156 selected cases on each architecture, including this feature's eight new cases. Earlier Debug failures remain separately recorded; full package/Photoshop and physical-platform qualification remain open. See [the cumulative evidence](SHAPE_STROKE_PRESETS_408.json).
