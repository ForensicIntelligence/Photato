[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-03.md) · [Next page](part-01.md)

## 2026-11-04 — Step 400: Quick Mask colour options and reference conflict

The remaining S05 check starts with a custom green overlay in Photoshop, Selected Areas and 37% opacity. Cancel restores the original red, Masked Areas and 50%; OK retains the custom settings. Tracing the complete double-click sequence shows its mode change matches Photato, so that initial suspicion is withdrawn. An owned Fill probe changed its remembered choice; it was restored and verified before the disposable document was discarded.

In Photato’s unchanged build 398, the options sheet’s colour well did not open a usable colour panel after normal and accessible actions. The existing foreground colour button did. The repair reuses that control with the same sRGB colour binding. A dialog releases its own panel when removed, and cannot close a panel that another control has since claimed. Old callbacks cannot alter a discarded draft. The existing API colour parameters and shared native transaction remain unchanged.

Four regression cases were added. Both optimized builds and all 227 selected S05/workspace/dock cases pass. The exact slices are packaged as universal build 400. In the actual app, a custom colour can be entered through RGB fields, cancelled, committed and retained after normal quit and relaunch. The entered defaults are restored afterwards. No installed app or App Store record changed. [Evidence](../PhotoCraftSwift/docs/S05_OPTIONS_GESTURES_400.json).


The restart check exposed another S05 problem. With Selected Areas and no initial selection, Photato shows a full overlay; Photoshop starts clear. A controlled 8×8 white image was opened in Photoshop and saved with that mask active. An independent PSD reader confirms the initially-empty flag, display record and all 64 mask samples. This case was absent from the passing tests.

The next work will establish how raw channel gray, selection coverage and indication changes relate, including painting and Q exit. Changing only the initial screen appearance could leave file interchange or selection behavior wrong. The counterexample stays open, and the current core-workflow completeness flag is corrected accordingly. The colour-panel repair and restart checks remain valid within their stated scope.


## 2026-11-04 — Step 401: Quick Mask reference matrix; repair parked

Seven owned Photoshop documents establish the relationship between selected areas, mask gray and Q exit. Changing the active mask indication preserves the selection but inverts its gray samples. In Selected Areas, black produces an explicit full selection on exit; white produces none. The partial test selected five columns, confirmed from the saved files. Earlier filenames saying half are retained with that correction.

The native model and PSD conversion need a shared repair, including initially-empty masks and Float32 source retention. No application code changed. The exact documents, parser reports, screenshots and failed UI attempts are retained, and the entered Photoshop mask/Fill settings were restored before closing the owned probes. This work is now parked under major still needed. S05 stays open.

## 2026-11-04 — Step 402: Seven-pass work order

The maintainer asked us to stop spending successive increments on the tail of one feature while other workflows remain incomplete. Every active package now has quick-win, still-needed and cleanup tracks. The order is major quick wins, major still needed, minor quick wins, minor still needed, major cleanup, minor cleanup, then final settings and checks.

We will visit each package once per pass. A quick win should fit one normal implementation checkpoint and include its native controls, menu/API behavior, history and focused tests. If investigation reveals a larger project, we will record what was found under still needed and move on. Packages without a credible small change skip the quick-win pass. Completed track work does not close a package or waive exactness and platform requirements.

Delete All Empty Layers is selected first. The command is pending and absent from the current source search; its Photoshop behavior still needs an owned-document check. It is shared by L01 and AUT02 and will count as one delivery. D01 follows, then L07/S01/G01/A03 candidates. C01 no longer waits for full S05 closure. The detailed inventory retains all 104 original active package scopes and 651 command records.

The current priority, diary, plan and dashboard now use this work order. Both offline diary copies are refreshed. No native application code or version changed, and no new native test result is claimed. Build400 remains the latest tested candidate. The full goal is still active.


The local dashboard checks pass: all 13 existing Python tests and JavaScript syntax validation. In the browser, the seven passes filter the correct package lists and every package displays its three tracks alongside the original acceptance criteria. The mobile layout fits without horizontal overflow. These are dashboard checks, not new editor tests.

The complete current work list follows. Candidates still need a source audit; a dash means no small implementation was identified.

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



## 2026-11-04 — Step 403: Delete All Empty Layers native baseline

File > Scripts > Delete All Empty Layers now runs through native Swift and the optional layers.deleteEmpty API. It examines stored alpha, so hidden, zero-opacity and off-canvas layers with content are kept. Plain groups made empty by deletion are removed. Clipping bases and extended editable content are preserved. Surviving selection and the active layer stay intact, with one Undo step when anything changes.

The first test run passed 80 of 81 cases on each architecture. Its failing test assumed the API view revision could not advance after a redraw; the established API includes view state in that token. The document, history and dirty-state checks passed. We corrected that new assumption and documented the distinction. The failed run remains available.

Review also found a real safety case: deleting an empty clipping base could reveal its nonempty clipped layers. The second source preserves clipping bases. New graph and rendered-output tests demonstrate the unsafe result and verify that corrected deletion keeps the exact pixels. An overstated Adobe-compatibility sentence was corrected too: the automatic empty selector is Photato-only, and the general Adobe deletion adapter remains an open gap.

Both corrected builds pass all 83 selected tests, including 14 new cases. In the actual universal app, two owned empty layers disappear through the native menu, return with one Undo, and disappear again with Redo. The entered panel is restored and owned artwork discarded. Final normal Quit is confirmed by process absence without a UI query that could reopen the app. Discovery finds 4,050 cases; that does not mean the full suite passed.

Photoshop reference automation did not produce a verifiable deletion result. The public command documentation and observed menu establish its presence, not full selector parity. Masks, effects, retained source data, native-mode and other extended types remain protected while their behavior is qualified. The full L01/AUT02 packages stay open. No installation or release occurred.

The native baseline is delivered and D01 is selected next, followed by L07 and S01. Optimized builds took 8–10 minutes each while the selected tests took seconds. Subsequent quick wins will use focused development builds, with optimized universal/runtime qualification batched at stable milestones unless needed earlier. The seven passes and all original acceptance requirements remain unchanged.

## 2026-11-04 — Step 404: Single-pixel marquee and quick-win audits

The quick-win sweep checked two candidates already present in the app. All 25 document-closing cases and 15 artboard cases pass on each architecture without source changes. The old closing failures did not reproduce, and artboard duplication/background controls already exist. Those candidates can leave this pass; their full major packages remain open.

Single Row and Single Column Marquee were disabled placeholders. They now draw a live row/column outline and commit one selection on release, with captured add/subtract/intersect mode and feathering, cancellation and Undo/Redo. The API accepts row/column indices through the same geometry/history path. All 87 focused arm64 development tests pass, including 7 new cases and both tools across all 16 modifier combinations. Sparse 300,000-square native persistence is covered; dense capacity is not implied.

The first Debug build crashed in a Swift compiler optimization pass before tests ran. The retained retry disables that pass for development only; production settings stay unchanged. Normal optimized universal and physical-platform qualification remain open. Grow/Similar requires larger color-selection work and moves to stillneeded. G01 Transform Again is next, followed by A03. Full S01 and all original acceptance remain open. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-404).

The isolated development app was also checked through its native flyout and canvas. A row spanned the width, a column spanned the height, and Undo/Redo restored the selection. The disposable document was returned to its clean state and the candidate quit normally. This is separate from normal optimized universal and Photoshop fidelity qualification.

## 2026-11-04 — Step 405: Color Lookup export and quick-win audits

The existing LUT export saved a table already loaded in an adjustment. File > Export > Color Lookup Tables now creates a CUBE table from the document's global color adjustments. It uses the native compositor at the document's bit depth and leaves the image and history unchanged. Spatial effects that cannot be represented by this path reject with a reason. The native file chooser and optional API share preparation and cancellation, including a matching operationID for direct API cancellation.

All 80 focused normal Release tests pass on each architecture, including 12 new tests. The first run's independent test parser counted domain headers as samples; that fixture was corrected and the failed attempt retained. Both the development app and final optimized universal app saved the same owned 181-byte inversion table. Its eight corners match independently expected values. One Undo removed the original Invert layer and restored the clean document; both apps quit normally. The universal package passes signing, minimum macOS 14 and ZIP extraction checks. Full Photoshop, physical-platform and remaining export qualification stay open.

Transform Again has no retained operation state to wire up, and the existing Brightness/Contrast model is an acknowledged approximation. Those larger candidates move to stillneeded. Red Eye's Pupil Size and Darken controls already work and pass their current checks. C01 is next, then AUT01. The checkpoint 404 source-label typo was corrected against preserved commands and hashes. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-405).

The complete native source backup is saved in the [private repository](https://github.com/ForensicIntelligence/Photato/commit/9421bbc320dcbaad28e53eba926d042386eeefe9), with all 7,150 included qualified inputs matching the tested source. The 34 excluded inputs are listed with reasons in the portable source manifest. All 1,061 non-native root/Rust files remain unchanged. The repository becomes public on release day; no app binary or software release was uploaded.

## 2026-11-04 — Step 406: RGB8 component selection

Ordinary RGB8 channel rows ignored Shift, despite the shared engine already supporting component sets. The rows and existing `mode.channel.select` API now select pairs. Single-channel compatibility is preserved. The selected set feeds existing Fill, Invert, Brush/Eraser and filter commands; visible channels remain independent. The API reports both sets accurately. Selection itself adds no pixel edit or Undo entry.

Eight new focused development tests pass. They cover row dispatch, modifier combinations, literal unselected/alpha values, native/API results and previews, captured targets, cancellation/history, errors and a maximum sparse canvas. The first affected run is 103/104 with an existing maximum-CMYK HTTP timeout, which also fails on preserved 405. Additional component/view and painting tests pass; separate broader clipboard processes terminate by signal 10, also reproduced on preserved 405. The failures are retained without changing their limits or fixtures. The union of 121 passing current IDs is not a single passing test suite.

The actual native app passes a singleton row/shortcut/Invert/Undo/Redo/Quit check on an owned document. Physical held Shift-click pair selection was not verified; the attempted focused Shift-Space made no accessibility change. Exact Photoshop last-target/composite behavior and full channel acceptance stay open. This is the selected development baseline, followed by AUT01 and G03 in the major quick-win sweep. Normal optimized packaging waits for a stable breadth batch. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-406).

## 2026-11-04 — Step 407: Duplicate saved actions

Step reordering already existed in the Actions panel and API. A dedicated Duplicate operation was missing. The panel menu and existing `actions.manage` API now copy one saved action through the same atomic library transaction. New action and step IDs keep the copy independently editable; ordered commands, names and enabled flags are retained. Copying changes no document pixels or Undo history.

