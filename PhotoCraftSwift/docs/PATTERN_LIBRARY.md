# Pattern library groups

Checkpoint 443 adds groups and preset organization to the native Patterns panel. The panel supports Shift range selection, Command toggle selection, group and preset moving, explicit duplication, renaming, deletion, and selected or whole-library PAT export. Drag onto a folder to move into it, onto an insertion target to reorder, or onto the root area to move out of a folder. Drop feedback and dispatch both use Move for every modifier combination; Option does not add a copy operation.

The [Adobe Patterns panel guide](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/create-fill-with-patterns/manage-patterns-in-the-patterns-panel.html), updated 4 October 2026, documents groups and multi-selection dragging. It supplies workflow intent; the current checks do not establish exact Photoshop appearance, defaults or output. Photato does not bundle Adobe’s legacy pattern artwork. Existing pattern application to document content remains as previously implemented; the complete text/shape/pixel and modifier-drop workflows remain open.

PAT import now retains the validated folder hierarchy instead of flattening it. Export writes the existing 8BPT version 1 pixel records and the observed 8BIM/phry folder-order descriptor. Empty groups and repeated preset occurrences survive. Repeated occurrences refer to one immutable validated pattern resource; duplicated presets receive independent resource IDs. Renaming, deleting or reorganizing user presets does not change pattern resources already captured in an image document.

The native user library uses format 2, with a flat serialized node graph and bounded parent links. Format 1 remains readable and is not rewritten merely by opening it. A successful persisted mutation saves format 2. The older flat asset-list API remains available. Selection and disclosure changes are session state saved with the next persisted library mutation.

Library edits prepare and validate in a worker. Cancellation, failed persistence or changed source authorization before commit retains the old file and memory. Atomic replacement is the commit point; matching memory publishes even if cancellation arrives afterward. An accepted request retains its input scope until completion. The initial document revision is still checked; completion checks document/session/library/lifecycle, token and sharing rather than a transient display revision. The image document, its dirty state, Undo stack and recorded Actions are not changed by library organization.

## Optional API

Use `pattern.library` at `POST /v1/documents/{id}/commands`. It shares the native implementation. Every request has the normal document revision. Every operation except `list` also requires the current `libraryRevision` from `patternLibrary` state. Changing the shared library invalidates brush-dependent revisions in all attached documents.

```json
{"command":"pattern.library","revision":"<document revision>","parameters":{"operation":"group.create","libraryRevision":"<library UUID>","name":"Textures"}}
```

| Operation | Fields besides operation and libraryRevision |
| --- | --- |
| `list` | No libraryRevision or additional fields. |
| `select` | Required nodeIDs; optional activeID, which names a selected pattern node or null. |
| `group.create` | Required name; optional parentID. |
| `rename` | Required nodeID and name. |
| `move`, `duplicate` | Required nodeIDs; optional parentID and beforeID. |
| `delete` | Required nodeIDs; deletes selected subtrees and unreferenced assets. |
| `collapse` | Required group nodeID and collapsed Boolean. |
| `import` | Required base64 PAT data; optional destination parentID. |
| `export` | Optional nodeIDs selecting complete subtrees; omission exports all. Returns base64 data, filename, content type and SHA-256. |
| `define` | Required name; captures the visible image within current selection bounds, using the native Define Pattern implementation. |
| `reset.builtins` | No extra fields; merges Photato built-ins and retains custom presets/groups. |

Omitted or null parentID means root; beforeID must identify a sibling in that parent. A group cannot move inside itself. Node and asset IDs are distinct: organization targets node UUIDs, while existing fill/paint operations continue to use captured resource IDs. State includes node hierarchy, pattern headers, selection, disclosure, busy/error state and library revision. Discovery provides operation-specific request schemas and result/state schemas. Unknown or irrelevant fields reject. Library edits create no image Undo transaction.

PAT transport uses bounded base64 of at most 3,000,000 characters within the existing 4 MiB HTTP request budget. No filesystem paths are accepted. Native import/export retains existing file budgets. This is a Photato extension; no desktop preset-library route or unqualified actionJSON operation was added to the pinned Adobe Photoshop v2 contract.

## Validation and remaining work

All 54 selected Debug methods pass, including seventeen new Core, IO and native/API methods. Tests cover exact existing PAT pixel/byte fixtures, independent descriptor order, all-depth record prefixes, folder and empty-group round trips, duplicate references, migration, actual provider transfers, all modifier combinations, two-document revisions, rejected stale/foreign/closed work, actual HTTP busy/revoked imports, cancellation and persistent-file retention. An offscreen test renders the actual SwiftUI panel; it is not a live Photoshop comparison. The same 71 optimized methods pass on Apple Silicon and under Rosetta, including all seventeen new methods. Universal macOS 14 packaging, signature and extracted ZIP verify. Earlier failed runs remain in the record. [Evidence](PATTERN_LIBRARY_443.json).

The first Core constructor and two later fixture compilation errors were retained before repair. A panel snapshot test initially over-released its AppKit window; an own-binary NSZombie diagnostic identified NSWindow release after deallocation. The test now retains its Swift-owned window until normal scope teardown and keeps the original rendering check. Product code did not change for that repair.

Working bounds remain 1024 unique resources and 1024 preset occurrences, 16 MP per pattern, 64 MP total resources, a 512 MiB file budget and a 1 GiB decoded tile budget. The graph admits 4096 nodes and 64 group levels. PAT export preflights repeated-record storage against the existing reader budget, rather than producing an export that exceeds it. These limits are not a claim of full Photoshop capacity.

Full A07 remains open: History Fill needs shared source/snapshot lifecycle; scripted Fill, remaining application/drop semantics, arbitrary PAT metadata/interchange, larger capacity, exact defaults/output and physical-platform/60 fps checks remain work. Existing wider-suite failures are retained. Numerical cleanup does not replace unfinished functionality.

Optimized tests exposed a request-authorization problem after preparation. A controlled regression isolated display-only revision invalidation; the completion path now uses relevant data and lifecycle checks. A short-lived request lease also makes accepted input ownership explicit and evaluates each server-side fence separately. The final optimized runs pass on both architectures; no compiler or ARC root cause is asserted.
