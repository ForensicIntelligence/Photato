[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-02.md)

## 2026-11-06 — Step 445: Public repository credential audit

At the maintainer’s request, checked the newly public [GitHub repository](https://github.com/ForensicIntelligence/Photato) for secrets. A fresh public mirror contains 69 commits and 10,680 unique historical file versions, totaling about 2.63 GB. Full history, every unique file version and commit metadata were scanned with Gitleaks 8.30.1. Its download was checked against the official release checksum. A separate byte scan checked provider-key formats, private keys, literal passwords and credential URLs; historical filenames were checked for credential files.

No exposed real credentials were found. Every scanner candidate was reviewed. The history findings include 145 SHA256 digests that match actual committed file bytes; the remaining matches are prose, JSON property names and a TIFF metadata enum. The separate scan found only test inputs: passwords for owned encrypted-PDF fixtures, deliberately wrong passwords and synthetic credential URLs used in rejection tests. Fixture provenance explicitly documents the test-only password. No credential was sent to a service for validation.

GitHub secret scanning and push protection were disabled and are now enabled. GitHub currently reports zero alerts; completion of its initial background scan is not inferred. Generic/non-provider scanning remains disabled on GitHub, so the independent scans also covered generic patterns. No public releases or Actions artifacts were present. The five existing prerelease drafts remain unpublished. Raw candidate values stay private, outside the repository. [Audit report](../PhotoCraftSwift/docs/SECRET_AUDIT.md) · [Evidence](../PhotoCraftSwift/docs/SECRET_AUDIT_445.json).

This changed no app code, tests, API, menu, shortcut or cursor. No new build, source upload, history rewrite or software release was needed. Custom Shape Blur resumes from checkpoint 444’s retained numerical failure; F01 remains current, then F02.

<a id="dev-step-446"></a>

## 2026-11-06 — Step 446: Custom Shape Blur reference and native validation

The first custom-kernel comparison assumed a binary shape mask. An owned Photoshop triangle and impulse image showed that assumption was wrong: edge cells receive fractional coverage, the footprint spans 2r+1 pixels, and convolution preserves the kernel’s orientation around an impulse. We saved 8-bit PNG and uncompressed 32-bit PSD outputs through Photoshop’s normal interface, checked the public PSD records, and retained the raw planes and provenance. No Adobe artwork or proprietary implementation was copied.

The Swift custom path now uses antialiased coverage and weighted convolution. Original built-in kernel arithmetic and previous fixtures are unchanged. An independent square/direct-sum check passes at all three depths. Two new exact Photoshop byte tests remain red: one coverage rounding difference changes 3 bytes in the owned RGB8 output and 435 bytes in RGB32. We retained the incorrect earlier model with its frozen source, replaced that new expected model with observed references, and kept exact assertions without increasing tolerances or patching an individual sample.

The original selector also expected 55 methods, rather than the 43 reported outcomes. Its process stopped after 43 with signal 10; earlier entries incorrectly omitted that failure. The same Adobe-job Debug method fails in preserved 443 and 446 binaries. We excluded only that reproduced method from focused Debug and kept it in normal optimized qualification, where it passes on both architectures. Debug executes 56 methods, with 54 passing; optimized builds execute the same 57 methods each, with 55 passing. The two strict Photoshop tests account for the failures. All nine new functional methods pass. Frozen inputs, 10,760 normal products, logs and failed attempts are retained. A postrun evidence-script syntax error and subsequent missing-proof rejection were repaired without rebuilding the app.

Both architectures package into a universal app with macOS 14 deployment metadata. Signature and extracted ZIP checks pass. The first isolated validation signature omitted user-selected file access; AppKit’s error log identified it, and the project’s existing App Store entitlement already provided the correct permission. A second validation signature used that permission with the same compiled code and resources. In the running app we opened our PNG, defined an owned shape, chose it in Shape Blur, checked local Undo/Redo, committed, and checked document Undo/Redo. The file stayed unchanged; the app was quit normally. Early native path/popup observations lagged actual state, so failed attempts and the automation reset are recorded separately rather than counted as passes.

F01’s remaining functions and exact output/default/platform/performance requirements remain open. Under the breadth order, F02 is next: Photoshop ACF Custom Kernel preset Load/Save, shared API conversion and retained JSON compatibility. Source inspection confirms the current controls are JSON-only; implementation has not started. All 104 original scopes and 652 command identities remain. No source upload, app installation, App Store change or software release accompanied this checkpoint. [Evidence](../PhotoCraftSwift/docs/CUSTOM_SHAPE_BLUR_446.json).

<a id="dev-step-447"></a>

## 2026-11-06 — Step 447: Custom Filter ACF presets

Custom Filter previously loaded and saved JSON only. It now supports Photoshop ACF files through the native Load/Save dialogs and optional API. We created an asymmetric preset in Photoshop with distinct values, including negative weights, and checked the file against the public format description. It contains 27 signed big-endian values: 25 kernel weights, Scale and Offset, in 54 bytes. No Adobe preset or implementation code was copied.

The shared Swift codec rejects malformed lengths and out-of-range values. JSON remains available for existing presets and fractional Scale/Offset settings. ACF cannot represent those fractions, so Save selects JSON and disables ACF instead of rounding. The new `filter.custom.preset` API converts bounded base64 data or settings using the same codec. It returns the existing filter recipe without editing a document or history; `filter.apply` remains the editing path. Schemas, capabilities and error checks were added. The typed catalogue has 257 commands; native format 87 and portable Actions 52 are unchanged.

Six preserved build attempts record the problems encountered. The first used an unavailable Save-panel property and failed compilation. The next two runs passed all new tests but found old catalogue counts; one rerun was unnecessary because its repair preparation failed before making a change. The corrected tests passed, but the actual native dialog exposed a doubled filename extension. Giving AppKit an extension-free name fixed that. Actual sandbox Save then failed despite passing ordinary unit writes. The small preset publisher now coordinates an atomic write to the selected file, using the existing production entitlement. The generic streaming writer and pixel math were left unchanged. Other native export paths require their own file-access audit; this does not claim they are all broken or repaired.

The final source passed all 36 selected Debug tests, including 13 new tests, with no unexpected failures, signals, skips or missing cases. The app built in 43.33 seconds and tests ran in 8.479 seconds. We retained 7,378 frozen inputs and 5,384 Debug products. Changes to 20 old test files were confined to current command counts and one owned test window's lifetime flag; numerical assertions and old fixtures remain unchanged.

In the actual sandboxed app, Load showed all 27 values correctly. Local Undo/Redo, ACF and JSON Save, filter commit, document Undo/Redo and normal Quit passed. Photoshop then loaded Photato's ACF and saved it again: the original, Photato export and Photoshop reexport are byte-identical. The original image stayed unchanged. These checks cover the selected preset workflow on this Apple Silicon host; no optimized, Intel, universal or full-suite checkpoint 447 result is claimed. Checkpoint 446 remains the latest optimized universal qualification, with its two strict Shape Blur failures still open.

F02's remaining catalogue, capacity, depth, descriptor and exact-output requirements remain open. The breadth queue moves to F03 Blur Gallery, then F04. We also rechecked the unchanged public repository and private audit evidence: no exposed real credentials were found, GitHub reports zero alerts, and secret scanning and push protection remain enabled. No source upload or software release was made. [Preset evidence](../PhotoCraftSwift/docs/CUSTOM_KERNEL_PRESETS_447.json) · [Credential recheck](../PhotoCraftSwift/docs/SECRET_AUDIT_447_RECHECK.json).

<a id="dev-step-448"></a>

## 2026-11-06 — Step 448: Save Blur Gallery masks

Photoshop's Blur Gallery can save a blur mask to the Channels panel. Photato had a mask preview but no reusable channel output. An owned five-pixel Field Blur reference also showed that our preview scaled coverage incorrectly: Photoshop saves full white for a uniform positive field. We added Save Mask to Channels and made preview and saved output share one calculation. Photoshop also confirmed the second channel name, Blur Mask 2. An Iris mask was captured for further comparison; its geometry and exact values are not yet qualified.

The filter and channel are prepared on a private document copy and commit together. Existing channels and selection survive. Cancel, invalid inputs, protection, channel limits, cancellation and revoked API access leave neither half applied. Smart Filter re-editing uses the input before the edited filter. Large empty canvases retain sparse storage; the current source and transformed mask processing bounds are 8,388,608 pixels, so full dense maximum-size support remains unfinished.

The native checkbox starts off. The optional `filter.blurGallery.apply` command offers the same output flag and Smart Filter re-editing, with schemas, availability and workspace state. Portable output Actions use format 53 and resolve layer targets and filter indexes at playback. Native document format 87 and ordinary filter recipes remain unchanged. No new Adobe endpoint or action descriptor was invented.

The first build failed because the new command was missing from an exhaustive routing guard. The next build passed ten methods, failed an exact constant-normalization assertion, then crashed in the new HTTP Smart Object test. We retained both runs. Debugging our own frozen test binary showed a worker stack exhausted beneath a redundant nested command transaction. Keeping one outer transaction and calling the same modular pixel/channel engines directly repaired the selected case. Uniform Field coverage now has an exact constant proof; the assertion was kept. This does not identify or repair earlier unrelated crashes.

The final source passed all 31 selected Debug methods, including 11 new ones. Optimized builds ran the same 57 methods each, covering 24 new methods across checkpoints 447–448; all passed on Apple Silicon and Rosetta. We retained 7,383 frozen inputs and 10,772 optimized products. Old filter math, settings, imaging code, fixtures and numerical assertions are unchanged. Changes to 37 old test files only update current command and maximum Actions counts.

Both architectures package with macOS 14 deployment metadata. Signatures and extracted ZIP contents verify. In the actual sandboxed app we set Field Blur to five pixels, checked the white mask preview, enabled Save Mask to Channels and committed. One Undo removed both the edit and mask; Redo restored them. Reopening started with the output option off, and Cancel after enabling it created no extra channel. Final Undo restored the owned image, and the app quit normally without modifying the original file.

Full F03 remains open: endpoint controls, Selection Bleed, Focus, High Quality, larger processing, editable Photoshop descriptors and remaining output-recipe behavior still need work. Nonuniform, combined, selection and transformed masks need independent comparisons, as do defaults and pixel outputs. Physical Intel/macOS14, full regression and 60fps remain unqualified. The next work is the authorized source/build backup of this qualified checkpoint, then Liquify and lens workspaces. No software release was published. [Evidence](../PhotoCraftSwift/docs/BLUR_GALLERY_MASK_448.json).

<a id="dev-step-449"></a>

## 2026-11-06 — Step 449: source and unpublished build backup

The qualified build 448 source is on public GitHub, including the Xcode project, tests and development records. Every one of the 7,349 included frozen inputs matches the tested snapshot. Thirty-four generated/model/cache/restricted inputs are explicitly excluded, and all 1,057 original Rust files are unchanged. Existing Git history is preserved. A documentation-only follow-up records delivery verification.

The universal app uses the retained optimized Apple Silicon and Intel binaries, production bundle identifier and unchanged sandbox entitlements. It includes the verified optional model with its Apache license, credit and conversion notice. This package was not launched in the production container. It is ad-hoc signed and not notarized. No application code or tests changed during this backup.

All four draft files were uploaded, downloaded and compared by hash. The downloaded app signature and all 18 packaged file contents match. The five earlier drafts are unchanged. This remains an unpublished alpha backup; software releases require manual approval and Photato remains completely free.

Before upload, full source/build scans and an independent byte/name scan found no exposed real credentials. Every scanner finding was reviewed as a verified digest, existing prose/key or intentional test input. Raw candidates stay private. GitHub secret scanning and push protection remain enabled, with no alerts at recheck. This is evidence for the pinned revision and assets, rather than a guarantee for future changes.

The readable diary's index had stopped at 426 although later entries existed. Its missing 427–449 rows now come from the recorded milestone dates/titles. The standalone diary and website mirror are regenerated from these records.

The software remains 448: 31 focused Debug and 57 identical ordered optimized methods per architecture passed, including 24 new across 447–448. Earlier numerical and wider-suite failures remain open, as do all 104 full scopes. Next is F04 Liquify, then F05. No new API operation, Adobe route, menu, shortcut or modifier cursor was introduced. [Source](https://github.com/ForensicIntelligence/Photato/commit/77b14d5eedf88f5b70dab96b9d8140d1fbc121c3) · [Delivery record](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_449.json).

<a id="dev-step-450"></a>

## 2026-11-06 — Step450: Liquify last mesh reuse

Liquify already had its main brushes, freeze/thaw and face sliders. It lacked a separate last-mesh path: applying another filter replaced Last Filter, leaving no quick way back to the previous Liquify program. Load Last Mesh now copies the last committed program into a new draft, with local history and Cancel. OK uses the same undoable document edit as before.

The default app retains one program across launches. Writes run in order, replace files atomically and finish before normal Quit. An unreadable file is preserved; a write failure keeps the current mesh usable for the session and reports the problem. A later successful edit can retry saving. Closing the source document preserves the shared cache and detaches a separate memory snapshot. Source image pixels are not stored in it.

The optional API exposes the program and any persistence warning through filterRecall state. Clients apply the reported settings with the existing filter.apply operation. State schema, discovery and revisions include the cache. There is no new command, Adobe route or document/Actions format. Existing zero/current-target coordinate semantics are preserved. Photoshop mesh files and exact last-mesh size, freeze, face and persistence behavior still need comparison.

The first build found two catch-block property assignments that needed self.error. After that repair, 32 of 33 methods passed. The failing new Smart Filter fixture used the layer ID from before conversion; conversion creates a new target. We corrected that fixture and strengthened the HTTP test to retrieve the reported program through the actual document-state route before applying it. All 33 methods then passed, including all eleven new tests. Failed attempts and 5,386 Debug products are retained. Old Core/Imaging math, fixtures and tests are unchanged.

An isolated arm64 Debug app has verified signing, macOS 14 metadata and unchanged sandbox entitlements. Its unsigned executable payload matches the tested binary. It has not been launched or installed. Light/Dark offscreen captures show the loading state; they do not qualify ready-state controls, live interaction or VoiceOver. The Mac unlock request is still pending. Optimized universal qualification remains build 448.

This selected workflow is implemented and tested in Debug; full F04 and earlier numerical/full-suite failures remain open. Work moves to F05, then F06 under the existing seven-pass order. No source push, App Store change or software release occurred. [Evidence](../PhotoCraftSwift/docs/LIQUIFY_LAST_MESH_450.json).

<a id="dev-step-451"></a>

## 2026-11-06 — Step451: Local build cleanup; lens-default audit

The local build history had grown to roughly 400 GB. At the maintainer's request, we removed 1,252 superseded product paths: old compiled app and test bundles, packaged ZIPs, validation staging directories, nineteen numbered installed previews and the older Xcode archive. Measured available space increased by approximately 277.1 GB, reaching 312.5 GB after verification.

The current Debug 450 and optimized universal 448 builds remain, along with the current production package, both working compiler caches, the installed default and Verified apps, the latest installed preview and Xcode archive 332. All 16,311 protected files and 7,385 current source/build inputs match their saved hashes. Strict signature checks pass for the current development and packaged apps. The Xcode project and source backups are intact.

Original source snapshots, test fixtures, reference artwork, build manifests and test/crash logs were kept. Old copies of fixtures inside retired compiled test bundles were removed with those builds. Earlier entries that say a binary was retained describe its status at that checkpoint; this cleanup deliberately removes those superseded payloads. Their manifests and test results remain as historical evidence, rather than as a promise that every old binary can still be run locally.

No GitHub commands were run. No repository content, release, tag or uploaded asset was removed. There was no source push, App Store change or software release, and this cleanup did not alter application code or API behavior.

Before the cleanup request, we audited camera-linked Lens Correction defaults. Existing manual controls and settings-file import/export already work. Saved defaults matched by camera, lens, focal length and aperture, plus Previous Conversion, are the selected next work. That implementation has not started. F05 remains current, followed by F06; no feature package was closed by this housekeeping step. [Evidence](../PhotoCraftSwift/docs/LOCAL_BUILD_CLEANUP_451.json).

<a id="dev-step-452"></a>

## 2026-11-06 — Step 452: Camera and lens defaults

Lens Correction had manual controls and settings files, but no defaults tied to the image's capture metadata. It now reads the camera make/model, lens model, focal length and aperture from supported EXIF/XMP data. Users can save a correction for an exact match. New drafts load it automatically; the Settings menu can recall Lens Default, Previous Conversion or Default Correction with local Undo/Redo.

Defaults belong to application preferences, separate from image edits. Set and Remove do not make the document dirty. Cancel leaves an explicitly saved default intact, while Previous Conversion changes only after a successful correction. Existing Smart Filters, Actions and Last Filter retain their explicit settings. Saved records are bounded atomic files. Corrupt files are preserved, removal retires them, and a write failure reports a warning while retaining usable settings.

The optional API adds filter.lens.defaults with the existing preference-change permission and request guards. It reports identity, settings, availability and warnings, and uses filter.apply for actual editing. There are now 259 typed commands; document version 87 and Actions version 53 are unchanged. No Adobe route or unsupported Lens Correction descriptor was added.

The first new test build failed because a helper needed explicit actor isolation. After that test-only repair, all 32 methods passed. Native same-session controls also worked, but checking the saved directory found that settings were not reaching disk. Actual executable startup used a designated initializer and omitted both persistent filter libraries. The earlier last-mesh convenience-initializer tests did not exercise that path. We corrected actual startup to use a shared tested factory and added a test for normal and isolated launches. The earlier application-persistence claim was too broad; its original tests and failed native attempt remain recorded.

All 33 focused Debug tests then passed, including 13 new tests and eleven last-mesh regressions. The same 33 pass in optimized Apple Silicon and Intel builds, with Intel tested under Rosetta. Native sandboxed testing verifies saving a default, Cancel, normal quit/relaunch, automatic restoration, committed Previous Conversion and document Undo. A fresh optimized native launch restores both records saved in the preceding Debug session. The original owned TIFF is unchanged. Universal deployment metadata, unchanged sandbox entitlements, signing and exact ZIP extraction verify.

These checks do not establish full Photoshop parity. Manufacturer calibration profiles, exact saved-field and matching policy, session behavior, preset transport, numerical output, wider metadata and physical-platform tests remain open. Photoshop's normal interface recognized the owned camera, focal length and aperture, but Custom/Settings behavior was not fully qualified. No proprietary implementation or stock artwork was copied. Filter Gallery is next, followed by Brush Settings. No installation, source push, App Store change or software release occurred. [Evidence](../PhotoCraftSwift/docs/LENS_DEFAULTS_452.json).

<a id="dev-step-453"></a>

## 2026-11-06 — Step 453: Custom Filter Gallery textures

Filter Gallery already had 47 effects, an editable stack, visibility and ordering controls. It lacked custom texture loading. Rough Pastels, Underpainting, Glass, Conté Crayon and Texturizer now accept a merged PSD or PSB height texture through a native file picker. Loading runs away from the main thread and can be cancelled. An old or closed draft cannot receive a late result. A load error preserves the previous usable settings and preview.

The loaded texture becomes a bounded embedded height plane. Choosing a built-in texture removes the custom override. Local Undo/Redo includes that choice. Committing uses the existing editing engine, document history and Smart Filters. Native archive version 88 and Actions version 54 retain the samples; ordinary Gallery edits keep their older minimum versions. The optional API adds a read-only filter.gallery.texture conversion command and uses filter.apply for the edit. There are 260 typed commands. Existing Adobe routes are unchanged, and unsupported Gallery action descriptors remain explicit.

The first new test build failed because it called a sharing helper that does not exist. The next run found a missed archive-output version guard and an HTTP test that had not enabled document transfer. Both attempts were preserved before repair. All 34 focused methods then passed, including sixteen new tests for sampling, PSD/PSB decoding, history, persistence, cancellation, stale requests, HTTP guards and large payloads. Adding output captures did not change the application binary. The same 34 methods pass in optimized Apple Silicon and Intel builds, with Intel tested under Rosetta. Ten of fifteen effect/depth output buffers match byte-for-byte between those optimized builds. Five Float32 buffers differ in 55 color values by one floating-point step, with identical alpha. The strict comparison remains failed and its cause has not been isolated; the original comparison and all captured data are retained for numerical cleanup.

Actual sandboxed native testing loads PSD and PSB textures, checks local history, commits a Smart Filter, uses document Undo/Redo and saves a Photato file. A fresh optimized launch reopens that file with its embedded PSB texture and settings intact. Cancel leaves the saved file unchanged. The universal package has both macOS 14 deployment targets, the production sandbox entitlements, a valid ad-hoc signature and identical contents after ZIP extraction. An initial Debug packaging comparison found one signing-allocation metadata difference in LINKEDIT; the record preserves that exception and does not claim whole unsigned binaries are identical. Two incorrect independent archive-parser assumptions were also retained and corrected without changing the saved file.

The current height conversion and sampling describe Photato's implementation. Photoshop's normal Filter Gallery interface was inspected, but the custom texture probe could not complete and produced no independent pixel oracle. Exact conversion, alpha/profile behavior, light and tiling defaults, output fidelity, the rest of Filter Gallery and broader platform/performance tests remain open. No proprietary Photoshop code or artwork was used. Brush Settings is next, then B02. The maintainer's plug-in question was answered separately: Photoshop plug-in hosting is not implemented, and Firefly API compatibility does not supply it. No installation, source push, App Store change or software release occurred. [Evidence](../PhotoCraftSwift/docs/GALLERY_TEXTURES_453.json).

<a id="dev-step-454"></a>

## 2026-11-06 — Step 454: Brush pattern textures

The brush engine already supported bitmap textures, and imported brushes could contain them. The Brush Settings panel could only choose generated textures. It now has a Choose Pattern menu that follows the saved Patterns library and its groups. Choosing a pattern enables Texture and keeps the other settings. Generated patterns remain available. Preparing a texture runs in a cancellable worker, with an enabled Cancel button while other controls are disabled.

The brush stores its own height samples. Changing or deleting a library pattern does not alter a saved brush, a started stroke or a recorded Action. The implementation shares the existing ABR texture conversion and preserves the brush rendering algorithms. Textures retain the existing 2500-pixel limit per axis; oversized patterns are rejected without resizing. Document pixels and Undo history do not change until painting begins.

The optional API adds texturePatternID to brush.configure. Its existing brush patch is still required and may be empty. The complete patch and prepared texture publish together, after cancellation, document, brush, library and sharing checks. The API reports loading state and documents the conversion and limits. Command count 260, native archive version 88 and Actions version 54 are unchanged. No Adobe endpoint or unsupported brush descriptor was added.

The first build failed because a trailing closure bound to the preparation parameter instead of authorization. After making that argument explicit, the application compiled. New tests then needed the actual initializer argument order and a private helper declaration. The first complete run passed 38 of 40 tests. Two new API tests had mismatched initial brush centers, expected a changed revision for a repeated no-op, and read the command schema at the wrong level. Those setups were corrected while retaining full brush and pixel comparisons. An explicit no-op revision check was added. The application binary is identical across the last three attempts.

All 40 selected Debug methods now pass, including ten new tests. They cover literal color/alpha/depth conversion, the prior ABR formula, cancellation, dimensions, preset locks, JSON/ABR/disk persistence, captured painting and Actions, native/API pixel equality, busy and stale requests, and revocation during preparation. Existing brush, ABR and all-tool modifier cursor tests also pass. Actual native testing selects Diagonal Lines, shows its embedded 8 × 8 texture and a ready preview, paints a textured stroke and verifies document Undo/Redo before restoring the disposable document and quitting normally. Deployment metadata, production sandbox entitlements, signing and unsigned payload identity verify for the isolated Debug app.

This is a selected workflow delivery, not full Brush Settings parity. Normal optimized qualification is deferred under the breadth policy; universal build 453 remains the latest. Offscreen Light/Dark captures have incomplete controls and do not qualify appearance. Photoshop's normal Brush Settings probe did not expand the panel, so no independent texture pixel reference was obtained. Exact conversion, defaults, positioning, physical bristles, complete ABR/input behavior, platform/tablet tests and sustained 60fps remain open, alongside earlier failures. Painting tools are next, then B04. No installation, source upload, GitHub deletion, App Store change or software release occurred. [Evidence](../PhotoCraftSwift/docs/BRUSH_PATTERN_TEXTURES_454.json).

<a id="dev-step-455"></a>

## 2026-11-06 — Step 455: Eraser mode reference

The six special painting and eraser tools already exist. A prior audit identified a remaining ordinary Eraser gap: Brush, Pencil and Block modes. Before changing the engine, we used an owned uniform gray image in Photoshop to measure Block behavior. Each result was saved separately and decoded with an independent PSD merged-plane parser.

A click at 100% changes exactly 16 × 16 pixels to the background color. At 200% it changes 8 × 8; at 125%, 12 × 12; at 1600%, one pixel. Two tested 6400% clicks change nothing. These selected results agree with truncating 16 divided by zoom. They do not establish every position or stroke, but they rule out a forced one-pixel minimum. No proprietary code or artwork was accessed. The original image is unchanged; Photoshop's Brush mode, 100% zoom and Brush tool were restored before closing the owned reference document.

The integration plan preserves the existing brush eraser's fast, paged and component-target paths, adds native and shared API modes, captures settings for strokes and Actions, and checks cursor feedback for all 16 modifier combinations. Pencil controls still need qualification. Erase to History requires a real history source and remains part of the original scope. Photoshop also displayed a 5000 px Eraser Brush, beyond Photato's 2048 px brush limit; that separate B01 capacity gap is recorded without claiming an Adobe maximum.

This checkpoint adds evidence and a concrete implementation plan, with no application source, tests, build or API changes. All 7,409 frozen inputs remain unchanged. B02 remains current, followed by B04. The prior 40-test Debug qualification belongs to 454; optimized universal remains 453. All previous output, platform, capacity and 60 fps requirements remain open. No source upload, GitHub deletion, installation, App Store change or release occurred. [Evidence](../PhotoCraftSwift/docs/ERASER_MODES_455.json).

<a id="dev-step-456"></a>

## 2026-11-06 — Step 456: Eraser modes

The ordinary Eraser now offers Brush, Pencil and Block. Brush retains the existing settings. Pencil uses the existing hard, aliased pencil behavior and ignores Flow. Block uses a solid square whose document size follows the current view zoom; it ignores brush diameter, opacity and Flow. At high magnification the inferred footprint can be zero, so the operation leaves pixels and history unchanged. This follows the six selected Photoshop reference results, not a claim about every position or continuous stroke.

The native toolbar disables controls that do not apply. Stroke settings and the mode are captured at gesture start. Cursor policy reports the selected mode and keeps temporary Hand behavior and modifier restoration. Erase to History and its Option alternate remain explicitly unavailable. The previous notes incorrectly assigned that work to B06, which is Content-Aware Fill and Scale. History-source selection belongs to D03, History and Art History Brush to B03, and ordinary Eraser integration to B02. No original package scope is removed.

The optional API adds eraserMode to brush.configure, with its existing required brush patch. paint.stroke accepts an explicit mode and optional captured zoom. Omitting the mode preserves the older brush.erase behavior. Both paths reuse the current native stroke, target, history and Actions engines. Command count 260, native archive version 88 and Actions version 54 remain unchanged. No Adobe endpoint or unsupported action descriptor is invented. Photoshop plug-in hosting remains separate, unimplemented work under AUT03.

The first attempt compiled the application but failed to compile a new test that assigned a read-only property. Its source, logs and 5,401 products were retained before repair. The test now uses the actual mask-selection operation. API schema metadata, explicit zoom capture and stationary cursor observation were also completed. All 44 focused Debug methods then passed, including ten new methods for the independent RGB8 Block references, all three depths, masks, maximum sparse canvas, captured modes, cancellation, Undo/Redo, Actions and real HTTP validation. The same 44 methods pass in normal optimized Apple Silicon and Intel builds, with Intel tested under Rosetta on the current host. All ten new methods pass on both. The six RGB8 Block buffers match the owned Photoshop outputs byte-for-byte in Debug and both optimized builds. Older tests, fixtures and existing Core/Imaging files are unchanged.

Photoshop's normal Pencil Eraser toolbar was checked on an owned reference document: opacity remains available and Flow is disabled. Brush mode and the Brush tool were restored before closing the unchanged reference. Native Photato testing painted a black stroke, used all three Eraser modes, and verified Block Undo/Redo before restoring a clean disposable document. The Debug app's Open and Quit commands were disabled, and the app remained open. That is an unresolved failure, not a successful Quit check. A preflight check caught the still-running process; an early release-driver invocation then exited before starting any compiler because its test-list file had not yet been prepared. The normal builds subsequently passed. A fresh optimized application with a distinct test identity opens the exact owned gray PSD, performs a Block erase at 400%, verifies clean/dirty transitions through Undo/Redo, closes the restored image and quits normally. The original file is unchanged. Its universal macOS 14 package verifies sandbox entitlements, signature and identical ZIP extraction contents. The earlier Debug session still had disabled Open/Quit after idle, settings inspection and workspace cancellation. Its cause is unresolved. Activity Monitor was used to stop only that clean disposable test process; a normal stop request did not exit, so force quit was required. Both owned Photato processes are now absent. This cleanup is not recorded as a successful native Quit.

Full Eraser and painting parity, independent Pencil pixels, continuous strokes, transforms, profiles, factory defaults, the observed 5000 px versus 2048 px brush-capacity gap, physical input and 60 fps qualification remain open, along with earlier numerical and full-suite failures. The next B04 source audit found that Blur, Sharpen and Smudge expose only a fixed Normal label and ignore the brush blend mode; Photoshop's supported choices and output need checking before implementation. No installation, source upload, GitHub deletion, App Store change or software release occurred. [Evidence](../PhotoCraftSwift/docs/ERASER_MODES_456.json).

<a id="dev-step-457"></a>

## 2026-11-06 — Step 457: Blur, Sharpen and Smudge blend modes

The three focus tools previously displayed a fixed Normal label. Their validation also rejected other modes; the earlier statement that the renderer simply ignored the setting was incomplete. They now offer Normal, Darken, Lighten, Hue, Saturation, Color and Luminosity. Each tool retains its own selection during the session and captures it at stroke start. The existing processed sample is blended with the original target before stroke opacity and selection. Alpha, locked transparency, hidden color and scalar-mask policies are explicit. The Normal arithmetic path, neighborhood kernels and Smudge pickup are unchanged.

The optional retouch.stroke API accepts the same modes, exposes them in discovery and conditional schemas, and rejects unsupported modes before publication. Native Mode changes advance the API revision without adding image history; unchanged values retain it. Explicit stroke overrides preserve native defaults. Non-Normal focus recipes require Actions version 55, while ordinary retouch recipes retain version 21. Native archive version 88 and 260 typed commands are unchanged. No Adobe route or plugin host was added.

Photoshop's seven-item Blur list was observed on an owned image through its normal interface. Attempts to select Sharpen and Smudge did not qualify their desktop lists. An unexpected Eraser state was undone and the unchanged owned image closed. Adobe's desktop help describes mode controls; its iPad list and the public W3C color-blending definition supply related evidence, not a Photoshop numeric oracle. The current Adobe Smudge help says R, but installed Photoshop selects Rotate View with R; factory shortcuts were retained. No proprietary implementation or artwork was copied.

Before editing the engine, an owned Swift helper captured 18 Normal buffers from the preserved build456 Core module. Those are Photato regression fixtures. The first new test attempt assigned a read-only property and did not run tests. A second attempt found an ambiguous BlendMode type in the new app test. Both sources, logs and products were retained before test-only repairs. The first retained cache app was stale456 and is labeled accordingly. Source02 and Source03 application hashes are identical; Source03 passed 56 tests. Source04 added the native-mode API revision guard and a tenth test. All 57 focused Debug tests pass. The optimized builds pass 57 methods on Apple Silicon and 56 of the same 57 on translated Intel; all ten new methods pass on both. The remaining Intel comparison reproduces all 234 failure messages and actual/expected hashes on the preserved456 test bundle. Its assertion and fixture remain unchanged. Twenty-nine older tests change only the maximum Actions-version counter. All 18 preserved Normal buffers match exactly. Of 126 mode buffers, 120 match across Debug and both optimized architectures; six Float32 buffers differ in 16 Intel color values by 1–4 ULP, with all alpha values exact. Debug and optimized Apple Silicon match all 126. No tolerance was substituted.

The native checks use the owned hard-edge image. Sharpen Lighten and Smudge Color drags each produce a dirty document, Undo restores clean, Redo returns dirty, and a final Undo restores clean. Blur retains its separate Darken setting. The initial rapid single-click/history sequence was inconclusive; the image was reopened and the drag/history actions observed separately. Open-panel navigation also produced a clipboard timeout and delayed selection; the selected file subsequently opened through the normal Open button. These attempts remain documented without a cause claim. The clean reference closed, and the validation app quit normally. The optimized universal application opened the same image, painted with Blur Darken, passed separately observed Undo/Redo and clean close, and quit normally. Its sandbox entitlements, macOS 14 metadata, signature and ZIP contents verify. Original artwork is unchanged. The earlier456 Debug Open/Quit failure is not claimed repaired by a successful fresh457 session.

Full B04, independent Photoshop pixel outputs and per-dab behavior, exact defaults, profiles and component contexts remain open. Physical Intel/macOS14, tablet input, 60 fps, capacity and all earlier strict/full-suite failures remain open. B06 Content-Aware Fill and Scale is next, followed by B07. All 104 original scopes and acceptance criteria, 652 command mappings, 81 major memberships and the seven-pass order are retained. No current build or GitHub content was removed, and no source upload, installation, App Store change, Xcode archive or software release occurred. [Evidence](../PhotoCraftSwift/docs/FOCUS_BLEND_MODES_457.json).

<a id="dev-step-458"></a>

## 2026-11-06 — Step 458: Apply Content-Aware Fill and continue editing

Content-Aware Fill previously offered only OK to commit and close. Apply now commits one fill while leaving the workspace open. It rebuilds its source from the committed document, retains settings and sampling strokes, and resets local selection edits and history. New output keeps the original source layer; Duplicate continues from the new duplicate. Exact Photoshop source and layer behavior still needs direct comparison.

Selection strokes now support New, Add, Subtract and Intersect. Native controls and Shift/Option modifiers capture the selected operation at gesture start, and cursor feedback follows it. The optional contentAware.fill API accepts the same explicit selectionMode, while old requests retain their add behavior. Discovery and read-only state expose Apply availability, applied-fill count and preview/commit status. Remote commands still reject a busy native workspace. Native archive88, Actions55 and260 typed commands are unchanged; existing Content-Aware recording and Adobe action-descriptor limitations remain.

Cancel discards the current preview and keeps earlier applied fills. OK commits a pending fill and closes; after an unchanged Apply it closes without another output layer or Undo. Each published fill uses the existing prepared edit and history path. Synthesis, output pixels, Content-Aware Scale, channel and history engines are unchanged.

The first run executed29 of38 selected methods:27 passed, two failed, and nine cursor methods were missing because the selector used a helper window's class name. The new HTTP test tried document Undo while the native modal remained open; it now closes the unchanged workspace first, retaining exact document equality. An older Scale fixture tried saving a protection channel without any selection. The preserved457 test bundle reproduced the same error. The fixture now selects explicit full coverage before saving, then clears selection before whole-layer scaling. All its original assertions remain. A new selection test also gained literal per-pixel expectations, and real HTTP state was checked. Source01/02 application binaries are identical.

All38 selected Debug methods now pass, including seven new methods. The tests cover all three bit depths and output choices, two Applies, Cancel, unchanged OK, stale and cancelled work, Undo/Redo, native archives, selection modes, HTTP equivalence/state/errors and all16 modifier combinations for captured selection cursors. Frozen7445 inputs and5421 retained products bind to the passing build. The isolated Debug package passes macOS14 metadata, full production sandbox entitlements, signature and exact unsigned-payload checks. Normal458 is deferred under the breadth policy; the latest universal remains457 with its known strict failures.

Adobe's current Apply/cancel guide describes continued filling and new Lasso selections. Photoshop Home was visible, but its Open and menu input calls timed out, so no new Photoshop reference was opened. In native Photato, the owned two-object PSD opened through the system panel. The first drag had no visible marquee and left Content-Aware Fill disabled; repeating the drag produced a visible selection and enabled the command. No cause is claimed. A stale menu index briefly opened File; its native Cancel action dismissed it before selecting the actual Edit command. The automation native pipe then closed while opening the fill workspace. Re-observation, a REPL reset and rebinding all failed. Photato is still running with the disposable document; only selection editing was observed, the post-disconnect UI state is unknown, and no live Apply, close or Quit result is claimed. The original image is unchanged. A single unlock-status question is pending while independent work continues.

Multi-image sampling and alignment, the existing16MP workspace/4MP synthesis and scaling limits, exact Photoshop output/defaults, full current-suite, physical Intel/macOS14, tablet input and60fps qualification remain open. The hosted Light/Dark control construction is not full visual or accessibility acceptance. All104 original scopes and acceptance criteria,652 command mappings,81 major memberships, seven passes and prior failures are retained. B07 is next, then D04; resume the pending458 native check when the connection returns. No current builds or GitHub content were removed, and no upload, installation, App Store change, Xcode archive or software release occurred. [Evidence](../PhotoCraftSwift/docs/CONTENT_AWARE_APPLY_458.json).

<a id="dev-step-459"></a>

## 2026-11-06 — Step 459: Eyedropper averaging and layer sources

The previous Eyedropper picked a single displayed pixel. It now offers Point Sample and 3, 5, 11, 31, 51 or 101 square averages, plus Current Layer, Current & Below, All Layers and the two choices that exclude adjustments. Dragging updates the foreground colour; Option at press captures background instead. The optional ring shows the new colour above the captured colour, with a gray surround. Settings are shared between documents and saved by the production startup path. Detached documents receive independent copies. No image edit, dirty state or Undo entry is created by sampling or these settings.

The optional color.sample API uses the same native sampler. Sampling is read-only unless foreground or background is explicitly requested. Overrides leave tool settings unchanged; configuring saved settings requires the existing preference-change permission. Results include colour, coverage, clipped region and contributing-pixel counts. Cancelled, revoked, busy and stale requests do not publish. Captured cursor feedback covers all 16 modifier combinations. Shift Color Sampler remains unavailable because persistent sampling points are not yet implemented.

The first build failed because a validation hook was placed in the schema loop. The second linked the app but found Swift 6 isolation and permission-setter errors in new tests. Both attempts were preserved before repair; the first retained executable was explicitly identified as cached build 458. The third executed 44 tests:42 passed. Investigation found that displayed composites use Float32 storage even for integer documents, so their averaging must capture the document depth. The new whole-composite reference and displayed-channel implementation now use that semantic depth, retaining exact result equality. Unsupported size 2 also returned HTTP 422 instead of HTTP 400; validation now returns400. A separate every-depth displayed-target regression was added.

All 45 focused Debug tests now pass, including 19 new methods. The same 45methods pass on normal optimized Apple Silicon and translated Intel. Tests cover literal averaging, transparency, HDR, source filtering, transforms/groups, bounded sampling on a 300,000 pixel canvas, native/API agreement, shared preferences and both startup factories, cancellation/stale/revoked results, palette/history effects and cursor capture. Strict sample-buffer hashes and any differences are in the [evidence](../PhotoCraftSwift/docs/EYEDROPPER_SAMPLING_459.json); no tolerance substitutes for byte equality. The 7,452 frozen inputs and retained build products bind these results to the tested source. Native 88 and Actions 55 are unchanged;261 typed commands are exposed. Only catalogue counters changed in28 old test files.

The universal validation package passes macOS 14 metadata, full production sandbox entitlements, signature and extracted ZIP checks. Debug staging also preserves the exact unsigned executable payload. A final event-dispatch audit also found that the canvas rejected Eyedropper before reaching the sampler when a channel was active. That admission guard now permits the implemented read-only tool. Controlled AppKit mouse events verify the sampled result and active foreground at all three depths, without changing pixels or history. The API now accepts every coordinate below the full 300,000 pixel boundary; the endpoint itself remains invalid.

The UI automation native pipe is still disconnected when selecting the earlier458validation app, so no459app was launched and live controls, dragging, ring appearance, relaunch, close and Quit are not claimed. The earlier disposable app remains open; no force quit or alternate input mechanism was used. Offscreen native controls are not live visual/accessibility acceptance.

Current public Adobe help and a first-hand Adobe-employee article guided the controls. The older article describes zoom-dependent sampling and shared sample size with other tools. This implementation uses document-pixel regions, and installed Photoshop 2026 footprint/source/alpha/profile/default/numerical comparisons remain required. Native/API agreement does not prove Photoshop equality. Persistent Color Sampler/Info points, real tablet pressure/tilt/eraser/buttons and replay, external-desktop sampling, physical-platform/60fps/full-suite checks and all prior failures remain open. All 104 original scopes/acceptance,652 reference command mappings,81 major memberships and seven passes remain. D04 clipboard interoperability is next, then L03. No current builds or GitHub content were removed, and no upload, production installation, App Store change, Xcode archive or release occurred.

<a id="dev-step-460"></a>

## 2026-11-06 — Step 460: Copy and paste masks and channels

Copy and Paste previously rejected auxiliary editing targets. They now work on alpha channels, Quick Mask, layer masks and Smart Filter masks using the existing menus and shortcuts. Cut and Paste In Place use the same target selection. Copy preserves grayscale samples, selection opacity, document depth and copied position. It does not change image pixels or history. Cut writes the clipboard before changing the document, and Cut/Paste each produce one Undo transaction. Cancelled work, changed targets and clipboard publication failures leave the document intact.

The implementation uses the existing grayscale document representation and native clipboard envelope. It does not flatten raw scalar values through an RGB preview. Colour sources use the existing native grayscale conversion with the captured working Gray profile. Transformed masks retain their geometry, outside value, density and feather; pasting expands stored mask bounds when needed. Standard TIFF/PNG generation was also preventing large native copies. Those fallbacks are now omitted above their materialization budget, preserving full native data instead of substituting a reduced image. This does not solve every large-document or cross-application clipboard case.

The optional API accepts an explicit channel or mask target without changing the desktop target or using the Mac clipboard. It shares the native engine and transaction history. Targeted Cut can take a numeric background value; Paste supports ordinary centered placement and Paste In Place. New Document accepts the grayscale payload while an auxiliary target is selected, with the existing transfer permission. State/capability schemas and limits are exposed. There are still 261 typed commands, native format 88 and Actions format 55. Targeted clipboard Action recording remains explicitly unsupported.

The first build failed because the existing 24MP clipboard benchmark assumed TIFF and PNG were always present. Its contract still requires both, now with an explicit throwing guard. No tests ran, and the retained executable was identified as cached build 459. The second attempt compiled and ran all 45 selected tests: 41 passed. Four new methods stopped at an invalid Smart Object media type in their test fixtures. Both fixtures now use the accepted native document type. The application executable is byte-identical before and after this test-only correction; the failed source, logs and products are preserved.

All 45 focused Debug tests and the same 45 optimized methods pass on Apple Silicon and translated Intel, including 20 new methods. Native/API comparison exercises all three depths and four targets. Other checks cover Undo/Redo, irregular selection opacity, spot samples, translated mask expansion, failed/cancelled/stale native edits, HTTP errors and a 300,000 × 300,000 sparse transfer. The 984-byte raw sample captures are compared across configurations and against independent literal rational values without tolerances. These own-fixture results do not establish Photoshop output equality. The 7,459 frozen inputs, retained products, exact commands and results are in the [evidence](../PhotoCraftSwift/docs/TARGETED_CLIPBOARD_460.json).

The isolated universal package passes macOS 14 metadata, full production sandbox entitlement, signature and extracted ZIP checks. Native UI acceptance is pending the existing automation connection issue. The Debug staging comparison differs only in the verified LINKEDIT virtual-size allocation changed by signing; all other unsigned bytes are exact. No build 460 app was launched or installed, no normal Quit is claimed, and the earlier disposable app has not been force-quit. Controlled native methods and a named test pasteboard are separate from physical UI acceptance. The user's system clipboard was not used by the tests.

Adobe's public guide confirms pasting image content into a displayed layer-mask channel. Exact mask-thumbnail versus mask-only context, floating selection, gray conversion, profiles, rounding and numerical output still require an installed Photoshop 2026 reference. The current layer-copy guide also says whole-layer Cut is unavailable; that discrepancy is retained for a contextual check. No Adobe implementation code or artwork was copied.

D04 remains open for RGB component-set/path clipboard, external vector/PDF/layered formats, Background Cut, scalar Paste Into/Outside, portable targeted Actions and the remaining fidelity/capacity/platform/performance checks. Existing earlier failures remain. All 104 original scopes and acceptance criteria, 652 command mappings, 81 major memberships and seven passes are preserved. L03 advanced blending is next, then L04. GitHub content and current builds were not removed; there was no upload, production installation, App Store change, Xcode archive or software release.

<a id="dev-step-461"></a>

## 2026-11-06 — Step 461: Channel blending

Blending Options now has native Red, Green and Blue checkboxes. Deselecting a channel preserves that component of the backdrop while the enabled channels use the existing composite. The layer context menu opens the same sheet. Preview changes stay private until committed; Cancel discards them. The setting participates in Undo/Redo and style copy, paste and clear. Pointwise channel-only styles are available on adjustment layers and large RGB documents without allocating an effect map. Other effects keep their separate availability and resource limits.

The renderer carries the setting through ordinary layers, groups, pass-through groups, clipping, masks, transforms and existing effects. Stored source pixels are unchanged. Existing unrestricted composition paths and their measured rounding remain intact. The current alpha, transparent-backdrop, all-off and group policies are implementation choices awaiting independent Photoshop 2026 comparison. They are not recorded as measured Photoshop behavior.

The optional API uses the existing layer style operations and returns the same setting in document state. RGB component IDs must be distinct and in range. Non-RGB exclusions reject explicitly. Native format 89 and Actions format 56 retain the new field, including styles stored in timeline keys, frames, Layer Comps and retained sources. Timeline channel choices hold until the next key. PSD and PSB use the public brst component-ID records, including an empty record for explicit all-on state. Earlier archive feature minima remain unchanged. There are still 261 typed commands. The published Firefly BlendOptions schema has blend mode and opacity, so no undocumented channel endpoint or plug-in compatibility was added.

The first test run used a helper class instead of the real cursor test class for nine selectors. Its new maximum-size reference also confused encoded fill values with stored linear samples. The second run executed the corrected selectors and a new temporal regression, but its maximum-size expectation still missed ordinary Normal composition rounding. That existing math was left unchanged. The new reference now compares excluded channels with the backdrop and enabled channels with the ordinary unrestricted composite, using exact words and no tolerance. The third attempt passed all 57 selected methods. The application executable is identical across attempts two, three and four.

A further regression test then demonstrated that a small raster edit under unchanged channel-only styles caused full-canvas redraws. Its pixel comparisons passed, but both bounded-damage assertions failed. The source and results were retained before changing invalidation. Channel-only settings now permit the existing bounded tile update; changing channel settings or using rich effects still forces full invalidation. This reduces unnecessary work but does not establish a measured 60 fps result. The fifth attempt passes all 58 selected Debug methods, including all 17 new methods.

The same 58 methods pass optimized on Apple Silicon and translated Intel. Tests cover all eight channel combinations at three depths, represented blend modes, groups, clips, masks, effects, adjustments, sparse maximum geometry, bounded/full-render agreement, native/API history and validation, native/Actions negotiation, and strict PSD/PSB records. Seven existing independent Photoshop RGB32 regression methods also pass on both retained build 460 architectures and the new selected configurations. Those regressions protect unrestricted output; they are separate from the earlier unresolved Intel failures and do not prove the new exclusion semantics.

The selected 384-byte captures match exactly across Debug and both optimized architectures. The 7,465 frozen inputs, five failed/passing attempts, retained products, exact commands and package checks are linked in the [evidence](../PhotoCraftSwift/docs/CHANNEL_BLENDING_461.json). The universal validation package passes minimum macOS 14 metadata, full production entitlements, signature and extracted ZIP checks. Any Debug signing-allocation difference is identified separately in its payload comparison. No build 461 app was launched or installed. Native checkbox, menu, focus, preview, history and Close/Quit acceptance remains pending the existing automation connection issue.

L03 remains open for non-RGB component exclusion, split Blend If controls, shallow/deep knockout, advanced interior-effects and transparency/mask flags, complete editable interchange, and the recorded default, alpha, numerical and output checks. Full-suite, physical platform, capacity, performance and earlier failures remain open. All original scopes and acceptance criteria are retained. L04 layer styles and effects is next, then L05. Current builds and GitHub content were preserved; there was no upload, installation, App Store change, Xcode archive or software release.

<a id="dev-step-462"></a>

## 2026-11-06 — Step 462: Saved layer styles

The existing editor had ten effect types, multiple effects, expanded controls and scaling, but no saved preset workflow. New Style now captures private Layer Style settings without committing them to the document. Window > Styles opens a native panel for applying, grouping, renaming, duplicating, moving and deleting presets. Effects and blending options can be saved separately. Saving and organizing leave document content and image Undo unchanged; applied styles remain independent of later preset edits.

Patterns are stored with a preset. Applying remaps conflicting IDs without replacing existing document artwork. A regression test demonstrated that recording a preset when its pattern was already installed omitted that dependency, causing replay to use foreign artwork. The repair embeds every dependency and remaps collisions during replay too. Applying uses one shared style transaction with Undo/Redo. New resources and general blending require Actions 57; native document format 89 remains current.

The library validates groups, resources and names before atomic persistence. Failed writes, corrupt files, cancelled preparation, stale sources and revoked API sharing retain the prior state. The Styles panel participates in the existing dock, floating windows and workspaces. Panel catalogue 4 migrates complete older layouts without moving their panels and adds Styles hidden. The new API uses the same model, source guards and history. Routine state carries metadata; inspect retrieves bounded full descriptors. Existing pattern and gradient effect schemas now describe their actual native fill objects. There are 262 typed commands.

Early attempts caught incorrect new model assumptions, a Swift Sendable test error and a missing try. The first retained executable was identified as cached build 461; later cached products are also labeled explicitly. The first executable test run passed 69 of 74 methods and exposed the dependency/replay bug, an overstrict duplication rule, incomplete fill schemas and two old metadata assertions. Source02 and Source03 applications are identical, confirming that the intervening Task-result repair was test-only. Every source, log, product and later correction is retained in the [evidence](../PhotoCraftSwift/docs/LAYER_STYLE_PRESETS_462.json).

The fifth attempt passed 75 of 76 methods. Its remaining new hierarchy assertion incorrectly ignored the copied group already preceding the moved entry; the reference was corrected to check the intended relative order. The final attempt also aligned the style-override schema with its existing object-only decoder. No old numerical assertion or tolerance changed.

The final selected run passes all 76 focused Debug methods, including 18 new methods. Tests cover all ten effects at three depths with exact native composites, resource conflicts, private draft saving/Cancel, native/API agreement, image history, portable replay, group operations, persistence/corruption/failure, synchronized cancellation/revocation, schemas and old-layout migration. Seven existing independent Photoshop RGB32 tests protect old output. Existing Imaging code, numerical fixtures and effect math are unchanged. Own round trips and equality do not establish new Photoshop preset output or defaults.

The packaging helper completed its checks but stopped copying its driver into a missing evidence directory. The driver was retained and the existing package reverified without rebuilding the app.

The isolated Debug package passes macOS 14 metadata, production entitlement, signature and payload checks. It is unlaunched; live controls, focus, appearance, accessibility and Close/Quit remain pending the native automation connection issue. Normal optimized/Intel/universal 462 testing is deferred under the existing breadth policy; optimized universal 461 remains the latest separate package. Adobe ASL Import/Export is still unavailable and visibly disabled. Internal library persistence is not an ASL substitute. Default artwork, thumbnails, hover/drag/display variants, complete effect/interchange behavior, convert-to-layers, exact defaults/output and all earlier platform/capacity/performance failures remain open.

All original scopes and acceptance criteria are retained. L05 Smart Objects is next, then L06 Smart Filters. Current builds and GitHub content were preserved. There was no source upload, production installation, App Store change, Xcode archive or software release.

<a id="dev-step-463"></a>

## 2026-11-06 — Step463: Convert Smart Objects to layers

The Layer > Smart Objects menu contained Convert to Layers, but the command had no implementation. It now restores the original editable layers through the factory menu, Layers context menu and optional API. Multiple layers become a group. The selected source Layer Comp is applied first. Following Adobe's public guide, conversion discards the original outer transforms and Smart Filters. It does not replace the command with Rasterize.

The transfer retains type, shapes, masks, styles, patterns and nested source contents. Conflicting resource IDs receive new identities without replacing existing document artwork. Nested instances keep sharing within their original source class. Imported appearance caches are rebound from their captured reference so that a stale cache does not become active accidentally. The parent selection, channels, paths and metadata are retained. All selected instances use one prepared transaction and Undo/Redo. Unsupported mode/profile, PDF/RAW, temporal, source-artboard and variable contexts reject the operation. Portable Actions replay remains unsupported.

The first compile caught a Swift exclusivity error in the new mask transfer. Subsequent tests caught two invalid new fixtures: shape dimensions omitted the geometry's padding, and a profile test changed the document's fixed metadata label instead of installing an ICC profile. The failed attempts were retained before repair. The three later applications are byte-identical; those repairs changed tests only. No existing rendering code, numerical fixture or tolerance changed.

All15new methods pass. The55selected methods include53passes, one older linked PSD/PSB test with two byte mismatches, and an older archive/API method that exits bysignal10. Retained build462reproduces both older problems. A separate continuation ran the methods blocked by that crash, including all nine cursor regressions. Seven existing independent Photoshop RGB32 regressions pass. This is not a full-suite pass or new independent Photoshop output qualification.

The isolated arm64 Debug package passes minimum macOS14, production-entitlement, signature, resource and unsigned-payload checks. It has not been launched or installed. Normal463and live acceptance are pending; optimized universal461remains separate. Native window and screenshot access partly recovered, but Open/File actions still timed out. The new reference copy did not open, so placement, outer attachments, defaults and numerical output remain unqualified. The full Smart Object package remains open; Smart Filters is next, followed by S02.

The plugin compatibility question was also checked against current source and Adobe's documentation. Photato has no Photoshop native-binary, UXP or CEP/ExtendScript host. The REST API is separate from desktop plugin compatibility. Future support needs its own implementation and testing for each supported plugin.

[Guide](../PhotoCraftSwift/docs/SMART_OBJECT_CONVERT_TO_LAYERS.md) · [Evidence](../PhotoCraftSwift/docs/SMART_OBJECT_CONVERT_TO_LAYERS_463.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-463).

<a id="dev-step-464"></a>

## 2026-11-06 — Step 464: Smart Filter stack and mask transfers

Smart Filter stacks and shared masks can now be moved or copied between Smart Objects. Drag the Smart Filters label for the whole stack, or its thumbnail for the mask; Option copies. The API uses the same operation, and one Undo restores both layers. Portable Actions record the source and destination by layer name so they can replay in another matching document. Actions now use version 58; the native document format stays at 89.

An existing destination stack keeps its mask and enable state. A new stack inherits those from the source. Mask transfers retain the original samples and document-space properties. Source pixels and original Smart Object contents stay intact. All 15 new transfer tests pass, including native/API equivalence, a layer with both mask types, stale requests, cancellation and Undo.

The first optimized runs exposed two saved-style API failures. Investigation found that weak request owners could disappear while an otherwise valid operation was preparing. The operation now retains its owners until completion and still checks whether the document was closed or sharing was revoked. A synchronized Close test verifies that the write is rejected. Failed runs, sources and binaries are retained alongside the passing repair.

The final optimized batch passes all 87 selected methods on Apple Silicon and translated Intel, including 49 new methods from saved styles, Convert to Layers and this work. The Debug record accounts for 56 methods: 55 pass and one older API test crashes, also reproduced in retained build 463. Three depth fixtures produce identical raw output across Debug and both optimized architectures: 1,152 bytes, checked without tolerance. That comparison does not prove Photoshop output equivalence.

Photoshop automation recovered enough to open our synthetic document, create two Smart Objects and apply a Gaussian Blur Smart Filter. Coordinate dragging still failed with a tool error. The fixture was saved and closed; transfer behavior remains unverified. The fresh universal validation app passes macOS 14 minimum-version, entitlements, signing and extracted-ZIP checks. It has not been launched or installed. Its only unsigned packaging differences are verified signing-allocation fields; all other bytes match the tested slices.

Full Smart Filter parity, independent Photoshop output, live gestures, physical Intel/macOS 14 and performance checks remain open. Work proceeds to **S02 — Color Range, Focus Area and Magnetic Lasso**, then S03.

[Guide](../PhotoCraftSwift/docs/SMART_FILTER_TRANSFER.md) · [Evidence](../PhotoCraftSwift/docs/SMART_FILTER_TRANSFER_464.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-464).

<a id="dev-step-465"></a>

## 2026-11-06 — Step 465: Magic Wand averages

The Magic Wand Sample Size control was fixed at Point Sample. It now offers Point Sample and 3 by 3, 5 by 5, 11 by 11, 31 by 31, 51 by 51 and 101 by 101 Average. Those choices were checked in the installed Photoshop 2026 popup. The test setting was restored and the owned reference document closed without saving changes.

The native tool and optional API use the same captured request. Samples can come from the current layer, visible composite or ordinary layer mask, including locked sources. Source pixels stay intact and the resulting selection has one Undo. The API can configure window-local options or select with temporary overrides; overrides leave the defaults unchanged. Existing W/Shift-W and selection modifiers remain.

The first build stopped because Swift integer SIMD vectors do not support checked addition. A second attempt caught an incorrect property name in the new availability check. Both attempts and their cached 464 products were retained before repair. The final code uses checked scalar sums and the existing pathTarget property. A live check then caught a truncated picker value. The control was widened, and the same 57 tests passed again. The final native app shows the full 101 by 101 label, makes a canvas selection, and completes Edit-menu Undo/Redo/Undo. Quit was verified by process termination. All 11 new tests and 57 selected Debug methods pass. They cover seven sizes, three bit depths, masks, captured settings, history/archive and request guards. A separate literal arithmetic reference agrees with all 74,263 captured mask bytes, and the old point-sampling regression still agrees with its 66,096 bytes.

These checks do not establish Photoshop pixel equivalence. Alpha, hidden-color, rounding, connectivity and profile details still need independent comparison. Full S02, dense/maximum capacity, restart preferences, semantic Actions, live controls and physical-platform/performance checks remain open. Normal 465 will join the next stable optimized batch; the latest optimized universal remains 464. Work moves to S03, then S04.

[Guide](../PhotoCraftSwift/docs/MAGIC_WAND_SAMPLING.md) · [Evidence](../PhotoCraftSwift/docs/MAGIC_WAND_SAMPLING_465.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-465).

<a id="dev-step-466"></a>

## 2026-11-07 — Step 466: Selection sources and Wand Subject

With Sample All Layers off, object and people analysis could still use the whole visible image for type, shape or fill sources. It now renders the selected source through the existing renderer. Sample All Layers explicitly chooses the composite. Groups and adjustments currently require that choice; their full Photoshop eligibility remains to be checked. The initial audit incorrectly included Smart Objects in the affected cases. They already retain raster previews and already used the current-layer path. That statement was corrected before implementation.

The installed Photoshop Magic Wand Options bar includes Select Subject. Photato now exposes the same entry, using Magic Wand’s own Sample All Layers flag. Object/Quick and Properties/Menu preferences stay independent. The existing Subject detector and raster/Smart Object eligibility were retained. No model, Core arithmetic or rendering kernel was replaced.

Twelve new tests cover source choice, rich layer families, masks/transforms, three depths, caches, HTTP/native behavior, history/archive and cancellation. All 82 selected Debug methods pass. The same 83 optimized methods pass on Apple Silicon and translated Intel, including all 23 new methods from this step and step 465. All 7,487 source inputs retain their hashes. Separate literal source samples and prior averaged-Wand masks match every captured byte on all three builds. These checks do not establish Photoshop or model-output equivalence.

The first native connection failed before launching this build. Resetting the computer-use session recovered it. In the isolated Debug app, the new button ran Apple Vision on a copy of the project icon and produced a visible subject selection. Menu Undo/Redo/Undo, closing the clean owned tab and Quit passed. The old validation app was left alone. A new optimized universal package passes macOS14 metadata, entitlements, signature, extracted-ZIP and compiled-payload checks; it has not been launched or installed.

A separate source/documentation audit answered the plug-in question: Photoshop native plug-ins, UXP and CEP/ExtendScript are not currently supported. They remain open under AUT03. HTTP API compatibility does not supply a desktop plug-in runtime.

Detailed face features, full S03, exact Photoshop source-kind/default/output behavior, broader target/capacity support, physical-platform/performance checks and earlier failures remain open. Work moves to Select and Mask, then pixel/vector masks.

[Guide](../PhotoCraftSwift/docs/SELECTION_SOURCE_POLICY.md) · [Evidence](../PhotoCraftSwift/docs/SELECTION_SOURCE_POLICY_466.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-466).

<a id="dev-step-467"></a>

## 2026-11-07 — Step 467: Smart Object refinement

Photato rejected Smart Objects at the Select and Mask entry point. Photoshop accepted the owned reference image after conversion to a Smart Object. Its Layer Mask output kept Edit Contents available, while New Layer with Layer Mask created a raster copy. Both neutral RGB8 references were saved and closed cleanly.

The existing native workspace and API now support that workflow. Selection and mask outputs retain source pixels, embedded data and Smart Filters. Copy outputs use the existing renderer, preserving supported geometry/effects in raster output. The source stays intact. Existing source, lock, cancellation, history and document-transfer checks remain. Smart Filter masks stay unavailable for refinement; Focus Area keeps its previous source boundary.

The first test build caught two fixture writes to a read-only property. After that repair, 123 of 124 tests passed. The remaining reference test exposed a valid empty Anno block inside Photoshop’s embedded PSD. Its documented annotation data is now preserved opaquely and re-exported unchanged, rather than removing it from the fixture. This does not add a Notes editor. After annotation retention, 124 of 125 passed; the embedded PSB’s explicit missing-composite declaration then exposed a second importer gap. Decoded layers are now authoritative only for an unambiguous complete false declaration and when decoded layers are present and no auxiliary channel planes are required. Ordinary malformed-cache rejection remains. Those repairs and two extra negative-case tests bring the selected run to 127 methods, including 17 new methods.

The neutral mask matches all 3,072 literal bytes. An isolated Debug app also passes packaging checks and native import; interactive refinement remains pending. Normal optimized 467 is deferred after the 466 batch. Detailed edge/hair algorithms, exact Photoshop defaults/output, full S04, broader contexts/capacity, physical platforms/performance and earlier failures remain open. Work moves to pixel/vector masks, then channel workflows.

[Guide](../PhotoCraftSwift/docs/SMART_OBJECT_REFINEMENT.md) · [Evidence](../PhotoCraftSwift/docs/SMART_OBJECT_REFINEMENT_467.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-467).

<a id="dev-step-468"></a>

## 2026-11-07 — Step 468: filters on masks

The filter dialogs rejected selected masks even though the same masks could be painted. Layer and Smart Filter masks now support Gaussian Blur, Box Blur, Motion Blur, High Pass, Unsharp Mask, Add Noise, Average and Mosaic through the existing menus. The API exposes the same targets. Color pixels, embedded Smart Objects, filter settings and mask properties stay intact. Preview and Cancel leave source history unchanged; commit and Repeat use one prepared Undo transaction.

The first run exposed a real API admission defect: an explicit color-pixel filter was rejected while a mask thumbnail was selected. That path now retains the thumbnail selection while applying the requested pixel edit. Two new-test expectations were also corrected: inverted mask storage needs a complement after filter-depth quantization, and irrelevant filter parameters omitted by the API should not be compared as retained settings. Original failures, source archives, products and the incorrect reference remain in the record.

97 selected Debug methods pass, including all 15 new methods. The planned 98th Debug method crashes with signal 10 on both 468 and retained 467. All 98 selected optimized methods pass on ARM and translated Intel, including that method. The separate 384-byte scalar-average reference matches exactly, as does the prior 3,072-byte neutral Photoshop refinement mask. That earlier reference does not establish mask-filter output parity.

The isolated Debug app and optimized universal ZIP pass checks for macOS 14 deployment metadata, entitlements, signatures and payloads. They remain unlaunched because the native automation connection still fails. Live preview/history/Close/Quit, wider filters, vector rasterization, compound masks, matte removal, exact Photoshop defaults/output, full S06 and earlier failures stay open. The readable index's missing 457–468 rows now link to their recorded entries. Work moves to channel workflows, followed by color adjustments.

[Guide](../PhotoCraftSwift/docs/MASK_FILTER_TARGETS.md) · [Evidence](../PhotoCraftSwift/docs/MASK_FILTER_TARGETS_468.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-468).

<a id="dev-step-469"></a>

## 2026-11-07 — Step 469: large channel filters

Alpha, auxiliary spot and Quick Mask channels stopped at an 8-megapixel filter-preparation limit. Simply removing the check would have kept full-canvas heap loops. Preparation now maps numeric samples sparsely or through file-backed storage, then runs the existing basic filter kernels. The native Filter dialogs and channel API use the same path, with Preview, Cancel, Repeat and one Undo. Channel identity, display/spot metadata, original spot-gray planes, other channels and image pixels stay intact.

Before changing production code, two new tests captured 288 small programs from unchanged build 468. They cover three depths, three target types, eight filters, selection and display indication. All 442,368 captured bytes remain exact. A separate scalar calculation verifies 576 mean-output bytes. A real 8.39-megapixel Noise operation matches its frozen selected row, while sparse 300,000-by-300,000 channel tests verify seven constant filters, native/API history, persistence and standalone selections without image layers.

The first implementation run passed 70 of 72 tests. The two failures were new-test assumptions: normalized output compacted to a single 64 KB backed tile rather than remaining dense, and invalid filter values retained the existing channel API's HTTP422 response. Only those assertions changed. The repaired run passes all 72 methods, including 12 new methods; both implementation attempts have identical application hashes. Source, logs, products and the original assertions are retained.

The audit also found that the existing direct channel API accepted bounded Liquify although native channel dialogs excluded it. That path is preserved with its previous 8 MP bound and checked against the old dense preparation. It is not presented as a new native workspace. Wider families and printing plates remain separate work.

The isolated ARM64 Debug app passes macOS 14 deployment metadata, entitlements, signature and payload checks. It is unlaunched because native automation still fails. Optimized 469 joins a later stable batch; latest universal remains 468. Full C02, exact Photoshop defaults/filter output, live controls, dense physical capacity, platforms, 60 fps and earlier failures remain open. Work moves to document color modes and separations.

[Guide](../PhotoCraftSwift/docs/CHANNEL_FILTER_CAPACITY.md) · [Evidence](../PhotoCraftSwift/docs/CHANNEL_FILTER_CAPACITY_469.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-469).

<a id="dev-step-470"></a>

## 2026-11-07 — Step 470: Split Channels

Split Channels was disabled in the Channels panel. It now prepares a grayscale document for each channel in a flat source, registers every output, then closes the original without saving. The source file is untouched. Outputs have fresh identities, empty history and no file association. Native Fill, Clear, Brush, Undo and grayscale native/PSD persistence are tested. Preparation reads channel numbers directly rather than sampling the rendered composite.

The API uses the same engine and publication path. It requires both document-transfer and document-closing permissions and replaces the source lease with all results together. Cancellation, revoked permissions/sharing, changed source/session/settings and document lifecycle checks prevent late publication. The eight-share limit applies to the final API set; native separation has no eight-document cap.

The first run passed 67 of 68 executed tests. A new grayscale numeric fixture had only one channel and correctly failed the selected minimum-two-channel policy. Six planned selectors also named a helper instead of the actual test class. The original attempt is retained. Adding a companion alpha to that Gray fixture and correcting selectors produced 74 passing Debug tests, including 15 new tests. Production and application hashes are identical before and after those test-only repairs. The same 74 tests pass in optimized ARM and translated Intel builds. All 416 component-word bytes match an independent literal calculation across all three runs, including float signed zero, subnormal and HDR samples.

Universal 470 passes deployment metadata, full entitlements, signature, archive extraction and payload checks. It remains unlaunched because native UI automation still reports a closed connection. Adobe documentation describes the intended lifecycle, but exact Photoshop context/spot eligibility, naming, profiles, metadata, defaults and Split output still need direct verification. Merge Channels, Merge Spot and the rest of COL02 remain unfinished. Dense physical capacity, supported machines/OS versions, 60 fps and earlier failures remain open. Work moves to proofing, HDR/EDR and print.

[Guide](../PhotoCraftSwift/docs/CHANNEL_SEPARATION.md) · [Evidence](../PhotoCraftSwift/docs/CHANNEL_SEPARATION_470.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-470).

<a id="dev-step-471"></a>

## 2026-11-07 — Step 471: large soft proofs

Soft proofing rejected documents above 8 megapixels even though the canvas could hold larger images. Preparation now uses sparse/file-backed patches around the existing color proof engine. A constant evaluation represents implicit pixels; stored component and composite tiles supply the remaining patches. Native numbers and working profiles are retained. Proofing happens before area reduction, so the viewport and API overview average proofed colors and gamut warnings. The large native canvas image cache also receives the proofed image. Source pixels, history, dirty state and normal exports stay unchanged.

Before production edits, two new tests captured 104 programs from unchanged build 470. The baseline passes 17 selected tests and has the same application hash as 470. All 159,744 sample bytes and the separate 240-byte reduced preview remain exact through both the old and paged paths. The small proof-kernel body is unchanged. These are regression references made from owned samples, not independently captured Photoshop proof output.

The first implementation passes all 62 selected Debug tests. Two further tests cover custom Display P3 working profiles at 16 and 32 bits, plus maximum-size native Gray32/CMYK16 Preserve Numbers through the desktop and API. The final run passes all 64 tests, including 14 new tests; production and application hashes are identical between the two implementation runs. Patch boundaries, sparse 300,000-pixel dimensions and an allocated 8.39-megapixel source also pass. Every source, log and product is retained.

The isolated Debug app passes deployment metadata, full entitlements, signature and payload checks. It is unlaunched because native automation still reports a closed connection. Optimized 471 joins a later stable batch; latest universal remains 470. Printing still has its separate preparation limit, and HDR/EDR proof display remains unfinished. Exact Photoshop gamut algorithms/defaults, legacy/color-blind presets, PSF interchange, per-window behavior, live controls, supported machines, dense capacity, 60 fps and earlier failures remain open. Work moves to photo alignment and merging.

[Guide](../PhotoCraftSwift/docs/LARGE_SOFT_PROOF.md) · [Evidence](../PhotoCraftSwift/docs/LARGE_SOFT_PROOF_471.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-471).

<a id="dev-step-472"></a>

## 2026-11-07 — Step 472: large image stacks

Statistics rejected a combined sample grid above 16 megapixels and more than 16 source frames. Preparation now evaluates implicit pixels once and processes stored sample support in file-backed patches. The eleven scalar operators are unchanged. Source order, visibility, masks, group treatment, transparent-sample exclusion and maximum alpha retain their previous behavior. Source photos remain editable in the Smart Object; mode switching, None, native saving and Undo use the same native and API implementation.

The native source picker follows the existing document-layer target. Automatic alignment keeps its separate limits, and HTTP creation keeps seven shared source slots plus one output slot. Source frames spill through the existing exact-copy Core operation before embedding. The native dialog reduces the finished result for display, without reducing input photos or changing the statistics.

The unchanged previous application first captured 99 programs across all eleven modes, three depths and three source arrangements. That baseline passes 10 tests. The first implementation build stopped at a missing `try` in a new Undo test; the next stopped at an internal renderer called across the module boundary. Both compile attempts and their cached products are retained. Preview preparation was moved into Imaging. The next run passes 43 of 44 methods; its new API test used the first source share instead of the new output share. That test address was corrected without changing production code. One request still raced the new window’s initial rendering; the test now waits for the existing tasks and fetches the public revision before editing. All failed runs remain recorded. The final 44 selected Debug tests pass, including 13 new tests. All 152,064 captured sample bytes remain exact, and the old small scalar loop is unchanged. Tests also cover 65 frames, a 17-source editable stack, maximum sparse geometry, an allocated 8.39 MP input and an owned source above 256 MiB.

All 44 selected checks pass on Apple Silicon and translated Intel. The broader batch passes 92 tests on Apple Silicon and 90 on Intel. Two Intel soft-proof reference tests still fail; the old and paged proof paths agree on Intel. Universal build 472 is an unreleased validation candidate. The latest fully qualified universal build remains 470. The isolated package is unlaunched. Live controls, full RAW02, independent Photoshop statistics pixels/defaults, complete alignment/blend/HDR workflows, physical capacity, supported machines, 60 fps and earlier failures remain open. These captured buffers establish regression retention; they do not establish Photoshop parity. Work moves to original PhotoCraft project migration.

[Guide](../PhotoCraftSwift/docs/PAGED_IMAGE_STATISTICS.md) · [Evidence](../PhotoCraftSwift/docs/PAGED_IMAGE_STATISTICS_472.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-472).

<a id="dev-step-486"></a>

## 2026-11-07 — Step 486: Classic RGB16 gradient boundaries

Two samples in the retained Classic RGB16 Gradient Map corpus differed from Photoshop by one working level. An exact-rational interpolation experiment made the result worse, increasing the differences to six. Using a fused second multiplication and addition removes the linear mismatch and leaves the older curved sample open. The rule applies to every Classic RGB16 linear segment; it has no preset-name or sample-position exceptions.

The candidate was fixed before three new owned references were recalculated and saved in Photoshop. Their controls cover linear, partial-smoothness and curved gradients with opaque and partial-alpha rows. New core, native-file/PSD/PSB and native/API/history tests exercise the actual path. A separate public-format reader finds all 786,624 merged sample bytes exact in each Debug, optimized Apple Silicon and translated Intel variant: 2,359,872 checked bytes. This does not establish whole-PSD or all-gradient equality.

All 61 selected Debug tests pass. Optimized Apple Silicon passes 61/61; translated Intel passes 60/61. All three new methods pass on both. The remaining Legacy float-transfer vector170 failure has exactly the same values on the retained build485 Intel binary. Its test, fixture and failure remain; no tolerance was widened and the batch is not recorded as wholly passing.

The isolated universal app opens an owned two-layer RGB16 reference. Reverse, Command-Z and Command-Shift-Z edit and restore it with the expected dirty state. At 100% the strip stays within the canvas viewport. The restored document closes without a Save prompt and the app quits normally; older running apps remain. Minimum macOS14 metadata, unchanged entitlements, signatures, payload and extracted ZIP pass. The package is a validation candidate; build480 remains the latest fully qualified selected universal.

The record retains an initial zero-test filter error, genuine pre-repair failures, a private staging-driver path error and all repaired attempts. No original numeric fixture was changed. One prior linear-corpus allowance was tightened to require zero differences; the curved allowance remains. Native92, Actions60, commands, menus, keys and cursors are unchanged. API discovery documents the shared kernel and its remaining limits.

The requested disk cleanup removes 20 unused old secondary app extractions only after matching every file, mode, symlink and signature against a retained primary copy. It reclaims about 5.1 GB. Every primary/current/running/failed app, archive, source and GitHub item is retained. A failed first read-only verifier is also preserved. Separate model-runtime probes establish the next AI01 investigation without claiming model or Photoshop equivalence.

Full A06 remains open: Smooth, the curved residual, RGB32 fill bits, dither/profiles/defaults, physical platforms and performance still need work. Earlier API and Fill-modal failures remain. Next: AI01 on-device model infrastructure, then AI02. All original package requirements remain.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-486) · [Guide](../PhotoCraftSwift/docs/CLASSIC_RGB16_BOUNDARIES.md) · [Evidence](../PhotoCraftSwift/docs/CLASSIC_RGB16_BOUNDARIES_486.json)

<a id="dev-step-485"></a>

## 2026-11-07 — Step 485: sampled Hue/Saturation ranges

Photato rejected Photoshop files after a color was sampled in Hue/Saturation. The saved adjustment record contains the sampled swatch’s hue, saturation and lightness; our reader expected fully saturated swatches at fixed lightness.

Four owned Photoshop files cover plain orange sampling, adding green, subtracting orange and sampling gray. Two native regression tests reproduce the rejection. The repair stores those display values separately from the pixel adjustment. Native Properties uses the stored color, presets and PSD/PSB preserve it, and existing API settings can read, replace or clear it. Native files require version 92 and recorded Actions require version 60 when the new data is present. Older documents and recipes keep their previous minimum versions.

All 68 selected Debug tests and the same 68 optimized tests pass on Apple Silicon and translated Intel, including 14 new tests. A separate public-format reader checks 16 fresh and retained PSD/PSB exports per variant: all 6,528 adjustment-record bytes match the Photoshop references. The Hue/Saturation transfer code and old numerical fixtures are unchanged. This verifies the captured settings records, not every Photoshop image operation.

Failed attempts remain in the record. A relocated compiler cache prevented the first isolated build. A driver reused an exclusive receipt name. Later new-test repairs corrected an enum name, an expectation that a constrained range handle would pass its neighbor, and a selected-frame setup that contradicted the document. The application implementation stayed unchanged through those final test repairs. The qualified source was copied into the main project only after checkpoint 484’s audit finished; all 7,619 inputs match the tested copy.

In the actual universal app, the orange reference opens with a 37°/65%/50% swatch and the saved 352°/22°/52°/82° range. Changing the end to 60° changes the swatch hue to 41°, retaining saturation and lightness. History Undo restores the original values. After canvas focus, Command-Shift-Z and Command-Z redo and undo the edit and restore the clean document state. Accessibility button actions had left the numeric editor focused during the first shortcut attempt; that context is recorded separately. The gray reference opens with a 0°/0%/50% swatch. Both owned documents close unchanged and the validation app quits normally. Older running builds are preserved.

The universal candidate’s two architectures, macOS 14 minimum metadata, unchanged entitlements, signatures, payload and extracted ZIP pass. Full Hue/Saturation and Color Balance output fidelity, on-canvas sampling, prominent colors, targeted dragging, physical platforms, accessibility and 60 fps remain open. The older Fill modal and broader API failure remain unresolved. Build 480 remains the latest fully qualified selected universal. Next: A06 gradient and RGB32 fill differences, then AI01. All original package requirements remain.

[Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-485) · [Guide](../PhotoCraftSwift/docs/SAMPLED_HUE_RANGES.md) · [Evidence](../PhotoCraftSwift/docs/SAMPLED_HUE_RANGES_485.json)

<a id="dev-step-484"></a>

## 2026-11-07 — Step 484: Quick Mask selection semantics

A full selection could disappear when leaving Quick Mask. Selected Areas also started with the wrong coverage when there was no selection, and selected-area PSD planes were interpreted as coverage rather than editing gray. These are distinct states, even when their pixels look similar.

Owned Photoshop documents establish the behavior for no selection, explicit full and partial selections, switching the display indication, and filling with Black through the dialog. Seven PSD fixtures are included with provenance. An earlier shortcut attempt saved white rather than black; it is retained as a diagnostic and is not used as the Black-fill reference.

The shared native/API commands now retain the selection origin and preserve explicit full selections. Selected Areas starts without an overlay when there is no selection. PSD/PSB readers and writers convert selected-area editing gray consistently, including auxiliary-only Multichannel files. Imported Float32 gray samples are retained separately because inversion loses some source bits. That retained data requires native format 91; older features keep their existing minimum versions.

The first baseline ran 18 checks: eight passed and ten exposed the defects. The first repair had a new-test compilation error. The next batch passed 60 of 64; two older expectations contradicted the new independent reference/version requirement, and two new tests had incorrect permission or sparse-metadata assumptions. The corrected source passes all 64 focused Debug checks and all 82 selected optimized checks per architecture, including 17 new methods. Failed attempts remain available. The 81 earlier auxiliary fixtures retain all 1,230,240 checked raw bytes per run. Eight finite Float32 source words survive native/PSD storage exactly across all three variants; that is not a claim about every Photoshop HDR operation.

The actual native app shows the expected red overlay when the indication changes with full coverage, a full selection on exit, and no overlay on fresh Selected Areas entry without a selection. The Fill check is incomplete. Selecting Black through accessibility stops exposing the dialog, but a process trace shows it still running in NSAlert.runModal. Keyboard cancellation, rebinding and window controls did not recover it through the available interface. It is not yet established whether this is an application defect or automation/window targeting. The owned temporary document and validation process are preserved; no successful Fill, Undo or normal quit is claimed.

The first final source check reported a mismatch in an older gradient-map fixture. Immediate rereads matched the frozen hash; no file was rewritten. A separate full rerun passes all 7,608 inputs. The failed check is retained and its cause remains unknown.

The universal candidate has both architectures, macOS 14 minimum metadata, unchanged entitlements, verified signatures and an exact extracted ZIP. Native API discovery and download negotiation describe the updated semantics and retained data. Factory menus, shortcuts and cursor policy are unchanged. Full S05, earlier failures, dense maximum-size documents, physical platforms, accessibility and 60 fps remain open. Build 480 remains the latest fully qualified selected universal. Next: A02 Hue/Saturation and Color Balance, then A06.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-484) · [Guide](../PhotoCraftSwift/docs/QUICK_MASK_SEMANTICS.md) · [Evidence](../PhotoCraftSwift/docs/QUICK_MASK_SEMANTICS_484.json)

