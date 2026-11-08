> Integrated into the source-delivery diary on 8 November 2026 UTC from the retained checkpoint494 working record. Status statements below describe that checkpoint. Local raw logs, user documents, reference sessions and app bundles are excluded from the public repository. The canonical historical-evidence audit is still pending; see the [delivery record](../SOURCE_PUBLICATION_500.md).

# Photato developer diary — checkpoint 494

Recovery and save durability now include directory synchronization after the file rename. Failed confirmation reports that new data may already be on disk. The document remains modified and its editing history is retained.

## Save and recovery behavior

The writer flushes the staged file, performs the rename through its retained parent-directory descriptor, then flushes that directory before confirming completion. It retries interruptions after publication, including when cancellation arrives. Other directory errors return an explicit failure and retain the published output. This also works in tested folders with write/search access but no listing permission.

AppKit initially replaced this failure with a generic autosave error. Recovery now retains the specific error under its snapshot identity and returns it through the matching completion. It is consumed once. The native and HTTP paths use the same implementation, preserve current edits and Undo history, clear their busy state, and allow a healthy recovery retry.

A failed settings/history write keeps the last confirmed values, revisions and timer in memory. Its file may already contain the new values. Existing external-change checks reject another update until an explicit restart reloads the file. The recent-file warning explains that distinction.

## Tests and build

| Configuration | Selected tests passed | New tests passed |
| --- | --- | --- |
| Debug, Apple Silicon | 143/143 | 11/11 |
| Optimized, Apple Silicon | 143/143 | 11/11 |
| Optimized, translated Intel | 143/143 | 11/11 |

The tests include injected I/O and space errors, directory-sync interruptions, post-rename cancellation, moved directory paths, streamed native archives, real loopback HTTP requests, AppKit recovery state, and an existing PSB output test exceeding 512 MiB. Every selected method executed; none was skipped. All 7,663 declared inputs remained unchanged during qualification. Existing tests and numerical fixtures were retained.

A local universal build passed architecture and macOS 14 deployment-metadata checks, strict signature verification, unchanged production-entitlement checks, resource/model provenance checks, and extracted-archive file-byte comparison. An independent signing replay verified the signing-related Mach-O metadata differences. The app was not launched or installed; this is a validation build.

## Failed attempts retained

The baseline exposed the missing directory sync. The first broader run passed 140 of 142 tests; two new failures identified the AppKit error-message defect. A subsequent build caught a missing MainActor annotation in a new test and executed no tests. The repaired source passed 23 focused checks before the final 143-test runs. Earlier coordinator preflight failures also remain recorded. See the detailed notes (local record: development-notes01.md), the qualification record (local record: qualification-selected01.json), and the uniquely named baseline/Debug/release logs in this directory.

## Remaining work

This completes the selected directory-durability workflow, not the complete recovery package. Full crash/restoration UX, real power-loss and network-filesystem behavior, physical Intel/macOS 14 qualification, and a live error-alert check remain open. Earlier gaps remain open too, including the Intel color-profile corpus difference retained at checkpoint 493. The full application suite and Photoshop equivalence are not established by these selected tests.

The canonical history audit is still running and was checked directly. This working diary and source have not yet been promoted into the website/project copy. All current applications, pending dialogs, builds, source snapshots and failed evidence were preserved. No GitHub, installation, App Store or release action was performed.

Next in the major-feature queue is **G02 — Warp, Puppet Warp and Perspective Warp**, followed by G05. The source audit records the current warp pixel limit and full-canvas preview path. Public Adobe references also identify handle, anchor and modifier behavior that still needs verification. The original package scope, command inventory and seven-pass order remain intact.
