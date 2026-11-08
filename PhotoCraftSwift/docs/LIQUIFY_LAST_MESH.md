# Liquify last mesh

Checkpoint 450 adds reuse of the last committed Liquify program. All33focused Debug methods pass, including11new tests. Normal optimized450, actual ready-state native UI and fresh Photoshop2026comparison remain pending. See [evidence](LIQUIFY_LAST_MESH_450.json). Full F04 remains open.

Apply a Liquify edit with **OK**. Later, open Liquify on another supported target and choose **Load Last Mesh**, or press **M** while its canvas has keyboard focus. The button is disabled until a program is available. Loading changes the draft: local Undo/Redo works, Cancel leaves the document alone, and OK uses the existing undoable filter transaction. Typing into controls has no global M binding.

The saved program remains available after an unrelated filter, document Undo/Redo or closing the source document. The default application keeps one last program across launches. Standalone stores and tests use isolated memory storage unless a persistence URL is supplied. The cache contains the program and its normalized face geometry, rather than the source image. It uses the existing version-1 Photato Liquify mesh format, bounded to 4 MiB. Writes are ordered, atomic and drained on normal Quit. An unreadable saved file is preserved; new committed meshes remain available for the current session and the workspace reports the persistence error.

Existing dimensions retain their existing meaning: explicit width/height preserve that program's coordinate space; zero means the current target. Freeze strokes and face parameters remain in the copied program. Photoshop's exact last-mesh size, mask, face, cancellation and persistence behavior still needs independent 2026 comparison. Photoshop `.msh` interchange and Liquify action descriptors remain unsupported. Numeric kernels, native document format 87 and Actions maximum version 53 are unchanged.

## Optional API

`GET /v1/documents/<shared-id>` adds two fields inside `filterRecall`:

- `lastLiquifyMesh`: the existing Liquify settings object, or `null` if no program is available.
- `lastLiquifyMeshError`: a persistence warning, or `null`.

The advertised state schema and `filterRecall.lastLiquifyMesh` capability describe the fields, lifetime and replay path. Library changes invalidate attached documents' opaque API revisions. The controller shares its cache across documents, following the existing application-wide filter recall scope.

To apply the saved program, copy `state.filterRecall.lastLiquifyMesh` into the existing `filter.apply` operation:

```json
{
  "command": "filter.apply",
  "revision": "<current document revision>",
  "parameters": {
    "layerID": "<target layer UUID>",
    "filter": {
      "kind": "liquify",
      "liquify": "<replace this placeholder with the settings object>"
    }
  }
}
```

The placeholder above must be an object in a real request. The ordinary command schemas, locks, selection/depth rules, computation limits, prepared-edit fences, cancellation, history and portable Actions apply. Failed, cancelled, stale or revoked operations do not publish a new cached mesh. A native preview or file import alone does not replace it.

No command ID or Adobe-compatible endpoint was added. Adobe Liquify descriptors remain explicitly unsupported; the Photato program is not presented as an Adobe mesh descriptor. Multi-step Actions/Batch and isolated Adobe-job recall remain outside the existing last-filter publication coverage.

## Startup correction — checkpoint 452

The executable's designated-initializer path omitted the persistent filter libraries. Checkpoint 450's convenience-initializer tests did not cover that path, so its persistence claim for actual application startup was too broad. Checkpoint 452 makes the executable use a tested startup factory that shares both persistent libraries in normal launches and isolates owned test sessions. All eleven 450 last-mesh tests and the new startup regression pass in the current focused Debug run. Native lens-default quit/relaunch testing verifies this injection path; an actual last-mesh native relaunch is still a separate, unperformed check. Earlier evidence and failures are preserved. See [the lens-default record](LENS_DEFAULTS.md).