<a id="dev-step-483"></a>

## 2026-11-07 — Step 483: Script Events Manager

Photato can now run a recorded Action when a document is created or opened. File > Scripts > Script Events Manager has Enable, a registration table, event and Action pickers, Add, Remove, Remove All and Done. Configuration saves as it changes and starts disabled. Scripts and the other listed application events remain unavailable.

The manager uses the existing native Actions engine. Events wait for opening to finish, then run in order. Each Action has its normal Undo. Changes to the document, Action library, configuration or document lifecycle reject stale work before it commits. Recovery and focusing an already-open document do not run the event again. Earlier completed Actions remain undoable if a later Action fails.

The optional API exposes the same configuration and results through GET/POST /v1/automation/events. Its separate permission explains that registrations can affect unshared documents. That permission also protects edits to registered Actions, including temporarily disabled registrations. Stopping the API resets permission; it does not erase saved native event configuration. Complete request, state and result schemas are included. This endpoint does not implement an Adobe script runtime or desktop plug-in host.

The first attempt compiled the app but failed to compile a new test that tried to assign a read-only document property. The repaired test uses a real edit. Later source review caught a startup wiring issue that would have kept normal registrations only in memory; the actual startup factory was corrected and tested. An API review then found that ordinary Action editing could bypass the new permission, so registered Action edits were fenced and tested. Every attempt and its products are retained.

