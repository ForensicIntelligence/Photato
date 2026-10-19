# Photoshop 2026 workspace comparison

Observed directly in the user's running **Adobe Photoshop 2026** on 2026-10-07. Reference window: `Untitled-1 @ 100% (Layer 1, RGB/8#)`, a transparent **921 × 921 px** document. The reference document was not edited. Inspected Move, Brush and its flyout, Marquee, Type, Color, Properties, Adjustments, Channels, Paths and the Image menu. Restored the original Paint Bucket tool and Properties/Layers panel selection after inspection.

This change reproduces the workspace organization and common interaction patterns in SwiftUI/AppKit using native controls and SF Symbols. It does not establish full Photoshop UI or engine parity. No Adobe application assets or implementation code were copied.

## Reference and implemented layout

| Surface | Observed Photoshop pattern | Swift implementation |
|---|---|---|
| Overall frame | Neutral gray, compact chrome, dark canvas pasteboard, minimal decoration | Replaced the spacious blue-accented prototype with neutral compact chrome; standard native document window |
| Options | Thin horizontal bar; controls change with the selected tool | Tool-specific options for Move, Marquee, Brush/Eraser, Crop, Type, Shapes, Eyedropper and navigation |
| Tools | Narrow left rail, grouped flyouts, small selected-tool border | 21 groups with remembered selection, right-click flyouts, Shift-shortcut cycling and optional two columns |
| Document strip | Name, zoom, layer, RGB/depth and close control | Equivalent strip; selecting another open document raises that document's native window |
| Canvas | Centered content, transparency grid, horizontal/vertical scrolling, zoom readout | Stable zoomed checkerboard; native scrollbars, Hand/Space pan, cursor-centered Zoom, optional pixel rulers |
| Color group | Color / Swatches / Gradients / Patterns; foreground/background; hue spectrum | Working saturation/brightness and hue controls, native color panel, foreground/background swap/reset, basic swatches and working flat pattern library; gradient library remains unavailable |
| Middle group | Properties / Adjustments / Libraries | Layer properties, position and raster flips; editable existing adjustment parameters; 16 adjustment slots with 5 working basic implementations; library gap shown |
| Lower group | Layers / Channels / Paths; filter, blend, opacity, lock, thumbnails, footer | Working layer filtering, rendered thumbnails, rename/reorder/visibility/lock/blend/opacity and layer/mask/adjustment actions; RGB channel previews; Paths gap shown |
| History | Compact history panel outside the main layer group | Native popover through icon rail or Window menu; select an earlier state, undo and redo |
| Context actions | Commands associated with the current editing task | Selection Fill/Mask/Deselect and Crop Apply/Cancel; Generative Fill visibly disabled |
| Main menus | File / Edit / Image / Layer / Type / Select / Filter / View / Plugins / Window / Help | Same top-level organization; implemented commands work, selected missing operations are disabled with explanations; this is not the full menu inventory |

The right dock can resize/collapse, and the Properties/Layers divider can resize. Small windows scroll tool and property contents. The macOS title bar, system color panel, symbols and menu appearance follow native platform styling.

## New functional connections

- Auto-Select chooses the top visible nontransparent layer under the pointer, respecting its mask. Show Layer Bounds outlines the selected layer; Edit → Free Transform now provides interactive handles in a separate preview/commit operation.
- Crop uses the existing selection and crop commands; it preserves off-canvas pixels and participates in undo. Shift/Option rectangle modifiers are shared between selection and shapes, including their previews.
- Zoom clicks keep the pointed document location under the pointer; Option-click zooms out. Space temporarily pans without committing a brush stroke. D/X reset/swap foreground and background.
- Adjustment catalog buttons create non-destructive layers. Properties exposes Exposure, Brightness/Contrast and Saturation parameters. The Black & White entry remains the existing luminance conversion; full Photoshop adjustment algorithms are still pending.
- RGB component views alter the preview only; the editable RGB document and undo history remain unchanged.
- Unavailable tools set an explicit inactive tool state. Mouse input cannot fall through to the previously selected brush. The options bar and **Help → Workspace Feature Map** explain the gaps.
- New Document now offers White, Transparent and Background Color. Startup uses a blank document; the procedural Field Notes sample remains in visual test captures.

