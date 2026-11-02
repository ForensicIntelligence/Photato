# App Store preparation — checkpoint 333

Photato 0.3.0 (332) has an updated universal Xcode archive for `ca.forensicintelligence.photato`, team `PATM9DNCLA`. The application is still an alpha. This is archive and draft-listing preparation, not a completed App Store submission or a Photoshop-parity milestone.

## Account retry333

The maintainer reports signing in to local Xcode. The new validation attempt still exits70 at the FI team’s App Store Connect access requirement. The332 archive binary is unchanged. Native inventory explicitly reports the Mac locked, and the App Store Connect browser tab remains at sign-in. Confirm the FI Forensic Intelligence team in Xcode Accounts, keep this Mac unlocked and sign in to the browser before another retry. The exact account/permission cause is not yet established; do not assume the maintainer’s reported sign-in failed.

Apple lists Account Holder, Admin, App Manager and Developer as roles that can upload builds: [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds). This reference does not establish which role the current account has. No remote policy/media/review/release action occurred. See WORKING_CHECKPOINT_333.json and the retained validation diagnostics.

## Updated archive332

The reliability repairs are included in `/Users/johnczlonka/Library/Developer/Xcode/Archives/2026-11-01/Photato-0.3.0-332-01.xcarchive`. Xcode completes with unchanged frozen archive inputs, and all 20 local package checks pass. The Source04 full inventory completes 3,242 unique tests with 12 failed cases; a separate Source05 focused run repairs one stale version-admission test. Numerical parity failures remain open. This archive is an alpha candidate, not a full-green or release-ready build. Apple validation still fails at FI account access. The account/host recheck and validation result are saved with checkpoint332. Nothing was uploaded, submitted or released.

The first331 archive and all failed attempts below are retained as historical evidence.

## Archive and signing

Open `Photato.xcodeproj`, select the Photato scheme and Product → Archive. The shared archive action now uses AppStore, a Release-derived configuration with App Sandbox. Debug/Release retain the local ad-hoc workflow. AppStore enables user-selected file read/write, app-scoped bookmarks, native printing and network access for the optional API and Apple services. Its default archive signing is Apple Development on the FI team; distribution export selects the App Store distribution identity. Developer ID Application signing is for distribution outside the store.

The first archive succeeded on1 November 2026:

`~/Library/Developer/Xcode/Archives/2026-11-01/Photato-0.3.0-331-01.xcarchive`

Both arm64 and x86_64 slices target macOS 14. Local verification passes 20 checks covering identity/version, universal architecture, minimum OS, FI team signature, sandbox entitlements, hardened runtime exceptions, exact privacy/license/attribution/link resources, icon, dSYM and Apple runtime dependencies. This is static package evidence, not Apple server validation or sandboxed workflow acceptance. The development archive does not embed a provisioning profile; distribution provisioning remains for Xcode to resolve.

The validation attempt is blocked with: “App Store Connect access for ‘PATM9DNCLA’ is required.” The maintainer must refresh the FI account in Xcode Settings → Accounts. App Store Connect in the browser also requires sign-in. The Mac is locked, preventing current native screenshots and video capture. No credentials should be placed in project files, logs or chat.

`scripts/ExportOptions-Validation.plist` selects method `validation`, destination `upload` as required by Xcode 27. It does not select a review or release action. `scripts/ExportOptions-AppStore.plist` prepares a local App Store export. Neither option file enables an automatic release. A successful archive alone is not a validated upload or an App Store listing.

## Listing and release policy

`distribution/app-store/en-CA.json` contains the local name, subtitle, promotional text, description, keywords, categories and URLs. `review-notes.json` records alpha scope and known gaps. The description explains AI-aided development, incomplete functionality, optional Apple local/Private Cloud Compute services, original PhotoCraft attribution, free/no-purchase terms and public source availability on software release day. Live website/contact/privacy URLs respond successfully; final privacy text still needs review for this release.

`release-policy.json` records the requested zero price and **MANUAL** release for every version. It is not proof that App Store Connect settings have been saved. Once authenticated, create or select the app record, verify the bundle ID/team, set the price to free, select **Manually release this version**, save and verify those settings. Keep TestFlight group distribution manual too. Do not submit for review or release this version during preparation. Repository visibility remains private until software release day.

Apple Review Guideline 2.2 directs beta/demo software to TestFlight. Prepare this unfinished alpha for TestFlight qualification; a public App Store listing can remain a draft. Do not hide the alpha status to obtain review approval. App Store acceptance has not been established.

## Images and preview

The unchanged maintainer-supplied icon is copied to `distribution/app-store/Photato-icon-1024.png`. It is artwork, not a screenshot. `media-plan.json` specifies four real 2880×1800 application captures and a 25-second 1920×1080/30fps H.264 preview showing layers/opacity, painting/undo and editable text/shapes/guides. Capture the actual signed application with owned sample documents after unlocking the Mac. Do not use Adobe screenshots, fabricated UI, private documents or stale-build screenshots as this build.

Capture, inspect and qualify media before uploading. Apple accepts Mac screenshots at 1280×800,1440×900,2560×1600 or2880×1800; Mac previews are 1920×1080,15–30seconds, at most30fps and500MB. Keep the alpha disclosure visible in the copy and preview. The media have not yet been captured or uploaded.

## Qualification still open

Known strict rendering/file comparisons remain unresolved. The full Release attempt was intentionally interrupted at an AppKit recovery-autosave wait, with 2,119 completed case records (9 failed) preserved. The root cause remains open; this is not a completed full inventory. The prior 330 focused qualification passes 297 cases. Physical 60fps editing, maximum-size operation, macOS 14/Intel runtime and complete native/Photoshop comparisons remain unqualified. Sandbox Open/Save/reopen/bookmark/recovery, optional API/file grants, printing and available Apple AI require runtime testing on the actual distribution build. No new editing kernel, command, menu, shortcut or API contract was added in331; 208 typed commands remain. Existing document/clipboard type identifiers are retained so the app bundle-ID change does not rename the document format.

Evidence and failures are preserved under `artifacts/runs/20261101T181125Z-331-app-store-preparation`. Those local logs and user/account state are not publication material. See `WORKING_CHECKPOINT_331.json`, DEVLOG 331 and the current developer diary for exact outcomes.

## Official references

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),2.2 beta testing and2.4.5 macOS sandbox requirements.
- [Select a release option](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/).
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
- [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/).
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox).
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