All 34 focused arm64 Debug tests pass, including eight new cases. They check payload/identity independence, Unicode and naming bounds, persistence/reopen/import/export, limits and write/corrupt-library rollback, availability and API guards, and source/copy playback producing identical native document bytes with one Undo. The fixed older offscreen capture was preserved; the new capture is saved separately.

A separate native sandbox provided an isolated test library. The app recorded Invert on owned artwork, created and selected the copy, then played it. Independent reading of the saved library confirms fresh IDs and an unchanged source/payload. Undo reverses playback in one step, then returns to the original clean image; duplication added no image-history entry. The app quit normally, and the existing shared library hash remains unchanged. Full AUT01 and exact Photoshop naming/order/hierarchy/drag behavior remain open. G03 is next, then G04. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-407).

## 2026-11-04 — Step 408: Shape stroke presets

The shape editor already had geometry, corners, arrows, paints and detailed stroke controls. The small missing control was a Solid/Dashed/Dotted selector. It now uses the existing dash/cap renderer and native preview/history path. Custom patterns remain editable and retain their values. Tool Settings and the existing shape API commands share the same transformation; no file-format change was needed.

Eight new cases cover rendering at RGB8/16/32, native/API document-byte equality, preview/Cancel/Undo, captured settings, persistence/playback and invalid/busy/stale requests. They pass in Debug. The wider Debug run retains a curved-stroke Rust mismatch and signal10 in an existing shape API test. In a separate standard optimized batch, all 156 selected cases pass on each architecture, including24 new cases across406–408. The two earlier timeout/crash IDs pass there. No cause or full-suite repair is claimed.

Packaging first encountered a PATH conflict with a Python xattr utility. That failed attempt was preserved; using the macOS system command allowed strict signature, both minimum macOS 14 targets and fresh ZIP extraction checks to pass. All37 available protected baseline hashes remain unchanged; three historical missing files remain unresolved.

The Mac locked before the live native check. The isolated candidate is retained, and its control/drawing/history/Quit validation awaits human unlock. This gate stays open while G04 source audit proceeds, followed by T01. Exact Photoshop defaults/output and all original G03 scope remain open. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-408).

The source backup is verified on [private main](https://github.com/ForensicIntelligence/Photato/commit/004b0f4625d99008f2bc3ae2e76a0d34f1074e50). All 7,153 included qualified inputs match the tested snapshot; the exclusions and pending live check are documented. Original root/Rust files and Git history are retained. No binary, App Store change or software release was uploaded.

## 2026-11-04 — Step 409: Quick-win source audit

Four candidates were checked against the source before choosing more implementation work. Paths already had Fill and Stroke controls and a shared API. The existing rich-text fields were already exposed, as were the shaped-text layout parameters. The selected 13 path, 20 typography and 18 tonal tests all pass on both architectures using the preserved optimized build. No new software or tests were needed for this audit.

The audit also found two real gaps. Curves has no Auto operation or Auto Color Correction Options; the reusable estimator returns Levels settings. Window > Character and Paragraph remain pending even though their controls are available in Properties. Proper separate panels require integration with the retained workspace layout and native lifecycle. These gaps stay under stillneeded, with full original scope and independent compatibility requirements intact.

The quick-win queue advances to A04, current 2026 adjustments, then A05. This is a source and regression audit, not four completed Photoshop features. The prior Debug failures, full-suite and physical-platform gates, and pending live stroke-preset check remain recorded. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-409).

## 2026-11-05 — Step 410: Gradient Fill API and Actions

The source audit found that modern adjustment controls and native gradient transforms/presets were already exposed. A direct API for editing a live Gradient Fill was missing. The new command uses the existing native transaction and publishes its request, active state and capabilities. It preserves masks, transforms, selection and unrelated data, and supports one-step Undo/Redo.

The first new test run exposed an older recorder limitation: Gradient Fill edits were saved as unsupported steps. A portable target-and-fill payload now records, validates, exports, imports and plays back those edits. New payloads require Actions 47. A separate existing mask-gradient test assumed the image palette while editing a mask; it now selects its intended ramp explicitly, and a new test checks the actual default mask ramp independently. No rendering kernel or palette default changed.

All 74 focused Debug tests and82normal optimized cases on each architecture pass, including eight new cases. Both Release runs execute the same ordered IDs. The universal package passes macOS 14 minimum, signature and ZIP extraction checks. Failed attempts remain in the detailed record. Actual native interaction, full Photoshop behavior, the current full suite and physical-platform/performance checks remain open. Next is the Pattern Fill/Fill/Stroke audit, then ordinary filters. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-410).

## 2026-11-05 — Step 411: Last Filter

The Pattern Fill audit confirmed that the existing angle, scale, offsets, linking, origin and canvas controls were already present. Stroke already supported Inside, Center and Outside placement. Selected model, native, API and interchange checks pass on both architectures. Full pattern and fill/stroke compatibility remains open.

The next package had a useful missing command: Last Filter was visible but unbound. It now recalls successful native filter settings, shares them between attached documents and repeats them with the current selection and target. Option invocation opens copied settings for preview or cancellation. The new API command publishes recall state and follows the same transaction and revision checks. Existing portable filter Actions handle recording; no document or action format change was needed.

All eight new tests and 42 focused Debug cases pass. Failed attempts are retained, including two corrected test assumptions and an existing Adobe-job Debug signal-10 failure reproduced on the previous build. Release, actual UI and full Photoshop acceptance remain open. The quick-win queue continues at the ordinary filter catalogue, followed by Blur Gallery. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-411).

## 2026-11-05 — Step 412: Filter Gallery dragging

The filter-workspace audit confirmed that the selected ordinary filter, Blur Gallery, Liquify and manual Lens Correction controls already existed. Their 59 regression tests pass on each architecture. Calibrated lens profiles, complete effect behavior and independent output/default comparisons remain open.

Filter Gallery had arrow buttons for reordering effects but no direct row dragging. The new private drag transfer checks the workspace, settings revision and individual gesture before moving anything. It rejects delayed drops after an edit or Cancel, transfers from other workspaces and superseded gestures. All effect values and hidden states survive moves. The existing native transaction, local history, document commit, Actions payload and ordered-array APIs are retained.

Eight new tests cover transfer, order/field retention, rejection, delayed callbacks, preview/Cancel/history/recording, desktop/API bytes, stack limits and modal cursor restoration. All 53 focused Debug tests pass. Normal builds pass 116 main cases and two additional metadata cases on each architecture, including all 16 new Last Filter/Gallery tests. The two metadata tests were omitted from the initial Release selector and then run separately on the same binaries; this was not a single 118-case run.

The universal package passes signing, macOS 14 minimum and archive extraction. The windowless capture is layout evidence with material/thumbnail limitations. Physical dragging and system feedback remain unverified while the unlock request is pending. Full F06 and all original Photoshop requirements remain open. Next is the brush-settings source audit, then B02. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-412).

The private full-source backup is verified at commit `1a7845d308aae9ddffb0f81a4ad0dbd15bbaefe5`. All 7,160 included qualified inputs match the tested source. The 34 excluded inputs are generated/cache material or the restricted external PSD, with acquisition and provenance instructions preserved. All 1,061 original root/Rust files and prior history remain unchanged. This is a source backup; it does not release the software.

## 2026-11-05 — Step 413: Brush Settings sidebar controls

The painting audit found that current brush-model settings, Pencil Auto Erase, Clone Source transforms/overlays and Content-Aware output choices already had native controls and API paths. Their 50 selected regression tests pass on both architectures. We kept those implementations and preserved the larger gaps in their full work packages.

One useful brush interaction was missing: enabling a group directly from the sidebar. Eleven checkboxes now use the existing setting flags, with preset locks kept separate. Tip Shape, Smoothing and Symmetry retain their existing controls without invented enable flags. Public Adobe guidance documents sidebar group checkboxes; this is not a new live Photoshop observation.

One new end-to-end regression checks all checkbox mappings, no-op/history behavior, busy/stale/type guards and subsequent native/API stroke bytes and Undo. All 62 focused Debug tests pass after a test-only compile correction and a runner-only capture-directory correction. Failed attempts remain in the detailed record. No kernel or file format changed. Normal universal and actual pointer/layout checks remain open. Next is clipboard interoperability, then layer styles. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-413).

## 2026-11-05 — Step 414: Smart Filter dragging

The layer-workflow audit found existing native/API controls for current clipping and fill settings, copying/pasting/clearing styles, and relinking/updating linked artwork. Clipboard support is still limited to composite image content; adding mask/channel/path targets needs new routing, transactions and API behavior. Those larger requirements remain in stillneeded.

Smart Filter rows had arrow-menu reordering but no direct drag or copy interaction. A private process-local transfer now supports single-filter copying within one document and reordering within a stack. It carries a random token rather than document content and checks source identity, generations and document attachment again after loading. Option feedback and the dispatched operation share one resolver. The existing stack transaction preserves target masks and source bytes, validates rendering and supports Undo and portable Actions.

Three new tests cover private transfer, copies across pixel depths and new/existing masks, desktop/API saved bytes, history/Actions, invalid and delayed transfers, limits and all modifier combinations. A test-fixture constructor mistake was corrected without production changes. All 53 focused Debug tests pass. Normal builds pass 99 of 100 cases on each architecture; the single linked-PSD/PSB alpha mismatch is unchanged from the earlier baseline and remains open. No tolerance was changed. The universal package passes signing and archive checks. Physical interaction, cross-document/group/mask transfers and full Photoshop acceptance remain open. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-414).

## 2026-11-05 — Step415: Select Subject options

The selection audit found that all settings represented by the current Color Range, Focus Area and Magnetic Lasso engines already had controls. Their41existing tests pass on both normal baseline architectures. Missing classifiers, gamut selection and Adobe preset semantics stay in stillneeded; full Photoshop acceptance remains open.

Object/Quick Selection lacked the Select Subject action in its Options bar. The new button uses the existing on-device foreground-selection transaction and captures the tool’s visible sampling choice. It does not overwrite the separate Properties/Menu preference. The optional API uses the existing selection.subject operation; availability and capability metadata now explain the native action.

One new regression checks both tools against input-dependent masks, including sampling capture, locked16-bit source preservation, replacement despite paint-mode settings, matching native/API documents and saved bytes, one Undo/Redo and guards. All81focused Debug tests pass. An initial baseline driver guessed three test paths incorrectly and was corrected before any worker launched; that failed attempt is preserved. No application/test repair was needed after compilation. Normal universal and actual pointer/layout checks remain open. Next: Select and Mask, then mask confirmations. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-415).

