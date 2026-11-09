# Repository administration record

## 2026-10-19 — Initial private GitHub repository setup

The owner requested a private GitHub repository in a side conversation, with public visibility deferred until they approve a release.

The authenticated account is `ForensicIntelligence`; the selected repository name is `Photato`. Initial inspection found no Git repository in `notphotoshop/` or its Swift and Rust source directories. Git previously resolved to an unrelated Desktop-level `exo` repository. The new repository is rooted at `notphotoshop/`, leaving that enclosing repository's configuration untouched.

Scope: preserve the Swift app and supplied Rust snapshot in their existing directories, including the Xcode project, tests, licenses, attribution and development documentation. Add a root README and Git exclusions. Do not change application code, tests, build configuration, running applications, or the main conversation's active implementation records. The captured source may include ongoing work and is not a release qualification.

The original Rust snapshot contains no preserved Git ancestry; no upstream base commit is inferred. The initial commit establishes version history from the current local sources. Local build output, artifacts, downloaded corpora, logs and user-specific state are excluded. Those exclusions are not a backup of the development evidence.

Pre-upload verification: `git ls-files -s -z` and a read of all staged blobs using `git cat-file --batch` found 1,863 files (86,469,805 bytes at the scan), no excluded paths, no symbolic links, no blobs over 50 MB, and no matches for the checked private-key, GitHub, AWS, OpenAI or Slack credential patterns. This is a bounded pattern check, not a guarantee that every possible secret format is detectable.

Created [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato) using `gh repo create ForensicIntelligence/Photato --private --source . --remote origin --push`. GitHub verification with `gh repo view ... --json nameWithOwner,url,isPrivate,visibility,defaultBranchRef,isFork` returned `isPrivate: true`, `visibility: PRIVATE`, default branch `main`, and `isFork: false`. The repository is a standalone private source repository, with upstream provenance retained as described above.

The initial source commit is `8f628341e698d64ad60165ad897a9c7850e130c9`. Both local `git rev-parse HEAD` and GitHub's `commits/main` endpoint returned that exact commit after the push. `main` tracks `origin/main`. The three shared Xcode project/workspace/scheme files are tracked. The enclosing Desktop repository still has its original `https://github.com/exo-explore/exo.git` remote. The working tree was clean at initial-upload verification.

Application tests were not rerun for this repository-only operation, and existing test results do not qualify any ongoing edits captured in the snapshot. No application source, native development checkpoint, runtime configuration, or original Rust source was edited by this setup. Only root Git metadata, exclusions, README and this administration record were added. Public visibility remains deferred until the owner explicitly authorizes it.

## 2026-10-29 — Qualified native source snapshot253

The maintainer requested another complete source commit when stable. This delivery updates `PhotoCraftSwift/` to the step253 candidate:2,660 full optimized tests and40 focused tests pass on Apple Silicon. The portable [source manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_253.json) identifies the2374 included qualified inputs;32 generated optional model/provenance/cache inputs are excluded. The original1057 tracked Rust files and upstream notices are unchanged. This remains a standalone repository with a supplied Rust snapshot, not preserved upstream Git ancestry.

The complete native source, tests/fixtures, Xcode project, scripts, assets and development documentation are included. Withdrawn purchase files are removed. Build products, runtime logs, local evidence, downloaded corpus, private documents, generated model weights and machine state are excluded. The optional model reconstruction instructions remain available. This source commit does not replace the installed app or upload another distribution ZIP; private preview243 remains the latest packaged build. Full Photoshop parity and physical Intel/macOS14 qualification remain open.

The repository stays private during development and becomes public on release day. The update is prepared in an isolated clone, preserving the unrelated enclosing Desktop repository. Source and remote verification receipts follow below after publication.

