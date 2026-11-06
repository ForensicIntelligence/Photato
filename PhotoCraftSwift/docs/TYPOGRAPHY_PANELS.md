# Character and Paragraph panels — development

Window > Character and Window > Paragraph now reveal separate tabs. Type > Panels has the corresponding commands. Tabs use the existing dock, floating stacks, columns, close/reveal and saved-workspace system. Their controls reuse the Properties text controls and native text engine. Text range selection is retained after formatting. Controls require an editable type layer; creation defaults without one remain open.

Saved panel catalogs1/2 are validated before migration to3. Existing placements and closed panels are retained; the two new panels start hidden. Loading does not rewrite the file. WorkspaceState1, native document86, Actions50 and settings4 remain unchanged. Native/API panel changes persist before publication, and failed writes retain the original state.

## Optional API

Enable Allow workspace panel changes in the native API window. It resets off at every API session. This permission affects the shared saved workspace across all open documents. Existing document sharing/token rules still apply.

Use `workspace.panels` with document revision and parameters `{"workspaceRevision":"UUID from workspacePanels state","operation":"show","panel":"Character"}`. hide accepts the same panel argument. operation layout accepts a complete layout snapshot from workspacePanels state, without panel. It covers validated order/group/selection/closed/collapsed tabs, columns, floating frames/stacks, dimensions and visibility. Use the exposed strict schema. Every supported panel has exactly one retained location. Workspace Lock permits show/hide but rejects layout replacement. Character/Paragraph visibility can change while typing; unrelated panel/layout and document operations retain their guards.

A workspace UUID is independent of the image revision and changes when native workspace state changes. No-op state edits retain it. Permission errors return403, stale/busy/locked409, malformed400 and storage failure422. Panel changes add no document Undo or recorded Action. Existing text.set and supported Adobe text jobs retain the text engine; no Adobe panel endpoint was invented.

## Current test result

Checkpoint437 is not stable-qualified.94of95focused development tests pass, including10of11new methods, the actual native numeric field editor, saved-workspace and API guards, all-depth native/API text documents/archives and factory menu tests. The original desired right-aligned point-text commit/Undo test still fails with five assertions. Its owned TextKit diagnostic produces a32768-pixel used width and32770-pixel padded metric for ten characters; the old dimension guard rejects it. The test has not been removed, relaxed or replaced with an easier input.

The next T01 work must correct point-text anchor/layout/render/editor behaviour coherently, with independent output references. Raising a capacity constant alone does not establish correct placement. Full paragraph composition, dynamic panel menus/shortcuts, defaults, Photoshop output and physical-platform checks remain open. Latest optimized universal/private-source qualification is436. [Evidence](TYPOGRAPHY_PANELS_437.json).

The expanded final run includes all 14 older command-count checks updated for the new 251st operation, retaining all original 80 cases. All 14 pass. Current evidence is Source08; the failing point-text case remains.

A mixed floating stack containing Character and Layers now keeps type controls available during typing while guarding unrelated content. The final95-case run adds an actual hosted-control regression;94pass and the same point-text case fails.