## 2026-11-05 — Step 416: Selected-mask removal and API

The mask audit found all six Select and Mask outputs already wired to native/API transactions. Current alpha/spot rename, duplicate, reorder and options controls also exist. Those packages retain their larger missing workflows and fidelity requirements.

Layers trash always requested layer deletion, even with a mask selected. It now routes pixel/vector/Smart Filter masks to their own operations, preserving the layer and compound masks. Native confirmation captures the source and editing context, blocks API edits and rejects stale replies. Properties trash shares the pixel-mask prompt; explicit menu commands keep their meaning. The new mask.manage operation fills the missing typed pixel/vector apply/delete API path and uses the same prepared engine/history.

Three new regressions check RGB 8/16/32 results, exact native/API files, one Undo/Redo, existing pixel/filter Actions, all modifiers, invalid/stale/busy/locked contexts and native alert choices/bounds. All 102 focused Debug tests pass after one real API admission correction and two new-fixture corrections. Failed sources, binaries and logs remain. No imaging kernel, file format or capacity limit changed. Vector portable recording, current Photoshop dialog/default/physical fidelity and normal universal qualification remain open. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-416).

## 2026-11-05 — Step 417: Statistical image stacks

The mode and proofing audits found existing controls rather than omitted menu actions. All eleven stack modes were also present, but five mathematical definitions differed from Adobe’s current public documentation. This was a useful correctness fix within RAW02; its larger photo-merging workflows stay open.

The shared Swift engine now uses sample variance, its standard deviation, signed skewness, raw kurtosis and Shannon entropy without the earlier binning or normalization. Four owned tests include 14 rational and high-precision Decimal cases, 70 exact Float32 expectations, native RGB32 pixels, persistence, history and both API interfaces. The original Rust fixture remains intact; its differential check now covers the six unchanged operators. Photoshop behavior takes priority over conflicting Rust formulas.

The first new action-job fixture requested PNG for RGB32, which the encoder correctly rejected. That failed attempt and its binaries are retained. Changing only the fixture to TIFF gave 41 passing Debug tests. Normal builds each ran the same 159 tests and passed 157, including all eight new tests from 415–417. The two failures match preserved baselines exactly: four alpha bytes in linked PSD/PSB previews and a master-palette CancellationError. Neither is waived or claimed fixed.

Both architectures match the independent 70-word reference. Universal packaging, signature verification and extracted ZIP equality pass. Actual native interaction, complete Photoshop output and edge behavior remain unqualified. All original scopes and prior failures remain recorded. Next: I03 migration audit, then I04 export/interchange. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-417).

## 2026-11-05 — Step 418: Frame Timeline dragging

The migration audit found the currently supported metadata already preserved. Adding nondefault notes, compositions, timelines and other source fields needs new adapters and reference files. Save/Copy already exposes the fourteen represented encoding options. AI generation currently has no durable model/seed result record to inspect; its lifecycle foundation remains stillneeded.

The frame Timeline had reorder arrows but no thumbnail dragging. A private process-local transfer now selects the source frame, previews an insertion edge and invokes the same reorder command. Source/session/panel/ownership checks reject stale or foreign drops. Frame contents remain in the document, and one Undo reverses the move. API capability metadata explains the existing selection and reorder operations; no new route or format is introduced.

All 49 selected baseline tests pass on both preserved normal architectures. After a test-only compile correction, all 50 focused Debug tests pass, including three new regressions. They compare native/API files, pixels and history across three depths, insertion positions and delayed-transfer rejection. Physical feedback, auto-scroll, multi-frame and modifier duplication, complete animation interchange and normal 418 acceptance remain open. Next are the Sky Replacement library and Adjustment Brush audits. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-418).

## 2026-11-05 — Step 419: Rename sky presets

Sky import/removal and API rename already existed, but the native workspace had no rename action. Adobe’s current sky-preset instructions include Rename Sky. The new native dialog uses the existing library method, captures its source and revision, and preserves IDs, order, image bytes and document history. Preview names update after a successful save. Library changes persist independently of cancelling the document replacement, matching import and removal.

All 26 selected baseline tests pass on both normal architectures. All 57 focused Debug tests pass after a test-only compile correction, including three new checks for native/API file equality, unchanged pixels/history, persistence, Cancel, invalid Unicode names, failed storage with retry and stale contexts. No generation model, rendering kernel, command or archive version changes. Existing Adjustment Brush controls were verified rather than rewritten.

Normal 419 and physical/current Photoshop dialog/hierarchy/default behavior remain open, along with full Sky Replacement and Adjustment Brush workflows. Next: measured responsiveness, then independent references. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-419).

## 2026-11-05 — Step 420: Rasterization responsiveness

The existing optimized brush benchmark retained all 240 samples in each of four cases. Its24MP input/render/offscreen-draw p95 values were about0.006ms,12.73ms and3.55ms. Those CPU measurements do not establish physical60fps. Source review instead found a synchronous native rasterization path. An unchanged419Debug probe and main-thread profile confirmed the blocker before product changes.

Native rasterization now uses the existing detached geometry preparation and shared API command. No image mathematics changed. Three functional regressions cover18depth/content combinations, exact native/API/old-command documents and archives, Undo/Redo, cancellation, source replacement and busy/locked/modal guards. The new tests passed before an unchanged Debug Shape API case crashed; the same case also crashes on retained419. Both optimized builds execute195identical cases with193passes and two exact recorded failures. All18new methods from415–420pass, including the actual opt-in performance measurement. Independent stack checks still match70Float32words per architecture.

Optimized24MP submission takes0.023ms on Apple Silicon and0.046ms under translated Intel, with preparation about6.94s/12.25s in the worker. The pinned old expression replay is explicitly a same-process reference, not a measurement of an old optimized binary. Universal packaging checks pass. Physical/UI/performance/Photoshop output and full Q03 remain open. Next: Q04, then REL01. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-420).

## 2026-11-05 — Step 421: Channel thumbnail options

The Channels panel had an Options context menu but no thumbnail double-click route. The new native control selects the captured alpha, spot or Quick Mask target and opens the same dialog. It preserves existing modifier clicks, validates document/session/channel identity, and leaves pixels and history unchanged on open or Cancel. Committing uses the existing native/API operation and Undo behavior.

All 56 focused Debug tests pass. Three new methods cover nine depth/target combinations, exact native/API documents and archives, pixels and history, 64 modifier/click cases, a hosted native mouseDown event and stale/busy/modal/deleted/replaced contexts. The earlier 39-test reference/channel baseline and final 11-test warp/typography baseline pass on both retained optimized architectures. Independent statistics checks match 70 words each.

Source review found existing independent fixtures, production identity/sandbox configuration, per-increment inventories, every represented warp preset and installed-font axis/OpenType control. Their broader gaps remain. The old step058package checker is already documented as historical; it was not counted as a new archive defect or rewritten. No current optimized build, native installation, source push, archive, Store action or release occurred in this checkpoint.

The major quick-win sweep is finished. Major stillneeded work starts with L01 layer collection workflows and D01 document workflows. All original scope, byte/default/shortcut requirements and earlier failures remain. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-421).

The final filesystem audit found 11 additional older temporary build binaries missing, alongside three previously recorded gaps. All 26 surviving protected files retain their expected hashes. The current source, 5,320 retained Debug outputs and 10,640 retained optimized outputs remain intact; the latest420candidate and ZIP also match. The cause and disappearance time of the older files are unknown. Their expected hashes and missing paths are recorded, and historical preservation remains incomplete.

## 2026-11-05 — Step 422: Arrange selected layers

Layer > Arrange now has all five commands. They preserve selected sibling order when moving, reverse only selected positions, carry complete group subtrees and retain every stored layer field. The native operation prepares in the background and commits one history entry after checking its source and target. The Photato API has strict parameters, state and availability; Actions 48 stores semantic targets. The supported Adobe MoveLayer placements run through the same primitives in isolated resource jobs.

All 106 focused tests pass, including 12 new regressions. An owned Python rank reference supplies 310 cases, checked at RGB8/16/32. The two first attempts each passed105tests and found one new test-fixture mistake: missing PSD IDs and an invalid translucent/masked Background. Both full attempts were retained before repair. Review also corrected the new adapter's bottom insertion index above Background. Source03 is test-only relative to Source02 and has the same app binary.

Both optimized architectures execute the same 281 cases and pass 279, including all 33 new methods from checkpoints 415–422. Existing failures remain recorded and are not waived. The universal macOS 14 package passes signature and extracted-ZIP content checks. This is feature qualification, not a passing full suite or complete Photoshop parity. Current physical checks still await Mac unlock.

The existing PSD writer omits regular layer-ID tags when no comp resources are active. The job fixture explicitly emits and verifies its IDs; a general ID-retention repair is not claimed. L01 filter/isolation, extended-empty and remaining lock/group workflows stay in major stillneeded. No minor or cleanup pass has started. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-422).

The complete native source backup is saved in the [private repository](https://github.com/ForensicIntelligence/Photato/commit/9c9723749d107c98cdbe9871879115edc6dcfdfb). All 7,187 included qualified inputs match422Source03; 34 generated/cache/restricted inputs are excluded with provenance. The 1,061 original root/Rust files are unchanged. Repository visibility remains private until release day. No binary was uploaded and no software release occurred.

## 2026-11-05 — Step 423: Layer filtering and isolation

The old filter lived in each SwiftUI view, permitted only one kind and compared display labels. It missed specific adjustment types. A shared document-local filter now drives native panel rows, Find Layers, Isolate Layers and the API. Multiple kinds and known Smart Object statuses can be combined. Name, effect, blending mode, metadata attributes, color, selected layers and artboards are available. Selection ranges follow filtered rows. Filtering retains the document's pixels, visibility, stored bytes and content history.

All 77 current focused tests pass, including the 13 new native/API methods. Final review corrected case-sensitive artboard UUID handling; lowercase references and idempotence now have regression coverage. The earlier 85-test affected run passed 83 cases. Its two capacity errors reproduce in the retained 422 Debug bundle and pass in 422 optimized ARM64/Rosetta. The first compile attempt failed on two overlapping accesses in the new linked-source fixture; the failed source and outputs were preserved before repair. Parameter review also corrected NUL/UTF16-limit errors to return400. No test tolerance was relaxed.

The owned nine-mode native control image was rendered and inspected. Current Photoshop comparison remains unavailable while the Mac is locked. Exact defaults and the complete attribute/hierarchy/path-selection behavior are unqualified. Empty/NotEmpty requires asynchronous pixel scanning, and library-linked sources require integration that is not present. Those controls are unavailable and remain major stillneeded work. Background-only/no-active-layer selection and extended empty-layer behavior also remain open.

Typed API inventory is 248; native archive86 and Actions48 stay unchanged. Configuration is presentation state and has no published Adobe panel-state counterpart. Current optimized/universal/private-source qualification is batched for the next meaningful milestone; latest packaged/private source remains422. No new install, archive, upload or release occurred. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-423).

