# Window presentation and document-worker availability

The full331 test process stopped in an AppKit recovery-autosave wait after repeatedly presenting windows on a locked Mac. Its retained sample shows about160 blocking NSAnimation workers. A fresh background writer could not be scheduled.

Checkpoint332 reproduces the worker exhaustion with200 owned window cycles. Plain AppKit text windows and SwiftUI text windows both reach165–166 threads, and a new background task times out. Disabling the window transition keeps the count at16/7 and background work completes. These are controlled local AppKit measurements on the current host, not physical frame-rate or Photoshop acceptance results. Actual app qualification is recorded in the working checkpoint.

The original spinner hypothesis was rejected. Two hundred unshown native spinner windows do not exhaust workers; replacing SwiftUI’s progress control or detaching its hosting view does not fix shown windows. Those failed/negative experiments are retained.

App-owned windows now use PhotatoWindow or PhotatoPanel. Their public AppKit animationBehavior is none. Workspace windows, floating panels, tool/progress windows and the tear-off backdrop share this policy. The app keeps its native controls and progress indicators. System-owned alerts and file panels are unchanged. The policy does not alter pixels, Save/Recovery algorithms, document formats, menus, shortcuts, tools or modifier dispatch.

The Photato API keeps208 commands and the same request/state/transaction/history semantics. Recovery capability metadata describes immediate owned-window presentation because it protects worker availability during background document operations. No corresponding Adobe v2 window/recovery endpoint is invented. Window-transition timing is not an editing command.

Regression qualification includes200 window/panel lifecycles followed by a background work item and exact native recovery, plus workspace/floating/progress window title/responder/presentation checks and existing document/UI/API/recovery workflows. Full supported-platform and physical UI acceptance remain open. Keep the331 archive preserved; a changed source tree does not change its qualification.

See WORKING_CHECKPOINT_332.json and DEVLOG332 for current results and artifacts/runs/20261101T185209Z-332-progress-lifecycle for immutable attempts.

## Layered TIFF boundary found during qualification

The wider document-recovery selection exposed a regression in the329 auxiliary-channel validation. TIFF supplies its composite raster outside the Photoshop layer adapter; the adapter declares process channels only. A negative layer count must not require a nonexistent PSD merged transparency plane in that carrier. PSDCodec now applies that merged-plane rule to actual PSD/PSB streams. TIFF ExtraSamples/auxiliary restrictions and ordinary PSD channel bounds remain enforced.

All346 affected cases pass at332 Source03, including three new cases: repeated-window/background/recovery stress, native window/responder policy and12 depth/endian/transparency TIFF sample combinations. Existing independent TIFF input/output matrices and desktop/API recovery workflows also pass. Two outdated tests were repaired: supported archive75–78 are accepted and a deliberately unknown version rejected; supported Lab auxiliary planes are retained while a genuinely missing plane is rejected. No strict pixel comparison was removed. The complete inventory is a separate qualification.

## Startup and cancellation qualification

A fresh viewport-class process exposed a startup-order requirement: AppKit had installed a plain NSDocumentController before AppDelegate constructed the custom subclass. LLDB captured the resulting missing DocumentWindows storage. Startup now constructs the custom controller before application UI initialization, and the viewport fixture follows that order. No runtime class replacement or private singleton reset is used. The first-instance contract is documented by Apple.

The panorama cancellation test had a race: its small worker could finish before the HTTP cancellation arrived. An internal preparation injection retains the same default Photomerge engine and permits a test barrier at the worker boundary. The test still requires active cancellation/revocation, no published document, and correct busy-state cleanup. Completion-before-cancel remains a legitimate409 response, rather than a cancellation success.

The first complete-inventory attempt is preserved as incomplete:1,627/3,241 completed records, two failed cases and one viewport process crash. Current follow-up qualification must not be represented as that earlier attempt passing.

Source04 passes all370 affected cases and all13 viewport cases in a fresh process. Production startup and the test fixture both install the custom controller before other application UI can create the default singleton. Full02 checks the complete inventory separately on that source. Earlier failures and the incomplete first inventory remain in the record.

## Completed inventory and archive332

Source04 completes all 3,242 unique cases in fresh bounded processes: 3,230 pass, 12 fail, 432 assertions, 0 unexpected errors and 0 crashes. Combined-stream warning corruption is retained in earlier incomplete reports; separate-stream capture and singular/plural failure parsing correct the diagnostic. Source05 repairs one stale supported-version rejection test, with separate passing focused evidence. Full-current green and physical long-session qualification remain open. Archive332 passes local universal/signature checks; Apple validation and media capture remain account/host gated. No tool/menu/shortcut or editing API is added; 208 typed commands, native78 and Actions30 remain.
