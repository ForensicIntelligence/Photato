[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-04.md) · [Next page](part-02.md)

## 2026-11-01 — Step326: original layer effects become editable native workflows

The324 draft reaches a tested functional checkpoint:all ten source effect kinds retain advanced records and editable controls,with native preview/Cancel/history,source import,shared global light,API access and native75/Actions30 saving. Pattern hints never open files or substitute artwork; retained original PSD data remains inert. The captured Global Light menu path now opens a dedicated dialog that changes document light without adding or replacing a layer style. Existing factory menus/default shortcuts and the shared tool-cursor policy remain intact.

Independent original Rust APIs generate138 direct effect vectors and138 source projects/full working-output references using owned artwork. The first two harness attempts fail compilation and are preserved before repairs. A standalone Swift module-emission probe crashes inside the compiler; the normal optimized build succeeds. Source01 passes23/24 cases; Source02 integrates the usable workflows and passes62/66. Source03 repairs an incorrectly read test schema and adds whole-project comparisons on identical production/binary. Those comparisons reveal gradients using tile allocation instead of original content bounds. Source04 fixes the actual frame, reducing project differences7,086→575 without changing an expected pixel. Source05 adds the native Global Light menu/dialog and its regression. Source06 removes an inactive generic row from the advanced-bevel UI and explains appearance changes. Source07 corrects stale source-import capability text and verifies typed effect/adjustment/archive discovery.

The final frozen source has6,685 inputs/902 production Swift files. Build307.77s;67 focused cases finish11.004s:64 pass,three strict cases fail136 assertions,zero unexpected errors/crashes. All16 new functional cases pass;the17th remains strict. Direct output matches83/138 vectors (393,576 words compared;622 differ). Imported-project working output matches75/138 (393,576 words;575 differ);each scope matches45/46 RGB32 vectors. These sets overlap. Two older fill/gradient strict cases remain too. Every failure,repair,source/binary identity and oracle stays recorded.

Noise/jitter/anti-alias and several other source-retained switches remain inactive. Expanded controls can change legacy appearance. Vector/text/off-canvas/transform/ICC/PSD/Adobe descriptor contexts,exact Photoshop output,full-current tests,native/platform/Intel/capacity/physical60fps remain open. Fresh native Photoshop access returns cgWindowNotFound,so there is no live visual acceptance. No app is installed or source pushed;normal283 and entirely passing/private298 remain preserved. The diary,website mirrors,dashboard and evidence records are synchronized,while I03 and the full goal remain open. Next comes original channels/guides/metadata breadth. [Checkpoint](../PhotoCraftSwift/docs/WORKING_CHECKPOINT_326.json) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-326) · [Source-effect guide](../PhotoCraftSwift/docs/SOURCE_LAYER_EFFECTS.md).


## 2026-11-01 — Step327: diary reconciled with tested source and remaining major work

At the maintainer's request, reconcile the diary against engineering326 and the actual324 Source07 test receipts. The previous edition already included326, but its dense overview did not make recent major workflows and build delivery easy to distinguish. Replace the current overview with readable tables for source filters, Relight, Lighting Effects, Displace, adjustment layers and layer effects. Keep each workflow's tested scope and open comparisons alongside its progress. Add the327 index entry and this account; preserve every prior narrative and the engineering-process note.

The latest application evidence is unchanged: 6,685 frozen inputs, 902 production Swift files, native75/Actions30 and206 typed commands. The latest affected run passes64/67 cases, including all16 new functional cases, with three strict failed cases/136 assertions and no unexpected errors or crashes. The latest complete inventory remains321, the last entirely passing full inventory/private complete source remains298, and the installed preview remains283. No passing current full suite, complete source/Photoshop parity or new delivered build is inferred from the documentation update.

Record the intervening channels/prepress investigation as investigation only. Existing native alpha and Multichannel ink workflows do not yet provide original-project auxiliary/spot-channel migration; the source importer still requires empty channels/guides, no Quick Mask and default metadata. This is next major work, with remaining modes/ranges/linked contexts also open. No channel model, renderer, UI, API or persistence code changes in this refresh.

Regenerate both standalone HTML diaries and their Markdown/provenance companions from the same sources. Verify chronological continuity, preserved earlier entries, current source hashes, embedded resources/downloads/JavaScript, mirror equality and dashboard journal freshness. Check the unchanged application inputs and binary, protected release/reference identities and original Rust; refresh and check the history inventory separately. No application tests are rerun for this documentation-only change. Package/command acceptance, APIs, installed283, private source298, artwork and release policy remain unchanged. [Refresh evidence](../PhotoCraftSwift/docs/DIARY_REFRESH_327.json) · [Engineering record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-327).


## 2026-11-01 — Step328: original channels and auxiliary spot workflows become editable

Extend existing alpha/Quick Mask and separate Multichannel ink support with ordinary-document auxiliary SpotInk color/Solidity. Black adds ink, white removes it, and changes to Solidity leave every separation sample untouched. Native creation/options/name/color/conversion, selection initialization, Cancel/stale protection, gray/overlay viewing, painting, history, native76 and API createSpot/configure/state/schema/download negotiation share the native engine. Original RGB8/16/32 projects import alpha/spot/Quick Mask with exact numeric coverage and retained names/options. Unknown fields, invalid spot Quick Mask, excess count, depth mismatch and nondefault off-canvas samples reject atomically.

The owned Rust fixture harness first fails coordinate typing, then succeeds after explicit u32-to-i32 conversions without changing original sources. Three projects, twelve planes and three ordered two-ink previews have per-file provenance. The native Source01 build reaches App then fails a shared non-Sendable static schema and unsupported AutomationValue equality. Source02 fixes those API compilation issues, builds328.39 seconds and passes101/102 cases in12.466 seconds. All12 new cases pass;12 planes match2,244 Float words and three overprints match2,244 RGBA words. An older archive test still expects supported75 to reject. Source03 corrects that contract to reject77 and positively round-trip73–76, builds39.41 seconds and passes all102 cases in11.229 seconds, zero failures/unexpected errors/crashes. Its904-file production and app binary are identical to Source02; no expected oracle or tolerance changes.

This qualifies a functional subset. PSD/PSB separations, simultaneous auxiliary visibility, Merge Spot, color libraries, printing/export policy, semantic channel Actions and exact Photoshop/native visual behavior remain open. Fresh Photoshop lookup returns cgWindowNotFound; no live screenshot/acceptance occurs. The current102-case selection does not execute at least eleven retained older strict failures or establish a current full-green inventory. Installed283 and the last entirely passing full/private298 source stay unchanged, with no installation or push.

Update the source-channel guide/reference, API/version metadata, native archive recognition, command evidence and phase328 progress, human overview/index, both standalone diary editions and menu/cursor references. C02 moves open to in_progress, I03 remains in_progress, and no package is closed. Existing factory menu/shortcut inventory and all16-combination cursor policy remain; nine menu and nine cursor regressions pass. Continue remaining prepress and guides/metadata major breadth. [Checkpoint](../PhotoCraftSwift/docs/WORKING_CHECKPOINT_328.json) · [Guide](../PhotoCraftSwift/docs/SOURCE_CHANNELS.md) · [Evidence](../PhotoCraftSwift/docs/SOURCE_CHANNEL_REFERENCES.json) · [Engineering record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-328).


## 2026-11-01 — Step329: PSD/PSB channels share the native file workflow

Ordinary RGB/Gray/CMYK/Lab PSD/PSB files now retain alpha, spot and Quick Mask planes with supported display records, names, IDs and Quick Mask index/flags. All four codecs use shared bounded row/scratch infrastructure. Imported Float32 spots retain original editing-gray words until a sample changes; depth changes clear only incompatible retained gray. Native77 preserves this metadata through history and desktop/API transfers. The56-plane boundary requires proven opacity before dropping a redundant transparency plane; transparent overflow rejects. Desktop Save permits the existing streamed backend for large canvases, with300,000-square policy admission covered separately from unqualified physical maximum-size editing/export. TIFF auxiliary mapping and private color-book records reject explicitly.

Independent generation uses pinned psd-tools1.26.0 and public format structures:80 owned cases plus one licensed corpus input,118 attributed fixture files and1,226,640 auxiliary sample words. A separate reader verifies all81 captured native outputs against those expected raw planes and metadata. Input/output scopes overlap and are not Photoshop-generated rendering references. The original Rust writer's modern display-record stride differs from the independently documented layout; it is not treated as an oracle. The second corpus input's private color-book/large native-mode context remains unqualified. CUA lists Photoshop running but reports a locked Mac after normal activation; manual unlock is requested without bypassing it.

Source01 reaches test compilation and fails a missing try. Source02 builds and passes118/119 cases; Source03 corrects an old native-version expectation and passes119/119. Inspection then discovers a retained Float32 gray lifecycle bug during bit-depth conversion; repair the actual Core/ordinary/ink conversion paths and add a fifth Core case. Source04 passes171/173, Source05 passes176/177; remaining failures are older supported-version expectations. Source06 updates the final indexed archive contract and passes177/177 including all14 new Core/Imaging/App cases, zero failed assertions/unexpected errors/crashes. Source04–06 production/binary and all expected sample oracles are identical. All six frozen attempts, failed patch/reference inspections, independent results and source hashes are retained.

Update engineering/human diaries, API/version/state, status/plan, command evidence, phase329, menu/cursor evidence and both standalone HTML/Markdown/provenance editions. Existing factory inventory and modifier policy remain unchanged; nine menu/nine cursor regressions pass. C03 moves open to in_progress; C02/I03 remain in progress and all 104 scopes/acceptance criteria remain. No whole package closes, no full-current or Photoshop/platform/60fps/capacity acceptance is inferred, and no install/push occurs. Continue major functional breadth with earlier strict numerical differences retained. [Checkpoint](../PhotoCraftSwift/docs/WORKING_CHECKPOINT_329.json) · [Guide](../PhotoCraftSwift/docs/PSD_AUXILIARY_CHANNELS.md) · [Evidence](../PhotoCraftSwift/docs/PSD_AUXILIARY_CHANNEL_REFERENCES.json) · [Engineering record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-329).


Diary presentation updated at step329: replace the introductory slogans and promotional copy with plain headings and descriptions. Historical entries, test results, attribution, process disclosures and release policy are retained. This changes documentation only; neither application API is affected.


## 2026-11-01 — Step330: document guides and source layout import

Original projects with guides can now open as editable documents. Guide positions retain the original Float32 words. The native app provides New Guide, Edit Selected Guides, New Guide Layout, preview/Cancel, ruler dragging, selection, lock/show/clear and guides from layer bounds. Rows, columns, margins and gutters produce a guide layout; Move snapping uses the current integer layer-position precision. Option changes guide orientation during dragging; Shift snaps to pixel ruler ticks, and Shift+Option-click selects multiple guides. Cursor feedback follows the dispatched action, including add/subtract selection and focus cleanup. Command temporarily suppresses layer snapping on macOS.

Guides save through native78/history and PSD/PSB resource1032, including supported ordinary, restricted and Multichannel paths. Unchanged file records retain bytes/order and grid header words; edited coordinates quantize to1/32 pixel. Older native opaque guides become editable at shared desktop/API admission before a new guide can overwrite them. Empty guide/grid headers keep their earlier native compatibility. Guide colors persist natively; PSD/PSB explicitly rejects custom colors until modern color records are implemented. Both API commands, schemas, state, availability and invalid/busy/stale behavior use the native engine. Semantic guide Actions and Adobe guide descriptors remain unsupported.

The owned reference harness uses unchanged original Rust crates. Its first attempt stops on the crates’ compiler-version declaration; the second uses the same explicit development override as earlier reference work and succeeds. Three projects provide30 source guide words and source-formula1032 records; two separately assembled public-format inputs check framing. Source01–03 expose and repair Core/App integration and test-isolation compilation errors. Source04 runs292 cases:287 pass, all17 new cases pass, five older cases fail. The failures identify three old command-count expectations and an empty-guide-header admission bug; the latter is repaired in production. Source06 passes296 cases after the shared count repair. Source07 adds an explicit PSD/PSB rejection for custom guide colors so they cannot be silently discarded. All attempts are retained separately. Source07 passes all297 affected cases in34.021 seconds, including all18 new cases, with no failed assertions, unexpected errors or crashes. The independent reader verifies8 exported files/80 guide records exactly. Native/source sample references and tolerances are unchanged.

Update the command matrix with the two previously untracked selected-guide factory commands, enable partial progress for ten existing guide/snap rows and record208 typed API commands. U05 is in progress as a dependency of major I03; no package closes. Existing factory menu order/shortcuts and other tool policies remain; nine menu/nine cursor regressions pass. Modern color records, broader ruler/grid/guide/snap/Actions/preferences and full-current/Photoshop/native/platform/capacity/60fps acceptance stay open. The Mac is locked, so no live Photoshop visual result is claimed. Installed283 and private complete298 remain unchanged, with no installation or push. [Checkpoint](../PhotoCraftSwift/docs/WORKING_CHECKPOINT_330.json) · [Guide](../PhotoCraftSwift/docs/DOCUMENT_GUIDES.md) · [References](../PhotoCraftSwift/docs/DOCUMENT_GUIDE_REFERENCES.json) · [Engineering record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-330).


