#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache .build/pm-cache artifacts
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift test --build-system native --scratch-path /private/tmp/photocraft-swift-build --disable-sandbox --cache-path .build/pm-cache "$@"