All 58 focused Debug checks and the same 58 optimized checks pass on Apple Silicon and translated Intel, including 20 new tests. Nine event-versus-manual native, PSD and PNG files across 8/16/32-bit depth match across all three variants: 14,470 bytes each. Those comparisons test our own shared engine; they do not establish Photoshop pixel equivalence.

The broader optimized batch passes 128 of 129 methods on each architecture. One old API check expects HTTP422 and receives400. The unchanged test fails the same way on the retained build480 binaries. Its assertion was preserved. Build483 is a validation candidate, while480 remains the latest fully qualified selected universal. The universal candidate’s minimum-system metadata, architectures, entitlements, signature and extracted ZIP were checked.

In the actual native candidate, an Invert Action was recorded, registered for New Document and run automatically on a white canvas. The canvas became black; Command-Z restored white. Reopening the manager showed one completed Action. Shrinking the manager retained Done and exposed scrolling. The owned registration was removed and disabled; the test documents were restored and the validation app quit normally. The older running builds were preserved. Screenshots are in the chat transcript; no local screenshot file is claimed.

Photoshop27.2 supplied the observed manager controls; its original empty, disabled configuration was restored and rechecked. Exact event timing/order/defaults, live OpenDocument, physical supported-platform and accessibility coverage remain open. Photoshop plug-ins remain unsupported: native C++, UXP and CEP require separate hosting work under AUT03. The HTTP API does not provide that hosting.