A source review also records a remaining pointer issue when Space is held during an active guide drag: the guide remains captured, while the cursor can fall through to Hand/the selected tool. This is outside the tested four-modifier matrix. It remains in the guide/gesture backlog; no live Photoshop comparison is claimed.


## 2026-11-01 — Step331: Xcode archive and alpha store preparation

The maintainer requested an archive and validation under ca.forensicintelligence.photato, followed by a free App Store page with images and video. The copy must identify the alpha limitations and AI-aided development. All releases require manual approval. The diary has passed checkpoint 300; the wider project-migration work started there remains unfinished.

The project now has an AppStore configuration derived from Release. Its shared archive action enables sandboxing, selected-file read/write, persistent bookmarks, printing and the network access needed by optional features. The app identifier is updated, while native document and clipboard identifiers are retained. A privacy manifest records local file metadata and app timing uses. Debug and Release keep the local ad-hoc signing workflow. No editing implementation or API contract changes.

Xcode archives Photato 0.3.0 (331) for Apple Silicon and Intel. The archive carries the FI team’s Apple Development signature; App Store distribution export uses the distribution identity. Twenty local checks pass, including code signing, architectures, minimum OS, entitlements, notices, icon and symbols. An initial diagnostic incorrectly required a profile in the development archive; that failed check is preserved and corrected. The first Xcode validation attempt exposes an export-option error. After repair, validation reaches the account gate: App Store Connect access for the FI team is required. Neither attempt establishes Apple validation.

The local store draft includes a name, subtitle, promotion, description, keywords, categories, verified live URLs, review notes and the original supplied icon. It describes working feature categories without claiming professional parity. A four-image and 25-second preview plan calls for real application captures with owned artwork. App Store Connect still needs sign-in; the locked Mac blocks capture. No app record, media upload, free-price setting or manual-release setting has been saved remotely. Apple’s beta-testing policy directs this alpha toward TestFlight qualification. No review submission, tester distribution or release occurred.

A full Release attempt records 2,119 completed cases (9 failed) before an AppKit recovery-autosave wait blocks the main thread. Sampling first confirms active large-file decoding; that Smart Filter/API case passes. A later sample shows the user-interaction wait with no progress. Only the verified disposable test process is terminated. The underlying cause, and whether the locked host contributes, are unresolved. Preserve this as an incomplete inventory, with strict comparisons intact. The previous focused guide qualification remains 297 passing cases; the last entirely passing full source checkpoint remains 298.

Thirteen preservation/static checks pass, including the original Rust source, supplied artwork and previous build/source identities. REL01 is now in progress; no major package is closed. Both offline diary editions are regenerated. Account access, genuine media capture, autosave investigation, current full qualification, supported-platform checks and release readiness remain outstanding. [Preparation record](../PhotoCraftSwift/docs/APP_STORE_PREPARATION.md) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-331).


## 2026-11-01 — Step332: Window lifecycle, recovery and updated archive

Investigation of the interrupted331 run found background workers blocked in window animation. The initial spinner hypothesis did not hold: stopping or replacing the progress control did not prevent exhaustion. A controlled 200-window probe reproduced the problem without any progress control. Disabling transitions on app-owned windows kept background work available. The repair uses public AppKit window and panel subclasses; system alerts and file panels keep their normal behavior. A regression test repeats the lifecycle and verifies exact document recovery afterward. This measures the failure mechanism, not screen refresh rate.

The first focused run exposed layered TIFF recovery failing because its metadata carrier was treated as though it also contained a PSD merged-transparency plane. The decoder now respects the external TIFF composite. Twelve depth, byte-order and opacity combinations round-trip exact layer samples. Broader tests then exposed custom document-controller initialization happening after AppKit had created a base singleton. Startup and the viewport fixture now install the custom controller first. Panorama cancellation tests use a gated worker so cancellation is measured while work is active. Stale archive, auxiliary-channel and large-canvas format assertions were corrected without relaxing numerical comparisons.

All370 affected tests and13 fresh viewport cases pass. The complete inventory runs 3,242 unique cases with 12 failed cases retained. Earlier incomplete reports survive: compiler warnings had interrupted test names in combined output, and a diagnostic parser missed the singular “1 failure” summary. Separate stdout/stderr capture and exact case-set checks repair the reporting. One obsolete archive75 rejection is then repaired and checked separately; other numerical failures remain open. No full-green or monolithic long-session result is claimed.

Xcode creates Photato0.3.0(332), a universal sandboxed archive for ca.forensicintelligence.photato, with all 20 local package checks passing. Apple validation still needs FI account access. App Store Connect sign-in and the locked Mac prevent saving the requested listing settings or capturing genuine screenshots/video. The free/manual-release/alpha drafts and supplied icon remain prepared locally. No upload, submission, distribution or release occurred. Installed283, private complete source298, original Rust sources and artwork remain preserved. Both offline diary editions are refreshed. Full parity, supported-platform runtime, physical60fps, maximum capacity and distribution readiness remain open. [Details](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-332).


## 2026-11-01 — Step333: Validation after Xcode sign-in

The maintainer signed in to local Xcode. We checked the existing332 archive’s binary identity and retried Apple validation. It still stops at the FI team’s App Store Connect access requirement, without changing the archive. Native automation reports the Mac locked; the browser remains at Apple Account sign-in. The remaining request is to keep this Mac unlocked, confirm FI Forensic Intelligence team membership in Xcode Accounts and sign in to App Store Connect. The precise account or permission problem is not established.

The retry and limited diagnostic classifications are saved separately from earlier failures. No credentials are copied into the project or diary. No source, API, application tests, archive, media or remote listing settings changed. Free alpha/AI-aided-development copy and manual-release requirements remain prepared locally. Nothing was uploaded, submitted or released. Both offline diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-333).


## 2026-11-01 — Step334: Native File Info and source metadata

With App Store access pending, work returned to major editing functions. File Info had a factory menu entry and shortcut but no native action. Original PhotoCraft projects with nondefault document metadata also rejected. The licensed source implements eight descriptive XMP fields; the native editor now supports those fields through Description and Raw Data pages, the existing factory shortcut, document history and a shared file.info API. It leaves pixel/channel targets and protected layers alone. Cancel, unchanged values and stale/busy requests preserve the committed document.

Apple ImageIO handles XMP, keeping unedited properties and localized alternatives. Descriptive IPTC/TIFF values are carried where supported. Source XMP, raw EXIF, named image resources and global-block payloads are retained with the manifest. Opaque globals remain source provenance; they do not become trusted rendering programs. Full metadata interpretation and export fidelity remain unfinished. No native archive or Actions version change is needed; the API now has209 typed commands.

The owned Rust harness first failed a declared toolchain minimum, then an Arc-copy mistake. Both attempts survive; the corrected harness generates three source-depth projects and24 expected values without editing the original crates. The first two Swift builds expose test-fixture type/selection errors. A third run passes158/160 cases and exposes two issues: comparing fresh random fixture identities, and byte differences between native/API metadata. A Foundation probe reproduces nondeterministic binary property-list ordering. The new writer uses XML properties; strict document equality remains enforced, with a new30-edit native-file byte comparison.

Source04 passes all161 affected cases and14 new cases, with no failed assertions, unexpected errors or crashes. An independent Python parser verifies six PSD/PSB outputs,48 field values and exact named-resource bytes. The source/binary hashes bind the result. Full Photoshop File Info panels/templates, exact serializers, further IPTC/EXIF/global interpretation and export, semantic Actions, live UI/platform and full-current qualification remain open. No major package closes. Store archive332, installed283 and private complete source298 remain unchanged; no new archive, installation, publication or release occurs. Both offline diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-334).

### Photoshop 2026 as the reference — step335

The maintainer clarified that PhotoCraft Rust is a source of inspiration and Photoshop 2026 is the gold standard. The project instructions and current plan now say this explicitly. Work is chosen from missing Photoshop workflows, in the existing major, minor and final-detail order. Finishing the Rust migration is not a prerequisite for adding a Photoshop feature. Rust comparison results remain useful regression evidence, but they do not prove Photoshop compatibility. Existing source attribution and earlier test records are retained.

This checkpoint changes documentation only. The tested334 source and binary, store archive332 and command/package inventories are preserved. No new function or parity closure is claimed. Both offline diary editions are regenerated; application tests are not rerun for this guidance change. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-335).

### Layer Comps and production export — step336

Production export needed saved layer variations, while the native Layer Comps menu entries had no implementation. The new Swift model records visibility, position and appearance without copying pixels. A floating panel handles named comps, comments, property choices, apply/update, duplicate/delete/reorder, previous/next and the state before application. Missing layers remain warnings. Native79 retains the records, and three API commands share native history, state and validation.

Comps export to PSD, PSB, PNG, JPEG, TIFF and Photato files or a multipage PDF. Each variation begins from the same source. File exports stage a complete new folder and preserve an existing destination; the API returns ZIP or PDF without filesystem access. Cancelling or revoking access returns no archive. Editable Photoshop comp metadata remains unsupported; ordinary PSD/PSB saves reject it rather than silently discard it.

The first build stops at an overlapping-access error in a new test. The second compiles the application but rejects an incorrect test-helper call. The third runs260 cases with257 passes: old tests still reserve native79 as invalid, and a new API test expects400 where semantic errors correctly return422. Those test expectations are repaired without changing production code or weakening pixel checks. Source04 passes all260 affected cases and17 new cases. Independent CoreGraphics page rendering checks red/blue PDF samples, order and dimensions.

An initial ledger draft duplicated the existing L08 package after an audit looked only at phase1. The draft is preserved and corrected:104 scopes remain; saved comps are a dependency of I05 production export, while optional local libraries stay in phase2. The existing PDF export menu was missing from the CSV and is now recorded. A final inventory check also finds two identical Keyboard Shortcuts rows; the redundant row is removed with the draft preserved. The ledger had the same duplicate and omitted the existing Embed All Linked command; both are corrected. The matrix and phase ledger now each contain651 distinct commands. This corrects the inventory, not the feature count. No package closes.

Photoshop’s published guide is the reference; the Mac is locked, so no live UI or Photoshop-generated comp fixture was acquired. Smart Object comp selection, editable PSD resources, complete warnings, geometry/timeline behavior, docking/defaults, Actions and full/platform/performance qualification remain open. Store332, installed283 and private full-source298 are unchanged. Both offline diaries are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-336).

### Smart Object comp selection — step337

The Smart Object Properties panel now offers the source document's named Layer Comps. Each placed instance can use a different comp while sharing the original source. Choosing one updates its cache through a native history transaction; original bytes, placement, masks, styles and filters remain. Source replacements rebuild the choices independently. A deleted selected comp stops the replacement atomically, and linked originals require existing authorization and matching fingerprints. Native80 keeps the choices; one new API command shares the native preparation, history, state and errors.

The first expanded run passes362/364 cases. A new test looks for compID at the schema envelope instead of inside parameters; correcting the assertion gives all13 new cases passing. The other failure is the linked PSD/PSB cached-pixel mismatch already recorded at332. Both diagnostic vectors match that earlier run exactly, and the strict comparisons remain enabled.

A review also finds selected revisions rehashing the full source during state reads. They now use the cached base revision. The added64MiB Core regression first exposes an overlapping-access error in its fixture; that failed compile is preserved and the fixture is repaired. Source04 passes all14 new cases and364 of365 affected cases, with no unexpected errors or crashes. One thousand revision reads take25.894ms. This does not establish physical60fps or Photoshop pixel parity.

The Mac remains locked, so no live Photoshop or Photato controls are verified. Parent comp recording of Smart Object choices, Photoshop resource descriptors, full warning/nested/source-change behavior, Actions, complete suite and platform/performance gates stay open. All 104 packages remain open. Store332, installed283 and private full-source298 are preserved. The diary's335/336 index cells are aligned with their existing date/milestone columns; dates and records are retained. Both offline copies are regenerated. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-337).


### Parent Layer Comp Smart Object choices — step338

Adobe's Photoshop guide lists a fourth property when creating a parent comp: the Layer Comp selection of each Smart Object. The native panel and API now record those source/choice IDs without storing extra pixels. Applying a saved parent variation or exporting it prepares current child artwork first, then commits the whole change in one Undo transaction. Last Document State retains choices from before preparation. Shared sources are decoded once per parent application, with independent selections and cached distinct renders. Embedded selections propagate under the existing nesting budget; nested linked originals still need an explicit resolver.

