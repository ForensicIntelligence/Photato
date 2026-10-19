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