No source was published, app installed over a current build, build deleted, Store record changed or software released. All original package requirements remain. Next: S05 channels, then A02 adjustments.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-483) · [Guide](../PhotoCraftSwift/docs/SCRIPT_EVENT_ACTIONS.md) · [Evidence](../PhotoCraftSwift/docs/SCRIPT_EVENT_ACTIONS_483.json)

<a id="dev-step-482"></a>

## 2026-11-07 — Menu inventory reconciliation

The saved menu CSV had fallen behind the app. It listed 802 entries; the verified Apple Silicon and translated Intel captures both contained 809. Seven paths were missing and 88 selector bindings were stale. The replacement CSV comes from those captures, with the old file and proposed replacement retained. Its labels distinguish submenus, partial native operations and disabled placeholders.

A new reconciliation script checks the captures against the current native source, tests, fixtures, assets and project files. It requires matching architecture reports, the original Photoshop menu order and factory shortcuts, consistent command identities and statuses, and all 16 modifier combinations for each captured main tool. It refuses existing report files and output locations inside product or tooling directories. It writes a proposed CSV for review rather than replacing the tracked inventory itself.

Twenty new tests passed first. Combined with the archive-tool tests, 36 passed. A further output-location guard and test were added; all 37 then passed, including 21 new inventory tests. The original failed drift report is retained alongside the corrected passing report. The manual CI template now discovers both test files and retains their fixture folders; it has not been dispatched.