## Verification

**49 tests pass** on macOS 27.0.1 / Apple Silicon, including seven new workspace tests: unavailable-tool input isolation, grouped keyboard selection, constrained/centered selection geometry, transparent/masked layer hit testing, RGB preview isolation and transparent-document crop/undo and distinct untitled document names.

Live UI verification exercised Brush activation, continuous painting and undo, Lasso unavailable-state isolation, the Shapes flyout and Ellipse selection, the adjustment catalog, Exposure creation and a −1 EV property change, Crop selection/apply (1200 × 800 → 444 × 402), undo back to the original canvas, the feature map, pixel rulers and creation of a transparent 921 × 921 document. Test edits were undone. Final visual checks include a 1700 × 1174 reference content area and the 1000 × 650 minimum content size. These snapshots exclude the native title bar.

Artifacts: [reference layout](../artifacts/workspace-reference.png), [minimum layout](../artifacts/workspace-small.png), [test log](../artifacts/full-tests.log). The app is rebuilt for arm64 and x86_64 with macOS 14 minimum. Runtime verification remains limited to the current Mac.

## Visible deficiencies to fill next

| Priority | Missing workflow exposed by the new UI | Dependency |
|---|---|---|
| 1 | Full group/clipping compatibility, vector masks, styles, smart objects and PSD/PSB editability | Complete document graph and codec parity before enabling controls |
| 2 | Object/magnetic selection, refinement, Quick Mask and advanced mask properties | Mask/selection engine and undoable native tools |
| 3 | Clone/heal/Patch/Remove, Pencil/Mixer and complete brush options | Port existing PhotoCraft algorithms and presets; qualify new local image models separately |
| 4 | Skew/perspective/warp, multi-layer transforms, pen/path editing, artboards and alignment | Geometry/transform/vector port with real preview/commit equivalence |
| 5 | Levels/Curves/full Hue-Saturation, professional color, RAW and filters | Source algorithm/ICC/RAW port and external image oracles |
| 6 | In-canvas type, paragraph/character editing, typography and font UI | Complete text model, shaping and PSD type round trips |
| 7 | Preset libraries, reusable assets, batch/actions, complete menus and workspace persistence | Command registry, preferences and native automation |
| 8 | Local generative fill/expand/removal | Qualified local image backend for offline edits; separately enabled Image Playground discloses Private Cloud Compute on macOS 27+ |

Remaining UX differences include animated marching ants, advanced transform/crop handles, complete context menus, detachable/rearrangeable panel groups, native single-window document tab groups, custom workspace persistence, full keyboard/accessibility coverage and brush-size cursor previews. Current document-strip buttons switch windows; they do not yet create one shared tabbed window. Channel previews are available, but alpha/spot/channel editing is not. No placeholders count as completed source commands.

Continue against [PhotoCraft parity](PORTING_PLAN.md) first; the [professional workflow plan](PROFESSIONAL_WORKFLOWS.md) covers subsequent Photoshop gaps.

## Geometry comparison and live verification — 2026-10-07

Inspected Photoshop 2026 Image Size and Canvas Size dialogs, then canceled both without modifying the user's 921×921 reference document. The new native sheets follow their dimensions/resolution/resampling and relative-size/nine-anchor structure. Adobe's [image size reference](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/image-size-resolution-and-resampling.html), [canvas size reference](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/change-the-canvas-size.html), and [layer scaling reference](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/transform-manipulate-layers/scale-layers-in-photoshop.html) inform remaining behavior gaps.

Native live checks: 1200×800→600×400 at 300 ppi; undo; relative canvas +200/+100 anchored bottom-right with original pixels moving to (200,100); undo; editable rectangle scaled proportionally with a corner handle and rotated 30°; undo. A second check disabled Resample, changed 72→300 ppi (4×2.6667 inches), entered width 6 inches (height 4 inches, 200 ppi), applied, reopened and confirmed unchanged 1200×800 pixels at 200 ppi; undo restored clean state. Fixed the user-input binding feedback loop discovered in the initial physical-unit check. All disposable test edits were undone.

