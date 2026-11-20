# Blend settings and pixel masks in Smart Object templates

## 20 November 2026

A composite job could add or replace a Smart Object and set its geometry, but rejected appearance settings that Adobe documents for the same layer entry. This left automated product and design templates unable to set a linked or embedded object's opacity, blend mode or editable pixel mask in a single job. The published schema enumerates blend modes and defines gray PNG, JPEG and PSD as mask inputs. Its mask migration guides describe offsets relative to the layer and give deletion precedence over the other fields. [Smart Object operations](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/layer-operations-smart-objects) · [Pixel mask operations](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/layer-operations-advanced) · [Mask metadata](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/manifest-migration)

`AdobeSmartObjectEdit.swift` now forwards these fields to `AdobeSmartObjectAppearance.swift`. The adapter uses the same layer blend, opacity, create-mask, mask properties and delete-mask commands as the editor. The job can fetch both the replacement artwork and the grayscale mask through the existing resource policy in `AdobeActionJobs.swift`. Replacement mask pixels retain existing placement and settings unless the request changes them. A true delete skips the other mask settings and does not fetch the mask source. Mask coverage uses the source's gray samples, with transparency composited over black. PNG and JPEG use the existing unpaged image budget. The native Photoshop decoder handles grayscale PSD and PSB coverage.

## Validation

`AdobeSmartObjectAppearanceTests.swift` covers the published blend tokens, range and type validation, numerical grayscale input at both depths, patch and delete semantics, resource collection and an actual local HTTP job reopened as an editable PSD. The HTTP job runs through Photato's authenticated loopback endpoint and asynchronous job registry. The resource transport supplies owned, generated fixtures in memory. Its resulting PSD is reopened and the rendered RGBA bytes are compared with a document assembled through the native commands.

The first Debug build stopped in the Swift compiler's predictable dead-allocation pass before compiling the app. The compiler report identified a stack guard fault. The same frozen source built successfully with the single-pass workaround used for build 660. All five focused tests passed. The two build logs are retained as `artifacts/661-template-appearance/build-debug01.log` and `artifacts/661-template-appearance/build-debug02.log`.

The second source adds runtime capability discovery to `AutomationService.swift`. Flag-only changes and replacements now retain the saved transform exactly even on rotated layers. The five updated focused cases passed, including the capability response and exact saved transform checks. Apple Silicon Debug regressions and both Release builds are in progress. Source staging verified 9,259 candidate build inputs and selected 9,246 for publication.

Each of the three configurations passed 1,481 of 1,482 selected cases and all five new tests. One old assertion in `SmartObjectWorkflowTests.swift` expected even an empty pixel-mask object to be rejected. The documented field is now accepted. The repair changes that negative assertion to an invalid Boolean offset and adds an explicit acceptance check for the empty object. The initial source, test executables and failed runs are retained separately. The replay covers the affected regression shard and all five new cases, with byte-identical production inputs.

The hosted Adobe service has not been measured. Mask behavior outside the supplied grayscale image and exact color compositing across Adobe outputs require an independent comparison.

## Next template workflow

The current OpenAPI specification still has the same appearance fields as the pinned contract. The new `smartObject.contentPlacement` field adds a separate workflow for fitting or filling an existing embedded frame. Adobe specifies that the replacement remains editable as a nested Smart Object, with alignment inside the frame. Photato's current replacement path can resize the source, but does not yet create that nested frame. The next comparison should cover fit and fill, one-sided and centered alignment, rotated frames, preservation of the original asset, and the unsupported frame variants described by Adobe. [Frame replacement workflow](https://developer.adobe.com/firefly-services/docs/photoshop/guides/workflows/smart_object/) · [Published schema](https://github.com/AdobeDocs/ffs-photoshop-API/blob/main/static/photoshopv2-api.json)

The 1,482 selected cases passed across qualification and replay in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Each initial run passed 1,481 cases. After updating the obsolete mask assertion, all 142 replay cases passed in each configuration. The application inputs and signed binary stayed byte-identical. Both slices of the signed macOS 14+ universal preview launched offscreen.

An authenticated local HTTP job used its authorized artwork and grayscale mask resources, reopened as an editable PSD, and rendered byte-identical RGBA with the equivalent native command sequence. Additional tests covered grayscale PNG and PSD samples, JPEG, mask replacement, deletion precedence, and rejected inputs.

[Qualification](SOURCE_PUBLICATION_661.md)