The measured inventories are 652 tracked commands, 809 menu entries, 55 main tools with 880 modifier contexts, and 40 professional acceptance scenarios. The commands remain 459 partial and 193 pending. Every professional scenario remains planned. These counts describe different things and do not provide a Photoshop completion percentage.

The original 801-entry Photoshop menu fixture and all 102 primary and eight alternate shortcuts are unchanged. Later Adobe commands and Photato-specific additions remain separate. Installed Photoshop is 27.2; Adobe's documentation also describes 27.11 features, betas, services and platform-specific behavior. The records distinguish those references and preserve the gaps, including plug-in hosting.

Application build 480 and all 7,499 native product inputs match the captured source. No editing code, native control, numerical fixture, entitlement or product API changed. No new application build, live UI check, full-suite run or archive is claimed. All original package requirements remain open where unqualified. Next: AUT02 automation, then S05.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-482) · [Evidence](../PhotoCraftSwift/docs/INVENTORY_RECONCILIATION_482.json)

<a id="dev-step-481"></a>

## 2026-11-07 — Repeatable archive validation

The package checker still used fixed build paths and historical test counts. We retained it and added a separate archive validator that takes an explicit archive, source manifest and new report path. It checks production identity and version, both architectures targeting macOS 14, required resources and an exact executable/dSYM UUID match for each architecture.

