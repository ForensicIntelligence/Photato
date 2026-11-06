# Photato

Photato is a native Swift image editor for macOS 14 and later. It is an independent port of [PhotoCraft](https://github.com/storytold/photocraft), with Photoshop 2026 workflow compatibility as a development goal.

**Development alpha — build 448:** The current native source adds ACF/JSON Custom Filter presets and reusable Blur Gallery mask channels, including shared APIs, history and saved Actions. All 57 selected optimized methods pass on Apple Silicon and Rosetta, including 24 new methods across checkpoints 447–448. Universal packaging and selected live native checks pass. Full Photoshop functionality/output parity, broader regression, physical supported-platform, capacity and 60fps requirements remain open. Next major work is Liquify, then lens workspaces. See [native status](PhotoCraftSwift/docs/STATUS.md) and [development log](PhotoCraftSwift/docs/DEVLOG.md).

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