## 2026-11-05 — Step424: Asynchronous layer content filters

Added Empty and Not Empty to the native panel and optional API. A cancellable worker checks stored alpha without a full-canvas allocation. It retains source storage while running, rejects changed sessions and revoked shares, and refreshes after edits. Pixels, layer visibility, Undo/Redo and recorded Actions stay unchanged. View selection can change when the active layer is filtered out; earlier whole-archive-unchanged expectations were corrected to test that observed distinction.

The owned Photoshop2026 document showed transparent raster and embedded Smart Object layers matching Empty, childless groups matching Not Empty, and no automatic selection when rows return. Group mode and the Advanced Blending attribute pair were observed but remain unimplemented. No proprietary code was inspected or executed as part of these comparisons.

All88focused Debug tests pass, including11new methods. The first build rejected a new Core test's dependency on an Imaging helper. The next run passed86of87cases; the mapped fixture had requested less storage than the existing index requires. Both attempts were preserved before test-only repairs. Later review found a read/close hook defect; optimized compilation was deliberately stopped before delivery, corrected, and covered by an actual NSDocument read/re-query/close test. The corrected source passes88of88. Subsequent optimized and packaged results are recorded below.

This remains major stillneeded L01 work. Full library/Group/Advanced Blending/special-content/default/platform qualification and all original104package scopes stay open. No installation, Xcode archive, AppStore upload or release was performed. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-424).

Later qualification caught an API compatibility defect: revision tokens had grown beyond the existing 256-character source-reference limit. A 64-character hash preserves all change tracking without increasing that limit. The affected stack and Smart Object tests now pass. Final source424Source05 passes91focused tests and358of360normal cases on each architecture, including all57new415–424methods. The two residual failures have the exact build422 diagnostics. Universal minimum14/signature/ZIP checks pass. In the packaged native app, an owned brush stroke left the Empty filter and cleared selection; one Undo restored the empty layer. Complementary filters and normal Quit passed. The owned document was discarded; no user document was edited. No physical60fps or full Photoshop qualification is claimed.

The full native source backup is saved in the [private repository](https://github.com/ForensicIntelligence/Photato/commit/ce9c535ef80b8ccfb8b8f6ce4bcc82bf8276bb41). The 7,196 included build inputs match the tested source; 34 generated, cache or restricted inputs are excluded with recorded reasons. All 1,061 original root/Rust files are unchanged. The repository stays private until release day. This was a source backup; no binary was uploaded and no app was released.

## 2026-11-05 — Step 425: Layer selection and deselection

Added Select > Deselect Layers, fixed Command-clicking the final selected row, and made the unused space below layer rows deselect on a plain click. The native blank-area control fills the available viewport, exposes an accessibility action and rejects drags and stale owners. The rows remain lazy and their eye/thumbnail controls remain separate. All Layers now keeps a selected layer as its active target.

New `layers.selection` API operations share native behavior and expose selection and availability. User deselection can be recorded as a portable Actions 49 step. Pure selection recipes validate targets atomically, preserve pixel history/Redo and avoid scanning image buffers on the main actor. Mixed recipes still commit edits through one prepared Undo. Native archive 86 is unchanged. No unpublished Adobe selection endpoint or ATN compatibility is claimed.

The new code passes 127 focused Debug tests, including nine new methods. Initial attempts exposed a test method-name error, an inaccessible offscreen SwiftUI control, and the empty native button's default accessibility role/return value. Sources, binaries and failed logs were retained before repairs. The expanded clipboard suite also stopped with signal10 in a method with earlier Debug crash evidence; current cause remains unproven and optimized testing includes it. These failures are recorded, not erased by the passing focused run. The first optimized run also found six catalog-count checks still expecting 248 after the new API raised the total to 249. Only those expectations were corrected; the app binary stayed unchanged. The expanded focused run passes 127 tests, and the full affected optimized set was repeated.

Adobe's public selection instructions were used; the Mac locked again before a fresh owned Photoshop comparison. Offscreen native layout/event tests are not physical UI proof. Both optimized architectures pass 393 of the same 395 cases, including all 66 new methods from checkpoints 415–425 and the clipboard method that crashed in Debug. The two remaining linked-alpha/master-palette failures have the same diagnostics as checkpoint 424; no Debug crash repair or full-suite pass is claimed. The universal package passes both macOS 14 slices, signature and ZIP checks. D01 document workflows follow. The substantive L01 remainder stays in major stillneeded, and no minor or cleanup pass begins. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-425).

## 2026-11-05 — Step 426: Customize Save Dialog File Formats

Added the Edit command documented by Adobe in August 2026. Its native dialog lets users select formats, restore defaults, clear the list, cancel or save the choices. Save As also respects the existing checks for preserving editable content; Save a Copy uses the selected supported encoders. This adds format visibility, rather than new codecs. Full Photoshop format support remains outstanding.

Choices are saved with File Handling settings through the existing atomic writer. Older settings load without being rewritten; a later commit writes settings version 4. Unknown or duplicate formats, malformed current settings, failed storage, active file operations and stale/external changes retain the earlier settings. Other recovery, recent-file and compression values are preserved. An empty or incompatible list cancels native panel creation with guidance, without silently inserting a hidden format. Exact Photoshop empty-list behavior is still unqualified.

The existing File Handling API accepts the same choices under its separate permission and revision guard. Document state exposes dialog choices separately from available encoders. Ordinary Save, recovery and explicit API output keep their existing behavior and bytes. Native archive 86 and Actions 49 are unchanged. The newly documented menu command supplements the earlier capture; all 651 tracked identities, captured hierarchy and factory shortcuts are retained. Exact placement, punctuation and default selections still need a live comparison.

All 101 focused Debug tests pass, including seven new methods. The initial run passed 100 of 101: a new API test reinitialized AppKit's document-controller singleton during the service and compared an unnegotiated legacy download with current archive bytes. Failed sources, binaries and logs were preserved before test-only corrections. The app binary is unchanged between those attempts. A normal-build helper then failed before compilation because its hash helper had been dropped during adaptation; that diagnostic was preserved and the helper repaired. Both optimized architectures pass the same 101 selected cases, including all seven new methods. The universal package passes minimum macOS 14, signature and ZIP checks. Earlier full-suite and checkpoint 425 residual failures remain open; this is not a full-suite pass. The owned offscreen dialog capture checks fit, not physical UI or visual Photoshop equivalence.

The Mac remains unavailable for live comparison pending the existing unlock request. L07 is next after this batch; remaining D01 and L01 functions stay in major stillneeded. No minor or cleanup pass starts, and no full package is declared complete. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-426).

## 2026-11-05 — Step 427: Adjacent artboards

Added the canvas + controls described in Adobe's public artboard guide. A click adds an empty neighbour with the source dimensions and background; Option held when pressing copies the existing board and its contents. Releasing elsewhere or pressing Escape cancels. Tool, focus, document/session and selected-artboard changes also cancel the press. Temporary Hand does not create a board. Placement uses logical pixels and the existing sparse-canvas rebase without resampling source content.

The existing artboard.edit API now accepts adjacent, a side and optional copy/spacing/name parameters. Both entry points use the same request and prepared editing engine, including one Undo/Redo transaction. The API's older32,768 dimension bound was corrected to match the current300,000-pixel engine extent. Canvas union and memory guards remain. Native spacing is100 logical pixels; the API accepts explicit spacing. Exact Photoshop spacing, naming, background inheritance and occupied-neighbour behavior still need live reference checks. No new menu, shortcut, typed command or file format was introduced. Native archive 86 and Actions 49 remain unchanged, including the outstanding artboard Action-recording coverage.

The first build failed because the app called an internal Core validator. After preserving that attempt, it was changed to the existing public validation path. The second build passed the editing checks, but a new test looked at the wrong level of the API schema. The broader run then crashed in an existing Frame draw-over-image case. The retained previous 426 Debug binary reproduces the same signal10. This establishes an earlier reproduction, without identifying a cause or fixing the crash. The corrected focused selection retains the other Frame tests and explicitly excludes that one case.

All 41 focused tests now pass, including all eight new methods, 24 side/depth/create-copy combinations and 16 modifier combinations. They check exact native/API rendered results, stored content, archive round trips, history, cancellation and invalid/busy/stale/unshared requests. Offscreen inspection found the top control overlapping the name on a small board; its spacing was corrected and the same tests rerun successfully. The final owned capture shows the controls clear of the label. This is layout evidence, not a physical Photoshop comparison. Failed attempts and binaries remain in the technical record.

Normal/universal 427 and physical qualification remain batched. The prior Frame crash, exact defaults, nesting/dissolve and the remaining artboard/frame functions stay open. S01 is next in major stillneeded; all 104 original package scopes and acceptance criteria are retained. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-427).

## 2026-11-05 — Step 428: Animated selection borders

The selection border was drawn with a fixed dash phase. It now uses native Core Animation layers for committed selections, Transform Selection and marquee previews. White strokes and black dashes stay the same screen width while zooming. Existing hole contours and bounded sparse-document geometry are reused. The layer animation does not request a Swift canvas redraw or recomposite the image for each frame.

Inactive, hidden, occluded, minimized or detached windows stop playback. Reduce Motion retains a static border. Selection Brush keeps its coverage overlay. The API exposes the presentation policy and requested animation, rather than claiming to report the compositor's actual playback state. This adds no editing command, menu, shortcut, cursor action or file-format field. Native archive 86, Actions 49, typed commands 249 and settings 4 remain unchanged.

The first focused run passed 81 of 82 tests. A new hole/zoom test installed a temporary path, then changed zoom, which correctly cleared that path. After preserving the failed source and outputs, the test was changed to use actual holed document coverage and await its render. The same 82 cases then passed. A further eight-method probe used asymmetric owned artwork to verify that the border follows the selected pixels in the native layer capture. The production binary was identical across those attempts. No selection algorithm or tolerance was changed to satisfy the test.

Both optimized architectures pass the same 98 selected cases, including all 23 new methods from checkpoints 426–428. The old Frame draw-over-image case also passes optimized; this does not explain or fix its earlier Debug crash. The universal package passes minimum macOS 14, signature and ZIP checks. Exact Photoshop dash timing, physical refresh-rate performance, complete Extras controls and broader platform/full-suite qualification remain open. All captures are owned offscreen evidence; no live Photoshop interaction is claimed.

