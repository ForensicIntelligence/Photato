#!/bin/zsh
set -euo pipefail
build_root="$1"
resources="$2"
bundle="$build_root/Photato_PhotoCraftImaging.bundle"
[[ -d "$bundle" && -f "$bundle/FactoryRGB8Gray20.zlib" ]] || { print -u2 "Missing compiled Imaging resources"; exit 1; }
mkdir -p "$resources"
ditto --noextattr --norsrc "$bundle" "$resources/Photato_PhotoCraftImaging.bundle"
