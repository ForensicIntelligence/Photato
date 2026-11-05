**Checkpoint 424 — Layer content filters:** Empty and Not Empty now scan stored alpha in a cancellable worker shared by native controls and the API. Filtering clears an excluded active layer, matching the owned Photoshop reference. All 91 focused tests pass. Both optimized architectures pass 358 of the same 360 cases, including all 57 newer feature tests; the two remaining errors exactly match build 422. The universal package and actual native filter/paint/Undo/selection/Quit checks pass. Full L01, earlier failures and all 104 package scopes remain open. Major stillneeded work continues before minor or cleanup. [Guide](LAYER_FILTER.md) · [Evidence](LAYER_CONTENT_FILTER_424.json).

**Checkpoint 423 — Layer filtering and isolation:** The Layers panel now shares document-local filter state with the API. Nine modes, multiple kind/Smart Object icons, Find Layers, Isolate Layers and filtered selection are implemented; specific adjustments and fill layers now match correctly. All 77 current focused tests pass, including all 13 new regressions and lowercase artboard UUIDs. The earlier 85-test run retains two capacity errors that reproduce in 422 Debug and pass its optimized builds. **Next: asynchronous Empty/NotEmpty and remaining substantive L01 work, before D01 or minor/cleanup.** Full filtering, current optimized/physical Photoshop qualification and all 104 package scopes remain open. [Guide](LAYER_FILTER.md) · [Evidence](LAYER_FILTER_423.json).