The source audit confirmed that Grow and Similar are missing. The existing Magic Wand matcher uses the licensed PhotoCraft RGBA8 comparison and full-canvas buffers. The recorded plan calls for independent Photoshop fixtures, bounded sampling, paged coverage and shared native/API transactions. It remains a functional gap in major stillneeded. G01 is next; no major package is declared complete and no minor or cleanup pass begins. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-428).

The full native source was backed up to the existing private [GitHub repository](https://github.com/ForensicIntelligence/Photato/commit/dd9f86229b43d0989a6fa8dfd7e48fd19cb75087). All 7,207 included qualified inputs match the tested snapshot; 34 generated, cached or restricted inputs are excluded with provenance. The original 1,061 root/Rust files are unchanged. The repository remains private until release day. This backup does not publish or release a binary.

## 2026-11-05 — Step 429: Transform reference point

The transform reference point can now be shown and moved freely, including outside the transform bounds. A shared nine-position locator remains available in Options. Rotation, numeric scaling and Option scaling use the chosen point. X and Y show its coordinates. The existing transform engine still prepares and applies the final matrix.

This works with the existing selection, pixel, mask, saved-channel, layer and Content-Aware Scale drafts. Moving the point or changing its visibility does not alter document bytes, add Undo, record an Action or request another preview. A Content-Aware Scale worker can finish after a reference-only change. Escape, focus or tool changes cancel a captured pivot drag, while owner/session/source checks prevent it restoring over later work. The scope cursor stays with the captured action for all 16 modifier combinations; Space before press retains Hand.

The API adds transform.reference and observable workspace state. It requires the current document revision plus a separate workspace UUID, preventing an old request from changing a newer transform. Ordinary editing commands remain blocked during the native transform. Typed commands total 250; native archive 86, Actions 49, settings 4, menu identities and shortcuts are unchanged. No Adobe route is invented for an operation outside the published contract.

The first attempt failed compilation because a cancellation call was placed before super.init. Its source, diagnostics and pre-existing outputs were retained before the call was moved to the tool-change lifecycle. The second attempt passed 123 of 125 tests, including every new method; two shared catalogue assertions still expected 249 commands. After preserving that run, only the two genuine count expectations were updated. The final run passes all 130 focused Debug tests in 41.571 seconds, including the additional affected layer-filter API checks. Production app bytes are identical between the last two attempts. Existing pixel fixtures and tolerances were not changed. The owned offscreen control capture shows the toggle and full locator grid; it is not a live Photoshop or performance test.

Transform Again still needs retained transform state across targets and commits. Remaining transform/crop functionality, exact Photoshop defaults, persistence, pixels and broader platform/performance checks are open. A03 classic adjustments follow in major stillneeded. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-429).

## 2026-11-05 — Step 430: Large-document Equalize

The source audit found that the classic tone processors stopped at 8,388,608 pixels. Match Color's source-document/layer pickers and tone preset files were already present. Brightness/Contrast still needs a properly referenced modern transfer and native workflow; its menu was not connected to the licensed approximation. The selected capacity work is Equalize.

The histogram now counts paged and implicit samples without allocating a full image array. Edge-tile padding is excluded. The existing 256-bin CDF, depth quantization, selection blending and transform/storage rules are retained. Native controls, API and portable Actions share one prepared edit and Undo. Maximum 300,000 × 300,000 implicit rasters and sparse selections pass at every native depth. This does not prove dense maximum throughput or exact Photoshop bins and output.

The first run passed 23 of 26 tests. It exposed an unrelated Smart Filter size gate in the reused bounds helper. The failed source and outputs were retained before Equalize received its own equivalent ordinary-pixel bounds calculation. All 26 then passed, but profiling found that the selected-area preview composed a whole 11-megapixel image before reducing it. The preview path now reuses exact sparse composition where eligible and paged composition otherwise, then reduces a bounded overview. A later memory assertion caught identical pixels being materialized in a constant overview. That source was retained before an exact implicit constant path was added. Expected pixels and tolerances were not relaxed.

The final 30 focused tests pass, including eight new methods. They include analytical CDF bytes, the frozen pre-change array engine, six canonical display-byte comparisons, implicit-versus-stored HDR/alpha comparisons, maximum sparse capacity, native/API/Actions/archive/Undo and preview/cancellation/source guards. Both optimized architectures pass the same 127 selected cases, including all 38 new methods from checkpoints 426–430. The universal package passes minimum macOS 14, signature and ZIP checks. Current source and binary hashes are recorded. Earlier full-suite and Debug failures remain open.

The large dialog labels its overview and disables controls that would falsely imply full-resolution inspection. A full-resolution interactive dialog viewport is still needed; full-resolution output can be inspected in the document after Apply. Other large classic tone families, Brightness/Contrast, presets/interoperability and independent Photoshop fidelity remain A03 work. The API advertises per-kind limits and overview state; its existing operation and archive/menu/shortcut identities are unchanged. Adobe Equalize descriptor coverage is not claimed. Photoshop remains behind the locked Mac screen; no live check or physical refresh-rate result is invented.

I05 color lookup/export follows. No major package is declared complete and no minor or cleanup pass begins. The private source backup follows the standing request after this optimized batch. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-430).

The [private source backup](https://github.com/ForensicIntelligence/Photato/commit/8400eb8e3bddc8bbbfeb9bd8e9e4e644d29daa39) contains the qualified source for this batch. The repository remains private until software release day. No app was installed, Xcode-archived, uploaded to the Store or released.

## 2026-11-05 — Step 431: Color Lookup output formats

The RGB adjustment-stack exporter now writes 3DL, CSP and ICC device-link files alongside CUBE. All selected formats use one bake through the existing compositor. CUBE and CSP retain extended floating values; the integer 3DL and ICC formats reject samples outside0–1. An ICC device link carries a transform between RGB values; it is not a document working profile.

The native dialog adds Copyright, base filename and four format checkboxes. Named FileDocument wrappers feed the native multiple-document exporter. The optional API adds individual format routes and ZIP output, with matching metadata, filename, date and format validation. Creation time defaults to request time and can be pinned for byte comparisons. Explicit cancellation, busy/source/revision checks and share revocation cover both preparation worker types. Exports leave the document and history untouched. Menu identities, shortcuts and the250 typed editing commands are unchanged. No unsupported Adobe endpoint or export descriptor is invented.

The first build failed in a test helper whose internal method accepted a private gate type. Its source, diagnostics and outputs were retained before only that method was marked private. The app binary is identical in both attempts. The repaired run passes all34 focused Debug tests in4.528seconds, including eight new methods and the affected existing LUT/PSD/API/archive tests. No old pixel fixture, expected value or tolerance was weakened. Offscreen inspection shows the metadata controls, all four choices and Export button. Owned named FileWrapper output was written and checked; this does not qualify live save-panel behavior.

Independent OpenColorIO2.4.2 reads the owned CUBE/CSP/3DL files. LittleCMS reads the ICC device link. Thirty vertices and interior samples reproduce the asymmetric test transform within bounds set before the checks. Apple ColorSync verifies the ICC without errors or warnings. The reader driver initially failed to discover the existing LittleCMS library from its isolated environment; that failure and script were retained before an observed absolute library path was supplied. No runtime dependency was added to the Swift app. The public ICC specification was available as web text, while direct PDF download returned403; the failed download was not retried or bypassed. Public OCIO source is retained as a format reference, not copied implementation.

Full256 grids/streaming, LAB/CMYK conversion, general CSP/ICC import, exact Photoshop presets/files/interpolation, live multi-file overwrite/error behavior and the rest of I05 remain open. Dark3DL tables are ambiguous to some readers that infer bit depth from their largest value; Photato's explicit metadata solves its own import only. B05 painting workflows follow within major stillneeded, thenC01. Current optimized universal/full-suite/physical qualification is unclaimed;430 remains the latest optimized/private-source batch. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-431).

## 2026-11-05 — Step 432: Pattern Patch

The existing Patch tool had Source/Destination and adaptation controls, but lacked Use Pattern. Normal mode now offers a saved-pattern picker and button. Document resources take precedence over library resources with the same ID. The chosen resource is captured when preparation starts. It supplies texture to the Normal healing solver, rather than applying an ordinary Pattern Fill.

Only the selected solve window and transformed output are prepared and written. A small repair therefore works on the maximum300,000×300,000sparse canvas. The current solve/output limit is4megapixels; larger solves and the other retouch tools' capacity remain unfinished. The source image, selection representation, outside pixels, layer/mask geometry, metadata and protected alpha are retained. Cancel, changed documents/sessions and revoked API requests publish nothing. Successful native/API edits share one Undo. Existing menus, shortcuts, archive formats and250typed commands are unchanged; retouch.patch gains a strict patternID alternative to the original drag parameters. No unsupported Adobe action descriptor is invented.

The first build stopped on a new test that tried to mutate a read-only session property. After preserving that attempt, the test installed an immutable locked document instead. The second run passed38of39methods; its255new outside checks expected ideal0.5rather than storedRGB8gray128/255. Those checks now compare the exact unchanged before/after bits. A separate donor comparison then exposed a representation difference: legacy Normal Patch materializes rectangle coverage, while the new path preserves it compactly. The final comparison requires equal coverage and every other document field after normalizing only the legacy selection representation. All previous outputs and helpers were retained. A slow read-only text-diff diagnostic was stopped separately; no compiler/test was terminated. No old fixture or tolerance changed, and production app bytes are identical across all four Debug attempts.

The final run passes40focused tests, including nine new methods. They cover analytical texture/diffusion, soft coverage, transparency, HDR, outside bits, maximum sparse capacity, transformed layers, native/API/Undo/archive and cancellation/stale/revocation. The new donor comparison matches old Normal Patch pixels exactly across three depths and three diffusion settings. Those are existing-engine and analytical checks, not Photoshop output evidence. The offscreen swatch/name is visible; live button appearance remains unqualified.

The stable batch also includes431's Color Lookup formats. Both optimized architectures pass the same199selected tests, including all55new methods from426–432. All eight current normal LUT files match the independently checked431files. Universal macOS14slices, signature and ZIP extraction checks pass. A packaging helper initially corrupted a pinned resource-hash literal while replacing a test count; its original script/output were retained and the original oracle restored, without changing any resource or app bytes. No install, launch, Store action or software release occurred. After workers finished, a fresh Photoshop binding confirmed the Mac is still locked. The earlier unlock request remains pending.

C01is next, with Channels quick-save/direct-load identified for source/reference audit. Full B05, mask/channel and projected targets, larger solve regions, exact Photoshop behavior and all broader platform/performance acceptance stay open. The private source backup includes7,220qualified inputs and preserves1,061original root/Rust files; generated/cache/restricted inputs are excluded with provenance. No test fixture changed. [Source commit](https://github.com/ForensicIntelligence/Photato/commit/315a12121fd1fc8f323a242316d1a60ef21ade67). [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-432).

## 2026-11-05 — Step 433: Channels footer Save and Load

Footer Save used to open the Save Selection dialog every time. It now creates an automatically named alpha channel directly; Option-click retains the dialog. It does not change the selection, source image, current editing target or channel eyes. At channel capacity it reports the limit instead of silently replacing another channel. Footer Load now uses the selected source directly, including a saved channel other than the first, rather than opening a dialog or choosing the first ink target. Ambiguous partial multi-channel sets remain unavailable pending reference-driven handling.

Smart Filter masks are now selection sources in the native/API source lists. The implementation reuses the existing projected raw layer-mask sampler, including the filter mask's document transform and outside value. Display density, feathering and enabled state are kept separate. Existing source masks and layer metadata remain unchanged. The optional API keeps channel.edit and adds the strict smartFilterMask owner descriptor, source discovery and footer availability metadata. Native and API use the same prepared Core Save/Load commands. New-alpha UUIDs remain independent per request. Menus, shortcuts,250typed commands and archive/Actions versions are unchanged; no unsupported Adobe endpoint or action descriptor is invented.

The first build compiled the app but stopped on a new test fixture's access to an internal surface helper. Full source, diagnostics and outputs were retained before the fixture was rebuilt with public sparse Surface/SelectionMask APIs and the same2×2coverage. No production code, old fixture or tolerance changed; both app hashes are identical. The repaired run passes all58focused Debug tests in5.211seconds, including eight new methods. Known raw arrays test mask placement at all depths. Maximum sparse canvas tests check source memory and all-depth quick-save/archive/Undo. Other tests cover16Save modifier policies, options Cancel/capacity, selected targets/eyes, native/API material equality, strict descriptors and cancellation/stale/session/revocation guards. No live screenshot or physical UI check is claimed.

Full C01still needs other source/destination, thumbnail/drop, multi-target and paint/filter workflows wherever missing or unqualified. Exact Photoshop defaults/output/modifiers, earlier numerical/full-suite residuals and supported-platform/60fps qualification remain open. AUT01Actions/Batch follows in major stillneeded. Current optimized universal/private-source qualification remains at432and will be batched at the next meaningful milestone. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-433).

## 2026-11-05 — Step 434: Batch file naming

Batch previously generated a numbered source name with a suffix. It now offers up to six ordered fields, including document names, text, numbers, letters, extensions and dates. The native panel has add/remove/reorder controls, a starting serial, compatibility flags and an example. Run captures the current configuration and sources. The optional API uses the same planner; clients that omit naming keep their existing output contract.

Adobe's public Batch guidance and the installed declarative scripting dictionary supplied the supported field inventory and bounds. Microsoft documentation supplied Windows filename restrictions. No proprietary implementation was examined. Exact Photoshop naming, sanitization and uncommon date/overflow/default behavior remain to be checked. The current implementation validates names instead of silently rewriting them, rejects a duplicate plan before processing and keeps the existing protected per-file publication. Completed files remain after cancellation or later errors.

The first run compiled successfully and passed 24 of 25 tests, but the six-field panel requested 787 points of height for a 620-point window. The failed source, diagnostics, outputs and screenshot were retained. An explicit viewport ideal height repaired that production behavior; the original assertion was kept. Source02 then passed all 25 tests. Source03 strengthened the new HTTP test with busy and revoked-save checks and passed the same 25 tests, including eight new methods. Its app binary is identical to Source02. Literal field vectors, date/timezone and number/letter boundaries, canonical collisions, unsafe names, symlinks, input bytes, cancellation/revocation, native binding/run snapshots and native/API output equality are covered. No old fixture or tolerance changed. The offscreen capture checks geometry; it does not qualify live scrolling, focus or control appearance.

All 104 original package scopes and 652 command identities remain. Full Actions/Batch is still open, including conditions, interactive dialogs, Open/Save overrides, other source/destination modes, subfolders/import/Bridge, ATN, droplets and Image Processor. G03 live shapes follows in major stillneeded, then G04. Latest optimized universal/private-source batch is 432; no new install, archive, App Store action or release occurred. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-434).

