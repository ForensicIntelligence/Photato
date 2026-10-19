# Open-source fork and voluntary support

**Photato**, part of the Pantry family, will be distributed as an independent native Swift fork/port of [storytold/photocraft](https://github.com/storytold/photocraft), retaining **MIT OR Apache-2.0** and the upstream copyright, license and attribution notices. The Swift README, About window and NOTICE identify the original ArtCraft Team and PhotoCraft contributors. The fork is not an official upstream or Adobe release.

## Repository layout and history

The current local Rust directory is an extracted source snapshot without `.git` history. No public repository has been created or uploaded by this change. To publish an actual GitHub fork with upstream ancestry, fork `storytold/photocraft` into the selected owner account, clone that fork, and add this directory as `PhotoCraftSwift/` alongside the existing Rust sources. Keep the Rust history and original root files; link the native port from the fork's root README and explain the platform/scope differences. Record the upstream base commit at that point; do not invent a commit for the extracted snapshot.

Use this folder's CONTRIBUTING.md for native work. Preserve upstream notices and follow asset-specific terms when retaining upstream assets. The native binary uses system fonts and SF Symbols, and ships no ArtCraft/Adobe brand artwork. The native application is named **Photato**, part of the Pantry family. The public fork owner/repository remains to be selected.

The source release includes Sources, Tests and fixture provenance/licenses, Assets, Package.swift, scripts, documentation and license files. Build caches, `build/` and downloaded `corpus/` remain excluded. Local artifacts contain development logs and machine-specific paths; curate the public evidence set before publishing instead of uploading the entire working folder. The current app remains a development preview; full source/Photoshop parity, notarization and the multi-OS runtime matrix remain open.

## Support model

**Support Development** in About and Help opens a native SwiftUI window for optional one-time **consumable tips through StoreKit 2**. All editing features remain available to everyone. There are no startup prompts, editing interruptions, subscriptions or external donation destinations. Code, testing and documentation remain welcome contributions. Tips support the developer; the app makes no charitable or tax-deductibility claim.

[Apple's App Review Guidelines, section 3.1.1](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase), permit in-app purchases for tipping developers. StoreKit supplies localized names, descriptions and prices and presents Apple's purchase confirmation. Only verified transactions for configured consumables are acknowledged and finished. Cancellation, purchase restrictions, unavailable products, failed verification, pending approval, repeated purchases and unfinished-transaction recovery have explicit handling. A launch-time listener receives delayed approvals. Duplicate deliveries finish once within the process; a tip grants no entitlement or feature unlock. Consumable tips do not have a Restore Purchases operation; uncompleted transactions are recovered automatically.

Set release metadata in `scripts/ProjectLinks.json`:

- `repositoryURL`: the published fork's HTTPS source URL.
- `tipProductIDs`: the ordered consumable product identifiers registered for this app in App Store Connect.

The repository URL remains `null`. The three `local.photocraft.swift.tip.small`, `.medium` and `.large` IDs are **provisional development identifiers, not registered products**. Replace them when the release bundle identifier and owner are selected, or register the exact intended identifiers with that app. The app shows only configured products that StoreKit returns as consumables. An empty or unavailable catalogue leaves editing fully usable. The build script bundles this configuration before signing; rebuild after changes. Legacy `donationURL` metadata is ignored. No image or document data is sent with tips.

## Testing and App Store release gates

`./scripts/test.sh` runs deterministic transaction-policy and configuration tests. `./scripts/test-storekit.sh` runs a separate app-hosted Xcode XCTest suite against Apple's local StoreKit service. It requires full Xcode and access to that local service. The test host compiles the actual production purchase adapter/model, checks that StoreKit reports the **Xcode** environment before purchasing, disables simulated dialogs and clears its simulated transactions afterward. SwiftPM's command-line test host is unsuitable for this service on the tested OS; the dedicated host supplies the app identity and purchase window.

`Tests/StoreKitHost/DevelopmentTips.storekit` contains three local sample prices for testing only. It does not set production prices. The fixture, test host and StoreKitTest framework are excluded from the distributed Photato app. [Apple's StoreKit testing guide](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode) describes this local environment. These tests do not charge an account and do not replace App Store sandbox/TestFlight qualification.

Before App Store submission:

1. Select the public fork owner, registered bundle identifier and Apple Developer team. Retain the upstream notices and publish the source using the history-preserving process above.
2. Create the consumable tips in App Store Connect with matching product IDs, localized names/descriptions, final prices, availability and review information. The account holder must complete applicable paid-app agreements and financial setup. No such enrollment or account changes have been performed here.
3. Produce a signed App Store archive with App Sandbox and the required file-access/network capabilities. Qualify document opening, saving, persistent access and optional Apple AI under those entitlements. The current universal ZIP is an ad-hoc-signed development build, not an App Store submission archive.
4. Test the registered products in App Store sandbox/TestFlight: cancellation, pending approval, transaction recovery after termination, repeat tips, restricted purchases, offline failures, localized prices and refund handling. Include Intel/macOS 14 and supported Apple Silicon releases in the runtime matrix.
5. Supply App Review notes locating **Help → Support Development**, explaining that tips are optional consumables and unlock nothing. Submit the IAP products with the app as required by App Store Connect.

Production product registration, final pricing, signing, sandbox/TestFlight tests and App Review remain release gates. They do not block continued editing-engine development.
