#!/bin/zsh
set -euo pipefail

# Keep the supplied artwork and the existing CLI package's icon rendition sizes.
iconset="$DERIVED_FILE_DIR/Photato.iconset"
mkdir -p "$iconset" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SRCROOT/Assets/PhotatoIcon.png" \
    --out "$iconset/icon_${size}x${size}.png" > /dev/null
  retina_size=$((size * 2))
  if (( retina_size == 1024 )); then
    cp "$SRCROOT/Assets/PhotatoIcon.png" "$iconset/icon_${size}x${size}@2x.png"
  else
    sips -z "$retina_size" "$retina_size" "$SRCROOT/Assets/PhotatoIcon.png" \
      --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
  fi
done
iconutil --convert icns --output \
  "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Photato.icns" "$iconset"
