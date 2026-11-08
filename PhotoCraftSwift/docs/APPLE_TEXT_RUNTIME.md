# Apple text services

Build 502 keeps Apple text generation optional. Editing remains available on macOS 14 and later. Prompt refinement uses the on-device model on supported Apple Silicon systems running macOS 26 or later. Reviewed edit plans can use that model or the direct Foundation Models PCC text service on macOS 27 or later. These services are distinct from Image Playground's system-controlled image interface.

Direct PCC text use requires the managed `com.apple.developer.private-cloud-compute` entitlement. Photato reads the running task's signed entitlement with Security.framework before opening a cloud text session. An Info.plist flag, an eligible CPU or a reported-ready system service cannot substitute for that signature. A signed entitlement also does not prove account eligibility, valid provisioning or successful service access; Apple and runtime availability still apply. There is no automatic provider fallback.

Ordinary signing remains `scripts/Photato-AppStore.entitlements`. The optional `scripts/Photato-PCC.entitlements` template contains those same sandbox/file/network/printing permissions plus the managed PCC entitlement. Once Apple assigns the capability to the developer account and the app's provisioning supports it, use the template through Xcode's `CODE_SIGN_ENTITLEMENTS` build setting. For example, an explicitly configured archive can override that setting to `scripts/Photato-PCC.entitlements`; this does not request approval, create a profile, upload or release a build. Do not add an unapproved managed entitlement to ordinary distribution. The existing production bundle ID and manual-release policy remain unchanged.

Apple's access requirements and entitlement documentation:

- https://developer.apple.com/private-cloud-compute/
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.private-cloud-compute
- https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute
- https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models

The native sheet displays the same readiness messages used by the API. `GET /v1/documents/{id}/ai` adds `reason` for image readiness and `textModel` containing `available`, `message` and `reason` for local text readiness. `GET /v1/documents/{id}/edit-plan` adds `reason` to each existing provider entry. Status values are `ready`, `deviceNotEligible`, `unsupportedSystem`, `appleIntelligenceNotEnabled`, `modelNotReady`, `systemNotReady`, `missingEntitlement`, `frameworkUnavailable` and `unknown`. A runtime image-framework rejection without a published detailed cause remains `unknown`; it is not guessed to be a download or settings issue. Capability reads never start generation or change document/history. A single sampled capability supplies each response's boolean, message and reason.

The existing HTTP image-preparation operation still requires native approval. The reviewed-plan HTTP interface still accepts supplied typed plans, not model-execution requests. No Firefly v2 endpoint defines this desktop provider-readiness lifecycle; there is no invented Adobe route or assertion of proprietary model equivalence. Existing local image approval, cancellation, stale-state barriers, saved originals, native/Actions formats, typed editing commands and factory menus/shortcuts/cursors retain their scope.

The current unsandboxed metadata probe reports local `modelNotReady` and PCC `systemNotReady`. No local Photato provisioning profile was found; the FI account's entitlement assignment was not inspected or inferred. Real on-device/PCC generation and supported physical-platform coverage remain unqualified. AI02's full scope includes those results and remains open. All original scopes and previous failures remain required.