71 automated tests now pass. New cases cover masks and all three pixel depths, independent canvas-turn pixel oracles, affine live type/shape archive preservation, invalid/stale/canceled edits, preview isolation, handle anchoring, undo and rasterization, and PNG/PSD resolution metadata. Geometry runs off the main thread with cancellation and revision validation.

Remaining differences: one full layer at a time; selection transforms, skew, perspective, distortion, warp, custom reference pivots, advanced resampling, canvas background semantics, and full metadata/color compatibility remain unfinished. Colored canvas extension is explicitly a separate layer. This does not establish Photoshop geometry parity.

## Coverage selections and masks — 2026-10-07

Observed Photoshop's selection flyout (Selection Brush/Lasso/Polygonal/Magnetic) and Lasso options: four combination buttons, feather, anti-alias and Select and Mask. Restored Paint Bucket afterward without editing the reference document. The native app now connects 14 tools; ellipse, freehand lasso and polygonal lasso join the prior 11. Selection Brush, Magnetic Lasso and Select and Mask remain unavailable. Adobe references: [lasso options](https://helpx.adobe.com/photoshop/using/selecting-lasso-tools.html), [marquee tools](https://helpx.adobe.com/photoshop/desktop/make-selections/get-started-selections/make-selections-with-marquee-tools.html).

Live native verification: created an ellipse, subtracted a smaller ellipse, filled the resulting ring, converted coverage into a layer mask and deselected. A black brush stroke across the ring hid pixels through the mask; clicking content and mask thumbnails visibly changed the editing target. Six undos restored the clean document. Separately created a three-point polygon, closed it with Return, feathered it by 20 px, filled and deselected; the canvas showed the expected soft edge. Four undos restored clean state. App tests exercise a freehand mouse gesture and canceled/tool-switched polygon drafts.

87 tests pass. Contours show actual 50%-coverage boundaries, including holes; they are static rather than animated marching ants. The polygon/combination implementation follows the Rust source's semantics; Gaussian feather radius is currently capped at 100 px and is CPU-based. These are partial Photoshop selection/mask workflows, not complete Select and Mask, mask-properties or PSD fidelity. See the [selection/mask visual fixture](../artifacts/workspace-selection.png).

## Mask interoperability checkpoint — 2026-10-07

Inspected and saved two separate reference PSDs in Photoshop 2026. Its Layers panel confirmed bottom-to-top stored record order; the mask Properties UI displayed PhotoCraft-exported density 50% and feather 1.5 px with no link. Tests compare Photoshop-stored composites and round-trip editable mask metadata. The native Properties panel now switches to mask controls when a mask thumbnail is selected; disabled thumbnails show a red cross and the link control is interactive. Advanced mask transforms and Apply Mask remain missing. See bundled fixture provenance for exact file preparation.

Live native check: imported the Photoshop raster fixture, selected its mask thumbnail, set density 50% and feather 6 px, unlinked and moved the mask, disabled it (red cross shown), then undid all five operations to clean imported state. The test document was closed; PhotoCraft remains open. [Mask-properties visual fixture](../artifacts/workspace-mask.png). 99 automated tests pass.


## Groups and clipping checkpoint — 2026-10-07

134 tests now pass. Nested groups, disclosure/indentation, multi-selection grouping, Pass Through/isolated blending, clipping arrows and base underlining are implemented. Cmd+G groups selected siblings; Shift+Cmd+G ungroups; Option+Cmd+G creates/releases clipping. Dragging onto a folder reparents a subtree. Incomplete clipping-chain grouping rejects with an explanation rather than hiding an orphaned member.

Live verification: opened the Photoshop-saved nested raster/group fixture in the rebuilt app; collapsed/expanded the outer group through undo, duplicated the entire group and undid to clean state, entered group Free Transform, released a clipping mask and undid to clean state. The folder thumbnail was changed to a visible folder icon. A focus issue found during this check led to window-level Cancel/Apply shortcuts for Free Transform. Original Photoshop Untitled-1 and native Untitled-1 were preserved. Group rasterization and arbitrary multiselection transforms remain unavailable; broader blend/adjustment/high-depth group combinations still need qualification.

