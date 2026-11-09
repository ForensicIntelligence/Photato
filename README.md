# Photato

Photato is a native Swift image editor for macOS 14 and later. It is an independent port of [PhotoCraft](https://github.com/storytold/photocraft), with Photoshop 2026 workflow compatibility as a development goal.

**Development alpha — source build 511:** Native Swift source, Xcode project, tests and diary through checkpoint 511. Repairs Gray32 Photoshop file export; 32 selected tests pass in Debug and each optimized architecture. Earlier numerical/workflow failures remain open. Merge Channels is still in progress. This is a source checkpoint, not a software release. [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_511.md).

## Project layout

- [`PhotoCraftSwift/`](PhotoCraftSwift/) — native Swift application, editing engine, tests, documentation, and build scripts.
- [`PhotoCraftSwift/Photato.xcodeproj`](PhotoCraftSwift/Photato.xcodeproj/) — Xcode project. Open it and select **Photato / My Mac**.
- [`photocraft-main/`](photocraft-main/) — original Rust PhotoCraft source snapshot retained for provenance and porting reference.
- [`PhotatoIcon.png`](PhotatoIcon.png) — supplied Photato application icon.

Build and test instructions are in the [native README](PhotoCraftSwift/README.md) and [contributor guide](PhotoCraftSwift/CONTRIBUTING.md).

## Repository and provenance

The repository is [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato). It is **public as of 6 November 2026**, at the maintainer’s request. Repository setup is recorded in [REPOSITORY.md](REPOSITORY.md).

The Rust source was supplied as an extracted snapshot without Git history. This repository starts a new history for the existing source tree; it does not claim to preserve upstream commit ancestry or to be a GitHub network fork. Upstream attribution and notices remain in both source directories. Native planning documents that describe publication as pending predate this repository setup; the repository is now public.

PhotoCraft-derived source retains **MIT OR Apache-2.0** licensing: [MIT](PhotoCraftSwift/LICENSE-MIT), [Apache-2.0](PhotoCraftSwift/LICENSE-APACHE), [NOTICE](PhotoCraftSwift/NOTICE), and [attribution](PhotoCraftSwift/ATTRIBUTION.md). Third-party fixtures and assets retain their individual terms. This is an independent project, not an Adobe or official upstream release.

Local build products, downloaded corpora, development artifacts, logs, and machine-specific settings are excluded from Git. Documentation may refer to evidence kept locally; the repository is not a backup of that excluded material.

The source repository is public. Application releases still require manual approval.

The source snapshot includes all native app/test code and the Xcode project. Generated models, caches, local runtime evidence, signing material and user documents are excluded. One external PSD is not redistributed because its upstream license excludes image assets; see the [optional reference instructions](PhotoCraftSwift/Tests/PhotoCraftImagingTests/Fixtures/layer-comps/README.md). Source availability does not install or distribute a new binary and does not approve a software release.


Build448 source is verified at [77b14d5eedf8](https://github.com/ForensicIntelligence/Photato/commit/77b14d5eedf88f5b70dab96b9d8140d1fbc121c3). The four unpublished draft build assets were downloaded and hash-verified, including the extracted app signature and contents. No software release was published. See [delivery verification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_449.json).
