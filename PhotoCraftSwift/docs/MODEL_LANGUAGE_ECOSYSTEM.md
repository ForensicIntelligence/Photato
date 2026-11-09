# AI, languages and plugins

Checkpoint508 records acceptance criteria for original AUD02. Native application build remains507; this checkpoint changes no app code, API, menus, shortcuts, cursor policy, signing or document format. Full Photoshop functionality is still unfinished.

## What the audit establishes

The [machine-readable record](MODEL_LANGUAGE_ECOSYSTEM_508.json) contains17open requirements with the evidence needed to close each, the complete24-entry reference language catalogue, separate plugin/runtime families and provider boundaries. Recording a requirement does not implement or qualify it.

Adobe's [language catalogue](https://helpx.adobe.com/photoshop/desktop/get-started/technical-requirements-installation/photoshop-language-availability.html) includes regional Arabic/Hebrew behavior with English/French interfaces. It does not establish24standalone translated interfaces. These text features need their own RTL/layout references. The source currently has no localization resource files; app-owned translations and complete locale workflows remain unqualified.

A read-only Foundation Models probe on this Mac, macOS27.2, reports24Apple language codes/variants. Framework locale-fallback checks accept15of the24reference audit keys and reject9: Hebrew, Hungarian, Indonesian, Polish, Finnish, Ukrainian, Czech, Russian, Arabic. Norwegian uses the generic audit key no; the model advertises nb, and precise reference variants remain to verify. Current en_US is supported, but the model is still not ready. No inference or cloud request ran. This metadata describes the current model/runtime, not translated app UI or validated generated text. Apple recommends [checking locale support at runtime](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models).

## Quality and provider evidence

AI acceptance requires real provider output and provenance, an owned/licensed corpus, intent and detail assessment, supported-mode/depth/profile/alpha checks and complete native/API history/cancellation/persistence behavior. Injected suggestions, a model availability flag or a prepared button are insufficient. Deterministic output comparisons retain the requested byte equality; different provider names and metrics do not prove Firefly identity or equivalence. The optional Apple/local provider implementations retain their explicit eligibility and readiness requirements.

Build507passes50focused tests in Debug and each optimized architecture. Its independent capture comparison still fails at two RGB32 green samples on Intel. Its native AI-sheet automation connection also remains closed while process26746 is alive. These failures remain required work; no tolerance, app restart or UI pass is substituted.

## Plugin boundaries

Adobe [documents four plugin categories](https://helpx.adobe.com/photoshop/desktop/app-integrations/supported-plugins-and-extensions.html). Photato currently has no host implementation for UXP, CEP, native SDK plugins or optional file-format plugins; legacy ExtendScript is also separate and unimplemented. Native Actions and the HTTP API do not make existing Photoshop plugins executable. The [UXP Photoshop DOM/modal/action APIs](https://developer.adobe.com/photoshop/uxp/2022/ps-reference/) are a distinct compatibility target from Firefly REST endpoints.

A compatible host needs implementation and real execution evidence for its formats, ABI/CPU variants, lifecycle, APIs, UI, isolation, cancellation and data access. A Photato-specific extension alone cannot be called Photoshop plugin compatibility.

The concrete distribution design must be checked against [Apple's current review rules](https://developer.apple.com/app-store/review/guidelines/), including2.4.5,2.5.2,4.4 and4.7. The latter addresses certain software/plugins; this audit does not infer a blanket prohibition or approval. No security setting, entitlement, distribution channel or free/manual-release policy has changed.

## Remaining work

The historical approval required before restoring a separately protected pre-existing Photoshop document is still pending; it was not touched. Separate owned reference work can continue. Full AI quality, language implementation, provider/service fidelity and plugin qualification remain open. Original104scopes,652command identities,81major memberships and sevenpasses are preserved. Next in the existing major-stillneeded sweep is AUT03, then COL01.

The Xcode project uses filesystem-synchronized source groups, including PhotoCraftAI; the new507source file is included by that configuration. This inspection is not an Xcode archive pass.

The documentation/runtime consistency check passes, and all7,745tested507native inputs remain unchanged. No application test suite was rerun for documentation-only work. Canonical evidence/website promotion remains separately pending; the original486audit processes were neither restarted nor mutated. No source push, production install, Apple upload or software release occurred in508.