## Native path checkpoint

Pen, Path Selection and Direct Selection now connect to editing tools (17 connected entries). Click/drag anchors, closed cubic contours, insertion/deletion, handle editing and component movement are undoable. Paths lists work/saved paths and the active layer vector mask; footer actions load a selection, create a vector mask, save/rename, create and delete paths. Vector-mask controls live in Properties; Layers exposes a separate vector thumbnail and Layer > Vector Mask provides mask actions. Live drawing, closure, mask creation, anchor movement, 12 px feather and complete undo were checked on the native canvas.

Three Photoshop-saved vector-mask references cover 8/16/32 bits. Path geometry, names, mask properties and separate pixel/vector masks survive interchange. Feathered edge rendering remains approximate (up to 0.02539 encoded-sRGB error in the 32-bit fixture). Missing workflows include Freeform/Curvature Pen, multi-anchor selection, numeric path transforms, path fill/stroke, selection fitting and clipping-path export. Full parity remains open.


### Editable fill follow-up — 2026-10-07

Layer → New Fill Layer → Solid Color creates a live fill with a selection-derived/default pixel mask. Properties exposes a native color swatch. Live RGB hex entry `3366CC`, canvas/thumbnail update, undo color and undo creation were verified. Inactive app color panels now activate and take focus. Gradient/pattern remain disabled. Photoshop's complete creation/confirmation dialogs, layer-thumbnail double-click color editing, shortcuts and preferences are still open UI parity items.


## 2026-10-07 — native Layer Mask commands (automated qualification)

Replaced the Add/Remove toggle with Layer → Layer Mask and its separate Reveal/Hide All, Reveal/Hide Selection, From Transparency, Delete, Apply, Enable/Disable and Link/Unlink entries. Added Apply/Delete to Properties and the layer context menu. The footer creates masks, with Option-click for hiding; it no longer removes an existing mask. Pixel-layer Apply and From Transparency use cancellable background edits. Applying a disabled mask asks whether to use that mask before changing transparency.