Linked reads use existing grants and file fingerprints. Native bookmark access alone does not authorize API file reads. Source identity changes, missing child choices, stale source bytes and permission changes reject atomically. Native 81 keeps the parent records; ordinary comps/per-instance choices retain their older feature versions where applicable. The command catalogue stays213. CONTRIBUTING's stale statement that Rust defines behavior is corrected: Photoshop 2026 is the acceptance standard.

All 13 new cases pass. The expanded optimized selection passes 377 of 378 cases, retaining one existing strict linked PSD/PSB cached-pixel case with two failed assertions, zero unexpected errors and no crashes. Its diagnostic vectors match checkpoint 332. Source02 freezes 6898 inputs and 926 production Swift files. No full-current-suite or Photoshop equivalence is claimed.

The first run passes374 of378 cases. It exposes a real API routing regression: ordinary comp capture is incorrectly sent through the linked-artwork commit guard. The repair uses that permission only for changed child-cache preparation. A cancellation fixture also rotates its file authorization after registering the API grant, so it is reordered; strict live-worker assertions remain. The nested expected state is strengthened by manually selecting its child. Failed and repaired inputs/logs are kept separately.

The Mac remains locked, so this is functional native/API/PDF-reader evidence and not a live Photoshop comparison. PSD comp resources/descriptors, full warnings/geometry/timeline/defaults, Actions, platform/capacity/performance and complete current-green gates remain open. All 104 scopes stay open. Store332, installed283 and private full-source298 remain unchanged. Both offline diary copies are regenerated. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-338).


### Editable PSD/PSB Layer Comps — step339

The saved-variation workflow now reaches Photoshop files. Public Adobe envelopes, MIT ag-psd field definitions and one independent saved file guide the mapping. Two fixture paths have identical bytes. The file contains a no-property comp and inherited visibility values; a primary report also describes how Photoshop2026 handles omitted visibility. Those findings replace earlier arbitrary restrictions. No Photoshop script implementation is copied, and the locked Mac prevents a new owned reference capture.

Supported catalogues, comments, integer IDs, visibility/position and prior state become native editable comps. Embedded shared sources retain separate selected child comps. Appearance changes, parent child-comp records and other unqualified fields retain explicit loss guards. Source01 passes all11 new cases and406/407 affected cases, retaining the old linked-cache mismatch. The separate reader initially verifies only8-bit layers; support for alternative16/32-bit sections repairs four reader failures. Original effect-reference fields are also preserved and tested in Source02, whose11 new cases pass.

Review finds that a nil typed library in an older native file can still hold opaque Photoshop comps. Saving must preserve those records. Explicit Clear now records native82 intent, with state/schema, history and recapture handling. Two further regressions cover the legacy and clear cases, plus real HTTP clear/download assertions. The exact older resource and per-layer records survive an unmodified legacy save. The legacy library is retained rather than automatically migrated.

All 13 new cases pass. Source03 passes 408 of 409 affected optimized cases; one existing linked PSD/PSB cache case retains two strict failed assertions. Both diagnostic vectors match332. There are no unexpected errors or crashes. The separate reader verifies six output files across8/16/32-bit PSD/PSB metadata. These are native/independent-format checks, not Photoshop2026 execution or full-current-suite acceptance.

The six Source01/02/final output sets overlap; they are not independent new fixtures. Native/API/Adobe output checks and the separate metadata reader do not prove Photoshop rendering or universal platform acceptance. Rich interchange, full legacy migration and all other parity gates remain open. All 104 scopes stay open. Store332, installed283 and private full-source298 are unchanged. Both offline diaries are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-339).


### Editable PSD/PSB Global Light — step340

Native shared-light controls existed, but Photoshop-file saving rejected explicit document light and changed participating shadows to local values. The shared encoder now carries both resources, global/local flags and inactive local angles. Both effect renderers use a consistent shared direction; local bevel altitude no longer follows document light. Conservative native migration preserves conflicting fallback behavior. PSD precision and unsupported rich effects keep explicit save guards.

The first optimized run builds and completes484 cases:478 pass,6 fail,136 assertions and4 unexpected decode/lifecycle errors. Ten new cases pass. The new public-fixture assertion is wrong: that file contains light resources but no modern styles. A separately extracted MIT public descriptor records shared angle132° with inactive local120°; its exact628 bytes and license become a test fixture. The full original effect file is not claimed as supported. Two existing transfer tests need native75 negotiation after light promotion. Another retained strict test catches resource order changing on unmodified saves. The repair preserves order, names and padding, with a positive edit assertion. The original failures and pre-repair files remain preserved.

All 11 new cases pass. Source02 passes 482 of 484 affected optimized cases, retaining two existing strict comparison failures (120 assertions): linked PSD/PSB cached pixels and source-effect words. Their diagnostic vectors match332. There are no unexpected errors or crashes. A separate reader verifies resources and style flags in six 8/16/32-bit PSD/PSB outputs. Native round trips and independent metadata checks do not establish Photoshop2026 pixel/UI equivalence or full-current-suite acceptance.

The11 new cases cover dialog/API/history/Cancel, native adoption, Adobe output, malformed resources, all depths, independent format metadata and failure atomicity. The private source-effect and linked-cache diagnostics match332; their strict checks remain. There is no live Photoshop acceptance while the Mac is locked. All 104 scopes remain open; no release or installation occurs. Both offline diary copies are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-340).


### Production Export As workflow — step341

The former Export As binding opened a basic save panel. This increment adds an asset workspace and Quick Export/preferences. Current Adobe documentation supplies the workflow and published per-output layer contract. Photoshop itself remains inaccessible while this Mac is locked, so no new live UI/default comparison is claimed.

Native workers prepare independent document/layer/group/artboard assets, scales, canvas sizes, profiles and limited metadata. Cancel/history/source behavior and HTTP output share the engine. Quick preferences and last Export As settings stay separate, and persistent API preference writes use the existing permission gate. Adobe create-composite gets layer references/crop modes and selection-aware output caching; editable single-group PSD uses the existing serializer. No new Adobe route or drawing tool is invented.

Source01 stops at a wrong geometry type reference; Source02 stops at a misplaced API schema-validation block. Both fail before runtime tests, with their inputs/diagnostics and repairs preserved. Source03 builds and runs316 cases:311 pass,5 fail, with one unexpected fixture error. Fifteen new cases pass. A noncontiguous group fixture, wrong imported-profile assumption, malformed UUID error class and two stale command-count assertions are repaired. The separate reader catches generated metadata under None; the encoder now strips descriptive PNG/JPEG metadata without changing samples or selected ICC tags. Every failed run and pre-repair file remains preserved. Source04 passes all316 affected cases. A final review then removes an unintended second resampling when changing export coordinates. Original pixels, masks and affine transforms now remain intact, with a nineteenth regression checking retained data and RGB8 appearance. Preview updates coalesce and wait for canceled encoders to finish before starting replacements. The test set includes deterministic cancellation/revocation, preference and existing-file preservation, privacy filtering, menu shortcuts and asynchronous Adobe output. The independent PNG reader checks owned analytical pixels rather than Photoshop images.

All 19 new cases and 317 affected optimized cases pass, with no failed assertions, unexpected errors or crashes. A separate reader verifies five owned PNG outputs and 412 analytical RGBA channels. This is native/format evidence; full-current-suite and Photoshop2026 output/UI/platform acceptance remain open.

Full production export, exact Photoshop encoders/options/UI, maximum dense processing, supported platforms and physical performance remain open. No entire package is closed. Installed283/private full298/store332 are unchanged. Both offline diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-341).


### Layers to Files — step342

This missing production command now exports individual layers through a native folder/options workflow. Adobe's current guide defines the visible controls. The implementation uses existing Swift codecs and private staging, with source checks before publication. Eye visibility is kept separate from opacity; groups supply retained ancestor context. The same selection implementation now serves published Adobe output layers, and canvas fills no longer inherit an unrelated alignment restriction.

Native PSD/PSB/Photato streams files independently of the API aggregate budget. Other formats use their existing encoders, including native indexed PNG. The folder transaction refuses existing names and rolls back only matching newly linked files after failure. Shared API settings/state/progress/cancel preserve source/history. The first compile fails on an encoder initializer's argument order and is repaired without withdrawing formats or assertions; every attempt remains in the detailed record. The first runtime run passes329 of331 cases. BMP/Targa need their own native destination path, and two numeric schema bounds need Double values for the existing validator. After those repairs all331 pass. A final comparison aligns Export As with batch/Adobe ancestor context; the final source repeats all331 passes.

All 14 new and 331 affected optimized cases pass, with zero failures, unexpected errors or crashes. The independent reader verifies four PNGs and384 analytical RGBA channels. A260-file native batch totals137216120bytes and publishes successfully while the128MiB API ZIP correctly rejects it. These owned/native checks do not establish full Photoshop2026/default/UI/codec/platform/capacity or current-full-suite acceptance.

The260-file boundary uses tiny owned images and metadata, not maximum-size real artwork. Complete Photoshop/UI/default/codec/platform/current-suite acceptance remains open. All 104 packages stay open, and installed283/private full298/store332 remain unchanged. Both offline diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-342).


### Color Range selection — step343

The factory command now opens native sampled-color and tonal controls, with localized clusters, pipettes and mask/image/matte previews. Existing selections constrain the result. Save/Load use portable Photato JSON presets. One shared native transaction supports desktop/API Undo and explicit-coverage Actions; preview, cancellation, stale-source checks and sharing revocation preserve the source. The independently written analytical kernel is documented. Skin Tones/Detect Faces, Out of Gamut, Adobe preset compatibility and exact Photoshop masks remain open.

All 14 new and 127 affected optimized cases pass, with zero failures, unexpected errors or crashes. The separate checker verifies10 analytical mask bytes. Sparse300000×300000 classification is tested; physical maximum-capacity editing,60fps, complete current suite and Photoshop numerical/UI/default/platform acceptance remain open.

All 14 new cases cover native math, profiles/depths, previews/history, API equality/errors/revocation and 16 modifier combinations for every sampler. The source/test changes, setup repair and every build attempt are preserved in the detailed record. Both standalone diary copies are regenerated. No new installation, archive, source push or release; all 104 scopes stay open. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-343).


### Magnetic Lasso — step344

The toolbar's existing Magnetic Lasso entry now uses an independent Swift tracer. Width, Contrast, Frequency, tablet pressure, Feather and anti-aliasing accompany fastening points, Delete, closure and temporary freehand/straight segments. The source snapshot, captured selection mode, incremental previews, modifier cursors, lifecycle cancellation and one Undo transaction share the API replay model. Photoshop's exact tracing algorithm and defaults remain unqualified;32-bit availability follows Adobe's published restriction.

All 14 new and 235 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate checker verifies all 768 analytical mask bytes. Sparse 300000×300000 output is tested; physical maximum dense capacity,60fps, the complete current suite and exact Photoshop paths/pixels/defaults/UI/platform behavior remain unqualified.

All 14 new cases pass. The independent mask is owned analytical artwork; sparse maximum dimensions do not prove dense capacity. The diary retains every failed attempt and repair. Both standalone copies are refreshed. No new installation, archive, push or release; all 104 scopes remain open. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-344).


### Selection Modify and Reselect — step345

Border, Smooth, Expand and Contract now have native controls, cancellation, validation and one Undo transaction. Their independent disc extrema/median and centered borders operate on tiled grayscale coverage. Reselect retains the previous deselected rectangle or soft mask in this open document; identity/size/read/close changes clear recall. A strict shared preparation path permits document selection edits in component/mask contexts without admitting pixel changes. Two API commands expose the same operations and state. No new native or Actions format is required.

All 14 new and 323 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 1,920 analytical mask bytes across four odd/even borders. Sparse 300,000 × 300,000/constant-plane admission is tested. Exact Photoshop kernels/gray coverage/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

All 14 new cases pass, with source/target preservation, HTTP/native equality, recall/history, admission/error/revocation, factory menu and lifecycle checks. Both standalone diary copies are refreshed. Complete S01 and all 104 scopes stay open. No new install, archive, push or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-345).


### Transform Selection — step346

The selection boundary now has scale, rotation, move, skew, distort, perspective and flip controls, including numerical values, reference positions, contextual menus and captured modifier cursors. Preview work transforms a bounded contour off the main actor; final coverage is resampled once from the original mask. Pixels, layers, masks, channels, profile, depth and editing targets are preserved. One new API command shares the same history and cancellation path; native 82/Actions 30 stay unchanged.

All 14 new and 356 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 320 analytical GRAY8 bytes across four transforms. Sparse 300,000 × 300,000 projective admission is tested. Exact Photoshop sampling/gestures/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

All 14 new cases pass, covering native/API equality, lifecycle/source/target preservation, history/Actions, invalid/busy/stale/revoked/canceled work and all 16 modifiers. Both standalone diary copies are refreshed. Full S01/G01 and all 104 scopes remain open. No new install, archive, push or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-346).


