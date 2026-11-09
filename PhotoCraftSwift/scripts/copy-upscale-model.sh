#!/bin/zsh
set -euo pipefail
project_root="$1"
resources="$2"
model_root="$project_root/Assets/GeneratedModels"
mkdir -p "$resources"
cp "$project_root/LICENSE-RealESRGAN" "$resources/LICENSE-RealESRGAN"
if [[ -d "$model_root/LocalUpscale.mlmodelc" ]]; then
  python3 "$project_root/scripts/verify-upscale-model.py" "$model_root"
  ditto --noextattr --norsrc "$model_root/LocalUpscale.mlmodelc" "$resources/LocalUpscale.mlmodelc"
  cp "$model_root/LocalUpscale.provenance.json" "$resources/LocalUpscale.provenance.json"
else
  # Only this optional resource in a reused derived product; never a source model.
  rm -rf "$resources/LocalUpscale.mlmodelc" "$resources/LocalUpscale.provenance.json"
fi
