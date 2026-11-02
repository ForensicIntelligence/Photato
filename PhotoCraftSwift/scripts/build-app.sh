#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache .build/pm-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --build-system native --scratch-path /private/tmp/photocraft-swift-build --disable-sandbox --cache-path .build/pm-cache -c release
swift build --build-system native --scratch-path /private/tmp/photocraft-swift-intel --disable-sandbox --cache-path .build/pm-cache --triple x86_64-apple-macosx14.0 -c release
stage_root=$(mktemp -d /private/tmp/photato-package.XXXXXX)
trap 'rm -rf "$stage_root"' EXIT
app="$stage_root/Photato.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/build"
lipo -create /private/tmp/photocraft-swift-build/release/Photato /private/tmp/photocraft-swift-intel/x86_64-apple-macosx/release/Photato -output "$app/Contents/MacOS/Photato"
cp scripts/Info.plist "$app/Contents/Info.plist"
cp LICENSE-MIT LICENSE-APACHE LICENSE-psd-tools NOTICE ATTRIBUTION.md "$app/Contents/Resources/"
cp scripts/ProjectLinks.json "$app/Contents/Resources/ProjectLinks.json"
cp scripts/PrivacyInfo.xcprivacy "$app/Contents/Resources/PrivacyInfo.xcprivacy"
./scripts/copy-people-model.sh "$PWD" "$app/Contents/Resources"
# Package the maintainer's original artwork at each macOS icon resolution.
iconset="$stage_root/Photato.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Assets/PhotatoIcon.png --out "$iconset/icon_${size}x${size}.png" > /dev/null
  retina_size=$((size * 2))
  if (( retina_size == 1024 )); then
    cp Assets/PhotatoIcon.png "$iconset/icon_${size}x${size}@2x.png"
  else
    sips -z "$retina_size" "$retina_size" Assets/PhotatoIcon.png --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
  fi
done
iconutil --convert icns --output "$app/Contents/Resources/Photato.icns" "$iconset"
xattr -cr "$app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --noextattr --norsrc --keepParent "$app" "$PWD/build/Photato.zip"
ditto --noextattr --norsrc "$app" "$PWD/build/Photato.app"
# Desktop's file provider can add FinderInfo immediately after the copy or clear.
# Keep the clean staged ZIP and bound retries; never report an unverified local app.
verified=false
for attempt in 1 2 3; do
  xattr -cr "$PWD/build/Photato.app"
  if codesign --verify --deep --strict "$PWD/build/Photato.app"; then
    verified=true
    break
  fi
  sleep 1
done
"$verified"
echo "$PWD/build/Photato.app"