### Selected-pixel Free Transform — step347

Command-T now handles ordinary RGB raster selections, using the same scale/rotate/skew/distort/perspective/reference controls as boundary transforms. Pixels are lifted from the immutable source and composited onto the cut remainder; newly transformed off-canvas content stays in layer storage. Native previews use a bounded image proxy without changing the document. The desktop, API, Undo/Redo and semantic Actions share the same engine. Old Action versions remain readable; selected-pixel steps require31. Native82 remains unchanged.

All 16 new and 424 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 3,072 analytical RGBA channels across four selected-pixel transforms. Sparse 300,000 × 300,000 admission is tested. Exact Photoshop sampling/soft overlap/gestures/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

All 16 new cases pass, covering native/API equality, preview/lifecycle/source/target preservation, raw identity, off-canvas masks/storage, history/Actions, invalid/busy/stale/revoked/canceled work and all 16 modifiers. Both standalone diary copies are refreshed. Full G01/S01 and all 104 scopes remain open. No new install, archive, push or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-347).


### Background layer semantics — step348

Background is now a layer identity rather than a name. Opaque RGB File/New documents create it; old documents retain their prior meaning. Layer/New conversion, the native options sheet, lock/name behavior, Clear/Cut/Eraser, canvas geometry and file/API persistence follow this model. Conversion and edits have shared history and portable Actions32. Published create-composite accepts Background add/edit/delete and explicit conversion; the existing JSON output describes its role.

All 20 new cases pass. Of 603 affected optimized cases, 602 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python parser verifies six owned8/16/32-bit PSD/PSB Background records. Sparse300,000 ×300,000 opaque planes are tested. These checks do not establish Photoshop output/UI/default equivalence, full-current-suite acceptance, supported-platform coverage, maximum dense capacity or physical60fps.

Both standalone diary copies are refreshed. Full L01 and all 104 scopes remain open, including richer conversion/selected-pixel contexts. No new installation, archive, push or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-348).


### Background selected-pixel Free Transform — step349

Background selections now use the existing Free Transform modes, numeric controls and previews. Vacated pixels use the background swatch captured at the start. The layer remains opaque and canvas-sized; ordinary layer behavior is retained. Apply/Undo/Redo, semantic Actions33 and the shared API use the same captured value. Native83 and227 commands remain.

All14 new cases pass. Of617 affected optimized cases,616 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies3,072 analytical RGBA channels across four Background transforms. Sparse300,000 ×300,000 editing and clipped virtual support are tested. Exact Photoshop pixels/soft overlap/interpolation/defaults/UI, full-current-suite, supported Macs, maximum dense capacity and physical60fps remain unqualified.

The14 new cases include captured palette/preview/commit, native planes/HDR/three depths, all16 modifiers, API/profile/PSD/history equality, cancellation/stale/revoked work, lifecycle and bounded previews/storage. Both standalone diary copies are refreshed. All 104 scopes remain unclosed. No new installation, archive, push or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-349).


### Move and copy selected pixels — step350

Move/V now handles selected image content before Auto-Select. A captured source and bounded coalesced proxy supply previews; release commits one Move transaction. Shift constrains, arrows nudge1/10pixels and Option copies on the same layer. Native/API/Actions34 share the selected-pixel compositor and target/lifecycle/history guards. Background holes remain opaque. The API now has228 commands; native83 stays unchanged.

All16 new cases pass. Of633 affected optimized cases,632 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies3,072 analytical RGBA channels for ordinary/Background move/copy. Sparse300,000 ×300,000 copies are tested. Exact Photoshop pixels/soft overlap/defaults/gestures/cursor art/live UI, key-repeat scheduling, full-current-suite, supported Macs, maximum dense capacity and physical60fps remain unqualified.

Both standalone diaries are refreshed. All 104 scopes remain unclosed. No new install/archive/push/release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-350).


## 2026-11-02 — Step 351: Pixel-mask Free Transform

Whole unlinked pixel masks now use the shared Free Transform controls, six modes, reference positions and numeric fields. The engine changes raw mask coverage and placement while retaining the layer and mask properties. Coalesced previews include gray/overlay views. Native/API history, target guards, cancellation and Actions35 accompany229commands; native83 stays unchanged.

All 16 new cases pass. Of 711 affected optimized cases, 710 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 186 analytical grayscale samples across four transforms. Sparse 300,000 × 300,000 masks are tested. Exact Photoshop samples, mask bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

All 104scopes remain unclosed. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-351).


## 2026-11-02 — Step 352: Auxiliary-channel Free Transform

Whole and selected auxiliary channels now use the shared Free Transform controls, six modes, reference positions and numeric fields. Whole projection shares the mask sampler; selected coverage shares the immutable-source compositor. Other channels/layers, display metadata and retained spot gray survive. Coalesced previews honor channel gray/overlay modes. Native/API history, target guards, cancellation and Actions36 accompany230commands; native83 stays unchanged.

All 16 new cases pass. Of 744 affected optimized cases, 743 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 768 analytical grayscale samples across four transforms. Sparse 300,000 × 300,000 channel planes are tested. Exact Photoshop samples, channel bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

All 104scopes remain unclosed. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-352).


## 2026-11-02 — Step 353: Multi-layer and group transforms

Multiple layers and groups now share affine scale, rotation, skew and fixed transforms around common bounds/reference controls. Parent/child targets normalize to root subtrees. Editable content, hierarchy, masks and Smart Object sources survive. Coalesced previews leave the original document/history intact; projective collection modes remain unavailable. Native/API history, target guards, cancellation and Actions37 accompany231commands; native83 stays unchanged.

All 16 new cases pass. Of 851 affected optimized cases, 850 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 5120 analytical RGBA channels across four transforms. Sparse 300,000 × 300,000 layers are tested. Exact Photoshop samples, collection bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

All 104scopes remain unclosed. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-353).


## 2026-11-02 — Step 354: Projective layer transforms

Distort and Perspective now work on supported whole RGB pixel layers, resolved Smart Objects and their groups. Inverse projection uses bounded paged patches without a dense UV map. Linked masks share the edit; unlinked masks keep world placement. Smart sources remain editable. Six-mode native controls, captured modifier feedback, coalesced previews and API state/history are integrated. Projective Actions38 preserve old affine37;231commands/native83 are unchanged. Unsupported editable target types are explicit and remain unflattened.

All 16 new cases pass. Of 963 affected optimized cases, 960 pass; 3 cases retain 12 failed assertions. There are zero unexpected errors and no crashes. An independent Python checker verifies 10240 analytical RGBA channels across eight ordinary/Smart-mask outputs. Sparse 300,000 × 300,000 projective layers are tested. Exact Photoshop samples, bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

All 104scopes remain unclosed. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-354).


## 2026-11-02 — Step 355: Layer links and whole-layer Move

Persistent links now connect regular layers and groups without flattening them. Individual links can be temporarily disabled; Select Linked Layers includes those partners without changing document history. Enabled partners and descendants join Move and whole-layer Free Transform once. Move/V without a pixel selection now previews whole-layer translation or Option-copy, preserving pixel storage and Smart sources. Copies use independent link groups. Native panel/menu controls,16modifier cursor modes, history, API graph/state/schemas and PSD/PSB resources1026/1072 are integrated. Native84 and Actions39/40 retain older feature minima.

All 22 new cases pass: 9 model, 5 imaging and 8 application cases. Of 1128 affected optimized cases, 1125 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. Independent readers verify 10240 RGBA channels across eight owned Move/copy outputs and link records in six PSD/PSB files. Sparse 300,000 × 300,000 Move/copy storage is tested. Exact Photoshop behavior/output, live UI, the full current suite, supported platforms, dense maximum capacity and physical 60fps remain unqualified.

Transform Again, full linking contexts and all 104 scopes remain open. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-355).


## 2026-11-02 — Step356: Color Fill and Stroke

The missing raster Stroke workflow now has native width/color/Inside-Center-Outside/mode/opacity/transparency controls. Solid-color Fill can blend at partial opacity, reaches the selected canvas beyond a small layer's storage, and retains palette choices/Content-Aware handoff. Raster/mask/auxiliary planes share one cancellable transaction; channel display inversion is applied once, masks and off-canvas source pixels retain placement, and live content is not rasterized implicitly. Portable Actions41 and235API commands preserve prior format minima. Width250, the edge kernel, initial settings and full preferences remain unqualified against Photoshop.

All 17 new cases pass: 7 model, 8 application and 2 imaging cases. Of 1178 affected optimized cases, 1175 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. An independent reader verifies 1080 alpha bytes across nine owned Stroke outputs. Sparse 300,000 × 300,000 Stroke and implicit full-canvas Fill are tested. Exact Photoshop edges/blends/defaults, live UI, full current suite, supported platforms, dense maximum capacity and physical 60fps remain unqualified.

All 104 scopes remain open. No installation, push, archive or release. Both standalone diary editions refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-356).


## 2026-11-02 — Step357: Pattern Fill

Pattern is now a Fill source with a native Custom Pattern choice. Document assets take precedence over library IDs, and each request captures its asset. The shared engine applies selection/canvas coverage, blend/opacity, raster transparency and scalar display rules, preserving untouched words and mask positions. Portable Actions42 carry the asset rather than depend on a later library lookup. Existing pixels.fill/state/schemas expose pattern selection and explicit native placement while keeping235commands/native84 and old solid41minimum. Full phase/sampling/profile/default/picker/range behavior remains unqualified.

All 13 new cases pass: 6 model, 5 application and 2 imaging cases. Of 1204 affected optimized cases, 1201 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. Independent modulo/pixel and PNG readers verify 4320 RGBA bytes across eight owned raw outputs and one PNG. Sparse 300,000 × 300,000 localized and implicit-uniform pattern fills are tested. Exact Photoshop phase/kernel/profile/defaults, live UI, full current suite, supported platforms, dense maximum capacity and physical60fps remain unqualified.

All 104complete scopes remain open. No installation, source push, archive or release. Both standalone diary editions refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-357).


## 2026-11-02 — Step358: Large-document Crop

Remove the16MP canvas and64MP aggregate RGB delete guards. Exact copies and rotated delete samples use bounded pages; Background expansion avoids a full-canvas Boolean array. Native width/height fields, preview and API share the range. Source/export resolution remains full size. History, cancellation and immutable prepared-source validation stay shared.

18 of 19 new cases pass: all 8 model and 7 application cases, and 3 of 4 imaging cases. One strict encoded-sRGB Float32 PSB sample comparison remains open. Of 1268 affected optimized cases, 1264 pass; 4 retain 13 failed assertions. No unexpected errors or crashes. Independent readers verify 432 RGBA bytes in eight owned integer crop vectors and one PNG. Maximum 300,000 × 300,000 sparse delete/retain/rotation, implicit saved channels,40.5MP Background output and80000wide PSB are tested. Dense maximum capacity, exact Photoshop interpolation/defaults/UI, full current suite, supported platforms and physical60fps remain unqualified.

All 104complete scopes remain open. No installation, source push, archive or release. Both standalone diary editions refreshed. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-358).

## 2026-11-02 — Step359: layer capacity

Remove the inconsistent512native/64API layer ceilings. Common document admission, native panel filtering, bulk hierarchy operations, native persistence and supported PSD/PSB/API workflows now use the declared8,000-layer development target. The exact Photoshop2026 ceiling remains unverified; Rust is a supporting reference only. Preserve separate algorithm/frame/file/memory limits and Adobe's100-reference output bound.

All 19 new capacity cases pass. Of 648 affected optimized cases, 640 pass; 8 retain 149 failed assertions. There are 1 unexpected errors and 0 crashes. Independent readers verify four owned PSD/PSB files: 32,000 layer names, 8,000 raster records or 16,000 group/divider records per file, and 128,000 raw channel bytes.

The exact Photoshop 2026 layer ceiling remains unverified. Dense stacks, sustained interaction speed, live UI, complete Photoshop output, supported Macs, the full current suite and physical 60fps are not qualified. All 104 complete package scopes remain open. No installation, source push, archive, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-359).

## 2026-11-02 — Step360: Flatten Image

Add the missing Layer > Flatten Image workflow, native hidden-layer confirmation, shared composition/history, Photato operation/state/schema, semantic Actions43 and Adobe flattenImage/FltI descriptor support through both resource-job interfaces. Preserve saved document state and numerical native planes in the supported single-layer case; specialized compositors remain required.

All 19 new cases pass. Of 312 affected optimized cases, 312 pass; 0 fail with 0 assertions and 0 unexpected errors. There are 0 crashes. Independent checks verify 48 RGBA bytes across three analytical vectors and three PNGs, plus six PSD/PSB headers.

This is a working Flatten Image increment. Layered/transparent native components, palette/ink and temporal flattening still need their numerical/plate/frame compositors. Full Photoshop output/defaults/live UI, complete L02 merge/rasterization, supported platforms, dense capacity and physical60fps remain open. All 104complete scopes are preserved. No installation, source push, archive, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-360).