Core, rendering and app tests qualify native behavior and menu wiring; live visual checks and direct Photoshop Apply/From Transparency results remain pending because the Mac is locked. Apply/Delete semantics are informed by Adobe’s [mask documentation](https://helpx.adobe.com/uk/photoshop/desktop/create-masks/layer-masks/apply-or-delete-layer-masks.html), and the corresponding Rust workflow was ported as a test. Non-pixel targets require explicit rasterization. This does not certify complete Photoshop mask UX or byte-identical output.

## 2026-10-07 — native clipboard commands (automated qualification)

Edit now has Cut, Copy, Copy Merged, Paste and Paste Special → Paste in Place/Into/Outside, with Cmd+X/C/V, Shift+Cmd+C/V and Option+Shift+Cmd+V. Standard Cut/Copy/Paste retain nil-target AppKit responder routing so text editors handle their own contents. File → New from Clipboard is also available. Image commands use the document controller when the editor is active; a no-document Paste creates a new native document. Copy retains editable selected layers/groups without a pixel selection; selected-pixel and merged copies use alpha coverage. Paste Into/Outside creates an unlinked selection mask.

Current behavior follows the Rust clipboard module and Adobe’s [layer copy guidance](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/create-layer-compositions/copy-and-paste-layers.html), [selection copy guidance](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/copy-and-paste-selections.html) and [Paste Into/Outside guidance](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/paste-one-selection-into-or-outside-another.html). Sixteen tests cover native transactions, precision, rendering, menus and an isolated system pasteboard. Direct Photoshop placement/rounding, live responder routing, mask/path clipboard, special Background semantics and broader external formats remain open; this is not a Photoshop clipboard parity certification. The Mac remains locked, preventing new live app comparisons.


## 2026-10-08 — color-region controls

Magic Wand and Paint Bucket are connected in the existing W/G groups (28 connected entries). Wand exposes selection combination, Point Sample, tolerance, antialiasing, contiguous matching and Sample All Layers. Bucket exposes Foreground, native blend mode, opacity, tolerance, antialiasing, contiguous matching and All Layers. Mask targets disable layer sampling. Four native workflow tests cover click routing, W/G remembered groups, Wand Shift/Option modifiers, Bucket Option color sampling, immutable settings, masked/locked targets, undo and Escape cancellation. The source matcher has 240 executed Rust reference cases. Current Adobe guide links and remaining controls are recorded in `COLOR_REGION_REFERENCES.json`.

This is not a fresh live Photoshop UI comparison. Averaged samples, Select and Mask, patterns and transparency locks remain unavailable. The existing narrow-window options bar scrolls horizontally; persistent preferences and complete keyboard/input fidelity remain open.

Packaged offscreen Wand and Bucket layouts were inspected at 1380×900. All visible controls fit without overlap. An unavailable Paint Bucket SF Symbol was replaced with a supported filled-drop symbol and the final package recaptured. See `artifacts/wand-workspace.png` and `artifacts/bucket-workspace.png`.


## Patterns — 2026-10-08

Window → Patterns opens a native persistent flat preset library with search, thumbnails, selected tile/name/dimensions, Define/Rename/Delete, PAT import/export and built-in restore. Edit → Define Pattern opens a name sheet and saves the visible selection bounding rectangle or full canvas. Paint Bucket now has Foreground/Pattern sources and a thumbnail/preset picker. Folder-bearing PAT files report that folders flatten; exact duplicate presets report their merge count. Original built-ins are upstream CC0; no installed Adobe tiles are redistributed.

The packaged 1380 × 900 offscreen capture `artifacts/pattern-workspace.png` was visually inspected. An initial oversized native-menu image was fixed by keeping the swatch outside the menu label. The Patterns panel now shows both rows of seven built-ins at this size; smaller panels scroll. Properties and Layers retain their existing scrolling/divider behavior. This qualifies native layout, not live Photoshop control/keyboard parity. Folders/drag/drop, pattern fill layers, overlays, Pattern Stamp, complete preferences and live comparisons remain pending.


## 2026-10-08 — Pattern Fill editor checkpoint

Added an editable Pattern Fill card using native SwiftUI controls. Layer → New Fill Layer → Pattern, the Layers footer, thumbnail double-click, Properties and Layer Content Options open it. It exposes preset, angle, scale, Link with Layer, numeric phase, Snap to Origin, Preview, Cancel and OK while the canvas remains available for dragging. Return/Escape and drag routing are exercised through actual AppKit event handlers; these are automated native interaction tests, not live Photoshop verification. Selection/default masks, one-step undo and captured document-owned tiles are covered.

The packaged `artifacts/pattern-fill-workspace.png` was visually inspected at 1380×900: all controls fit, the masked rotated pattern is visible, and the Layers thumbnail/mask remain clear. The existing `pattern-workspace.png` was refreshed and inspected from the same binary. No new live Photoshop UI evidence was obtainable while the Mac was locked. Current Photoshop link/snap behavior, dialog positioning, shortcut/preferences fidelity, preset drag/drop and minimum-window editor ergonomics remain unqualified. Adobe's current Patterns panel guide and the public PSD format specification are linked in `PATTERN_FILL_REFERENCES.json`. Direct fill Free Transform is unavailable; unsupported native affine transforms require rasterization for PSD export.


## 2026-10-08 — rendering and layer-picking checkpoint

The Pattern Fill and Patterns captures were refreshed from the optimized universal binary and visually inspected. The controls, swatches, layer/mask thumbnails and rendered sample retain their previous appearance. Auto-Select now reads one pattern content pixel without rendering a full-canvas temporary; a native 24 MP workflow test verifies opacity, transparent tiles and continuous mask-edge coverage. This is automated native interaction evidence and offscreen visual QA. No new live Photoshop control/performance comparison is claimed. Performance and exactness scope are recorded in `RENDER_PERFORMANCE_REFERENCES.json`.


## 2026-10-08 — Resumed workspace visibility audit (step060)

The maintainer resumed development with UI → menus → UX → major functions → subfunctions → minor functions → everything else as the implementation order. Earlier sections describe historical checkpoints, not current complete capability counts.

Fresh Photoshop 2026 native UI captures qualify Tab hiding all panels/tools/options, Shift-Tab toggling panels while retaining tools/options, mixed-state Tab restoring the full workspace, and Window → Layers revealing only its group while everything else remains hidden. The reference workspace was restored without editing its original document. [Adobe’s panel guide](https://helpx.adobe.com/photoshop/desktop/get-started/learn-the-basics/hide-show-panels.html) independently documents the shortcuts.

Photato now has explicit presentation state for those groups, conditional canvas space, targeted menu reveal and preserved collapse/selected tabs. It uses canvas responder shortcuts so text fields retain native Tab navigation. Five new tests cover these transitions and preserve document/undo state. Current qualification evidence is in `artifacts/runs/20261009T030105Z-060-workspace-visibility/`; ten packaged live checks pass, including visually confirmed X/Y field focus. See [workspace visibility evidence](WORKSPACE_VISIBILITY_REFERENCES.json).

Remaining UI priorities: real shared document tabs; detachable/reorderable panel groups and per-tab closing; application-wide persisted workspaces; hidden-panel edge reveal; complete keyboard/accessibility; canvas overlays/cursors and contextual interactions. Panel content and exact visual metrics remain partial. The earlier fake document strip still switches separate windows.

The native live Window menu also contains AppKit-injected Fill/Center/Move & Resize/window-management items before the curated Photoshop hierarchy. The 801-entry static inventory does not qualify those dynamic entries. Preserve document-window navigation while fixing this menu discrepancy in the next UI/menu pass.


## 2026-10-08 — Shared document workspace (step061)

Replaced the window-switching document strip with actual shared native windows and separate NSDocuments. Tab close review, current-document/sheet routing, independent undo/pixels, Control-Tab/reverse, Window document selection, Float/Float All and consolidation are now tested. The custom native Window menu preserves the Photoshop catalog without AppKit-injected Fill/Center/Move & Resize entries. Ten document regression tests join the existing workspace/menu tests; 601 full and 155 optimized tests pass. Twelve bounded live checks include real native saves whose decoded dimensions, layers and every pixel remain independent. See [document workspace evidence](DOCUMENT_WORKSPACE_REFERENCES.json).

The first package’s intrinsic-sizing/reopen defect was repaired and requalified. A later tap-surface experiment did not establish pointer drag success and was reverted with its evidence retained. Coordinator reordering passes tests; live pointer reordering remains unqualified. Floating workspaces still duplicate tools/panels instead of Photoshop’s canvas-only document windows inside one application frame. Native autosave close wording, recovery, panel docking, workspace persistence, complete accessibility and exact visual metrics remain open. Earlier sections are historical checkpoint descriptions.


## 2026-10-08 — Native tab control candidate (step062)

Replace the ambiguous parent SwiftUI drag gesture with native AppKit tab controls, a private document-only payload and before/after insertion targets. Plain clicks and accessibility activation remain separate from Close. Hosted-view tests now confirm tab centers reach the native controls, using AppKit parent coordinates; the initial opposite-axis test mistake and its failed output are preserved. Coordinator, payload, click and unchanged-document checks pass alongside the full 605-test / optimized 159-test suite.

The Mac is locked, so live pointer drag, insertion feedback and cross-window drops remain pending. This is automated native UI evidence, not a Photoshop drag-parity pass. The last bounded live-qualified build remains step061. See [native tab evidence](NATIVE_TAB_DRAG_REFERENCES.json).


## 2026-10-08 — Shared application frame candidate (step063)

Separate document canvases from the common tools, panels and editing dialogs. Floating windows retain NSDocument ownership and native save sheets while frame controls follow the globally active document. Native child-window ownership keeps floats above the frame; the last docked document can float, new documents dock, and consolidation returns to the original frame. Keyboard canvas actions reach the active float while text responders retain their input. Pending dialogs block document target changes.

Eight added regressions pass alongside **613 full / 167 optimized / 42 focused tests**, zero failures/skips. A text-service side effect in the test process exposed a Services-role identity failure; the preserved diagnostic distinguishes it from the tested native responder dispatch. No production menu rewrite was made for it. The Mac remains locked, so actual floating geometry, stacking, panels, dialog/save/close interactions and pointer dragging are pending. This is automated AppKit evidence, not a live visual match. See [application-frame evidence](APPLICATION_FRAME_REFERENCES.json).


## 2026-10-08 — Native viewport and percentage entry (step064)

Unify zoom input through one display-geometry model. Replace the fixed percentage menu with an editable AppKit field; preserve native text input, reject invalid percentages, cancel on Escape and guard against document replacement during editing. Menu zoom uses the displayed scale and a source-derived ladder. Initial fitting resolves once, while explicit Fit uses current bounds. Backing-scale conversion and center-preserving display transitions correct logical-point assumptions; navigation activates its document, and queued detached views cannot overwrite the new host’s geometry.

Eleven new viewport regressions join the existing suites: 624 full / 182 optimized / 57 focused pass, with 220 exact executed Rust step cases. Preserve the type-conversion failure, decimal-rounding assertion failure and the older Wand fixture’s implicit-fit/coordinate repairs in the run record. Offscreen normal/minimum layouts are separately identified in the viewport manifest. Actual percentage-field editing, devices/monitors, Photoshop zoom values/preferences, frame interactions and dragging remain pending while the Mac is locked. See [viewport evidence](VIEWPORT_REFERENCES.json).


## 2026-10-08 — Compact workspace layout (step065)

The step064 minimum-size offscreen render exposed a tool-rail color footer outside the visible viewport. Keep that footer outside the scrolling list, reveal selected tool groups and expose the column-toggle state. Constrain the horizontal options row to leave room for fixed right-side controls. Replace the inspector’s fixed splitter offsets with allocation from the visible groups; preserve the requested size through resize and begin dragging at the displayed divider position.

Three new regressions include 192 sizing configurations and a test-owned native scroll view whose color well remains visible and stationary. All 627 full / 185 optimized / 56 focused tests pass. Inspect four package renders: normal, compact, compact two-column and compact Gradients. Keep the first visibleRect assertion failure and repair in the development record. The two-column compact render fits all tool groups; the one-column list and inspector content still scroll. These checks do not qualify physical input or exact Photoshop layout. Existing Quick Mask/Screen Mode, full panel docking and saved workspaces remain gaps. See [compact evidence](COMPACT_WORKSPACE_REFERENCES.json).


## 2026-10-08 — Saved workspaces (step066)

Share panel layout across all documents, retain last-used arrangements independently of saved reset targets and expose supported native Workspace menu commands. Eight new tests qualify bounded persistence, rollback, ownership, menu routing and native dialog structure; 635 full / 193 optimized / 64 focused tests pass. The initial controller injection failed because AppKit reused its singleton; configuring the returned controller repairs it.

Native-alert offscreen captures have incomplete button/popup rendering in XCTest and are not visual acceptance. Live dialogs, restart, selection/reset/deletion and shared layout with actual input remain pending while the Mac is locked. Lock Workspace is still disabled: Rust evidence distinguishes locking panel movement from resizing, and Photato does not yet support panel rearrangement. Factory presets and optional shortcut/menu/toolbar capture also remain unavailable. See [saved-workspace evidence](SAVED_WORKSPACE_REFERENCES.json).


## 2026-10-08 — Editable panel dock groups (step067)

Replace the fixed three inspector groups with an editable topology for all ten existing tabs. Native AppKit tab/group sources, insertion targets and splitters support regrouping, splitting, reordering, collapse and retained close/reveal; group menus provide keyboard-accessible actions. Persist topology and keep workspace locking separate from saved layouts. Correct the hidden-active-tab group move using its visible selection.

643 full / 201 optimized / 72 focused tests pass. The additional hosted hit-test assertion initially failed because it used the flipped host coordinates instead of its superview coordinates; the preserved hierarchy diagnostic confirms this test-harness defect. Corrected hit testing and native splitter callbacks pass. Own normal/reorganized renders are inspected. These checks do not qualify live pointer dragging, modifier/Escape behavior or exact Photoshop geometry. Native floating panels, extra columns/stacks, History/Clone Source integration, panel-specific menus, factory presets and complete accessibility remain open. See [dock evidence](PANEL_DOCK_REFERENCES.json).