A new local pipeline runs the tool tests and the selected editing checks, creates an unsigned universal archive through the existing Xcode project, verifies it, and compares its ZIP extraction with the original. It preserves logs and failed outputs, detects source changes and refuses existing output directories. Capacity checks stop it before another step if disk space is low. Existing builds are retained.

Sixteen new tests use real Swift-built ARM and Intel executables and dSYMs, plus damaged copies. They check missing or mismatched symbols, stale metadata, altered resources, source mutations, unsafe release settings, path escapes and report overwrite refusal. The first private runner failed to parse before any test started; its source and error remain in the record. The tool tests then passed twice before the full pipeline run.

The pipeline exposed an old menu test writing a report into the source checkout. It now uses the existing capture-directory setting when supplied and creates the destination. All original menu, shortcut and row assertions are retained; the fallback output path remains available.

The complete local run passes: 16 tool tests, all 104 selected editing checks on Apple Silicon and translated Intel, and 34 archive checks. Both dSYM UUIDs match their binaries; every extracted archive file matches the verified original. The seven controlled lookup cases still retain all 1,474,560 original Photoshop RGB bytes on each architecture.

The application remains build 480. No editing algorithm, native control, API, menu, shortcut, cursor, fixture, entitlement or project setting changed. The archive is unsigned and unlaunched. A manual-only GitHub workflow template is prepared with pinned official actions and read-only repository permission; it has not been installed in the public fork or dispatched. Signing, Apple validation, actual sandbox behavior, privacy declarations, hosted execution and full REL01 remain open. No software was uploaded, submitted or released.