## 2026-11-02 — Step361: Duplicate Image

Add Image > Duplicate with an editable name, merged-layer option and cancellation. Whole-document copying retains editable and numerical state; the copy has independent native history and no saved file association. Shared preparation powers the new document.duplicate API (201). Merged static RGB output retains transparency; unsupported specialized composition remains visible.

All 15 new cases pass. Of 233 affected optimized cases, 233 pass; 0 fail with 0 assertions and 0 unexpected errors. There are 0 crashes. Independent analytical/PNG readers verify 48 RGBA bytes across three document depths.

Merged native component, palette/ink and temporal composition, multi-document Actions, exact Photoshop output/defaults/live UI, supported Macs, full current suite, dense maximum capacity and physical 60fps remain open. All 104 complete package scopes remain open. Rust comparisons do not determine Photoshop acceptance. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-361).

The final lifecycle review caught a focus bug: a copy could be registered while its source was still busy or its sheet was closing, leaving the original tab active. The source now clears its busy state before presentation, and a pending presentation waits for the native sheet to detach. Closing the queued copy removes the request. The passing 15-case feature set includes this repair. Earlier attempts and the initial passing run that missed the bug remain in the detailed record.

## 2026-11-02 — Step362: Trim and Reveal All

Add Trim controls, retained-content Reveal All, exact sparse/paged canvas framing and numerical component byte copies. The UI, typed API and semantic Actions share preparation/history. Bounds, stored origins, masks, saved channels/guides/paths and comp positions are handled together. Preserve failed attempts and distinguish owned/native checks from live Photoshop qualification.

All 24 new cases pass. Of 304 affected optimized cases, 302 pass; 2 fail with 2 assertions and 1 unexpected errors. There are 0 crashes. Independent analytical/PNG readers verify336RGBAbytes; 12 PSD/PSB headers are checked separately.

Temporal and ink-mode canvas rebasing, layered native component Trim, advanced mask/effect bounds, authoritative Adobe actionJSON descriptors, exact Photoshop defaults/output/live UI, supported Macs, full current suite, dense maximum capacity and physical60fps remain open. All 104complete package scopes remain open. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-362).

## 2026-11-02 — Step363: Private full-source backup

Deliver the complete current native source to the existing private repository, preserving the Rust snapshot and history. Retain actual qualification limits and known failures. Check every included qualified input against362Source03. Exclude generated/private runtime material and the external Layer Comp PSD identified by the upstream image-asset exception; retain source/hash/acquisition instructions. Verify the no-network helper, package/project structure, staged blob contents and destination privacy before committing. The source commit is [4514839](https://github.com/ForensicIntelligence/Photato/commit/45148392a5a3977ed731c4624730e8cbfcb9e29f); GitHub commit/tree and private visibility are verified. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-363).

Private source commit [4514839](https://github.com/ForensicIntelligence/Photato/commit/45148392a5a3977ed731c4624730e8cbfcb9e29f) includes the complete current native app/test code and the documented source exclusions. GitHub main/tree and private visibility are verified. The app was not installed, uploaded as a binary, submitted to Apple or released.

## 2026-11-02 — Step364: Rich layer merging

Extend the native merge commands beyond plain pixel layers. Add shared compositor preparation, hierarchy validation, rich/paged output, source-bound history and both API paths while retaining measured plain-pixel behavior. Preserve unavailable specialized/retention cases and failed attempts explicitly.

All 18 new cases pass. Of 298 affected optimized cases, 297 pass and 1 fail; 2 failed assertions, 0 unexpected errors and 0 crashes. Independent readers verify 288 RGBA bytes and 672 raw merged PSD/PSB component bytes across three PNGs and six Photoshop files.

Complete L02 merge/rasterization, numerical/palette/ink/temporal composition, cross-parent selections, clipped artwork without its selected base, hidden descendants inside visible merged groups, stamp/merge-clipping variants and exact Photoshop backdrop/effects/geometry/defaults/live UI remain open. Supported-platform, full-current-suite, dense maximum capacity and physical60fps qualification remain open. All 104 work packages remain open against their full acceptance criteria. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-364).

## 2026-11-02 — Step365: Linked preview sampling

Correct the export-only source-edge policy and project linked masks as numerical coverage. Preserve the native document and general geometry defaults, and test desktop/API serializers and missing-source reexport. Keep integer rounding and Photoshop reference gaps explicit.

All 12 new cases pass. Of 359 affected optimized cases, 358 pass and 1 fail, with 2 failed assertions, 0 unexpected errors and 0 crashes. Independent math checks cover 5184 raw RGBA bytes; a standalone PSD/PSB parser checks 12432 bytes across all owned layer, alpha, mask and merged-image planes.

Integer preview/mask quantization still needs independent Photoshop qualification: the retained strict RGB8 round-trip comparison is not waived. Other current affected failures are recorded by case below. Full L05/I01 functionality, general Photoshop interpolation/ICC/filters/projective/effect/mask defaults, complete live UI, full current suite, supported Macs, dense capacity and physical 60 fps remain open. All 104 work packages retain their full acceptance criteria. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-365).

## 2026-11-02 — Step366: Quick Mask and saved selections

The maintainer asked for one major workflow to be completed and tested. S05 was selected, with C01 queued next. Photoshop reference files exposed incorrect gray selection combinations; the shared engine now matches the controlled8/16/32-bit channel samples. The native dialogs, Quick Mask defaults/gestures and API gained the missing workflow pieces. The first run found own-sheet admission and test-fixture issues; those failures and their repairs are retained.

All 15 new cases and all 266 affected optimized tests pass, with 0 failed assertions, 0 unexpected errors and 0 crashes. The 491.43-second optimized build and 34.724-second affected run used 7,065 unchanged frozen inputs and 1,003 production Swift files.

S05 is still in progress: finish the remaining Save/Load source/destination cases and live UI qualification before closure. C01 is preselected next. The full current suite, all-input Photoshop output, supported physical Macs and 60 fps qualification remain open. Installed preview283, private source backup363 and store archive332 are unchanged; no installation, source push, archive, binary upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-366).

## 2026-11-02 — Step367: Saved-selection documents; C01 queued

Photoshop Save Selection > New produces a document containing mask channels, with no image layers or printing plates. Photato now represents that directly, with native85 storage and8/16-bit PSD/PSB interchange. Load Selection gained the remaining component, layer transparency and mask source choices. New-document transfers require explicit API permission and preserve the source document and its Undo history. A failing first run found an incorrect sample-depth tag, unhandled Photoshop document metadata and a stale test expectation; the logs and repairs are retained.

All17 new cases and all388 affected optimized tests pass, with0 failed assertions,0 unexpected errors and0 crashes. The run used7,074 unchanged frozen inputs and1,007 production Swift files.

The next full major function is C01: separate channel viewing and editing targets, grayscale/color display, temporary mask rows, actual paint/filter targets, eye gestures and Photoshop shortcuts. It starts after S05 completes and is tested.

S05 remains in progress pending native live UI and remaining qualification; C01 is preselected and starts after S05 completes and is tested. The full current suite, all-input Photoshop output, full supported-platform coverage, dense maximum capacity and 60 fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. No installation, source push, archive, binary upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-367).

## 2026-11-02 — Step368: Quick Mask workflow checks; C01 next

We checked Quick Mask painting, Undo/Redo, saved selections, standalone selection documents, cross-document loading, channel shortcuts and reopening files in the native app. The checks found two display bugs: saved documents appeared under their internal names in the source picker, and layerless Multichannel documents were labelled RGB in Properties. Both were repaired.

A coloured Photoshop reference exposed a larger difference: loading the composite as a selection used fixed RGB weights instead of the working Gray profile. The standard RGB8 transform now uses numerical calibration captured from our own test image, with every possible RGB8 colour represented. Embedded-profile and untagged Photoshop references agree. Other profiles retain their separate fidelity checks. No Photoshop source code, executable internals or proprietary runtime is used.

All 432 affected optimized tests pass on Apple Silicon and translated Intel, including all 11 new cases on each architecture. There are no failed assertions, unexpected errors or crashes. The runs used 7,084 unchanged frozen inputs and 1,010 production Swift files.

The first ARM test run caught an incorrect test expectation. Intel test discovery also chose the wrong architecture; running the unchanged test bundle directly under Rosetta resolved the launcher problem. Failed attempts remain in the record. The universal package includes its required selection resource, and the Xcode Release resource path was checked separately. The final current-source live check could not run because the Mac was locked; the earlier native checks used367Source03.

C01 is next because the Channels panel needs complete, independent viewing and editing targets. The plan includes component and mask rows, eye controls, real brush/filter targets, factory shortcuts and matching API behaviour.

S05 remains in progress; its current-source live recheck awaits an unlocked Mac. C01 is queued after completion. General profile/CMM fidelity, the full current suite, physical supported-platform coverage, dense maximum capacity and sustained 60 fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-368).

## 2026-11-03 — Step369: Quick Mask visibility and hidden brush target

The previously blocked Mac checks could be completed. Saved-document names and the Multichannel Properties label were correct. The packaged composite-selection command also matched64 coloured Photoshop reference samples saved through the native UI. An ordinary Photoshop-saved PSD opened normally; the minimal test PSD's disabled Open-panel state remains unqualified.

The channel audit found that the Quick Mask eye was wired to exit the mode. We separated its display visibility from the editing target, mask data and Undo history. A direct Photoshop check added an important rule: painting a hidden Quick Mask raises a hidden-target warning. An early candidate allowed that painting; it was withdrawn and replaced with matching native/API rejection. Showing the overlay restores painting, and Undo removes only the new stroke.

All 454 affected optimized tests pass on Apple Silicon and translated Intel, including all five new Quick Mask visibility cases on each architecture. There are0 failed assertions,0 unexpected errors and0 crashes. All7,085 frozen inputs and1,010 production Swift files remained unchanged.

The first test attempt read the schema at the wrong level. The first Intel build also omitted testability support. Both failures and repairs remain in the record. One unqualified raw executable was overwritten before it was copied; its source snapshot, hash and failed logs survive. The qualified Source02 executables, resources and universal app are preserved separately. The current native eye, warning, show, paint and Undo checks pass.

S05 remains in progress against its full acceptance criteria; C01 stays queued. Other hidden-target Fill/filter/tool contexts, general profile/CMM fidelity, full current suite, physical supported-platform coverage, dense maximum capacity and sustained 60 fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-369).

## 2026-11-03 — Step370: Private source backup and next major function

The tested369 source is now backed up in the existing private repository. Every7051 included qualified input matches its frozen SHA256;34 model/cache/external-image inputs are excluded with reasons. All original1057Rust files remain unchanged. The source includes the app, tests and redistributable fixtures, Xcode project, scripts, assets, licenses and developer records. This was a source delivery; it did not upload or install a new app.

The maintainer asked again which major feature follows S05. We confirmed C01: Component visibility and edit targeting. The plan covers independent viewing and editing, channel/mask rows, real painting/filter targets, factory shortcuts, history and API support. C01 starts after S05 is complete and tested; neither package is marked closed by this decision.

The source retains checkpoint369's454 affected passing tests per architecture and its native Quick Mask check. No native tests were rerun for documentation and source-copy changes. The full current suite, complete Photoshop behaviour and supported-platform/performance gates remain open. GitHub's main ref and source tree were verified, and repository visibility remains private. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-370).

## 2026-11-03 — Step371: Hidden Quick Mask commands and pixel Invert

Photoshop treats hidden Quick Mask commands differently. Fill opens its dialog but rejects the commit; Invert is disabled. Gaussian Blur can still run on the hidden mask. We reproduced those rules in direct and prepared native/API commands, including the separate modern painting path. The factory Image Adjustments Invert command now changes supported pixels rather than adding a layer; RGB clients can use the existing adjustment.apply operation.

The first run caught a bad test request: it sent saved-filter JSON instead of the public API’s kind/radius fields. We corrected the request without relaxing the decoder. Another test still expected the retired64-layer limit; it now checks the current8000-layer boundary and atomic admission. Strict source comparisons remain unchanged and open, including three additional Intel assertions.

All eight new cases pass on both architectures. The affected totals are583/584 on Apple Silicon and582/584 through Rosetta, with no unexpected errors or crashes. Both source attempts and their raw executables survive. The first case-list inspector overlooked Intel stderr; reading both preserved streams proved that the same584 case IDs ran on each architecture.

An owned Photoshop Invert output supplies the numeric reference. Independent parsing confirms192 RGB bytes and64 unchanged alpha bytes in each native PSD export. The current universal app also passes the native shortcut, hidden Fill warning, Gaussian preview/cancel/commit/Undo/Redo and reveal checks, then closes the disposable document and quits. The input file remains unchanged.