Verified source commit: [`4b3fdb6cd08c07a32d8f47f627c4687c838f10d3`](https://github.com/ForensicIntelligence/Photato/commit/4b3fdb6cd08c07a32d8f47f627c4687c838f10d3). GitHub main returned this exact SHA after push and repository metadata confirmed private visibility. The staged tree is `922ea96253d55f1b952abd5f578de26e6f9602a8`;3,880 blobs/133,460,282 bytes passed the bounded scan and all2,374 included qualification inputs match their SHA-256 manifest. The complete source passed2,660 optimized tests before publication. A documentation-only follow-up records this receipt; native code is unchanged. See [source delivery](PhotoCraftSwift/docs/SOURCE_PUBLICATION_254.json).

## 2026-10-29 — Qualified native source snapshot255

Step256 updates the complete native source to qualified checkpoint255, including retained PDF Smart Objects and the native/API placement workflows. All2,415 original qualification inputs match the65-test focused and2,682-test full optimized runs. The portable [source manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_255.json) lists the2,383 included inputs;32 optional generated model/provenance/cache inputs are excluded. The supplied1,057 tracked Rust files and all existing Git history remain unchanged.

The source, tests/fixtures, Xcode project, scripts, assets, notices and development records are included; builds, runtime artifacts and private working files are excluded. Source is prepared in the existing clean isolated checkout. This does not install an app, upload a new binary or change private visibility. The repository becomes public on release day; full Photoshop and platform acceptance remain open. Verified source commit: [`f2a9711d0f1e95c4e5bcf713bfa3181d31520057`](https://github.com/ForensicIntelligence/Photato/commit/f2a9711d0f1e95c4e5bcf713bfa3181d31520057). GitHub main returned this exact SHA after push and private visibility remains confirmed. The staged tree is `df8fbe011420e67f800f5a10ee93762faf5b2957`;3,895 files/134,204,522 bytes passed the bounded scan. A documentation-only follow-up records the [publication receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_256.json); native source stays identical to the qualified candidate.

## 2026-10-29 — Qualified native source snapshot257

Step258 updates the complete native source to qualified checkpoint257, including initial transform previews for raster/native/PSD/PSB/RAW placement, Camera Raw placement controls and corresponding APIs. All 2,419 qualification inputs match the 70-test focused and 2,690-test full optimized runs. The portable [source manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_257.json) identifies 2,387 included inputs and 32 excluded optional generated model/provenance/cache inputs. The 1,057 original Rust files and existing Git history remain unchanged.

Sources, tests/fixtures, the Xcode project, scripts, assets, notices and development records are included; builds, runtime artifacts and private working files are excluded. The repository stays private until release day. This source delivery does not install an app or upload a binary; Photoshop and supported-platform qualification remain open. Verified source commit: [`5115d649088720c395b3f3f5793e6f0fc361ead3`](https://github.com/ForensicIntelligence/Photato/commit/5115d649088720c395b3f3f5793e6f0fc361ead3). GitHub main and the staged tree match, and private visibility remains confirmed. The [publication receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_258.json) records qualification and scope; a documentation-only follow-up preserves that receipt.

## 2026-10-30 — Qualified native source snapshot280

Step281 publishes the complete qualified native source280, including brush/retouch feedback and semantic Actions/APIs,300000-side sparse canvas geometry, paged dense RGB input and checked mapped native persistence/file IO above512MiB. All2496 local qualification inputs match the71-test focused and2829-test full optimized candidate. The portable [source manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_280.json) identifies2464 included qualified inputs and32 excluded optional generated model/provenance/cache inputs. The1057 original Rust files and existing repository history remain unchanged.

Sources, tests/licensed fixtures, the Xcode project, scripts, assets, notices and development records are included; builds, runtime artifacts and working files stay excluded. Private visibility remains until release day. This source delivery does not replace the installed/local preview or upload a binary; full Photoshop, capacity and platform qualification remain open. Verified source commit: [`e4e359b6d230d5c95984eefaa94325a56e53885e`](https://github.com/ForensicIntelligence/Photato/commit/e4e359b6d230d5c95984eefaa94325a56e53885e). GitHub main and staged tree match, private visibility remains confirmed, and the [publication receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_281.json) records qualification/scope. A documentation-only follow-up preserves that receipt.

## 2026-10-31 — Software-qualified source checkpoint288

Step289 publishes the complete Source13/checkpoint288 native source: indexed/paged native63/64 persistence, large RGB geometry and PSD/PSB file workflows, paged selections, bounded channel/Quick Mask/raw-mask previews, shared API resources and tool modifier cursors. All2,698 local qualification inputs match the2,912-test full optimized arm64 run and37 focused workflows. Fourteen translated Intel Core component tests pass on identical production; this is not full application/physical Intel testing. The [portable source manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_288.json) lists2,666 included qualified inputs;32 generated optional model/provenance/cache inputs stay excluded. All1,057 original Rust files and prior Git history are preserved.

Sources, tests/fixtures and provenance, Xcode project, scripts, assets, notices and development records are included. Builds, runtime evidence and working documents are excluded. Native acceptance of recent candidates remains pending while the Mac is locked; normal283/artwork and private universal243 remain unchanged. The repository stays private until release day. This source delivery uploads no binary and makes no Photoshop/capacity/platform completion claim. Verified source commit: [`85565519fdff911a6a16fbda6739cd173d27970b`](https://github.com/ForensicIntelligence/Photato/commit/85565519fdff911a6a16fbda6739cd173d27970b). GitHub main and the staged tree match; private visibility remains confirmed. The [source receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_289.json) records actual qualification/scope, and a documentation-only follow-up preserves that receipt.

## 2026-10-31 — Software-qualified source checkpoint293

Step294 publishes the complete Source06/checkpoint293 native source: paged composition, large vector preparation, eight basic RGB raster filters and editable Smart Filters, native RGB source/depth conversion, shared APIs and the earlier large-file/index/cursor work. All2,878 local inputs match the2,942-test full optimized arm64 candidate;90 earlier focused tests run on identical production, with only the final maximum HTTP conversion regression added for the full run. Six translated Intel Core module tests pass separately; full Intel/physical supported-platform acceptance remains open. The [portable manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_293.json) lists2,846 included qualified inputs and32 excluded optional generated model/provenance/cache inputs. The1,057 original Rust files and all existing history are preserved.

Sources, tests/fixtures and provenance, Xcode project, scripts, assets, notices and development records are included. Builds, runtime evidence and working documents are excluded. Normal283/artwork and private universal243 remain unchanged; no new binary is uploaded or installed. Visibility stays private until release day. Native acceptance, full Photoshop/dense-capacity/performance, rich large PSB/job/output and supported-platform gates remain open. Verified source commit: [`fbb9edaf9841930a443568d33a4fcec14de752b4`](https://github.com/ForensicIntelligence/Photato/commit/fbb9edaf9841930a443568d33a4fcec14de752b4). GitHub main/tree and private visibility match independently. The [source receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_294.json) preserves actual qualification/scope; a documentation-only follow-up records publication.

## 2026-10-31 — Software-qualified source checkpoint297

Complete native source297 includes modern editable adjustment layers/native65/Actions22, preceding streamed Smart Filter caches and large resource jobs. All2965 inventoried optimized arm64 cases in bounded module processes and23 final focused checks pass on2901 frozen local inputs;2869 included qualified files match exactly and32 generated/model/cache inputs stay excluded. Original1057 Rust files remain unchanged. Single-process AppKit lifecycle, native/Photoshop/Intel/supported-platform/descriptor/legacy/spatial/dense-capacity/performance gates stay open. Normal283/artwork remain unchanged. Private source delivery only, with no new binary upload or installation. [Source manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_297.json).

## 2026-10-31 — Software-qualified source checkpoint298

Complete native source298 includes native Apply Image/Calculations dialogs, shared channel arithmetic, all three calculation outputs and197 typed API commands. All2980 inventoried optimized arm64 cases in bounded module processes and11 final focused checks pass on2911 frozen local inputs;2879 included qualified files match exactly and32 generated/model/cache inputs stay excluded. Original1057 Rust files remain unchanged. Single-process AppKit lifecycle, native/Photoshop/Intel/supported-platform/descriptor/Actions/mode-storage/dense-capacity/performance gates stay open. Normal283/artwork remain unchanged. Private source delivery only, with no new binary upload or installation. [Source manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_298.json).

## 2026-11-02 — Native source delivery363 (qualified source362)

Complete current native source, tests/redistributable fixtures, Xcode project, scripts, assets, notices and developer records are included. All7000included qualified inputs match362Source03;33generated/cache/external-image inputs are explicitly excluded in the [portable manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_363.json). App/test Swift remains unchanged during delivery. All24new cases pass;302of304affected cases pass with two known PSD Layer Comp failures/one unexpected error/zero crashes. This is limited functional qualification, not a clean current full-suite or Photoshop/platform/performance result. The optional external Layer Comp PSD is not redistributed; its license, pinned source/hash and opt-in acquisition instructions remain. Original1057Rust files and existing history are preserved. The repository remains private until release day. No new binary upload, installation, App Store action or software/public release. The post-commit publication receipt will record the actual commit/tree verification.

Verified source commit: [45148392a5a3977ed731c4624730e8cbfcb9e29f](https://github.com/ForensicIntelligence/Photato/commit/45148392a5a3977ed731c4624730e8cbfcb9e29f). GitHub main/tree and private visibility match. The [source receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_363.json) records actual qualification and exclusions. A documentation-only follow-up records publication; its own commit is not part of the immutable source tree above.

## 2026-11-03 — Native source delivery370 (qualified source369)

Complete native source, tests and redistributable fixtures, Xcode project, scripts, assets, notices and developer records are prepared for private main. All7051 included qualified inputs match369Source02;34 generated/model/cache/external-image inputs are excluded explicitly in the [portable manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_370.json). All454 affected optimized cases and five new cases pass on each of Apple Silicon and translated Intel. Native Quick Mask visibility, hidden-brush rejection, painting and Undo are verified. This is scoped qualification, not a clean full-suite or complete Photoshop/platform/performance result.

Original1057Rust files and existing history are preserved. The externally restricted Layer Comp PSD is not redistributed. Repository visibility stays private until release day; this source backup uploads no binary, replaces no installed app and authorizes no software release. The post-push receipt records the actual source commit/tree and remote verification. C01 is confirmed as the next major workflow after S05 completes and is tested.

Verified source commit: [9dc8d7c4494911f00e9605f5d7c11bf4b4ca1586](https://github.com/ForensicIntelligence/Photato/commit/9dc8d7c4494911f00e9605f5d7c11bf4b4ca1586). GitHub main/tree and private visibility match. The [source receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_370.json) records the scoped qualification and exclusions. A documentation-only follow-up records this delivery; its own commit is not part of the immutable source tree above.

## 2026-11-04 — Native source delivery389 (qualified source388)

Complete native Swift source, tests and redistributable fixtures, Xcode project, scripts, assets, notices and developer records are prepared for private main. All7113included qualified inputs match388Source03;34generated/model/cache/external-image inputs are explicitly excluded in the [portable manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_389.json). Fourteen new cases pass on each architecture. The broadened1184-case run passes1182ARM/1175translatedIntel; every remaining failure/count reproduces on the prior387baseline. No clean full-suite or Photoshop/UI/platform/dense/60fps result is claimed.

Original1057Rust files and existing history are preserved. No external restricted PSD is redistributed. Visibility remains private until software release day. This backup uploads no binary, installs no app, changes no App Store record and authorizes no software release. S05 remains open; C01 follows complete and tested S05. Three missing older temporary binaries remain a preservation gap; source/log/hash records do not replace original bytes. Actual commit/tree/privacy verification follows in the delivery receipt.

Verified source commit: [16968a2485246f49c19789ab7a6c64c344abcffc](https://github.com/ForensicIntelligence/Photato/commit/16968a2485246f49c19789ab7a6c64c344abcffc). GitHub ref/tree and continued private visibility match. The [source receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_389.json) retains exact tested inputs, exclusions and failing qualifications. A separate documentation commit records this delivery.

## 2026-11-04 — Native source delivery395 (qualified source394)

Complete native Swift source, tests and redistributable fixtures, Xcode project, scripts, assets, notices and developer records are prepared for private main. All7130included qualified inputs match394Source02;34generated/model/cache/external-image inputs are explicitly excluded in the [portable manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_395.json). All335affected cases, including13new cases, pass on each architecture. Current3976-case discovery is not full execution. Full Photoshop/UI/platform/dense/60fps gates remain open.

Original1057Rust files and existing Git history are preserved. No external restricted PSD is redistributed. Visibility remains private until software release day. Source delivery uploads no application binary, installs no app and changes no App Store field. Full S05 stays open; C01 follows completion/testing. The existing generic public listing copy is reconfirmed, with feature keywords retained under Apple search guidance. Three missing older temporary binaries remain a preservation gap. Actual commit/tree/privacy verification follows in the receipt.

## 2026-11-06 — Repository made public

The maintainer explicitly requested public visibility, superseding the earlier release-day restriction. Verified ADMIN access, changed ForensicIntelligence/Photato to public with the GitHub CLI, then verified PUBLIC/isPrivate=false and unauthenticated HTTPS200. Existing commits/history remain intact. No app release, Store submission, binary upload or live website deployment accompanied this change. Current root/native README and source-availability wording now reflect public access. Dated private-backup records remain historical. The in-progress custom Shape Blur source is not included in this documentation-only publication; the source checkpoint remains443.

## 2026-11-06 — Qualified build 448 source and draft build backup

Checkpoint 449 backs up the full curated native source for build 448, including ACF/JSON Custom Filter presets and Blur Gallery mask output with shared APIs and Actions. The Xcode project, source, tests, licensed fixtures and documentation are included. All 57 selected optimized methods pass on each architecture; full-suite and full Photoshop qualification remain open. The original 1,057 Rust files are unchanged. Generated model/cache/runtime/signing material and the restricted external PSD remain excluded from source; optional model preparation instructions remain.

The universal development ZIP is ad-hoc signed, not notarized or an App Store release. Its upload is an unpublished draft requiring manual approval; public source availability does not publish the app. The [source delivery receipt](PhotoCraftSwift/docs/SOURCE_PUBLICATION_449.json) records actual commit/tree, draft assets and verification after they complete. No repository history is rewritten.


Build448 source is verified at [77b14d5eedf8](https://github.com/ForensicIntelligence/Photato/commit/77b14d5eedf88f5b70dab96b9d8140d1fbc121c3). The four unpublished draft build assets were downloaded and hash-verified, including the extracted app signature and contents. No software release was published. See [delivery verification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_449.json).

## 2026-11-08 — Native build500 source snapshot

This source delivery includes all qualified distributable build500inputs and the developer working records through500. All originalRustsource and existing Git history are retained. The current selected export workflow passes42focused tests in Debug and each optimized architecture; the repository remains an unfinished alpha with earlier failed acceptance targets explicitly retained. Generated models, caches, signing material, restricted external image fixtures and raw local evidence are excluded. Canonical historical-evidence processing is still pending. Source availability does not publish an app or authorize an automatic release. See PhotoCraftSwift/docs/SOURCE_PUBLICATION_500.md.

## 2026-11-08 — Native build 503 source snapshot

Adds the distributable source and developer records through 503 while preserving all original Rust files and Git history. Current focused qualification passes 114 methods in Debug and each optimized architecture. This remains an unfinished development alpha. No binary or software release is included. See PhotoCraftSwift/docs/SOURCE_PUBLICATION_503.md.

## 2026-11-08 — Native build 505 source snapshot

Adds large-document background references, explicit Apple reference-image editing and developer records through 505. Current focused checks pass 81 methods in each of three configurations. Original Rust files and Git history are preserved. This remains an unfinished development alpha; no binary or software release is included. See PhotoCraftSwift/docs/SOURCE_PUBLICATION_505.md.

## 2026-11-08 — Native build 506 source snapshot

Adds local learned super-resolution, optional BSD-3 model preparation, native/API create/cancel and diary506. The same source passes 46 selected app methods in each of three configurations and 19 archive-tool checks. Original Rust files and existing paths/history remain. Generated models stay optional with pinned acquisition instructions. This is an unfinished development alpha; no binary or software release is included. See PhotoCraftSwift/docs/SOURCE_PUBLICATION_506.md.

## 2026-11-08 — Native source checkpoint510

Includes source and diary507–510, reviewed numeric edit plans, language/plugin acceptance audits and editable gradient/vector profile conversion. Original Rust source, all existing paths and Git history are preserved. The broader Intel profile failure reproduces unchanged on506; it is not marked passed. This is a free unfinished development alpha, with no binary or software release. See PhotoCraftSwift/docs/SOURCE_PUBLICATION_510.md.
