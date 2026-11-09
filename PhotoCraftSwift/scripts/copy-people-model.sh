#!/bin/zsh
set -euo pipefail
project_root="$1"
resources="$2"
model_root="$project_root/Assets/GeneratedModels"
if [[ -d "$model_root/PeopleParts.mlmodelc" ]]; then
  python3 "$project_root/scripts/verify-people-model.py" "$model_root"
  mkdir -p "$resources"
  ditto --noextattr --norsrc "$model_root/PeopleParts.mlmodelc" "$resources/PeopleParts.mlmodelc"
  cp "$model_root/PeopleParts.provenance.json" "$resources/PeopleParts.provenance.json"
else
  # Remove only this optional generated resource from a reused build product.
  rm -rf "$resources/PeopleParts.mlmodelc" "$resources/PeopleParts.provenance.json"
fi

"$project_root/scripts/copy-upscale-model.sh" "$project_root" "$resources"