S05 remains in progress; C01 stays next. Broader channel/filter contexts, exact profiles/kernels/defaults, the full current suite and physical platform/performance checks remain open. No binary was installed or uploaded and no software release was made. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-371).

## 2026-11-03 — Step372: Quick Mask targets; next major feature

C01, Component visibility and edit targeting, remains next after S05. Its scope includes independent channel eyes and editing targets, grayscale/color views, temporary mask rows, painting and filters, gestures and factory shortcuts. Native/API behavior, history and workflow tests are part of completion.

An owned Photoshop document exposed a shared dependency. Command2 selects RGB while leaving Quick Mask present and visible; component and saved-alpha shortcuts choose their own editing targets. The temporary mask has the next numbered shortcut. Q exits the mode even when RGB is selected. Photato had inferred the target solely from the mask's presence, so it could send an intended RGB edit to the mask.

The native target override is now scoped to the document and temporary mask. RGB and numerical components can receive edits without changing Quick Mask; alpha and temporary-row shortcuts share that state. API visibility changes only the eye, while API state reports the actual target. Native reopen and a new mask reset the session override. Full independent component/auxiliary visibility remains C01.

All six new channel-transition cases and all 293 affected optimized cases pass on Apple Silicon and translated Intel, with0 failed assertions,0 unexpected errors and0 crashes. The exact same ordered case IDs run on both architectures. All7089 frozen inputs and1010 production Swift files remain unchanged. Current universal native checks are recorded separately. The371 broader strict source comparisons remain open; these focused runs do not replace them or prove full Photoshop output equality. No app was installed, source pushed or software released. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-372).

## 2026-11-03 — Step373: Mask paint colors and remaining S05 work

The image foreground color was carrying into Quick Mask. Photoshop keeps separate image and mask colors: mask painting starts black/white, X swaps that pair, and RGB restores the image colors. An owned Photoshop document confirmed that the mask pair survives Q exit and re-entry. Its original foreground was restored and the file closed without saving.

Photato now remembers the image and auxiliary pairs when targets change. The API exposed another mismatch: changing a brush background did not change the native palette background. Both now agree, and included-color presets update it too. API state reports the active context and both pairs; no new command or Adobe route is added.

The first builds failed before tests because old brush presets can omit a background. The repair keeps the current background when it is absent. The failed attempt and its source survive; its retained executables are correctly identified as the older372 binaries, since373 had not linked. All eight new paint-color workflow cases and all 347 affected optimized cases pass on Apple Silicon and translated Intel, with0 failed assertions,0 unexpected errors and0 crashes. Both architectures run the same ordered case IDs. All7091 frozen inputs and1011 production Swift files remain unchanged.

The full S05 audit also identifies the next file-workflow gap: standalone Multichannel selections still pass through dense ink-plane storage and cannot reopen above8.4 megapixels. Auxiliary planes need the paged row decoder. That remains open along with application-global palette and full output/platform requirements. C01 stays queued. No app was installed, source pushed, uploaded or released. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-373).

## 2026-11-03 — Step374: Large saved-selection files

Standalone selections were still going through dense printing-plate storage when opening Multichannel PSD/PSB files. That imposed an8.4-megapixel limit even though native selections already supported paged storage. Auxiliary channels now use the bounded row decoder and paged tiles. Printing-plate capacity stays separate and remains open.

Independent Python fixtures cover8/16-bit PSD/PSB, raw/RLE/ZIP/prediction encodings,40.5 megapixels, maximum PSB side and every16-bit word. Photoshop opened the owned RLE input and saved both PSD and PSB copies. An independent reader verified every numeric sample. It rejected both ZIP PSB probes, so those are not qualified for Photoshop interoperability. Channel Unicode terminators and identifiers also needed repairs to survive saving and reopening.

The first native run passed269 of273 cases per architecture. The second passed272 of273, including every new case; its remaining version85 assertion compared against version11 bytes. The final test-only repair checks version85 bytes and decodes the response back to the model. All exported values were correct, but the new path allocated tiles for implicit black samples. The repair keeps those regions implicit without changing the pixel assertions. An older HTTP test also rejected native85 even though the format was already supported; it now positively checks85 and rejects86. All 11 new large-selection file cases and all 273 affected optimized cases pass on Apple Silicon and translated Intel, with 0 failed assertions, 0 unexpected errors and 0 crashes. Both architectures run the same ordered case IDs. All 7,118 frozen inputs and 1,011 production Swift files remain unchanged.

The live large-file check remains unqualified after unreliable chooser navigation; both test executables and resources are preserved. S05 stays open against its full requirements. C01 remains the next complete major function, covering independent channel visibility and real editing targets. No installation, source push, archive, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-374).

## 2026-11-03 — Step375: PSB file compatibility

The large selection opened and painted correctly in Photato. Undo removed the stroke, and the saved file retained every original sample. Photoshop rejected that output. The problem was in the file structure: wide tagged blocks had8-byte lengths preceded by the ordinary8BIM signature. Photoshop used8B64 for those blocks. An owned probe changing only the two signatures opened successfully.

The shared writer now pairs each supported block signature with its length width. The audit also found the same issue in16/32-bit layer-depth records, saved paths, mask-display records, embedded Smart Objects and Smart Filter caches. PSD and ordinary PSB block framing remain as before. Existing native/API saves use the same repair; no new route or format option is added.

The first build failed before tests because a new test passed a URL to the Data reader. That attempt is preserved; its retained executables were still the previous374 build. The test now uses the file reader. All nine new cases and all 356 affected optimized cases pass on Apple Silicon and translated Intel, with 0 failed assertions, 0 unexpected errors and 0 crashes. Both architectures run the same ordered case IDs. All 7,120 frozen inputs and 1,011 production Swift files remain unchanged. Independent output checks and the current native/Photoshop workflow are recorded separately.

Shared image/mask paint palettes and other S05 requirements remain open. C01 stays next with its full scope. No installation, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-375).

## 2026-11-03 — Step376: Shared paint colours

Photoshop carries foreground/background colours from one document to another. Its image and Quick Mask pairs are separate: a swap in Quick Mask survives a document change without replacing the image colours. Two owned RGB8 files confirmed that behaviour, including the exact d24a7e image foreground in the second picker. The probe files were closed without saving, and the entered original colours restored.

Photato now keeps both pairs in the document controller. Editors select the appropriate pair while retaining their own brush settings. Old copies cannot overwrite the live palette when targets change. Closed editors detach a snapshot. Palette changes update API revisions in other documents, and in-progress native strokes retain the colour captured at their start. Normal application startup uses a bounded preference record; snapshots and test controllers stay isolated.

The first candidate was cancelled after a test review found an impossible comparison of UUID-bearing layers from different documents. The corrected tests compare each document with its own original. The next diagnostic passed every new palette case but found an obsolete test expecting large Background clearing to be unsupported. That test now checks the working white clear and two-step Undo/Redo. The startup audit also found a second launch path needing explicit palette injection. All 11 new shared-palette cases and all 485 affected optimized cases pass on Apple Silicon and translated Intel, with 0 failed assertions, 0 unexpected errors and 0 crashes. Both architectures run the same ordered case IDs. All 7,121 frozen inputs and 1,011 production Swift files remain unchanged.

The current native workflow and preference restart are checked, with independent HTTP-state comparisons kept separate from pixel/CMM claims. S05 stays open against its full scope. C01 remains next. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-376).

## 2026-11-03 — Step377: App Store listing and media

The existing App Store Connect record was an empty1.0 draft. It now uses0.3.0, with copy describing the current editor, its alpha limitations, optional Apple AI and AI-aided development. The source-release policy and upstream attribution are included. Free pricing is saved across175storefronts, and automatic release has been changed to manual.

Four screenshots show a real layered composition, the opacity slider, brush work and Quick Mask. The original CoastalLight artwork was made for these captures. Its lettering is raster artwork, so the screenshots do not claim editable type. A27.478-second preview shows actual layer, painting and selection actions. The capture service limits source cadence; the video makes no physical frame-rate claim.

The first artwork candidate used the wrong layer order and was retained. Preview preparation also caught a timing overrun, an unavailable text filter and a full-range video-format mismatch. The passing export preserves real frame timings and uses separate caption cards. All824 output frames decode correctly. Four screenshots and one preview are uploaded; Apple is still processing the preview.

The privacy label is saved as a draft. Apple’s agreement, the content-rights declaration and private review-contact details remain pending. There was no binary upload, review submission or software release. Native source376 is unchanged. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-377).

## 2026-11-04 — Step378: App Store familiarity wording

The App Store description and promotional text now say: “If you know your way around a professional image editor, Photato will feel familiar.” The early-alpha disclosure remains clear. Generic reviewer-note wording is prepared locally, but the portal still has its prior private notes because the required reviewer contact is missing.

Apple’s keyword documentation explicitly excludes competing app and company names. The saved keywords therefore describe layers, masks, painting, retouching, colour, selections, PSD/PSB, brushes and open source. An initial same-tab reload appeared to show all four changes. The Save error then exposed missing contact fields; an untouched fresh tab confirmed only the three public changes persisted. The older private notes remain saved. Manual release remains selected; no build was submitted or released. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-378).


## 2026-11-04 — Step379: Multichannel Quick Mask files

Photoshop saves selection-only documents with Quick Mask active. Photato rejected them and required leaving the mode before saving. The shared Swift reader/writer now retains the temporary mask separately from saved selections and printing channels, including display options, identifiers and the initially-empty flag. Native SaveAs permits it, and standalone opening selects Quick Mask for editing.

All nine new cases and all494 affected optimized cases pass on Apple Silicon and translated Intel, with0 failed assertions,0 unexpected errors and0 crashes. Both architectures execute the same ordered case IDs. All7125 frozen inputs and1011 production Swift files are unchanged. Independent readers verify78 files/4480 samples. Real native brush/Undo/Redo/SaveAs passes; Photoshop opens that8-bit output and a16-bit RLE output with Quick Mask active. The initial failed new test compared internal tile storage outside document bounds; the corrected test checks every document pixel exactly. Production binary hashes did not change. Both attempts remain recorded.

The reused aggregate-report name and diary-format assumption were caught and corrected. Their initial helpers and failures remain. S05 remains in progress against its full scope; C01 follows after completion and testing. Cross-profile/custom-gray/layer-mask/component palette semantics, Photoshop restart defaults, full interoperability, current full suite, exact all-input output/settings/shortcuts, supported physical Macs, dense maximum capacity and sustained 60 fps remain unqualified. Prior371 broader strict comparison failures remain open. Native Float32 standalone selection storage remains supported;32-bit mode7 output remains unavailable after the observed Photoshop save failure. Printing plates retain their separate dense capacity limit. Prior ZIP PSB rejection is not cleared by native/independent decoder passes. No installation, source push, archive, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-379).


## 2026-11-04 — Step380: Mask paint-colour contexts

Photoshop remembers a mask colour pair separately from its image and Quick Mask pairs. A layer-mask colour also appears when selecting a Smart Filter mask. D uses white/black for these masks. Q returns to image editing when its own target is selected; if another mask is selected while Q remains, removing Q keeps that mask target. These observations came from owned test artwork and normal Photoshop controls. Original palette values were restored and the artwork closed without saving.

Photato now has the third shared palette, migration of the old preferences, target-aware D/X and the same native/API mask selection and painting path. Invalid or deleted mask targets fall back safely. The API retains the selected mask after supported brush/channel operations.

All 545 affected optimized tests pass on Apple Silicon and translated Intel, including eight new mask-palette workflow cases. There are no failed assertions, unexpected errors or crashes. Both architectures run the same ordered cases. The run uses 7,126 unchanged frozen inputs and 1,011 production Swift files. Independent checks cover128 colour components and256 mask samples. The first candidate was cancelled for new test-helper defects. The next test build caught a private-setter misuse; the following run correctly rejected a malformed RGBA-array fixture. Those attempts remain. The corrected test sends the existing object format and checks actual black mask pixels. Production binaries were unchanged by the test-only repairs.

The Mac locked before the current app could be inspected. Live acceptance remains pending; no successful screenshot is claimed. S05 remains in progress against its full scope; C01 follows after S05 is complete and tested. Current-build live UI is pending an unlocked Mac. General profile/custom-gray conversion, component colour contexts, Photoshop restart defaults, complete channel visibility/temporary rows/filter targets, full interoperability, the current full suite, exact all-input Photoshop output/settings/shortcuts, supported physical Macs, dense maximum capacity and sustained 60 fps remain open. Earlier strict comparison failures and ZIP PSB rejection are retained. Native Float32 standalone storage remains supported; 32-bit Multichannel output and full printing capacity remain unqualified or unavailable. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-380).


## 2026-11-04 — Step381: Mask target lifecycle

Returning from a Smart Filter mask had cleared its owner but left an editing flag set. Merge and Calculations still treated the document as a mask target, even after selecting RGB, previewing the composite or selecting all layers. Six new workflow cases reproduce five failures and21 assertions per architecture against unchanged build380. The document-read case passes as a control.

