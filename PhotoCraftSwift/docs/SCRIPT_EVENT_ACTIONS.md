# Script Events Manager

Build483 adds native Action playback for **New Document** and **Open Document** through File > Scripts > Script Events Manager…. Record or load a native Action in Window > Actions, enable events, choose an event, set and Action, then Add. Remove/Remove All change the registrations; Done closes the window. Changes save immediately. Events default off. Disabling retains the list.

Normal launches save configuration in Application Support/Photato/ScriptEvents.json. Invalid files and failed writes are reported and preserved. Isolated validation/snapshot sessions keep their own configuration and Actions in memory. Recovered documents and focusing an already-open document do not replay events.

Publication queues matching Actions in registration order after document opening finishes. Each Action uses the ordinary native prepared transaction and one Undo. The queue accepts64pending events and128registrations. Changed document/configuration/library/interaction/lifecycle state rejects pending work before commit. An earlier successful Action remains undoable if a later Action fails. These are the current semantics; exact Photoshop timing and ordering are not yet qualified.

## Optional API

The native API window has a separate **app-wide event** permission, `scriptEventChangesEnabled`. It defaults off and resets when the API stops. Both GET and POST `/v1/automation/events` require it. Stored event registrations persist independently of that permission and can apply to newly created/opened unshared documents. Clients must opt in with this scope understood.

GET returns `revision`, `configuration`, `libraryRevision`, available `actions`, `isPersistent`, `isRunning`, `pendingEvents`, `lastResult`, `loadError` and `actionsLoadError`. POST supplies only the current revision and complete configuration:

```json
{
  "revision": "<revision UUID returned by GET>",
  "configuration": {
    "version": 1,
    "enabled": true,
    "bindings": [
      {
        "id": "<fresh registration UUID>",
        "event": "newDocument",
        "actionID": "<existing native Action UUID>"
      }
    ]
  }
}
```

`event` accepts `newDocument` or `openDocument`. Empty bindings with `enabled:false` clear and disable. All bindings require unique registration IDs. New bindings must reference existing Actions; an orphaned retained binding may be removed. Exact request/configuration/state/result schemas appear in API discovery.

Stale configuration returns409; missing app-wide permission403; malformed/unsupported input400; wrong content type415; rejected persistence/configuration application422. Invalid requests leave the prior configuration/revision unchanged. The HTTP response is configuration state, not a synchronous promise that queued Actions have finished; inspect running/pending/lastResult.

The existing `actions.manage` operation also requires this permission when renaming, deleting, enabling/deleting/moving steps of an Action referenced by any registration, including temporarily disabled registrations. Unbound Action edits and existing list/export/duplicate retain their prior rules. This prevents a shared-document client from changing callbacks that can affect unshared documents.

No event-configuration route is defined in the pinned Photoshop/Firefly v2 HTTP contract; no Adobe endpoint is invented. HTTP compatibility does not host desktop Photoshop plug-ins.

## Qualification and remaining work

All58focused Debug checks and the same58optimized checks pass on Apple Silicon and translated Intel, including20new methods. Native recording, event setup, automatic Invert on a white new document, Command-Z, result, constrained manager scrolling and cleanup pass in the isolated universal483app. OpenDocument publication/focus/recovery paths are covered by tests; its live gesture remains unqualified. Nine8/16/32bit native/PSD/PNG event/manual file pairs match across all three test variants,14470bytes eachvariant. This is shared-engine equivalence, not independent Photoshop output.

The broader batch passes128of129methods perarchitecture. The unchanged old API assertion expects422and receives400; the same failure reproduces on retained480botharchitectures. Build483is therefore a validation candidate, while480remains the latest fully qualified selected universal. Universal minimum14metadata, slices, fullentitlements, signatures and extractedZIP match; supported physical platforms/distribution remain unqualified.

Scripts, startup/save/close/export/print/custom events, Photoshop notifier compatibility and third-party plug-in hosting remain unavailable. FullAUT02, original104package requirements, exact defaults/output, broad regression and60fps remain open. [Evidence](SCRIPT_EVENT_ACTIONS_483.json).
