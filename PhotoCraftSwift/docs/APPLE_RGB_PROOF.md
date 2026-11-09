# Legacy Macintosh RGB proof

Photato adds View > Proof Setup > Legacy Macintosh RGB (Gamma 1.8). The preset selects Apple RGB, relative colorimetric intent, Preserve RGB Numbers for RGB documents, and disables BPC, paper simulation and black simulation. Gray, CMYK and Lab proofs convert into the RGB proof condition instead of preserving unlike component numbers. Gamut Warning is unavailable for this preset. In Custom, paper/black controls are disabled while RGB numbers are preserved.

Proofing changes the view only. Document pixels, Undo, dirty state, normal previews and exports remain unchanged. Custom preview, Cancel and OK retain the existing proof transaction. Sparse/paged proofing keeps the existing300,000-pixel-per-side logical support and independent renderer/resource limits. This does not establish dense 90 GP capacity, physical platform or 60 fps qualification.

The shared Swift engine writes a small ICC v2 matrix/TRC profile from standard Apple RGB colorimetry and independently observed ICC rounding values. Its D65 white and D50 PCS colorants/TRCs match the installed standard profile's functional fields; no Adobe profile file, program code or SDK is distributed. Normal 8/16-bit profiles retain the 461/256 ICC gamma representation. Existing native linearization supplies 32-bit working profiles. Generated ICC description/copyright/header metadata is Photato's own; whole-profile byte identity is not claimed.

## APIs

`proof.configure` accepts `settings.device: legacyMacintoshRGB`. Explicit selection resets the factory fields above; supplied settings then override compatible fields. Invalid custom profile replacement, ink plates or Gamut Warning reject atomically. Observable proof state includes `gamutWarningAvailable`, alongside `preserveNumbersAvailable`. Existing revision, explicit sharing, busy and revoked-document checks remain. `proof.settings.read` and the committed `proof-preview.png` route use the same view state. There is no invented Adobe soft-proof endpoint.

Adobe-compatible document creation and output ICC schemas now accept the already-published standard name `Apple RGB` for RGB8/16/32. `/v2/create-composite`, Photato `/v1/action-jobs` and output conversion share the generated profile and native color engine. Other named profiles and full Adobe service fidelity remain incomplete.

## References and qualification

- [Public CC0 Apple RGB colorimetry](https://github.com/hughsie/colord/blob/main/data/profiles/AppleRGB.iccprofile.xml).
- [ICC v2 recommendations](https://www.color.org/v2profiles/) and [ICC matrix/TRC specification](https://www.color.org/icc301.pdf).
- [Adobe profile names and usage](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/llm-migration-reference).
- Actual Photoshop 2026 Customize Proof Condition observed on an owned RGB16 fixture; only standard ICC tag facts and file hash retained in the test fixture. Original file was closed without saving.

Current Source03 passes all seven new tests and 54/55 selected Debug methods. Native menu/controls/Cancel/Command-Y/SaveAs/reopen/normalQuit pass; 576 saved component values remain exact. All seven new methods also pass optimized ARM and translated Intel. Broader runs pass 54/55 and 52/55, retaining the same failures as actual public 512 binaries, including Intel frozen-proof differences. The original numerical requirements remain. Universal static checks pass; the candidate is unlaunched. Independent Python ColorSync conversion of 18,513 RGB points in both directions, four intents and BPC off/on matches 888,624 Float32 values exactly per architecture against the installed standard Apple RGB profile; a separate translated-Intel Python run confirms this comparison too. This verifies these ColorSync ICC transforms on this OS, not Photoshop's ACE rendering or screen pixels. All original COL03 acceptance remains, including color-blind presets, AdobePSF, HDR/EDR, per-window settings, print, full mode/context/default/output/platform/performance fidelity. The existing Gray8/16 native-vs-isolated-API default ICC mismatch remains a failing requirement.