The repair clears filter-mask editing whenever its owner is cleared. It preserves viewing state so supported prepared mask edits can restore their captured target. Native and HTTP Merge now produce a single layer and one Undo, and busy rejection keeps the original valid mask. API availability/state/capabilities describe the same behavior; existing contracts and command counts remain.

All 698 affected optimized tests pass on Apple Silicon and translated Intel, including six new mask-target lifecycle cases. There are no failed assertions, unexpected errors or crashes. Both architectures run the same ordered cases. All 7,127 frozen inputs and 1,011 production Swift files remain unchanged. Independent analytical red8x8 comparisons verify1,024RGBAbytes across native/API and both architectures. The initial repaired attempt was stopped before tests after finding an invalid argument in the new HTTP capture helper; frozen source, partial logs, process cleanup and stale380 executables are retained. The corrected test uses the helper’s existing GET behavior.

S05 remains in progress against its full scope; C01 follows after S05 is complete and tested. Current native live UI awaits an unlocked Mac. General profile/custom-gray conversion, component colour contexts, Photoshop restart defaults, complete channel visibility/temporary rows/filter targets, full interoperability, the current full suite, exact all-input Photoshop output/settings/shortcuts, supported physical Macs, dense maximum capacity and sustained 60 fps remain open. Earlier strict comparison failures and ZIP PSB rejection are retained. Native Float32 standalone storage remains supported; 32-bit Multichannel output and full printing capacity remain unqualified or unavailable. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-381).


## 2026-11-04 — Step382: Current full test inventory

The last complete test run was at checkpoint 332. This pass discovers 3,845 unique cases in both current compiled bundles and runs every case in 21 fresh processes per architecture. The app and test source stay frozen at build 381. No existing result is reused.

All 3,845 discovered tests execute on each architecture in 21 fresh bounded groups. Apple Silicon: 3779 pass, 66 fail, 0 skip, 37 unexpected errors and 0 crashes. Translated Intel: 3771 pass, 74 fail, 0 skip, 37 unexpected errors and 0 crashes. This is a complete execution with failures, not a passing full suite. Raw logs retain every failed assertion, unexpected error and test identity. These test counts are not a measure of Photoshop functionality.

The installed Xcode discovery helper is ARM-only, so it could not list the Intel bundle. A small test-only helper using public XCTest APIs lists the same 3,845 test IDs from both bundles. Its dependency/name-format repairs and failed discovery attempts are recorded. A generated environment diagnostic was sanitized immediately; raw environment values were not retained.

The failures include old fixture assumptions and checks that still need functional diagnosis. The next repair pass starts with lifecycle/API failures and preserves the current Photoshop Background and mask-colour behavior. Strict Rust comparisons remain supporting diagnostics; Photoshop remains the reference. S05/C01 and the full original goal remain open. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-382).


## 2026-11-04 — Step383: Document lifecycle regression repairs

The complete baseline exposed generic fixtures that made invalid edits to protected Background layers. Those tests could not reach the recovery or closing behavior they were meant to check. They now use regular layers with the same factory pixels, dimensions, depth, profile and IDs. All original history, cancellation, permission and saved-byte checks remain. Production guards are unchanged.

A new test uses actual indexed recovery for opaque Background layers at all three depths. It checks the restored model and snapshot identity, supported painting, rejected rename, one Undo/Redo and unchanged backup bytes. The first repaired run passed 715 of 718 cases on each architecture; its remaining failures were stale native-version expectations.

The follow-up pins the existing native85/Actions44 inventories, extends positive indexed round-trips through85, and rejects86. It preserves minimum feature versions and corrupt-input/resource tests. The 40-million-pixel HDR/alpha fixture now uses a regular layer, and the layer-limit test checks 8,000 accepted/8,001 rejected instead of treating 65 as invalid.

All 740 affected optimized tests pass on Apple Silicon and translated Intel, including the new all-depth indexed Background recovery case. There are no failed assertions, unexpected errors or crashes. Both architectures run the same ordered cases. In this focused run, 43 previously failing full-baseline cases pass per architecture. The full current inventory has not been rerun. Production executables are byte-identical to381. This does not erase the full382 baseline or prove complete Photoshop parity. S05/C01, current live UI and all original global gates remain open. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-383).


## 2026-11-04 — Step384: Animated layer-style transactions

A style edit changed a private candidate, then validated it against the old keyframe or animation-frame state. Validation rejected the edit before the outer engine could record the new value. An existing regression and new native/API checks reproduced this on both architectures. The unchanged-code run passed one of six cases; the other five failed. All failed runs and source snapshots remain in the record.

The first repaired run passed 467 of 468 cases per architecture. The new 32-bit midpoint assertion had read an encoded display value; the renderer blends those pixels in linear RGB. The corrected test checks linear working values and independently checks encoded PNG output. The production blending path is unchanged.

The style transaction checks its source composition, then records the changed temporal composition before final validation and assignment. It retains the existing key identity and interpolation when replacing a key, changes only the selected animation frame, preserves movie/source pixels, and keeps invalid edits atomic. The API uses this same path for replacement, patch and clear. No new endpoint or file-format version is required.

All 476 affected optimized tests pass on Apple Silicon and translated Intel, including 6 new temporal-style regression cases. Both architectures run the same ordered cases with no failed assertions, unexpected errors or crashes. Independent checks cover 36 PNGs and 3,456 RGBA8 channel values. The full current test inventory has not been rerun. The independent samples check a red square with a blue overlay at authored times. They are regression evidence, not a claim of matching Photoshop pixels. Current live UI and full S05/C01 acceptance remain open. The store copy already followed the requested generic wording; no portal field was changed in this increment. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-384).


## 2026-11-04 — Step385: Fit Image and reusable batch constraints

The Automate menu listed Fit Image but had no implementation. Recording an absolute Image Size also failed to express a useful constraint for a batch with different aspect ratios. Fit Image now records the bounding box and enlargement policy, calculates each input’s dimensions independently and uses the existing native geometry engine. A fit that leaves a small image unchanged remains recordable without adding an Undo entry.

The native dialog, API and Actions share the operation. Image Processor now uses it for its existing per-format resize settings. The checks cover portrait and landscape sources, small images, all three component depths, source preservation, target identities, error guards, persistence and history. All 220 affected optimized tests pass on Apple Silicon and translated Intel, including 10 new Fit Image cases. Both architectures execute the same cases with no failed assertions, unexpected errors or crashes. Independent checks cover 30 PNGs and 2,032 exact RGBA8 channel values. The current full inventory has not been rerun. Independent files check authored white pixels and dimensions; photographic interpolation and Photoshop output are still unqualified. The initial Photato bounds and resampling policy are documented working defaults, not verified Photoshop defaults. S05 remains open, with C01 next after completion and testing. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-385).


## 2026-11-04 — Step386: Find and Replace Text

The Edit menu listed Find and Replace Text without an implementation. It now opens a native dialog with search scope, caret direction, case and word options. Find Next highlights the matching context. Change, Change/Find and Change All use the same rich-text replacement and shaping path as the API, with one Undo per edit. Search itself leaves the document and history unchanged. On-canvas Photoshop-style selection remains unqualified.

Replacements preserve untouched character/paragraph runs and use the first replaced character’s style for inserted text. Hidden or image-locked type layers, including inherited visibility/protection, are skipped. Native Actions46 retains the search policy, so Batch recalculates matches in each input rather than repeating previously baked text. Long Unicode layer names use the existing native capacity.

The first compilers rejected combined observable-property declarations before any test ran; that failed source and logs remain. Separate declarations repaired the compiler error. Review also corrected a narrow target-name guard and the new caret test’s baseline after the existing TextKit draft commit. All 16 new Find/Replace cases pass on Apple Silicon and translated Intel. Of 211 affected cases per architecture, 210 pass and one retained imported-text comparison fails with three assertions; there are no unexpected errors or crashes. A previous385run of the195existing cases reproduces that one failure with identical word counts. Independent checks cover 10 owned text/state outputs with 31 exact literal checks. The affected run fails; the current full suite has not been rerun. Independent owned output checks compare literal text/counts/ranges; they do not establish Photoshop glyph/pixel or default equivalence. A fresh native attempt still found the Mac locked. S05 remains open and C01 stays next after completion and testing. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-386).


## 2026-11-04 — Step387: Numeric component-plane storage

The component/printing modes still have an 8 megapixel limit. Lifting it safely needs storage that can retain exact numeric values and history without allocating a complete plane per edit. We added raw blocks of 4,096 samples, implicit uniform fills, bounded row transfers and private immutable mapped snapshots. InkPlane now uses shared blocks; legacy file bytes and capacity guards remain. Rendering/export loops use exact sample reads to avoid repeatedly exporting whole planes. API metadata describes the backing and unchanged limit.

All nine new numeric storage cases pass on Apple Silicon and translated Intel. Of 139 affected cases per architecture, 138 pass and one retained master-palette case reports an unexpected CancellationError; there are no crashes. Preserved build 386 test bundles reproduce that same cancellation. Two other retained test failures are repaired by updating obsolete command-count expectations. Independent Python packing verifies 40,136 raw bytes from eight owned outputs. The affected run fails; current full execution has not been rerun. Tests also cover cancellation, invalid ranges, admission/I/O failures, negative zero, snapshot ownership and concurrent history branches. The maximum-size sparse tests are sparse storage checks, not full-document rendering/save/performance qualification. All 104 package scopes and 651 menu identities stay intact. S05 remains open; C01 stays next. No installation, source push, archive, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-387).


During the final evidence check, three old temporary candidate binaries from builds 284–286 were missing. Their source, logs and recorded hashes survive, but the original binary bytes were not retained in those run folders. The remaining 37 protected files match. Build 387 source and complete test/binary evidence are retained; this does not recover the missing historical binaries. The final verification reports that preservation gap separately from current build checks.


## 2026-11-04 — Step388: Native component blocks

Native component storage now uses shared raw blocks. Uniform conversion and display/channel preparation no longer fill a dense plane. Local edits retain untouched sample words; geometry and TIFF access preserve raw order. Native85/Actions46and242API commands keep their existing contracts, with backing/limit metadata added.

All 14 new native-component and Surface-equality cases pass on Apple Silicon and translated Intel. The broadened run executes 1184 identical ordered cases per architecture; Apple Silicon passes 1182, translated Intel passes 1175. Six regressions from the earlier storage attempt now pass without changing their assertions. Independent Python packing checks 40,248 raw bytes from 14 owned outputs. Retained failures are listed in the evidence; this is not a passing full suite. The first compiler failure and earlier six document/cache regressions remain in the evidence. Their existing assertions were not weakened; Surface equality now checks logical sample bits across implicit, owned and mapped storage. Broad qualification includes all Core cases because equality is shared. Application limits remain8MPuntil component file streaming and operation integration are complete. S05, full Photoshop/platform/performance requirements and historical binary gaps remain open. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-388).


## 2026-11-04 — Step389: Private source backup

We backed up native build 388 before changing component file storage. Every included tested input matches the frozen source. Generated models, caches, machine/signing/runtime files and an externally restricted PSD remain excluded. The original Rust source and existing Git history are preserved.

The commit includes current native source, tests, Xcode project, assets, scripts and records. Its notes retain the actual test results: all 14 new cases pass; the broader run has two remaining ARM failures and nine Intel failures, all reproduced by the prior baseline. No new native test run is needed for this delivery because the tested code and configuration are unchanged. The repository remains private and no application binary is uploaded or released. Component streaming remains next; S05/C01 and full parity gates stay open. [Receipt](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_389.json).


## 2026-11-04 — Step390: Component archive streaming

Native86 and history now use a bounded raw-component tree, with4096sample blocks,1024-entry leaves and256-reference branches. The decoder validates exact words, geometry, alpha, padding, tree order/counts, budgets and failures before publication. Existing APIs advertise/accept86; older requested versions retain their previous layouts. No tools or shortcuts change.

All18 new component archive/history/API cases pass on Apple Silicon and translated Intel. The broadened run executes1217identical ordered cases per architecture, passing1215ARM and1208translatedIntel; remaining failures reproduce on preserved388. Independent Python verifies57,351logical sample bytes and86,016raw block bytes per architecture. This is a focused affected run, not a passing current full suite. The first compiler failure and its repair remain recorded. Application admission remains8MP; complete operation/metadata/codec integration and original Photoshop/platform/performance gates stay open. The Desktop package later failed signature checking after Finder metadata appeared. A copy outside Desktop and a ZIP extraction preserve every file byte and pass signature checks; the original failed candidate is retained. No installed preview, repository push, Xcode archive, App Store change, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-390).


## 2026-11-04 — Step391: Large native component documents