**Checkpoint 422 — Arrange selected layers:** All five Layer > Arrange commands now move or reverse selected layers and complete groups through one prepared Undo. Native menus/default shortcuts, Photato API, portable Actions 48 and the supported Adobe MoveLayer job subset share the engine. All 106 focused Debug tests pass; both optimized architectures pass 279 of 281 tests, including all 33 new methods from checkpoints 415–422. Existing failures remain recorded; universal macOS14/signature/ZIP checks pass. **Current: major stillneeded L01, next layer filtering/isolation; D01 follows the remaining substantive L01 work.** All 104 package scopes and physical Photoshop qualification remain open. [Guide](LAYER_STACK_ORDER.md) · [Evidence](LAYER_STACK_ORDER_422.json). [Private source backup](https://github.com/ForensicIntelligence/Photato/commit/9c9723749d107c98cdbe9871879115edc6dcfdfb) · [Receipt](SOURCE_PUBLICATION_422.json).

**Checkpoint 421 — Channel thumbnail options:** Plain double-click now opens existing alpha, spot or Quick Mask Options through a captured native thumbnail control; context Options shares its guards. Existing modifier selection/load behavior, channel planes and layer pixels are retained. All56focused Debug tests pass, including3new regressions;50existing normal baseline tests pass per architecture. Current421normal and physical/full Photoshop acceptance remain open. **The major quick-win sweep is finished. Next: major stillneeded L01 layer workflows, then D01 document workflows.** All104full package scopes remain open. [Guide](CHANNEL_THUMBNAIL_OPTIONS.md) · [Evidence](CHANNEL_THUMBNAIL_OPTIONS_421.json).

**Checkpoint 420 — Rasterization responsiveness:** Native Rasterize now prepares the existing command in a background worker and commits one Undo after source validation. The optimized 24MP sample returns from the main-actor call in 0.023ms on Apple Silicon while preparation takes about 6.94s. Native/API/old-command documents and saved bytes match across RGB8/16/32. Both architectures pass 193 of 195 tests, including all 18 new methods from 415–420; two exact old failures remain open. Universal macOS14/signature/ZIP checks pass. Physical60fps, full Q03 and Photoshop acceptance remain open. **Next: Q04 independent references, then REL01 archive/sandbox.** Six major quick-win candidates remain. [Guide](RASTERIZATION_RESPONSIVENESS.md) · [Evidence](RASTERIZATION_RESPONSIVENESS_420.json).

**Checkpoint 419 — Rename sky presets:** Sky Replacement now offers a native Rename dialog using the existing library/API operation. It preserves IDs, order and image bytes, refreshes preview names, and adds no document history. Cancel, stale context, validation and failed storage retain the library. API state and capability metadata describe native availability. All 57 focused Debug tests pass, including three new methods; 26 existing normal baseline tests pass per architecture on preserved 417. Normal 419 and physical Photoshop/UI acceptance remain open. **Next: Q03 measured responsiveness, then Q04 independent references.** Seven major quick-win candidates remain; full package scopes are unchanged. [Guide](SKY_PRESET_RENAME.md) · [Evidence](SKY_PRESET_RENAME_419.json).

**Checkpoint 418 — Frame Timeline dragging:** Animation thumbnails now drag before or after another frame through the existing reorder command, with insertion feedback and one Undo. Frame IDs, timing, content and selected-frame appearance are retained. Existing animation.view/animation.edit API paths match native documents, saved bytes and history across RGB8/16/32; capability metadata describes dragging. All 50 focused Debug tests pass, including three new methods. The import/encoding/frame baseline passes 49 existing normal tests per architecture on preserved 417. Normal 418 and physical Photoshop/UI acceptance remain open. **Next: AI09 sky-library audit, then B08 Adjustment Brush.** Nine major quick-win candidates remain; full package scopes are unchanged. [Guide](ANIMATION_FRAME_DRAG.md) · [Evidence](ANIMATION_FRAME_DRAG_418.json).

**Checkpoint 417 — Statistical image stacks:** Five existing operators now follow Adobe’s published sample-moment and entropy definitions through the shared native engine, Photato API and supported Adobe action jobs. All 41 focused Debug tests pass. Normal builds pass 157 of 159 tests per architecture, including all eight new tests from 415–417 and 70 independently calculated Float32 results. Two exact pre-existing failures remain open. The universal package passes macOS 14, signature and ZIP checks; physical UI and complete Photoshop output qualification remain open. **Next: I03 migration audit, then I04 export/interchange.** There are 13 major quick-win candidates left; all original package scopes remain. [Guide](STACK_STATISTICS.md) · [Evidence](STACK_STATISTICS_417.json).

**Checkpoint 416 — Selected-mask removal:** Layers trash now removes the selected pixel, vector or Smart Filter mask and retains its layer, including the final layer. Native/API operations share prepared history and exact native bytes. New `mask.manage` brings 246 typed operations; native format 86 and Actions 47 remain unchanged. All 102 focused Debug tests pass, including three new methods; 59 existing normal baseline cases pass per architecture. Normal 416, physical UI and full Photoshop acceptance remain open. Latest normal/private source stays 414 with its linked-alpha residual. **Next: COL02 color modes, then COL03 proofing/print.** There are 16 major quick-win candidates left. [Guide](MASK_REMOVAL.md) · [Evidence](MASK_REMOVAL_416.json).

**Checkpoint 415 — Select Subject options:** Object Selection and Quick Selection now offer Select Subject in the Options bar, capturing the visible Sample All Layers setting. Native/API documents, saved bytes and one-step Undo/Redo match; source pixels and Properties/Menu sampling stay unchanged. All81focused Debug tests pass, including one new regression.60existing normal baseline tests pass per architecture. Normal415/live/full Photoshop qualification remains open; latest normal/private source stays414. **Next: S04 Select and Mask, then S06.**19major quick-win candidates remain. [Guide](SUBJECT_OPTIONS.md) · [Evidence](SUBJECT_OPTIONS_415.json).

**Checkpoint 414 — Smart Filter dragging:** Plain drag reorders within a stack; Option-drop copies a complete filter to another/same Smart Object in the document. Existing source bytes and target masks are preserved with one Undo and shared API. All53focused Debug cases pass. Normal builds pass99/100cases each, including all4new413–414methods; the remaining linked-PSD/PSB alpha mismatch exactly matches the preserved baseline. Universal macOS14/signature/ZIP checks pass; physical/full Photoshop/current-suite acceptance remains open. **Next: S02 Color Range audit, then S03.**21major quick-win candidates remain. [Guide](SMART_FILTER_DRAG.md) · [Evidence](SMART_FILTER_DRAG_414.json).

**Checkpoint 413 — Brush Settings sidebar controls:** Eleven groups now have direct enable checkboxes, independent of preset locks, using the existing brush settings and API. All 62 focused Debug cases pass, including the new native/API regression. Selected Pencil, Clone Source and Content-Aware controls already work; 50 existing normal cases pass per architecture on unchanged412. Full B01/Photoshop/live/normal413 qualification remains open; latest normal/private source stays412. **Next: D04 clipboard interoperability audit, then L03.** There are26major quick-win candidates left. [Guide](BRUSH_SECTION_CONTROLS.md) · [Evidence](BRUSH_SECTION_CONTROLS_413.json).

**Checkpoint 412 — Filter Gallery dragging:** Effect rows now drag to reorder through the same native move/Undo operation as the arrows. All 53 focused Debug tests pass. Normal builds pass 116 main tests plus two separate API metadata tests per architecture, including all 16 new Last Filter/Gallery cases. Universal macOS14/signature/ZIP checks pass. Physical native interaction, full F06/Photoshop/current-suite acceptance remain open. **Next: B01 brush settings audit, then B02.** There are 31 major quick-win candidates left in this sweep; this is not a parity estimate. [Guide](GALLERY_EFFECT_REORDER.md) · [Evidence](GALLERY_EFFECT_REORDER_412.json).

**Checkpoint 411 — Last Filter:** The native Filter menu now recalls successful filter settings through the captured Control-Command-F shortcut and shared `filter.repeat` API. All eight new and 42 focused Debug cases pass. A07 placement/location controls already exist and pass29selected normal cases per architecture on410. Normal optimized/universal411 and actual live UI remain open; latest qualified normal/private source stays410. An existing Adobe-job Debug signal10reproduces on410and411and passes410normal; it remains recorded. **Next: F02 ordinary filter audit, then F03 Blur Gallery.** [Guide](FILTER_RECALL.md) · [Evidence](FILTER_RECALL_411.json).

**Checkpoint 410 — Gradient Fill API and Actions:** Live Gradient Fill settings now have a strict shared `gradient.fill.patch` API and portable Actions recording/playback. All 74 focused Debug tests and 82 normal optimized tests per architecture pass, including eight new cases. The universal package passes macOS 14/signature/ZIP checks. Typed catalog244, native archive86, Actions47. Full A05 and live UI/Photoshop/current-suite qualification remain open. **Next: A07 Pattern fills and pixel fills/strokes, then F01.** Human unlock for live408/410checks is still pending. [Guide](GRADIENT_FILL_API.md) · [Evidence](GRADIENT_FILL_API_410.json).

**Checkpoint 409 — Quick-win audit:** Paths, existing typography controls and shaped-text parameters are already implemented. All 51 selected existing tests pass per architecture across three normal optimized groups. Curves Auto is confirmed missing and moves to stillneeded; separate Character/Paragraph panel menus remain open. Software is unchanged at 408 Source01. **Next: A04 current2026 adjustment layers, then A05.** The 408 live check still awaits human unlock. [Evidence](QUICKWIN_AUDIT_409.json).

**Checkpoint 408 — Shape stroke presets:** Solid, Dashed and Dotted native controls/shared API are implemented. All 156focused normal optimized cases pass per architecture, including24 new across406–408 and eight new preset cases. The universal package passes macOS 14/signature/ZIP checks. **Actual408 native control/history/Quit awaits Mac unlock**; no live pass claimed. Full G03/Photoshop/current-suite qualification remains open. **G04 is next, then T01.** [Guide](SHAPE_STROKE_PRESETS.md) · [Evidence](SHAPE_STROKE_PRESETS_408.json).

**Checkpoint 407 — Duplicate saved actions:** The native Actions panel menu and existing `actions.manage` API now make independent saved-action copies through the shared library transaction. All 34 focused Debug tests pass, including eight new cases. Actual sandbox duplication, saved IDs/payloads, playback/Undo and normal Quit pass; the existing shared library hash is unchanged. Full AUT01/Photoshop/normal universal qualification remains open. **G03 is next, then G04.** [Guide](ACTION_DUPLICATION.md) · [Evidence](ACTION_DUPLICATION_407.json).

**Checkpoint 406 — RGB8 component pairs:** Ordinary RGB8 channel rows and the existing API now select component pairs for the shared editing engine. All eight new focused Debug tests pass. The initial run is 103/104 with an existing maximum-CMYK timeout; a separate clipboard-test signal10 also reproduces on preserved405. These failures remain open. Native singleton shortcuts/Invert/Undo/Redo/Quit pass; physical Shift-click pairs and normal optimized qualification remain unverified. Full C01 remains open. **AUT01 is next, then G03.** [Guide](RGB8_COMPONENT_SELECTION.md) · [Evidence](C01_RGB8_SELECTION_406.json).

**Checkpoint 405 — Color Lookup export:** File > Export > Color Lookup Tables and the optional API now bake eligible global RGB adjustment stacks to CUBE without changing pixels or history. All 80 focused normal Release tests pass on each architecture, including 12 new cases. The final universal app saved the expected file and passed the clean Undo and Quit checks. Full I05 and Photoshop qualification remain open. G01 Transform Again and A03 Brightness/Contrast move to major stillneeded; B05 Red Eye controls already work. **C01 is next, then AUT01.** [Guide](COLOR_LOOKUP_EXPORT.md) · [Evidence](COLOR_LOOKUP_EXPORT_405.json).

**Checkpoint404 update:** D01 closing and L07 artboard duplicate/background candidates are already implemented and pass25/15focused cases per architecture on unchanged403Source02. S01 now has a development-qualified Single Row/Single Column Marquee native/API baseline. Grow/Similar moves to major stillneeded. **G01 Transform Again is next**, then A03. Full package acceptance is unchanged. Focused development builds lead this sweep; normal optimized universal qualification is batched at stable milestones. [Current queue](WORK_PRIORITIES_404.json) · [Evidence](SINGLE_PIXEL_MARQUEE_404.json).

**Checkpoint403 update:** L01/AUT02’s ordinary raster/plain-group native baseline is delivered and tested. Full selector parity remains open. **D01 is selected next**, then L07 and S01. The original per-package table below is retained; current queue and delivery scope are in [WORK_PRIORITIES_403](WORK_PRIORITIES_403.json). Focused development builds now lead breadth work; optimized universal/runtime qualification is batched at stable milestones unless the change needs an immediate architecture check.

# Current work order

Updated 4 November 2026 at the maintainer’s request. This changes scheduling, not the Photoshop 2026 target or the definition of a completed feature.

1. Major quick wins
2. Major still needed
3. Minor quick wins
4. Minor still needed
5. Major cleanup
6. Minor cleanup
7. Final settings and cleanup checks

Quick wins are small, useful changes that fit the current engine. Still needed contains substantial missing behavior. Cleanup contains residual fidelity, uncommon combinations, refinement and broader qualification. All original acceptance criteria stay attached to their packages. The phrase “final 5%” is not a measured feature-completion estimate.

We sweep each package once per pass. A quick win gets one normal implementation checkpoint, including its UI, menu, API, history and focused tests. If it turns into a larger engine project, record the findings under still needed and move on. Fix safety and transaction failures before treating a path as delivered. Do not spend successive checkpoints exhausting one subsystem’s details.

**Current: L01 — Layer collection workflows, major stillneeded (pass2).** The major quick-win sweep has no remaining candidate. Audit the original full L01scope and remaining acceptance, implement missing useful functionality, then continue D01. No minor or cleanup pass starts yet. All104original scopes and earlier failures remain.

**S05 is parked, still open.** Its seven-file Photoshop reference matrix is complete. The selected-gray/initially-empty/explicit-full and PSD repair will resume during major still needed. A channel-row double-click candidate can be considered once when S05 is reached in the quick-win sweep. C01 no longer waits for S05 closure.

Candidates below require a source audit before implementation unless evidence already confirms the gap. A blank quick-win cell means no honest small implementation was identified; that package skips the quick-win pass. Existing functionality will not be rewritten to create a completion count. Final-detail tracks stay inside pass7, in quick-win/still-needed/cleanup order.

[Machine-readable priority](WORK_PRIORITIES_421.json) · [All scope, acceptance and tracks](FUNCTION_PHASES_421.json) · [S05 restart point](QUICK_MASK_GRAY_401.json)

## Major functions

| Package | Quick-win candidate | Still needed |
|---|---|---|
| L01 — Layer organization and Background semantics | Implement Delete All Empty Layers through one native transaction and the optional API | Complete remaining Background/locks/links/selection/arrangement/filter/isolation operations |
| D01 — Open, save, close and revert workflows | Repair a bounded failing Close All/Others or Save a Copy case before broad lifecycle expansion | Complete remaining open/save/revert/quit, read-only access and persistent permissions |
| L07 — Artboards and frames | Add a missing artboard duplicate/background command on existing geometry | Complete artboard coordinates/guides/export and Frame tool content replacement |
| S01 — Basic selection completeness | Implement confirmed missing Grow/Similar commands with native/API selection history | Complete marquee variants, Reselect, border/move/transform and selection options |
| G01 — Transform and crop completeness | Wire Transform Again to the retained transform operation | Complete multi-target/mask transforms, reference/snapping and nondestructive crop/resize |
| A03 — Remaining classic adjustments | Connect existing Brightness/Contrast to native destructive and adjustment-layer menus | Complete remaining classic adjustments, presets, masks and dialogs |
| I05 — Production export workflows | Add native LUT export for an existing supported color transform | Complete Save for Web/slices/assets, presets/scales and layer/artboard/comp exports |
| B05 — Patch, Content-Aware Move and Red Eye | Complete Red Eye controls using the existing removal engine | Complete Patch adaptation and Content-Aware Move/Extend protected-region workflow |
| C01 — Component visibility and edit targeting | Bring RGB8 component rows to existing high-depth Shift-selection behavior where supported | Complete multi-target editing/visibility, temporary masks, eye gestures and factory shortcuts |
| AUT01 — Actions and batch processing | Expose an existing action reorder/duplicate command in native UI | Complete semantic targets, dialogs/conditions/ATN/droplets/batch/Image Processor |
| G03 — Live shape tools and vector operations | Expose a missing shape property backed by existing live shapes | Complete shapes/arrows/corners/stroke/booleans/presets and pixel/shape/path modes |
| G04 — Pen and Paths completion | Expose a missing Fill/Stroke Path action using the existing path engine | Complete pen variants/modifiers, multi-anchor editing, fitting and clipping-path export |
| T01 — Full native text editing | Add a missing Character/Paragraph control already supported by rich type | Complete on-canvas/rich type editing, point/box conversion and editable PSD text |
| T04 — Path, warped and Dynamic Text | Expose an existing path/warp text parameter in native controls | Complete text-on/inside paths, Dynamic Text, auto-fit/reflow and persistence |
| A01 — Levels, Curves and Auto correction closure | Expose a missing Levels/Curves preset or Auto option backed by existing engine | Complete sampling/clipping/targeted/freehand curves, mask/HDR and presets |
| A04 — Current2026 adjustment layers | Add a missing native control for an existing modern adjustment | Complete 2026 nondestructive adjustments and editable PSD behavior |
| A05 — Gradients and gradient-fill completeness | Expose an existing gradient transform/preset through on-canvas controls | Complete modern editing/interpolation/noise/dither and GRD/preset behavior |
| A07 — Pattern fills and pixel fills/strokes | Add a missing Fill/Stroke placement option backed by current engine | Complete pattern transforms/libraries/interchange and fill/stroke target semantics |
| F01 — Filter framework and ordinary blur/sharpen/noise | Expose a supported filter's missing preset or repeat-last action | Complete ordinary blur/sharpen/noise catalogue and consistent preview/cancel pipeline |
| F02 — Distort, Pixelate, Stylize, Render and Other | Implement one bounded missing ordinary filter with shared native/API path | Complete remaining Distort/Pixelate/Stylize/Render/Other and available legacy filters |
| F03 — Blur Gallery | Add an existing Blur Gallery parameter missing from controls | Complete field/iris/tilt/path/spin handles, bokeh/noise and editable Smart Filters |
| F04 — Liquify | Expose existing freeze/thaw/reconstruct operations in the Liquify workspace | Complete mesh/push/twirl/pucker/bloat/face-aware controls and persistence |
| F05 — Perspective and lens filter workspaces | Expose a missing manual lens-correction parameter backed by existing engine | Complete perspective planes/constraints, Adaptive Wide Angle and lens workspace |
| F06 — Filter Gallery and legacy applicability | Expose existing gallery-stack reorder or preset commands | Complete legacy effect catalogue and applicability across supported document modes |
| B01 — Brush engine and brush settings | Add a missing brush setting control backed by existing deterministic engine | Complete tip families, dynamics/scatter/texture/symmetry/ABR and input curves |
| B02 — Missing paint and eraser tools | Complete one missing option on an already working Pencil/eraser tool | Complete Mixer/Replacement/Pattern/Background/Magic Eraser target and sampling behavior |
| B04 — Clone, heal, blur and toning completeness | Expose a missing clone-source control backed by the current renderer | Complete healing/sample modes/dynamics/overlays and toning/focus behavior |
| B06 — Content-Aware Fill and Scale | Expose an existing output-layer choice in Content-Aware Fill | Complete sampling workspace, adaptation, crop fill and protected content-aware scaling |
| B07 — Tablet, stylus and eyedropper qualification | Add missing persistent Color Sampler point controls using current sampling | Complete real stylus/eraser/button replay, averaging and cursor/latency handling |
| D04 — Clipboard interoperability | Add one missing channel/path clipboard format using existing serializers | Complete external layered/vector/PDF clipboard, depth/profile and Background Cut semantics |
| L03 — Advanced blending | Add a missing native control for an already implemented advanced-blend property | Complete Fill opacity, split Blend If, knockout/channel/clip/mask flags and PSD persistence |
| L04 — Layer styles and effects | Expose missing Copy/Paste/Clear Layer Style actions on the existing style engine | Complete effect options, contours/global light, multiple effects, presets and editable interchange |
| L05 — Embedded and linked Smart Objects | Finish a bounded missing-link or relink action without reopening precision research | Complete nested/shared/independent source editing, replace/update/export/package and transforms |
| L06 — Smart Filters | Add a missing enable/reorder/copy operation on existing Smart Filters | Complete editable stacks, masks/blending and supported metadata/fallback behavior |
| S02 — Color Range, Focus Area and Magnetic Lasso | Add an omitted preset/control to existing Color Range | Complete focus-region detection, edge-following lasso and averaged sampling |
| S03 — Object, Quick, Subject, Sky and People selection | Expose a supported subject/sky/person selection as a context-sensitive action | Complete object finder, all-object/person-part/quick selection and manual correction |
| S04 — Select and Mask workspace | Wire missing output choices to the existing selection/mask transaction | Complete refine workspace, edge/hair/smart radius, decontamination and outputs |
| S06 — Pixel/vector mask workflow closure | Expose a missing apply/delete-mask confirmation using existing mask commands | Complete target transforms/filters/clipboard, compound masks, defringe/decontamination |
| C02 — Alpha and spot channels | Expose a missing duplicate/reorder/rename channel action on existing core | Complete alpha/spot ink/solidity and native/PSD channel persistence |
| COL02 — Document color modes and separations | Expose a supported mode conversion missing from menus with its true restrictions | Complete all mode/depth/palette/dither/ink semantics and editable storage |
| COL03 — Proofing, HDR/EDR and print | Expose an existing proof preset missing from native controls | Complete proof/gamut/HDR/EDR, print/page setup and output profiles/overprint |
| RAW02 — Photo alignment and merging | Expose an existing stack statistic through a native command | Complete align/blend/panorama/HDR/focus stacking, masks/crop and deghosting |
| I03 — Original PhotoCraft .pcraft migration | Add an omitted supported upstream metadata migration with a licensed fixture | Complete all represented pcraft layers/types/metadata and safe original retention |
| I04 — Export and interchange formats | Expose an existing encoder option missing from export UI | Complete layered TIFF/EPS/DCS/PDF/SVG/EXR/HDR formats, profiles/depths/metadata |
| AI07 — AI job/document lifecycle and persistence | Expose already tracked model/seed/provenance in result inspection where available | Complete immutable jobs, stale/cancel/results, editable persistence and offline reopening |
| SP01 — Timeline, frame animation and video | Expose an existing frame-timeline command missing from native controls | Complete timeline/video/keyframes/transitions/audio and import/render/animation export |
| AI09 — Sky Replacement | Expose an existing sky-library import/delete action in native controls | Complete replacement masks/horizon/light/color and nondestructive manual refinement |
| B08 — Adjustment Brush | Expose an existing Adjustment Brush preset or targeting option in native controls | Complete adjustment painting, automatic target/refine and native workflow |
| Q03 — Responsiveness and cancellation | Remove one measured remaining main-thread blocker in an ordinary tool path | Complete progressive preview/cancel/low-memory and sustained interactive responsiveness |
| Q04 — Independent Photoshop oracle and corpus programme | Add focused independent fixtures for each newly implemented quick win | Expand independent modes/depths/profiles/formats/workflow corpus and malformed input coverage |
| REL01 — App Store archive, sandbox and release CI | Repair one confirmed archive/sandbox validation defect using existing project | Complete production identity/entitlements, reproducible archive CI and disclosures |
| AUD01 — Reconcile all inventories and freeze the target | Keep new function/menu/API inventories synchronized as each quick win lands | Reconcile all tools/commands/scenarios and current 2026 platform/service boundaries |
| AUT02 — Scripts, variables and command automation | Implement Delete All Empty Layers jointly with L01; one deliverable, not two completions | Complete scripts/events/variables/data-driven output and extension contracts |
| S05 — Quick Mask and saved selections | Add channel-row double-click to existing Quick Mask options | Repair confirmed selected-gray/initially-empty/explicit-full semantics; complete save/load/combine/shortcuts |
| A02 — Hue/Saturation and Color Balance exactness | — | Complete targeted sampling and Hue/Saturation/Color Balance range semantics |
| A06 — Gradient and RGB32 fill exactness | — | Resolve RGB16/32 gradient transfer and fill semantics |
| AI01 — Model evaluation and native runtime | — | Complete licensed model selection/download/hash/remove and native inference memory/latency |
| AI02 — Apple local text and Private Cloud Compute validation | — | Complete real local/PCC generation, disclosure/cancel and unavailable-device behavior |
| AI03 — Remove, distractions and generative fill | — | Complete offline remove/distractions/prompted edits, protected pixels and reversible variants |
| AI04 — Generative expand and backgrounds | — | Complete reversible expand/background/full-image generation with retained subject/source |
| AI05 — Reference-guided edits, prompts and markup | — | Complete reference-guided/markup/prompt edits, variants and provenance |
| AI06 — Harmonize, generative upscale and Neural Filters | — | Complete harmonize/restoration/upscale and available Neural Filter equivalents |
| AI08 — Assistant and provider capability differences | — | Complete assistant capability audit and user-reviewed native command planning |
| AUD02 — Resolve model, language and ecosystem boundaries | — | Resolve model-quality/locales/services/plugin boundaries and acceptance decisions |
| AUT03 — Third-party plugin compatibility | — | Define and implement supported native plugin/extension compatibility and isolation |
| COL01 — ICC working-space and color management | — | Complete import/profile policies, assign/convert, intents/BPC and calibrated display |
| D02 — Crash recovery and autosave durability | — | Complete crash-safe journal/recovery, fault handling and restoration UX |
| G02 — Warp, Puppet Warp and Perspective Warp | Expose a missing warp preset backed by existing geometry | Complete editable grids, Puppet pins and perspective/nondestructive smart transforms |
| G05 — Vector rasterization fidelity | — | Complete winding/sample/raster coverage behavior and supported PSD path forms |
| I01 — Editable PSD feature coverage | — | Complete missing editable PSD feature records and safe unknown-block editing restrictions |
| I02 — PSB and large/streaming file support | — | Complete bounded PSB streaming, multi-GB editable round trips and malformed-file guards |
| L02 — Layer composition and merge exactness | — | Complete group/clipping/mask blends, multi-layer rasterize and merge/flatten correctness |
| Q01 — Large-document storage and scratch engine | — | Complete scratch/tile paging, bounded undo and large mask/vector/group storage |
| Q02 — Metal and incremental rendering | — | Complete incremental GPU/CPU composition and deterministic rendering fallbacks |
| Q05 — End-to-end professional acceptance and runtime matrix | — | Complete professional scenarios, real runtime/device/input/display matrix and soak testing |
| Q06 — Universal byte-identical Photoshop results | — | Resolve sample/render/file identity boundaries and known cross-architecture/output differences |
| RAW01 — Camera RAW development | — | Complete native RAW development, local masks, lens/highlight/XMP and nondestructive sources |
| RAW03 — RAW restoration and reflection removal | — | Implement/evaluate RAW restoration and reflection-removal equivalents |
| S07 — AI edge enhancement | — | Implement and evaluate editable Enhance Edge refinement for hair/translucency |
| SP03 — Cross-application and asset ecosystem | — | Complete native local/open-service asset and cross-application equivalents |
| T02 — Multilingual and OpenType typography | Expose a supported variable-font axis or ligature option in native controls | Complete bidi/RTL/Indic/East Asian/vertical typography and font fallback/composers |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.

## Minor functions

| Package | Quick-win candidate | Still needed |
|---|---|---|
| B03 — History and Art History Brush | Expose a missing history-source selector over current history state | Complete pixel-compatible History Brush and artistic styles/constraints |
| C03 — Channel calculations and interchange | Expose an existing Apply Image/Calculations setting absent from native controls | Complete split/merge/spot merge, cross-document sources and mode/depth interchange |
| C04 — Channel display and thumbnail parity | Finish thumbnail-size preference persistence with existing panel options | Complete channel color display, preview samples and menu/cancel lifecycle |
| D03 — History, snapshots, Fade and purge | Expose Toggle Last State through existing history state | Complete snapshots, nonlinear history, Fade, history source/logs and purge |
| G06 — Rotate Object and pattern preview | — | Implement object-reorientation equivalent and seamless Pattern Preview |
| I06 — Metadata and content provenance | Expose a missing copyright/description field in File Info | Complete EXIF/IPTC/XMP retention, provenance and supported credentials/signatures |
| L08 — Layer comps and local libraries | Expose a missing Layer Comp update/rename action on the existing engine | Complete comp capture/apply/appearance, reusable local assets and cross-document workflow |
| SP02 — Slices, measurement and scientific workflows | Expose a supported Ruler/Count measurement through the native panel | Complete slices/measurement/logs/annotations/DICOM and image-stack analysis |
| T03 — Text styles and utilities | Add Find/Replace for existing editable text runs | Complete styles, spelling, font resolution, type masks and conversion/rasterization |
| U01 — Post-dialog panel command state | Reproduce and repair stale Panel Layout validation after options Cancel | Complete document-switch, Escape and OK command-state coverage |
| U03 — Docking and document-window interaction | Add one missing document-arrangement command using the existing arrangement engine | Complete tab tear-off, floating/docking and synchronized multi-view workflows |
| U04 — Canvas navigation and view modes | Add missing Fit Layers or Fit Artboards command through existing view geometry | Complete scrubby/animated zoom, view modes, print/pixel-aspect and Retina behavior |
| U05 — Rulers, guides, grids and snapping | Expose missing guide locking/clearing commands over existing guides | Complete unit-aware origins, smart guides, layouts and snap targets |
| U06 — Remaining utility panels | Finish one existing utility panel's missing menu action | Complete Navigator, Histogram, Info, Notes, Measurement and Tool Presets |
| U07 — Home, New Document, search and contextual actions | Add a reusable New Document preset using the existing creation path | Complete recent/clipboard presets, search discovery and contextual actions |
| U08 — Menu and shortcut closure/customization | Wire confirmed missing alternate shortcut bindings to implemented commands | Complete custom shortcut/menu/toolbar sets and context validation |
| U09 — Preferences and settings | Expose a working engine preference missing from Settings | Complete preference categories, migration, reset and factory defaults |
| U10 — Numeric input and dialog behavior | Add arithmetic expression entry to an existing unit-aware input | Complete ranges, scrubbing, modifiers, preview and modal keyboard behavior |
| U11 — Color and asset panels | Add search to existing local swatch/pattern groups | Complete grouped assets, import/export and Photoshop color picking |
| U12 — Accessibility and localization | Repair confirmed missing accessible names/focus in a working editor panel | Complete keyboard-only/VoiceOver workflows and localization architecture |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.

## Final details and release completion

| Package | Quick-win candidate | Still needed |
|---|---|---|
| REL03 — Open-source fork publication | — | Complete curated upstream-history fork, notices/provenance and public release preparation |
| REL04 — Beta, documentation and release readiness | — | Complete help/migration/known-limits, installation/update and release documentation |
| U02 — Workspace appearance and factory defaults | — | Match workspace geometry, icons, contrast, compact layouts and factory defaults |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.