## 2026-11-05 — Step 435: Create Rectangle and Ellipse

A click without dragging used to create a 1×1 rectangle or ellipse. It now opens a native dialog with Width, Height and From Center. Rectangles also have individual corner radii and a link control. Dragging keeps its existing behavior. The dialog captures the clicked point, output mode, target, operation and pattern resources. Cancel leaves the document and history unchanged. Apply uses the existing shape, path or pixel renderer and one prepared Undo; changed or closed sources are rejected.

The existing shape.edit API now accepts point placement, an optional center flag and shape combination. Strict request schemas and native draft state accompany it. Existing transform requests and default API names retain their behavior. Native and API output bytes and document material match in the tested workflows; independently created layer/path identifiers remain separate. No dedicated Adobe endpoint or proprietary action descriptor was invented. Public Adobe rectangle and ellipse instructions supplied the workflow reference; exact Photoshop defaults and output remain unqualified.

The first build found an initialization error in the new draft model. The next compiled the app but stopped on two new fixture declarations. Both attempts were retained before repair, with old cached test outputs distinguished from current binaries. The first runtime run then crashed in native pixel creation. A debugger captured a large Layer copy near the worker stack boundary. Splitting the new combination branch from ordinary creation let the full depth/mode test pass. A second crash occurred on the API pixel path; its debugger trace included the stack probe. Separating unrelated path/configuration Layer lookups from API creation repaired that selected path without changing Core/Imaging algorithms or removing validation.

All 28 initial selected cases then passed. A selector audit caught a misspelled cursor-test method, so the final run added the correctly named cursor matrix and an existing imported-shape HTTP path-edit case. All 30 cases pass, including eight new methods and 880 cursor rows. The final two source manifests and app binaries are identical. Tests cover known placements, all depths and output modes, linked radii, Cancel/Undo/Redo/archive, captured patterns, rotated combinations, native/API document material and exact PNG output, malformed/busy/stale requests and source/session/settings/lifecycle/cancellation guards. No old fixture, assertion or tolerance was weakened. The offscreen sheet image checks bounds; it does not qualify physical appearance or live gestures.

G04 Pen and Paths follows in major stillneeded, then T01. Other shape click dialogs, on-canvas widgets and the existing geometry/raster limits remain substantive G03 work. Earlier unrelated crashes, full-suite/numerical failures, exact Photoshop pixels/defaults and supported-platform/performance checks remain open. Latest optimized universal/private-source batch is 432; no new install, archive, App Store action or release occurred. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-435).

## 2026-11-05 — Step 436: Fill Path options

The Paths context menu and Option-click on the Fill footer now open a native Fill Path dialog. It supports foreground, background, custom colour, black, gray, white and saved patterns, blend modes, opacity, Preserve Transparency, feather and anti-aliasing. Clear changes alpha while retaining hidden RGB values and cannot clear a Background layer. History is unavailable because a history source has not been implemented. Ordinary footer fill retains its previous behaviour while conflicting Adobe default instructions await verification.

The implementation reuses the existing Core paint engine. Captured path coverage multiplies the current selection without replacing selection metadata. Expanded layer storage, mask positions, patterns and protected alpha follow the existing fill rules. The optional path.paint fill request, exposed state and schemas use the same builder and transaction. Recorded Actions version 50 carries captured coverage and resources; older feature formats remain readable. No Adobe endpoint or proprietary descriptor was invented.

Testing caught a parser declaration error before linking the app. The next attempt passed 41 of 44 methods: a new test incorrectly required identical sparse storage layouts, and two older tests still expected the current Actions version to be 49. The RGB test now compares exact stored RGB words at corresponding coordinates. Version assertions were updated for 50 while retaining old format and pixel expectations. All 44 cases then passed. An optimized batch passed 338 of 340 cases on each architecture, with only two more stale current-version assertions failing. An audit found 16 remaining assertions of that kind; all were corrected. The original source archive confirms that these 18 one-line changes are the only changes to pre-existing tests or assets. Every failed source, log and output was retained before repair.

The final development run passes 60 cases, including all 10 new methods. Both optimized architectures pass the same 354 cases in the same order, including all 89 new methods from checkpoints 426–436. Tests cover literal coverage products, Clear RGB preservation at every depth, expanded masks and geometry, native/API document and PNG equality, options state, Undo/archive, Actions compatibility, Cancel, malformed requests and stale source/settings/session guards. Optimized app binaries are identical before and after the test-only version repairs. Universal macOS 14 minimum, signature and extracted ZIP checks pass. Intel tests ran under Rosetta on Apple Silicon; this does not qualify physical Intel or macOS 14.

The fresh native-app check after all workers finished again reported the Mac locked. Live UI, exact Photoshop output/defaults and 60 fps remain unqualified. Extended Fill currently has a 16 MP canvas and 100 px feather working limit. History and remaining Pen/Stroke/target workflows stay major stillneeded. T01 typography follows, then T04. All 104 original scopes and 652 tracked command identities are retained. No install, Xcode archive, App Store action or release occurred. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-436).