Logical native component geometry is now separate from dense-operation limits. Owned/mapped accounting reaches document, history/recovery and API admission; implicit fills and local blocks let sparse300,000²documents pass creation, conversion, channel/brush edits, native86save/reopen, viewport rendering and Undo/Redo tests. Dense exports/tools still report their unfinished limits. Public Swift planes access now throws instead of allocating a large logical plane. Existing byte assertions add try without being weakened.

All 13 new cases pass on Apple Silicon and translated Intel. The broadened run executes 1,481 identical ordered cases per architecture, passing 1,478 on Apple Silicon and 1,470 on translated Intel. Remaining failed IDs and assertion counts reproduce on preserved build 390. This is an affected run, not full-suite success. A viewport failure exposed native buffers in a scalar render comparison; they are stripped only after exact equality. An independent maximum-file reader validates stored words but its cross-architecture Gray32default comparison fails by one ULP. That remains a colour-fidelity gate. All original Photoshop/S05/platform/dense/60fps requirements stay open. No installation, source push, Xcode archive, App Store action, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-391).


## 2026-11-04 — Step392: Large component geometry

Component resampling, expanded canvas framing and Trim now work through bounded native storage. Shared checked scratch, direct numerical sampling and bounded derived caches keep the source intact on cancellation, I/O or admission failure. Existing native/API history transactions use the same implementation.

All 19 new cases pass on Apple Silicon and translated Intel. The affected run executes 1,547 identical ordered cases per architecture, passing 1,543 on Apple Silicon and 1,535 on translated Intel. Every remaining failed ID and assertion count reproduces on preserved build391. This affected run retains failures; the full current suite has not been rerun. The failed compile typo and downscale cutoff are preserved with their repaired reruns. Independent owned kernel checks pass; Photoshop, physical dense/platform/60fps and the prior Gray32comparison remain open. S05 is not closed. No install, push, Xcode archive or App Store release action. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-392).


## 2026-11-04 — Step393: Large component tools

Individual colour-channel Fill, Invert, Brush/Eraser and eight basic filters now use bounded storage beyond the former eight-megapixel guard. The small implementation remains unchanged for regression comparisons. Forward selection samples, native untargeted planes and alpha, history and API availability are checked.

All 12 new cases pass on Apple Silicon and translated Intel. The affected run executes 195 identical ordered cases per architecture, passing 194 on Apple Silicon and 194 on translated Intel. Remaining failed IDs and assertion counts reproduce on preserved build392. The full current suite has not been rerun. The stopped maximum Motion Blur attempt, exact binary shortcut, fixture compilation error and repaired run remain documented. Independent owned sample checks pass. Full Photoshop, dense capacity, current live/platform/60fps, prior Gray32comparison and full S05 requirements remain open. No install, push, Xcode archive or App Store release action. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-393).


## 2026-11-04 — Step394: RGB8 component routing

Ordinary RGB8 selected-channel tools now share the native component engine. The legacy target/view/API state and neutral Fill label remain. Held brush previews, captured release, filters, Undo, cancellation, maximum RGB8 edits and temporary Quick Mask/image transitions are covered.

All 13 new cases pass on Apple Silicon and translated Intel. The affected run executes 335 identical ordered cases per architecture, passing 335 on Apple Silicon and 335 on translated Intel. Three stale command-count assertions reproduce on preserved393 and are corrected to the unchanged242-command catalog. The full current suite has not been rerun. The maximum guard-order bug, nonneutral API/UI mismatch and stale count assertions remain recorded with the repaired rerun. No test identity or source is removed. Full Photoshop/S05/C01/platform/dense/60fps requirements and prior strict/Gray32failures stay open. No install, push, Xcode archive, upload or release. [Record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-394).


## 2026-11-04 — Step395: Private source backup and listing wording

We backed up native build 394 after its 335 affected tests passed on each architecture. All 13 new RGB8 component tests pass. Every included tested input matches the frozen source; generated models, caches, machine/signing/runtime files and an externally restricted PSD remain excluded. The original Rust source and existing Git history are preserved.

The commit includes native source, tests, the Xcode project, assets, scripts and developer records. We verified the staged file bytes, source commit/tree on GitHub and continued private visibility. No new native test run was needed because tested application code and configuration are unchanged. Current full-suite, live UI, physical supported platforms, dense capacity, 60 fps and exact Photoshop qualification remain open. Full S05 stays open and full C01 follows it.

The maintainer asked that App Store blurbs avoid named Photoshop comparisons. The current files and step378saved record already use familiarity with a professional image editor. Rechecking Apple's search guidance confirms it excludes competing app names from keywords, so functional and file-format terms remain. The browser is at sign-in; no new App Store write or fresh field verification is claimed. The private review-note edit remains pending contact details. Free pricing and manual release stay unchanged. [Delivery receipt](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_395.json).


## 2026-11-04 — Step 396: Large native channel arithmetic

Apply Image and Calculations New Document had separate 8 MP guards in native component storage. We replaced those large-document paths with bounded numeric projections and immutable component output, while keeping the small-document arithmetic and initializer. Existing native sheets and APIs use the same preparation and transaction.

The first run passed 101 of 102 affected cases on both architectures. A new HDR assertion expected 5 but omitted the existing partial-transparency step; the scalar result is 4. We corrected the expectation and added a dense comparison. A maximum expansion also took 88 seconds. Sampling traced it to scanning the entire output during identity resampling; large integer expansion now uses exact raw reframing. The failed run, sample, correction and tested source/binaries remain saved.

The second run passes all 103 affected cases on both architectures, including 13 new cases. The expansion case takes 0.013/0.019 seconds in those runs. Independent Python checks verify literal 8/16/32-bit gray and opacity words at three positions. Native/API preview/cancel/commit, Undo, transfer policy, invalid/busy/stale handling and native86 reopen pass. A universal package and its extracted copy pass signature/hash checks. The reporting script initially read Intel stdout instead of stderr; that failed postprocessing attempt and its repair are recorded separately from application test outcomes.

Full 3,989-case execution, Photoshop output/ICC/defaults, current live UI, physical supported systems/dense capacity and sustained 60 fps remain open. The Mac is locked. Full S05 and C01 scopes are unchanged; no software release is made. [Evidence](../PhotoCraftSwift/docs/LARGE_CHANNEL_ARITHMETIC_396.json).


## 2026-11-04 — Step 397: Independent channel eyes

Saved alpha/spot eyes formerly selected the channel and the renderer displayed one auxiliary plane. The new session view separates eyes from the editing target, combines saved masks in document order and shares bounded presentation with the canvas and API. Native eye buttons support click, drag, accessible state and cancellation. Reopening clears the view; Undo can restore a deleted channel’s prior visibility.

The first run passed 306 of 312 affected cases per architecture. A fresh run of the retained build reproduced five of the six failed cases. We restored the isolated layer-mask viewing guard for the new regression, repaired three obsolete command-count assertions and made a palette test’s starting image/ink explicit. We also added missing partial-alpha neutral component Fill support rather than weakening its workflow expectation. A repair script stopped midway on whitespace; that partial state and failure were preserved before completing the repair.

The second run passed all 316 cases per architecture, including 26 new cases. The extra Fill/component run stopped at its first async test after two document lifecycle tests; its caller did not retain the native exit code. Starting with the existing HTTP initialization test let all 39 extra cases pass. The runner then incorrectly rejected XCTest’s grouped case order. The actual ordered lists matched between architectures and contained every requested case; that reporting correction is recorded separately. The initial unsuccessful attempt remains in the evidence.

Native UI access became available. In disposable documents, we checked two saved masks, independent eyes, a native process-eye sweep, image painting beneath overlays and Undo. Photoshop showed that selecting RGB or Red clears saved mask eyes, while toggling eyes keeps the target. The earlier implementation kept those eyes on row selection, so we corrected that behavior and added an HTTP regression. The temporary documents were discarded; the existing Photoshop document was left intact. Exact Photoshop sweep traversal was not established by the synthetic reference drag.

The third run passed all 370 cases on each architecture. A live check then found that re-selecting an already-selected RGB row hid the saved eye but left the red overlay on the canvas. We added the missing redraw condition and strengthened the HTTP test to check the actual awaited canvas and revision. That failed native interaction and its screenshot remain saved.

The final Source04 run passes all 370 affected cases on each architecture, including 27 new cases. Independent Python checks verify four literal 2×2 RGBA outputs. The corrected universal package and extracted copy pass signature/content checks, with macOS 14 minimums in both slices. Current 4,016-case discovery is not full execution. Full S05/C01, exact output/defaults, all supported physical systems, dense capacity and sustained 60 fps remain open.

App Store wording still describes familiarity with a professional image editor, without named Photoshop comparisons. Free pricing and manual release policy stay unchanged; no new portal write is claimed. [Evidence](../PhotoCraftSwift/docs/CHANNEL_VISIBILITY_397.json).


## 2026-11-04 — Step 398: Temporary mask channels

The next mask-workflow gap is in the Channels panel. Photato already has layer-mask and Smart Filter-mask edit targets and gray/overlay views, but their temporary channel rows are missing.

We checked Photoshop on an owned 256×256 RGB document. A layer-mask row stays available when returning to RGB; selecting its name changes the edit target, while its eye changes display. With image channels hidden, the mask can be viewed in gray. A vector mask appears in Paths rather than as another raster channel. Quick Mask and saved alpha channels can coexist with these rows.

After adding a Smart Filter and a new pixel mask, both raster-mask rows are visible. Backslash toggles a mask overlay without changing RGB editing. The observed shortcut chooses the layer mask in the tested RGB context when both masks exist. Row ordering and naming vary during creation and need further checks. Thirteen reference screenshots are retained; the owned document was discarded and the prior Photoshop document was left unchanged.

The next implementation will connect those rows to native target selection, independent visibility, previews, the applicable shortcut and the API. At the maintainer’s first diary refresh, no application code had changed yet and build 397 remained the tested software. Implementation and testing followed that reference investigation. [Investigation](../PhotoCraftSwift/docs/MASK_CHANNEL_ROWS_398.json).


The native rows and API are now implemented. Testing first caught an assertion looking at the editor’s projected mask instead of the stored layer. After correcting the inspection, an actual API issue remained: Fill rejected a selected Filter Mask. Its prepared transaction now accepts the matching mask and retains the target. Source review also found that row availability had used the same projection; it now reads the stored owner, with a Filter-Mask-only case to prevent a phantom row.

All 404 targeted cases pass on both architectures, including 16new cases. Independent checks cover560 literal display and stored-mask bytes each. The universal build 398 package passes signature and extraction checks. In the actual app, both mask eyes retain RGB editing; Filter Mask can be viewed in gray, painted and undone. The Filter-Mask-only file keeps one temporary row after selection. A screenshot comparison initially included the brush cursor; the retained correction checks the canvas away from it. No raw output tolerance was changed.

This completes the398 increment, not the full mask/channel package. Footer commands, display options and further factory gestures remain, along with the original full-parity gates. No installation, source push, App Store upload or software release was made. [Build 398 evidence](../PhotoCraftSwift/docs/TEMPORARY_MASK_CHANNELS_398.json).


## 2026-11-04 — Step 399: Consolidated S05 validation

S05 had drifted into adjacent Channels work. This step returns to its Quick Mask and saved-selection requirements and runs a single consolidated set of 195 cases. The current inventory contains 4,032 cases; only the selected set executes here.

The first pass ran 194 successfully on each architecture. The remaining test expected 239 API commands, although the catalogue already contains 242. Its actual HTTP, file encoding, decoded mask and history assertions passed. Only the stale count was corrected, using the shared expected-count constant. The rebuilt test bundles pass all 195 cases on both architectures. The application executables are byte-identical to build 398.

The native check uses disposable RGB8 artwork. Options Cancel preserves the starting defaults; OK retains a changed indication and opacity within the process. Black and white paint change mask coverage, Q returns to the selection, and image colors return. Save/Load, a q-containing name field, cancellation, subtraction and Undo/Redo work. Save Selection into a new document produces a standalone channel; that document can supply a selection to the original image. Saving and reopening a native file retains alpha and active Quick Mask together.

File-picker automation also had failed attempts. A reordering file list initially left the chooser open; exact-path selection established the actual reopen later. Format-popup navigation did not select PSB and produced two disposable native files. They remain in the evidence. This pass makes no new native PSB-export or Photoshop-reopen claim. Earlier PSB interoperability checks and current automated codec/API results remain separately recorded.

The consolidated pass is finished. Full S05 acceptance stays open for the remaining independent settings, gestures and original output/platform requirements. Custom-color restart checks were not performed in this native subset. The old locked-Mac wording has been corrected in the current assessment while earlier records remain intact. No installed app, repository delivery or App Store record was changed. [Validation](../PhotoCraftSwift/docs/S05_VALIDATION_399.json) · [Requirement assessment](../PhotoCraftSwift/docs/S05_ACCEPTANCE_399.json).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-04.md) · [Next page](part-02.md)
