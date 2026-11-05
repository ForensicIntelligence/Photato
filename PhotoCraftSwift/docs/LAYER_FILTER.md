# Layers panel filtering

Docked and floating panels share document-local criteria and the optional API. Kind accepts multiple icons and recognizes adjustments and fills. Name, effect, blending mode, metadata attributes, color, Smart Object status, Selected and Artboard modes are available. The switch suspends filtering while retaining criteria. Find Layers focuses Name with Option-Shift-Command-F; Isolate Layers follows current selection without changing image visibility.

Checkpoint424 adds **Empty** and **Not Empty**. A cancellable background worker reads stored alpha, including native component planes and sparse implicit defaults, without allocating the logical canvas. Native controls show pending criteria, progress and Cancel. After content changes, membership refreshes without a global editing lock. Unresolved content queries expose no stale matches. Session and document-lifecycle changes reject late results; document reads reset the workspace and final close cancels it. The cache conservatively refreshes on session changes, including some metadata-only changes.

In the owned Photoshop2026 RGB8 reference, transparent ordinary and embedded Smart Object layers match Empty; childless groups match Not Empty. Masks, layer visibility, opacity and styles do not define stored pixel emptiness. Smart Object queries use retained cache pixels and do not read linked files or fetch URLs. Non-RGB numeric storage tests are independent native regressions, not a Photoshop cross-mode comparison. Complete special-content, inherited and group semantics remain unqualified.

Filtering preserves samples, image visibility, Undo/Redo, dirty state and recorded Actions. An excluded active layer is deselected, and returning rows are not auto-selected. That view metadata can change in a saved archive; checkpoint423's blanket whole-archive-unchanged assertion was corrected using the live reference. Current tests compare every other saved document field exactly. Active criteria expose matching children through collapsed groups without changing disclosure metadata; a renaming row stays exposed. Complete path/mask and multi-selection edge cases remain open.

## API

Use the existing authenticated command endpoint with the current shared-document revision:

```json
{
  "command": "layers.filter",
  "revision": "<current revision>",
  "parameters": {
    "operation": "configure",
    "filter": { "mode": "attribute", "attribute": "empty" }
  }
}
```

`configure` accepts a nonempty partial filter. Arrays replace old choices; omitted fields retain them. Operations are `configure`, `enable`, `disable`, `find`, `isolate`, `selectAll`, `reset` and `cancel`. Enabling/configuring Empty or Not Empty awaits the shared worker. Other operations retain their native paths. A cancelled, superseded, changed-session or revoked pending query returns409 and cannot publish its criteria.

`layerFilter.evaluation` exposes `phase` (`idle`, `running`, `ready`, `cancelled`, `failed`), `resolved`, `operationID`, `candidate` and `message`. Matching/visible IDs use committed criteria and a generation-valid cache. Opaque revisions are64hex characters to remain within existing multi-document source-reference limits. Worker progress changes polling revisions; the worker's own status does not invalidate its captured admission. HTTP publication rechecks token, share, document owner and the remaining document/view revision. Strict schema/parameter errors return400, unavailable new artboards404, library links422 and stale/busy/revoked requests409/404 as appropriate.

There is no panel-filter counterpart in the pinned published Adobe Photoshopv2 contract; no Adobe route or action descriptor is invented. Typed operation inventory248, native archive86 and Actions48 remain unchanged.

## Qualification and remaining work

All91focused Debug tests pass on424Source05, including11new content-query/workflow methods and13amended filter methods. Core cases cover sparse300000², padding, mapped pages, signed zero/subnormal alpha and supported RGB/Gray/CMYK/Lab depths. Native/API cases cover selection, history/recording, cancellation, superseding, changed sessions/lifecycles, actual native read/close, source refresh and sharing revocation. Earlier failed attempts and the reviewed lifecycle repair are retained in the detailed record.

Both optimized architectures pass358of360same ordered cases, including all57new415–424methods. The two failures exactly match422; no broad-suite repair is claimed. Universal min14/signature/ZIP and actual isolated native Empty/NotEmpty, painting, one Undo, selection clearing/return and normal Quit pass. Qualification is recorded separately in [checkpoint424 evidence](LAYER_CONTENT_FILTER_424.json). These focused results do not establish a full-suite or Photoshop pass.

Group mode and the Advanced Blending attribute pair appear in the current Photoshop menu but are not implemented. Library-linked artwork needs source/service integration; it remains disabled, and remote URLs are not falsely classified as local/library links. Extended empty-layer deletion, complete hierarchy/path-selection/default behavior, supported physical platforms and performance remain major stillneeded or later qualification as appropriate. Full filtering and L01 are open.
