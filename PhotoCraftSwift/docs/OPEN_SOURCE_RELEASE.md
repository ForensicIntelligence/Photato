# Free and open-source release

**Latest private preview (step243,2026-10-28):** [Universal Timeline/FOSS build](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-7bc5c587b82133536302) packages the recent Timeline work and removes purchases. All four uploaded assets were downloaded and hash-verified. The installed app remains221. The build uses frozen local source, not remote main; this upload does not push source or change visibility. It is ad-hoc signed and not notarized. [Qualification](UNIVERSAL_TIMELINE_PREVIEW_REFERENCES.json).

**Release decision (2026-10-27):** Keep [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato) private during development. The repository will become public on the same day the software is released.
**Private development build (2026-10-28):** [Draft preview220](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-3913ac56396348d02611) adds the qualified native four-mode workflow and includes the earlier window corrections. All2,173 optimized tests pass. The universal ZIP, checksums and source-input provenance were downloaded again and verified. This is a local-source build; no source commit/push or public visibility change accompanied it. The earlier209 draft below remains preserved.

**Private development build (2026-10-27):** [Draft preview209](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-04479448d8da0ffe8270) contains the verified universal ZIP, checksums and build/source-input provenance. This draft is not the software launch; visibility stays private. Its local source snapshot is newer than remote main, and the release notes make that distinction explicit. No source changes were pushed with this build-only upload.


**Photato**, will be distributed as an independent native Swift fork/port of [storytold/photocraft](https://github.com/storytold/photocraft), retaining **MIT OR Apache-2.0** and the upstream copyright, license and attribution notices. The Swift README, About window and NOTICE identify the original ArtCraft Team and PhotoCraft contributors. The fork is not an official upstream or Adobe release.

## Repository layout and history

The supplied Rust directory is an extracted source snapshot without upstream Git history. [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato) is an existing standalone private repository, initialized on19 October2026; it is not a GitHub network fork and does not claim upstream ancestry. It contains the native port in `PhotoCraftSwift/` alongside the preserved `photocraft-main/` source snapshot. Step254 published the qualified step253 source; step256 published the qualified step255 PDF Smart Object source. Step258 published the qualified step257 embedded placement source. Step281 published the qualified step280 native paging/large-file source. Step289 published software-qualified Source13/checkpoint288. Step294 publishes the complete Source06/checkpoint293 source while retaining repository history; native acceptance and all remaining Photoshop/platform/capacity gates stay open. No upstream base commit is inferred. Repository setup and subsequent source deliveries are recorded in the root `REPOSITORY.md`.

Use this folder's CONTRIBUTING.md for native work. Preserve upstream notices and follow asset-specific terms when retaining upstream assets. The native binary uses system fonts and SF Symbols, and ships no ArtCraft/Adobe brand artwork. The native application is named **Photato**. The repository is https://github.com/ForensicIntelligence/Photato. It remains private during development and will become public on the same day the software is released.

The source release includes Sources, Tests and fixture provenance/licenses, Assets, Package.swift, scripts, documentation and license files. Build caches, `build/` and downloaded `corpus/` remain excluded. Local artifacts contain development logs and machine-specific paths; curate the public evidence set before publishing instead of uploading the entire working folder. The current app remains a development preview; full source/Photoshop parity, notarization and the multi-OS runtime matrix remain open.

## Release model — updated 28 October 2026

The maintainer has chosen a **pure FOSS release**. Photato will be free and open source under **MIT OR Apache-2.0**, with no tips, donations, in-app purchases, subscriptions or paid feature unlocks. This decision supersedes the former voluntary IAP plan. Code, bug reports, testing, accessibility improvements and documentation are welcome contributions.

The purchase adapter, purchase UI, launch/activation transaction listeners, product configuration, StoreKit test host and purchase-only tests have been removed. About retains source links, licensing and upstream credit. `scripts/ProjectLinks.json` now contains only the HTTPS repository URL. Older configuration's unused funding fields are ignored. The GitHub repository remains private until the software release day.

Historical development entries and immutable test evidence describe the former implementation accurately. They are retained as history, not current instructions. The withdrawn code is preserved only in local development evidence and is excluded from the app and public website bundle. The current work-package ledger withdraws REL02; it is not a Photoshop functionality requirement or a remaining release gate.

## Distribution qualification

The intended App Store distribution remains a free app. Before submission, finalize the registered app/team identity, sign and archive with App Sandbox and required file-access/optional AI/network capabilities, and qualify opening, saving and persistent access on supported macOS/Intel/Apple Silicon configurations. Prepare privacy/accessibility disclosures and App Review metadata. No purchase products or paid-app configuration are required by the current app design.

The current development ZIP is ad-hoc signed. App Store acceptance, notarized standalone distribution and supported-platform qualification remain open. Public release still requires reviewing the curated repository, recorded snapshot provenance, notices and fixture/model/asset licensing. No account, store, repository-visibility or live-site changes are made by removing purchase support.