The full-source backup is verified in the private repository. It includes 7,237 qualified inputs, the Xcode project and development records; 34 generated, cached or restricted inputs are excluded. All 1,061 root/Rust files are unchanged. No fixtures changed and no stale native files were removed. A final documentation-only commit follows the history and standalone diary refresh. [Source commit](https://github.com/ForensicIntelligence/Photato/commit/76527a7b791685b21fc9248ef6e50cfdb8c21a05) · [Backup record](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_436.json).

## 2026-11-06 — Step 437: Character and Paragraph panels, in development

Window > Character and Window > Paragraph now open separate tabs. Type > Panels has the matching commands. The panels use the existing dock, multiple columns, collapsed icons, floating stacks and saved-workspace system. Their controls reuse the text engine and Properties controls. Existing saved layouts are validated before migration to panel catalog 3; old placements, closed panels and floating frames are retained. New panels start hidden. Loading does not overwrite the old file.

The optional workspace.panels API can show or hide a panel and apply a complete validated layout. It has its own workspace revision and a native permission for changing the shared saved workspace, which resets off each API session. A failed write leaves memory, revision and disk unchanged. Panel changes add no image Undo or recorded Action. Existing text APIs and supported Adobe text jobs retain their contracts.

Testing found that replacing selected text with new attributes collapsed its selection. The native editor now restores the original range, including when paragraph formatting expands the edited paragraph. Character and Paragraph controls can also remain available during typing; document switching, other modal work and layout rearrangement retain their guards. A test using the actual native numeric field editor and Return confirms that changing size affects exactly the selected characters.

The first build linked the app but found two errors in the new test fixture. After those were repaired, 75 of 79 tests passed. Three older workspace tests assumed the previous default panel visibility; their setup and expected catalog were updated while retaining the full transfer and sizing checks. The new panel test also found a probe that looked for the wrong native accessibility property, the selection collapse, and a point-text alignment failure. Native field metadata corrected the probe. A manual callback without editing a native field did not prove numeric input, so the next test used the real field editor and retained the same expected values. Sources, logs and binaries from every attempt were kept before repair.

The latest run passes 79 of 80 tests, including nine of ten new methods, with five assertions failing in the original right-aligned point-text workflow. There are no unexpected errors or crashes. The diagnostic records a used width of 32,768 pixels and a padded width of 32,770 for ten characters. The existing dimension check rejects the result with a misleading 16 MP error. All 528 Core/Imaging source files are unchanged from checkpoint 436; this diagnostic is new evidence, not a rerun against an older binary. The desired right-alignment, commit and Undo assertions have not been removed, relaxed or replaced with an easier input.

T01 remains current. The next work is a coherent correction to point-text anchors, layout, rendering and the native editor, preserving existing left-point and paragraph behaviour and qualifying output independently. Full typography, detailed paragraph composition, dynamic panel menus and shortcuts, defaults, PSD fidelity and physical-platform checks remain open. T04 follows afterward. Four represented menu commands advance from pending to partial; none is complete. The repository remains private, and the latest stable source backup and universal qualification are still checkpoint 436. No new install, archive, upload or release occurred. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-437).

The offscreen panel capture does not establish visual appearance: the final image chiefly shows the title. Native control metadata and the numeric input test provide separate functional evidence, but complete rendering and live panel appearance remain unverified. No cause for the incomplete capture is claimed.

The final expanded run passes 93 of 94 tests. It retains all original 80 cases and adds the 14 older methods whose current command-count assertions needed to change from 250 to 251. All 14 pass. The same point-text workflow still fails with five assertions; the app binary is unchanged from Source03 through Source06. No image fixture, pixel expectation or tolerance was changed.

A final review found that placing Character and Layers in one floating stack disabled the type controls during typing. The guard now applies separately to non-type content, leaving type tabs usable. The new regression first used the old host identifier after stacking; it now resolves the actual shared-stack identifier and checks both rows and the enabled native Size control. The final run, Source08, passes 94 of 95 tests, including ten of eleven new methods. The same point-text workflow remains the only failing method, with five assertions. Source07 and Source08 app binaries are identical. T01 stays active; this is not a stable qualification.

## 2026-11-06 — Step 438: Point-text alignment and native editing

The previous panel work exposed a long-standing point-text layout problem. Right-aligning ten characters produced a 32,770-pixel-wide raster and hit the 32,768-pixel dimension limit. Before changing the engine, we captured fifteen owned regression images and their metrics from the unchanged application. They cover ordinary left-point, paragraph and vertical text at each depth. They are references for prior Photato output, not Photoshop output.

The repair gives each non-left point-text line a common insertion coordinate in TextKit's positive layout space. Raster allocation uses the resulting glyph bounds, excluding newline control tails. Rendering, outlines, the native editor's crop and its layer placement use the same geometry. No capacity constant was raised, and no document format changed. Existing native/API text edits, supported Adobe text jobs and portable Actions retain their shared engine.

The first build found a new tuple-versus-point compile error. The next run passed 129 of 132 tests, with native caret checks exposing a second alignment offset applied by NSTextView. Removing that duplicate fixed ordinary horizontal and vertical carets and typing at an empty insertion point. A repeated-layout test then caught stale line bounds for rich paragraphs with a centred or right-aligned final line. The shared paragraph adjustment now updates those bounds along with glyph positions. It runs after a fresh layout with a reentrancy guard. Tests retain selected ranges, test real native caret/hit coordinates and verify commit, Cancel and Undo. All failed sources, logs and binaries were preserved before repair; the original desired alignment test was not weakened.

The final affected Debug run passes 132 of 133 tests, including all ten new point-layout methods and all eleven panel methods. Its three remaining assertions are the same imported-text source mismatch seen in the unchanged baseline. The same 468 optimized methods run on both architectures: Apple Silicon passes 467, and Rosetta passes 466. There are no unexpected errors or crashes. All selected native caret, typing, formatting, API and history workflows pass both.

The exact image checks found an additional architecture difference. Five 8-bit ordinary-text outputs differ under Rosetta: 225 to 344 pixels per case, with alpha differences up to one byte and straight RGB differences too. All ten 16/32-bit planes match exactly. The mismatch is larger than a one-ULP conversion residual. Its cause and whether it predates this repair have not been established by an old Intel binary rerun. The fixtures and exact assertions remain unchanged. Cross-architecture output fidelity stays open, and neither affected suite is described as completely green.

A separate validation app contains both architectures with a macOS 14 deployment target. Its signature, extracted ZIP and file hashes verify. It has not been installed or launched for a live check, archived in Xcode, uploaded to App Store Connect or released. These checks do not establish physical Intel/macOS 14 or Photoshop equivalence. The new readonly textGeometry API state reports the active/draft type's metrics, separate model and TextKit origins, and layout errors without adding a command or changing request schemas.

The selected Character/Paragraph and point-editing workflow is usable, so the major still-needed queue advances to T04. Source inspection and Adobe's public guide identify direct Type-tool creation on a path as a missing entry workflow; the shaped engine and existing dialog controls are already present. That candidate still needs its native hover/click/cursor behavior, draft lifecycle, shared API and tests. T01's remaining functional work, old centred-document placement, large-type limits, defaults, PSD and exact output remain open. No full package closes, and the seven-pass order is unchanged. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-438) · [Point-text guide](../PhotoCraftSwift/docs/POINT_TEXT_LAYOUT.md).

The full development source checkpoint is now verified in the private repository: 7,262 frozen inputs are included, 34 generated/cache/restricted inputs are excluded, and all 1,061 root/Rust files are unchanged. The seventeen new fixture files contain owned generated text data and provenance. A final documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/211a318af342788a705334992f7adb28f05f90fc) · [Backup record](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_438.json).

## 2026-11-06 — Step 439: Type directly on a path

The Type tool could previously create ordinary point or box text, while path layouts were entered through a separate dialog for an existing layer. Even an existing curved layer used a straight text box for canvas editing. The native editor now creates a draft by clicking a selected connected path, and keeps typing, carets and selection on the curve. It copies the path and insertion fraction, preserving the saved path. Existing horizontal Path, Circle, Arch and Bow layers use the same editor.

Before editing the engine, we captured thirty-six owned render references from unchanged production code. They cover the four baseline layouts, fitting, reverse direction, offsets and each pixel depth. Shared preparation now supplies the same flattened baseline, CoreText line, fitting and alignment to rendering and editing geometry. Grapheme-safe UTF-16 positions keep combining marks and surrogate pairs together. The existing renderer's output stays pinned by exact word and metric comparisons; the fixtures contain generated test data, with no redistributed font or Adobe artwork.

The canvas editor retains NSTextView's rich text storage, marked input, local typing Undo and existing keyboard policy. It supplies curve caret/range drawing, hit testing and IME window coordinates, with layer and viewport transforms. Preview runs in a cancelled/generation-guarded worker. Detaching and reattaching restarts an interrupted preview, and cancelled work cannot commit a document. Straight-text insertion drawing is suppressed. The offscreen native canvas capture shows the complete curved text, selection and underline; it is not a live Photoshop or physical-device check.

A wavy insertion cursor indicates path entry. The press captures the source, document and tool; document/tool changes and a drag beyond the click threshold cancel it. All sixteen modifier combinations currently share the same path-entry dispatch and cursor. Unsupported vertical path typing shows an unavailable cursor. Exact Photoshop alternate behavior remains unobserved. The existing text.create/set/layout API uses the same model and renderer; readonly pathTypeEditing state adds selection, caret count, overset and preview/error information. No command, Adobe route, menu shortcut or serialized version was added.

The first build found a Swift concurrency error in mutable preview captures. Immutable snapshots repaired it. The next runs passed the new workflows and exact ordinary render comparisons. Source review then corrected preview reattachment and straight-caret behavior. An explicit tool-switch assertion found that an earlier insertion had matched the constructor instead of the actual tool-synchronization hook. The failed assertion was retained, and the production hook was repaired. Every attempt's inputs, logs and binaries were kept before repair; no exact fixture, old assertion or tolerance was relaxed.

The final Debug run passes 158 of 159 methods, including all ten new methods and the existing point/panel workflows. Its three remaining assertions match the older imported-text reference failure. The same 485 optimized methods pass 484 on Apple Silicon and 482 under Rosetta, with no unexpected errors or crashes. All six new native workflow methods pass both. Apple Silicon matches all thirty-six old path planes; Rosetta matches thirty-three. Thirteen alpha words in three Float32 planes differ by one ULP. Their RGB words and a separate 8-bit diagnostic match, but the original Float32 assertions still fail. The prior 8-bit point-text mismatch also remains. No old Intel baseline rerun or cause has been established. Neither suite is called completely green.

The isolated universal validation package verifies its macOS 14 target, both architectures, signature and extracted ZIP. It has not been installed, launched for a live test, archived in Xcode, uploaded to the store or released. The selected native path workflow is tested; full T04 is still open. Vertical/inside/warped inline editing, delimiters and flip/drag gestures, fully composited mask/opacity/effect appearance during typing, full fitting/composers/affinity, PSD and maximum capacity remain functional work. Exact defaults/output, platforms and performance remain unqualified. The next major item is Auto Color Correction Options for Curves; the current Curves UI lacks Auto/Options, while Levels provides some supporting foundation. [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-439) · [Path typing guide](../PhotoCraftSwift/docs/DIRECT_PATH_TYPE.md).

The full source checkpoint is verified in the private repository: 7,307 frozen inputs included, 34 generated/cache/restricted inputs excluded, and all 1,061 root/Rust files unchanged. Thirty-eight new fixture/provenance files contain owned generated text data. A final documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/1e138cfb64a0851c90396e198049836dfa6bec66) · [Backup record](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_439.json).


## 2026-11-06 — Step 440: Histograms for large sparse documents

