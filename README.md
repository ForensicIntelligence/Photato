# Photato

Photato is a native Swift image editor for macOS 14 and later. It is an independent port of [PhotoCraft](https://github.com/storytold/photocraft), with Photoshop 2026 workflow compatibility as a development goal.

**Development preview:** Photoshop2026 defines the target behavior, UI, shortcuts and output. Native394Source02 includes bounded component editing, geometry and storage, RGB8 Brush/Eraser/filter routing and the earlier Quick Mask, Fit Image and document workflows. All335affected cases, including13new cases, pass on Apple Silicon and translated Intel. The full current suite has not been executed, and complete Photoshop/platform/capacity/60fps qualification remains open. Full S05 remains open; C01 follows completion/testing. See [native status](PhotoCraftSwift/docs/STATUS.md) and the [portable source manifest](PhotoCraftSwift/docs/SOURCE_SNAPSHOT_395.json).

## Project layout

- [`PhotoCraftSwift/`](PhotoCraftSwift/) — native Swift application, editing engine, tests, documentation, and build scripts.
- [`PhotoCraftSwift/Photato.xcodeproj`](PhotoCraftSwift/Photato.xcodeproj/) — Xcode project. Open it and select **Photato / My Mac**.
- [`photocraft-main/`](photocraft-main/) — original Rust PhotoCraft source snapshot retained for provenance and porting reference.
- [`PhotatoIcon.png`](PhotatoIcon.png) — supplied Photato application icon.

Build and test instructions are in the [native README](PhotoCraftSwift/README.md) and [contributor guide](PhotoCraftSwift/CONTRIBUTING.md).

## Repository and provenance

The repository is [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato). It remains **private during development and will become public on the same day the software is released**. Repository setup is recorded in [REPOSITORY.md](REPOSITORY.md).

The Rust source was supplied as an extracted snapshot without Git history. This repository starts a new history for the existing source tree; it does not claim to preserve upstream commit ancestry or to be a GitHub network fork. Upstream attribution and notices remain in both source directories. Native planning documents that describe publication as pending predate this repository setup; publication to the public remains pending.

PhotoCraft-derived source retains **MIT OR Apache-2.0** licensing: [MIT](PhotoCraftSwift/LICENSE-MIT), [Apache-2.0](PhotoCraftSwift/LICENSE-APACHE), [NOTICE](PhotoCraftSwift/NOTICE), and [attribution](PhotoCraftSwift/ATTRIBUTION.md). Third-party fixtures and assets retain their individual terms. This is an independent project, not an Adobe or official upstream release.

Local build products, downloaded corpora, development artifacts, logs, and machine-specific settings are excluded from Git. Documentation may refer to evidence kept locally; the repository is not a backup of that excluded material.

The repository remains private during development and will become public on the same day the software is released.

The source snapshot includes all native app/test code and the Xcode project. Generated models, caches, local runtime evidence, signing material and user documents are excluded. One external PSD is not redistributed because its upstream license excludes image assets; see the [optional reference instructions](PhotoCraftSwift/Tests/PhotoCraftImagingTests/Fixtures/layer-comps/README.md). This private source backup does not install or distribute a new binary and does not approve a software release.
