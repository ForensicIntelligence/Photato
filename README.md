# Photato

> ## 🎉 50% to Photoshop 2026 Parity!
>
> This is our current estimate for overall desktop workflow parity. We update this banner when the tested workflows support the next 10-percentage-point milestone. See what works today and what’s still in progress in the [Developer Diary](DEVELOPER_DIARY.md).

Photato is a native Swift image editor for macOS 14 and later. It is an independent port of [PhotoCraft](https://github.com/storytold/photocraft), with Photoshop 2026 workflow compatibility as a development goal.

We replay the same operations in Photato and Photoshop 2026 with matching documents and settings, then compare the relevant pixel or file bytes. We report byte-for-byte matches only for cases that pass and record differences and untested cases in the [Developer Diary](DEVELOPER_DIARY.md).

**[Download Photato for macOS (Universal)](downloads/Photato-universal.zip?raw=1)** · Ad-hoc signed development alpha · macOS 14+ · Apple Silicon and Intel

## What Photato adds

- **A desktop editor with two local automation APIs.** Enable Photato’s optional HTTP server to edit shared documents and run jobs from scripts or a browser on the same Mac. The Photato `/v1` API publishes the available commands and their schemas at `GET /v1/capabilities`. Both interfaces use the native Swift editing engine. [Automation API](PhotoCraftSwift/docs/AUTOMATION_API.md)
- **Adobe Photoshop API v2 compatibility on your Mac.** Use the supported Firefly Photoshop v2 request and job formats against Photato’s local server. The compatibility layer is independently implemented. It covers a documented subset, and full endpoint and action coverage remains a development goal. [Photato compatibility matrix](PhotoCraftSwift/docs/ADOBE_API_COMPATIBILITY.json) · [Adobe’s published contract](https://developer.adobe.com/firefly-services/docs/photoshop/getting-started/v2-ga/)
- **An offline Workflow Guide for learning while editing.** The optional floating window follows the active layer, selection, tool, and supported editor controls. It offers a short list of likely next tasks, then walks through the one you choose. The guide can recognize supported steps as you perform them in the editor. The walkthroughs are authored from tested workflows in the developer diary.
- **An editor you can audit and build yourself.** Photato’s Swift editor, file codecs, automation engine and Xcode project are public. The diary links each published source checkpoint to its tests, independent references and remaining gaps. [Source and license](PhotoCraftSwift/) · [Developer diary](DEVELOPER_DIARY.md)

## Developer Diary

**[Read the latest diary entries](DEVELOPER_DIARY.md)** · [Browse the full diary archive](diary/README.md)

The diary records each source checkpoint, what was tested, and what still needs work. The archive includes a chronological index starting with the original source audit.

**Development alpha — source build 743.** Vanishing Point Brush and Stamp follow linked perspective planes through the desktop and Photato API. [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_743.md).

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

Each published source checkpoint includes its verified Universal development ZIP. Intermediate builds, downloaded corpora, logs, and machine-specific settings stay local. The checkpoint’s validation record includes the ZIP’s SHA-256.

The source repository is public. Application releases still require manual approval.

The source snapshot includes all native app/test code and the Xcode project. Caches, local runtime evidence, private signing material and user documents stay local. The Universal preview includes the redistributable models described in the app’s bundled license notices. One external PSD is excluded under its upstream terms. [Optional reference instructions](PhotoCraftSwift/Tests/PhotoCraftImagingTests/Fixtures/layer-comps/README.md)


Build448 source is verified at [77b14d5eedf8](https://github.com/ForensicIntelligence/Photato/commit/77b14d5eedf88f5b70dab96b9d8140d1fbc121c3). The four unpublished draft build assets were downloaded and hash-verified, including the extracted app signature and contents. No software release was published. See [delivery verification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_449.json).
