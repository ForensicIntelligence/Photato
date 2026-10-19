# Photato

Photato is a native Swift image editor for macOS 14 and later, part of the Pantry family of applications. It is an independent port of [PhotoCraft](https://github.com/storytold/photocraft), with Photoshop 2026 workflow compatibility as a development goal.

**Development preview:** feature parity is not complete. Work in progress may be present on `main`; this repository snapshot is not a qualified release. See the [native implementation status](PhotoCraftSwift/docs/STATUS.md) and [development log](PhotoCraftSwift/docs/DEVLOG.md) for the scope of completed validation and remaining gaps.

## Project layout

- [`PhotoCraftSwift/`](PhotoCraftSwift/) — native Swift application, editing engine, tests, documentation, and build scripts.
- [`PhotoCraftSwift/Photato.xcodeproj`](PhotoCraftSwift/Photato.xcodeproj/) — Xcode project. Open it and select **Photato / My Mac**.
- [`photocraft-main/`](photocraft-main/) — original Rust PhotoCraft source snapshot retained for provenance and porting reference.
- [`PhotatoIcon.png`](PhotatoIcon.png) — supplied Photato application icon.

Build and test instructions are in the [native README](PhotoCraftSwift/README.md) and [contributor guide](PhotoCraftSwift/CONTRIBUTING.md).

## Repository and provenance

The repository is [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato). It is intended to remain **private until the owner explicitly approves making a release public**. Repository setup is recorded in [REPOSITORY.md](REPOSITORY.md).

The Rust source was supplied as an extracted snapshot without Git history. This repository starts a new history for the existing source tree; it does not claim to preserve upstream commit ancestry or to be a GitHub network fork. Upstream attribution and notices remain in both source directories. Native planning documents that describe publication as pending predate this repository setup; publication to the public remains pending.

PhotoCraft-derived source retains **MIT OR Apache-2.0** licensing: [MIT](PhotoCraftSwift/LICENSE-MIT), [Apache-2.0](PhotoCraftSwift/LICENSE-APACHE), [NOTICE](PhotoCraftSwift/NOTICE), and [attribution](PhotoCraftSwift/ATTRIBUTION.md). Third-party fixtures and assets retain their individual terms. This is an independent project, not an Adobe or official upstream release.

Local build products, downloaded corpora, development artifacts, logs, and machine-specific settings are excluded from Git. Documentation may refer to evidence kept locally; the repository is not a backup of that excluded material.
