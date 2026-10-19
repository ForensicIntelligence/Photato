#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# StoreKitTest needs an app-hosted XCTest process and access to Apple's local test service.
# The tests verify .xcode before calling purchase; they never use an App Store account.
xcodebuild test -project Tests/StoreKitHost/PhotoCraftTips.xcodeproj \
  -scheme PhotoCraftTips -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/photocraft-storekit-tests \
  -parallel-testing-enabled NO -maximum-test-execution-time-allowance 60 \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