Next: AUD01 inventory reconciliation, followed by AUT02 automation workflows. Full Photoshop parity remains open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-481) · [Evidence](../PhotoCraftSwift/docs/ARCHIVE_VALIDATION_481.json)

<a id="dev-step-480"></a>

## 2026-11-07 — Independent Color Lookup references

We created our own patch images and two small Cube lookup tables, then saved editable results in Photoshop at 8, 16 and 32 bits. A second 8-bit image used odd-valued samples to distinguish rounding rules. A separate Python parser extracted the saved composite planes; Photato's renderer did not produce the expected data.

Those files exposed differences our earlier self-comparisons missed. Native creation and Reset now use Tetrahedral interpolation. The 8-bit path uses the observed working-code conversion, while 32-bit lookup edits retain linear samples. The interpolation expression also needed a different evaluation order to preserve low Float32 bits. Old documents and omitted Photato API parameters retain their explicit Trilinear choice.

The PSD reader previously rejected Photoshop's embedded lookup cache. It now accepts a bounded float CLUT only when its values exactly match the embedded table. The writer needed repair too: Photoshop rejected a fresh export after all pixel tests passed. Live diagnostic files isolated the descriptor's declared padding and required cache. Fresh exports now contain correctly framed records, the proper name field and a newly encoded cache with Photato metadata. No proprietary Adobe lookup or cache implementation was copied.

All 95 selected Debug checks and the same optimized checks on Apple Silicon and translated Intel pass, including 16 new methods. All 1,474,560 reference RGB bytes match through editable and destructive native editing code, Photato HTTP and both action-job routes. Structure, source-table retention, cancellation, Undo/Redo, guards, file transfers, menus and cursors are tested separately. Nine additional auxiliary-channel and PSD-transfer checks also pass in Debug and both optimized architectures. Earlier failed sources, compile errors, incorrect test headers and selectors, and rejected native files remain in the record.

Photoshop opened fresh Cube3 exports at RGB8, RGB16 and RGB32 without warnings. We toggled Dither on and off, saved separate copies and independently compared them with the original references: all 688,128 RGB bytes matched. Those derived files verify interchange; they do not replace the original independent oracles.

The selected lookup increment is complete; Q04 and full Photoshop parity remain open. Other modes, profiles, LUTs, domains, shapers, masks, blends, stochastic Dither, wider files, physical platforms, 60 fps and full-suite qualification still need work. The universal validation package is unlaunched and unreleased. Next: REL01 archive, sandbox and release CI, followed by AUD01 inventory reconciliation.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-480) · [Evidence](../PhotoCraftSwift/docs/INDEPENDENT_COLOR_LOOKUP_480.json)

<a id="dev-step-479"></a>

## 2026-11-07 — Color Lookup property responsiveness

Editing a Color Lookup layer used the synchronous command path, including full document validation. Properties now sends that preparation to the existing background worker. The controls disable competing edits and offer progress and Cancel. Publication, Undo history and dirty notifications stay on the main actor; cancellation or a replaced/closed document discards unfinished work.

The LUT and pixel kernels are unchanged. Tests compare the resulting document, native file and rendering with the former expression and the API at every supported depth. They also check masks, Undo/Redo, recorded Actions, locks, invalid tables, busy/modal/transform/component targets and stale/cancelled work. Two older tests await completion before their original assertions. The first compile caught a new test attempting a private setter; the failed source and products remain preserved. The first implementation shortened submission but left main-actor timer gaps unchanged. A sampled run found repeated sorting of unchanged raster keys in document comparisons. A positive shared-storage identity proof now skips that work while preserving the original logical pixel-bit fallback. Four new Core tests and the existing surface, mapped storage, validation and serialization suites cover the change.

The benchmark measures 20 edits for each combination of three document cases and two LUT sizes. It uses owned dense gradients, fresh sessions and excludes initial/final rendering. The first two multi-layer fixtures exceeded Photato’s counted raster budget and measured rejection; those failed runs are retained. The corrected 32-layer case uses 1024 × 1024 images and validates before timing. The other cases are 24 MP and 36 MP single-image-layer documents.

