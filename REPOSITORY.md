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

Sources, tests/fixtures, the Xcode project, scripts, assets, notices and development records are included; builds, runtime artifacts and private working files are excluded. The repository stays private until release day. This source delivery does not install an app or upload a binary; Photoshop and supported-platform qualification remain open. The verified source commit receipt follows after push.