The Curves and Levels histograms still visited every pixel. A document could use sparse storage successfully and then spend an impractical amount of time on statistics. The new traversal examines stored image and coverage tiles and counts the remaining cells in bulk. UInt64 bins retain exact counts at the 90-gigapixel logical limit. Tile padding is excluded, and the existing depth, alpha and selection rules are preserved.

Ordinary layers translated by whole cells are clipped to the canvas and selection. Their image and mask are cropped into the same sample grid using existing paged storage. Fractional and rotated affine layers retain the previous sampling path. Adjustment layers use the same paged histogram reader after their existing input composition. This change does not establish maximum-size capacity for every compositor or editing operation.

The optional tone.histogram API shares the native Curves/Levels request. It exposes three 256-bin channels and the sample, transparency, invalid and endpoint counters, with strict parameter/result schemas. It rejects invalid, stale, busy or unavailable sources. Successful queries do not change pixels, document revision or Undo history. No Adobe endpoint or document-format version was added.

Two new-fixture compile failures were preserved and repaired. A first runnable test attempt caught two stale catalogue counts and an incorrect expectation for the existing revoked-share response. The first optimized selector also named seven helper classes instead of their test classes. All 54actuallyselected methods passed, but that run failed qualification for missing intended tests. The corrected selector ran all 61methods on the same source and binaries; both architectures passed. All old fixture bytes and numerical assertions are unchanged. Fifteen existing test files only update their current API catalogue count from 251 to 252.

The final focused run passes 27 Debug tests, including eight new methods. The same 61optimized methods pass on Apple Silicon and under Rosetta; universal macOS 14 packaging, strict signature and ZIP extraction also verify. These are selected tests. Existing full-suite failures, cross-architecture text-output differences, Photoshop fidelity, physical-platform qualification and 60 fps remain open.

The original A01 Auto Options candidate needs further work, including independent Photoshop references and native point-sampling transactions. It is not marked complete. This checkpoint delivers its statistics dependency, records the remaining scope and moves the major still-needed sweep to A04, then A05. The seven-pass order and every original acceptance criterion remain in force.

The private source backup includes 7,310 frozen inputs, excludes 34 generated/cache/restricted inputs and preserves all 1,061 root/Rust files. No new image fixtures were added. A final documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/097bf4ddf55224176fe85066d51d95600a1bd65a) · [Backup record](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_440.json).


## 2026-11-06 — Step 441: Pause Light while painting below

Light's Highlights and Shadows require neighborhood processing. Previously, that processing stayed in the live painting path. The editor now pauses the affected Light layers during native paint and retouch gestures and restores them at release or Cancel. Exposure, Contrast, Whites and Blacks remain live when no neighborhood controls are used. A passive notice in the document tabs and Properties explains the temporary appearance; the API exposes the same state.

The pause belongs to display snapshots. Stroke sampling and prepared edits keep the original document and full Light parameters. The structural plan follows visible layer order, isolated/pass-through groups and clipping boundaries. No command, shortcut, cursor, preference or document-format version was added.

The first projection hid the Light layer. A new regression showed why that was wrong: it also hid layers clipped to Light. The repair substitutes identity Light settings and Normal blending while preserving visibility and clipping topology. An independent red-clip assertion retains the base's exact alpha. Final brush and retouch results still match the full original commands, with their usual Undo and Cancel behavior.

A fixture compilation failure and two incorrect fixture assumptions were preserved before repair: API revisions already include view renders, and a no-op mask stroke creates no Undo entry. The final run passes 43 Debug tests and the same 43 optimized methods on each architecture, including all nine new methods. Existing tests, fixtures, Core adjustment math and the Adobe API contract are unchanged. Universal macOS 14 packaging, signature and ZIP extraction also verify.

This closes a selected A04 painting workflow, not the whole package. Modern PSD/PSB descriptors, actual Light version switching, larger neighborhood processing, other editing contexts and independent Photoshop/platform/performance qualification remain open. The major still-needed sweep moves to A05, then A07; no minor or cleanup pass has begun.

The private source backup includes 7,314 frozen inputs, excludes 34 generated/cache/restricted inputs and preserves all 1,061 root/Rust files. No new image fixtures were added; existing tests and Core math are unchanged. A final documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/350101b8245a25386a9add2f5a25b2721196eb16) · [Backup record](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_441.json).


## 2026-11-06 — Step 442: Gradient creation and recorded Actions

The Gradient tool previously applied several Options settings to the selected fill. Adobe’s current guide says these controls configure new gradients. Options and toolbar preset selection now keep creation defaults separate; canvas and Properties controls continue to edit existing fills. Delayed presets, drags and colour-stop changes reject a replaced document or tool context.

Three optional API commands configure the defaults, create a live Gradient Fill, or paint a captured Classic Gradient. They use the same native factories and prepared history. Tool configuration changes only session defaults and the view revision. Creation and painting use their usual Undo transactions. Tests compare native and HTTP documents and saved bytes across RGB8/16/32, five gradient shapes and pixel/mask targets.

A new recording test found that creation and painting still produced unsupported Action entries. Portable recipes now preserve their settings and layer references without saving document UUIDs or raster snapshots. Actions format 51 gates the new operations; older operations keep their minimum versions. Custom creation templates containing unsupported metadata still reject instead of silently losing it.

The selected Debug run passes 69 tests, including eleven new methods and older Actions workflows. Both architectures run the same 99 optimized methods: 99 pass on Apple Silicon and 98 under Rosetta. The first optimized run also caught an old catalogue assertion fixed at 251; it now checks the current 255 commands. The remaining Intel Rust interpolation assertion reports 15,580 of 15,633 exact samples and reproduces exactly in the preserved checkpoint 441 bundle. It remains selected, with its original expectation and fixture. No numerical cause or Photoshop equivalence is claimed.

The rendering math and old image fixtures are unchanged. Older tests changed only for current API/Actions counts or to request existing-fill edits explicitly while keeping their numeric assertions. Universal macOS 14 packaging, signature and ZIP extraction verify. The Mac remains locked for live reference checks; no live pass, install, archive or store release is claimed.

This completes the selected creation, painting, API and recording paths. The full gradient package remains open, including canvas opacity, preset/noise/GRD cases, remaining transforms, numerical/default fidelity, platform and performance checks. Work moves to A07 under the seven-pass order; no minor or cleanup pass has begun.

The private source checkpoint includes 7,319 frozen inputs, excludes 34 generated/cache/restricted inputs and preserves all 1,061 root/Rust files. No new image fixtures were added. A documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/4f7c736d74f1bf276e1fc5674dee2b2ec4f53c7e) · [Receipt](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_442.json).


## 2026-11-06 — Step 443: Pattern groups and PAT folders

The Patterns panel previously stored a flat list. Its PAT reader recognized folder metadata but discarded the grouping. The native library now keeps a flat node graph with parent links, and the panel shows groups with preset grids. Shift selects ranges, Command toggles selection, and private native dragging moves groups or presets with insertion feedback. Duplication creates independent resources; renamed or deleted presets do not alter resources already captured in documents.

PAT import and export retain nested and empty groups and repeated preset occurrences. Existing pixel records and compression are unchanged. Native user-library format 2 stores the hierarchy; format 1 loads without rewriting the original file. Selection and disclosure changes stay in memory until the next persisted mutation. Candidate data is prepared in a worker, authorized before atomic replacement and then published to matching memory.

The optional pattern.library API shares native selection, organization, import/export and Define Pattern. It publishes operation-specific schemas and shared library revisions. Initial document revisions still reject stale requests. Accepted work checks document/session/library/lifecycle, token and sharing at completion, allowing harmless display redraws while rejecting real document changes or revoked sharing.

Early constructor and actor-type compilation errors, followed by two test-fixture errors, were retained before repair. An offscreen panel test initially over-released its AppKit window. An own-binary NSZombie diagnostic identified release after deallocation; the fixture now keeps Swift ownership through normal teardown and retains its original view check. Product code was unchanged for that test repair.

Optimized tests then exposed valid HTTP library edits returning 409. A paused real import proved that a view redraw alone could invalidate accepted work. Removing that extra view comparison fixed the controlled Debug case, but did not finish optimized qualification. An explicit short-lived request lease now holds accepted inputs and checks each relevant server-side predicate separately. The final optimized runs pass on both architectures. No compiler or ARC root cause is asserted, and all failed attempts remain recorded.

The final result is 54 Debug tests and 71 identical ordered optimized methods per architecture passing, including all seventeen new methods. Existing image kernels, PAT pixel writer, version 1 encoder, image fixtures and numeric expectations remain unchanged. Older tests changed only for catalogue counts, optional library injection and the intended retained-folder behavior. The actual SwiftUI panel was rendered offscreen; live Photoshop and physical-platform checks remain pending.

This completes the selected pattern-library organization and transport workflows. History Fill still needs a shared source/snapshot mechanism. Scripted Fill, remaining application/drop semantics, arbitrary PAT metadata, capacity and exact Photoshop defaults/output remain open. Work continues with F01 under the seven-pass order; no minor or cleanup pass has begun.

The private source checkpoint includes 7,319 frozen inputs, excludes 34 generated/cache/restricted inputs and preserves all 1,061 root/Rust files. No new image fixtures were added. A documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/0f4c25b920f135ebb2fc637965e5b0a08fea73b8) · [Receipt](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_443.json).

## 2026-11-06 — Step 444: Public repository and filter development

The maintainer asked to make GitHub public now. We changed the existing [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato) repository from private to public and checked GitHub’s returned visibility and access without signing in. This exposes the existing repository and its history. No app binary, App Store release or live website deployment accompanied the change. Current source-availability wording is updated; earlier private-backup entries remain as dated history. [Visibility evidence](../PhotoCraftSwift/docs/REPOSITORY_VISIBILITY_444.json).

Before that request, work began on F01’s missing custom Shape Blur kernels. Native preset snapshots, the chooser, shared vector geometry, archive87/Actions52 and optional API schemas are implemented locally. The first attempt failed to compile a new HTTP fixture; the second passed40of43methods with seven new-test assertions failing. After correcting stored-alpha, linearRGB and generated-ID expectations in the new fixtures, Source03 passes42of43methods. The independent convolution oracle still fails at all three depths. No expected byte output or tolerance was relaxed. This feature remains in development; the public source checkpoint remains443 until a qualified source delivery. [Development evidence](../PhotoCraftSwift/docs/CUSTOM_SHAPE_BLUR_444.json).

A correction to step443’s narrative: its publication includes7,327frozen inputs, not7,319. The original curation receipt and source manifest already record7,327; the narrative number was a transcription error. Historical receipt data is unchanged.

F01 remains current, followed byF02. All major, minor and final scope is retained.

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-03.md) · [Next page](part-01.md)