All 161 selected Debug checks and the same optimized checks on Apple Silicon and translated Intel pass, including twelve new correctness checks. The separate benchmark records submission, completion and a main-actor timer. Exact measurements and their limits are in the evidence record. Faster submission is useful, but does not prove physical input latency, sustained painting or 60 fps. History spilling/rendering, the existing raster budget, broader platforms and full Q03 remain open.

Next: independent Photoshop references, then release-readiness work. The master goal remains active and incomplete.

[Guide](../PhotoCraftSwift/docs/LOOKUP_PROPERTY_RESPONSIVENESS.md) · [Evidence](../PhotoCraftSwift/docs/LOOKUP_PROPERTY_RESPONSIVENESS_479.json) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-479)

<a id="dev-step-478"></a>

## 2026-11-07 — Local Color Lookup painting

Photoshop’s current Adjustment Brush menu includes Color Lookup. Photato already had a LUT engine and layer editor, but its brush type list omitted it. That prevented painting a local LUT adjustment through the tool. The existing native picker and validation now accept it, and Properties keeps the lookup file, interpolation and Dither editable.

Painting creates or refines the same masked adjustment layer. Preview/Cancel, Add/Subtract, object masks and Undo/Redo keep their existing transaction path. The API can use an uploaded lookup or a Photato Look, retain the embedded table during partial edits, or explicitly clear it. Clearing an API cache does not change a table already in a layer.

Portable Actions 59 records the new brush operation with its table, so replay does not depend on an upload session. Earlier action minima and native lookup layer storage remain. Native creation currently uses an identity lookup. The reference’s filmstock_50.3dl setting was observed in its current context, not established as a factory default; no Adobe lookup assets were bundled.

The first compile caught a malformed schema literal and an attempt to call a command initializer that does not exist. The failed source/logs and cached477 products were retained. The fix split the schema and reused the existing strict lookup parameter resolver directly. All 94 selected Debug checks and the same94 optimized checks on Apple Silicon and translated Intel pass, including 8 new checks. 38 older tests advance only their global supported Actions-ceiling expectation from 58 to 59; per-feature version gates and numerical/sample checks remain intact.

Live reference inspection used an owned synthetic photo. The test stroke was undone, the original tool selection restored and the photo closed without saving. It also exposed Photoshop’s newer Color and vibrance option; its semantics need separate investigation. The current native validation package is verified and unlaunched. Native-code gestures are tested; current physical interaction and exact Photoshop pixels remain unqualified.

Full lookup formats/defaults/interpolation/dither/profile output, saved Tool Presets, large object masks, physical platforms, performance and the original B08 scope remain open. Next: responsiveness and cancellation, then independent reference coverage.

[Guide](../PhotoCraftSwift/docs/ADJUSTMENT_BRUSH_LOOKUP.md) · [Evidence](../PhotoCraftSwift/docs/ADJUSTMENT_BRUSH_LOOKUP_478.json) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-478)

<a id="dev-step-477"></a>

## 2026-11-07 — Sky preset groups and batch import

The sky library was a flat list, and native Import accepted one image. It now stores named groups and image memberships, with controls to create, rename and remove groups, filter the list and move a sky. Removing a group requires a choice: keep its images in Ungrouped, or remove them from the library. Layers already in a document retain their pixels.

Import accepts several images and validates the whole batch before saving any. An invalid image, storage/capacity failure, cancellation or changed library/selection prevents partial publication. The API exposes the same operations and returns groups and memberships. Library management leaves document pixels, selection and Undo history unchanged.

Version 1 libraries open without being rewritten. Their next successful edit stores version 2 while retaining image IDs, names and original bytes. Unknown versions and corrupt files stay preserved. The internal format is separate from Adobe `.sky` files.

The first compile caught an initializer using a field before the observed object was fully initialized. Its source, logs and cached476 products were retained before repair. The private test runner also needed module-qualified test names; no tests had run before the compile failed. The corrected source passes all 51 selected Debug methods and the same51 optimized methods on Apple Silicon and translated Intel, including 9 new methods. Existing sky, menu/cursor and independent RGB32 checks pass. No prior numerical fixture or tolerance was changed; older float32 sky flattening differences remain recorded.

The owned offscreen view shows the added controls fitting its scrolling sidebar. Live Photoshop inspection now opens Sky Replacement on an owned synthetic photo and shows its thumbnail gallery and an existing Blue Skies group. On that input Photoshop shows Foreground Lighting 48 and Edge Lighting 70, while Photato currently initializes 50 and 0. These are observed context values, not proven factory defaults; automatic initialization and exact output remain open. The preview was cancelled and the owned photo closed unchanged. This does not qualify current Photato live interactions. The universal validation package is verified and unlaunched.

Large sky canvases/masks, exact Photoshop detection/output/defaults/layer structure, `.sky` transport, recents/default skies, wider library organization, live controls, physical platforms/performance and full AI09 remain open. Next: Adjustment Brush, then Q03.

[Guide](../PhotoCraftSwift/docs/SKY_PRESET_GROUPS.md) · [Evidence](../PhotoCraftSwift/docs/SKY_PRESET_GROUPS_477.json) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-477)

<a id="dev-step-476"></a>

## 2026-11-07 — Blank video drawing layers

Video-frame painting already existed, but the New Blank Video Layer command was unavailable. This workflow adds separate drawing footage for animation and rotoscoping. The Layer menu, Timeline menu and video.edit API now create the same transparent clip with one Undo step.

A dense frame array would impose the existing imported-media limit on empty drawing footage. The new collection stores one prototype and only frames that differ from it. Logical indexing stays constant-time; validation, archive and memory accounting visit stored samples. Existing imported clips keep their old array encoding and decode budgets. Native version 90 retains sparse footage, including sources kept during animation conversion.

The first compile caught an old fixture assigning an array directly to the changed collection type. Two old test expressions now wrap the same expected surfaces; their values and assertions remain. The first retained executable was still cached from build 475, and its initial origin label was corrected rather than counted as a new pass. Later runs pass the full selected suite. Recovery-header checks also cover indexed versions 89 and 90.

All 111 selected Debug methods and the same 111 optimized methods on Apple Silicon and translated Intel pass, including 13 new tests. These cover native/API creation, exact brush results, gesture preview/Cancel/commit, neighbouring-frame isolation, history, file/conversion recovery, strict parameters, busy/stale/mask contexts and explicit native90 downloads. Existing video/rendering, menu/cursor and independent RGB32 regressions pass.

An owned 300,000 × 300,000 canvas with a 24-hour timeline at 240 fps keeps one empty stored frame and remains below the tested document/archive storage bounds. This is a logical storage test, not dense-capacity or 60 fps proof. The selected native universal package is verified and unlaunched. Live native inspection remains unavailable.

Photoshop’s exact creation defaults and group placement, additional frame/source editing, footage interpretation/replacement, longer imported media, codec/HDR/interchange, physical platforms, performance and the full SP01 scope remain open. Sky Replacement is next, followed by Adjustment Brush.

[Guide](../PhotoCraftSwift/docs/BLANK_VIDEO_LAYERS.md) · [Evidence](../PhotoCraftSwift/docs/BLANK_VIDEO_LAYERS_476.json) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-476)

<a id="dev-step-475"></a>

## 2026-11-07 — Generated image jobs and saved originals

The old system-image callback used the current document and a mutable prompt. It now captures a request ID, initial prompt and document revision before opening the system interface. Cancel, close, duplicate and late callbacks share that identity; one accepted placement is one Undo step.

Returned originals are saved atomically before decoding or placement. A separate Generated Results window can recover them after the source changes or closes. It opens a new unsaved document without a model. Explicit Move to Trash is the only removal action; the inbox has file/count/byte limits and no automatic purge. Native archives keep original bytes and descriptive records with generated layers.

The API exposes the same job, records, original downloads and saved-result recovery. Private-inbox access is tied to the real document session, so imported UUIDs cannot grant access. Preparation opens the native prompt sheet and never starts a model from HTTP. File transfers and local Trash have separate permissions and revision/lifecycle checks.

Tests found an invalid metadata-key length and a physical-path mismatch in the new inbox. The metadata now follows the existing four-byte Core contract. A POSIX path resolves the macOS /var alias for the unchanged strict atomic writer after Foundation resolution failed to do so. Testing also caught a surviving closed document still permitting another image request; closing now disables that source, and the API reports eligibility.

A new fixture closed an unregistered document before creating Photato’s custom AppKit document controller. The debugger caught a nil paint palette when a later test published a recovered document. The fixture now follows application startup and registers its document before closure. The complete selected batch passes afterward on unchanged production code. Failed attempts remain in the record; this does not explain or close every earlier crash.

All 67 selected optimized methods pass on Apple Silicon and translated Intel, including 30 new methods. Source09 passes 67 focused Debug methods. Storage failure, interrupted publication, corruption, quotas, symlinks, stale/failed/cancelled/closed placement, native archive reopening and API session/permission behavior are covered with owned images. Existing menu/cursor checks and independent RGB32 regressions pass in the optimized batches. No model was invoked.

The SDK does not provide typed model, seed or final edited-prompt fields, so those remain unknown. Original file metadata is retained but not interpreted or independently qualified. Full variations, generative workflows, provider/native live checks, physical-platform/performance qualification, exact Photoshop output/defaults and the complete AI07 package remain open. The next selected package is SP01.

Photoshop plugins do not run in this build. Matching menus or the Firefly web API does not supply Adobe’s desktop plugin interfaces. AUT03 remains open.

[Guide](../PhotoCraftSwift/docs/AI_GENERATION_LIFECYCLE.md) · [Evidence](../PhotoCraftSwift/docs/AI_GENERATION_LIFECYCLE_475.json) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-475)

<a id="dev-step-474"></a>

## 2026-11-07 — OpenEXR HDR files

The file-format audit found that layered TIFF and several PDF export paths already worked. OpenEXR was missing. An Apple encoder probe wrote Half samples from 32-bit input, so the new file codec follows the public ASWF layout directly, using Swift and system ZIP compression. It preserves tested negative, above-white and zero-alpha colors without SDR tone mapping.

Open, Save, Save a Copy and API file transfers now share this codec. The save dialog offers compression, precision and transparency. Ordinary Save rejects choices that would discard editable content, remove meaningful alpha, reduce precision or convert the working profile. Copy makes those choices explicit. EXR output avoids the old 36-megapixel dense-raster Save guard; broader size and workspace limits remain.

The first compile caught a new test calling a nonexistent helper. Debug batches later crashed in shared revision/native paths; isolated replays against the same retained binary passed, without establishing a cause or repair. The first optimized run passed 94 of 96 checks on Apple Silicon. The remaining two fixtures needed the new format title and the required API replacement field. Intel compilation exposed unavailable Float16 conversions. Native Swift bit conversion now handles Half on both architectures, with independent reference words for every finite pattern.

The final optimized batch passes all 97 selected checks on Apple Silicon and translated Intel, including all 14 new tests. Seven captured EXR files match across architectures; an independent Python reader verifies 6,168 sample bytes each. The validation-only universal package passes minimum-system, entitlement, signature, payload and extracted-archive checks. It has not been installed or released.

These are owned synthetic format references, not Photoshop-generated EXR results. Other EXR compression, tiled/deep/multipart/AOV files, wider profiles/metadata, dense maximum capacity, live controls, exact Photoshop defaults/output and all earlier failures remain open. The complete I04 package remains in progress. Next is AI07, then SP01.

[Guide](../PhotoCraftSwift/docs/OPENEXR.md) · [Evidence](../PhotoCraftSwift/docs/OPENEXR_474.json) · [Detailed record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-474)

<a id="dev-step-473"></a>

## 2026-11-07 — Step 473: embedded originals in source projects

The source importer rejected every linked Smart Object, including references to originals already embedded in project metadata. The import now looks up those embedded records with the existing native linked-data decoder. Original bytes, shared identity, placement, filters and retained appearance remain separate editable data. External records, aliases, missing sources, duplicates and malformed data reject without opening archive-supplied paths. Unrelated globals remain source provenance.

Nine owned fixture derivatives cover affine placement, shared sources and statistical modes at three depths. Before production changes, build472 rejected them even though the native block decoder could recover every original. Their 737,280 cache bytes were captured and remain exact after migration. The original payloads also match exactly. Native Open, Edit Contents, shared-child updates, Undo, Save As and API upload/download/rasterization tests pass. Imports cannot overwrite the original source project.

All 11 new tests pass. The broader run has 41 planned checks: 39 pass, an older uncached-render method retains nine original-Rust assertions, and an older nested-source HTTP test crashes by signal10. The same crash reproduces in preserved build472; the uncached changed-word report is identical before and after this change. The 22 checks skipped after the crash pass separately with unchanged sources and application bytes. Every attempt and product is retained; no old assertion, fixture or numerical kernel was changed.

The isolated Debug app passes macOS14 metadata, entitlements, signature and payload checks. Native automation still reports a closed connection, so the app is unlaunched and live checking remains pending. Optimized473 joins a later batch. Full I03, additional source formats/features, independent Photoshop output/defaults, physical capacity, supported machines, 60 fps and earlier failures remain open. Work moves to export and interchange formats.

[Guide](../PhotoCraftSwift/docs/PCRAFT_LINKED_ORIGINALS.md) · [Evidence](../PhotoCraftSwift/docs/PCRAFT_LINKED_ORIGINALS_473.json) · [Technical record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-473).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Previous page](part-02.md)
