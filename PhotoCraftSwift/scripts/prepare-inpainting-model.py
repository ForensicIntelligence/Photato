#!/usr/bin/env python3
"""Download and compile the optional LaMa512 model for Photato."""
from argparse import ArgumentParser
from hashlib import file_digest
import json
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory
from urllib.request import urlopen


REPOSITORY = "heypatkay/solume-big-lama-coreml"
REVISION = "c4358e4356b4c576a7fbfaabf27b5ffd5d9d7758"
FILES = {
    "lama/LaMa512.mlpackage/Manifest.json": (617, "a2576a37183e5a04265456092e18271e165564bd2e6578f6091e404236f3069b"),
    "lama/LaMa512.mlpackage/Data/com.apple.CoreML/model.mlmodel": (1323980, "a50e4ed35d3588892615046a111d274451ee83d29e854175fc91acc1361ffdd1"),
    "lama/LaMa512.mlpackage/Data/com.apple.CoreML/weights/weight.bin": (102068096, "4db509018e12aec710ab28d8ac1a88812665decf7511e538666590db3e5c88fb"),
    "LICENSE": (11348, "4ceeeac5a802e86c413c22b16cce8e9a22027b0250c97e6f8ac97c14cf0542c0"),
}


def acquire(path, name, size, digest):
    path.parent.mkdir(exist_ok=True, parents=True)
    with urlopen(f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{name}", timeout=60) as source:
        with path.open("xb") as target:
            while remaining := size - target.tell():
                chunk = source.read(min(remaining, 1024 * 1024))
                if not chunk:
                    break
                target.write(chunk)
            if target.tell() != size or source.read(1):
                raise ValueError(f"Unexpected length for {name}")
    with path.open("rb") as file:
        if file_digest(file, "sha256").hexdigest() != digest:
            raise ValueError(f"SHA-256 mismatch for {name}")


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New directory for the compiled model and license")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error("Choose a new output directory.")
    with TemporaryDirectory(prefix="photato-lama-", dir=output.parent) as directory:
        work = Path(directory)
        for name, (size, digest) in FILES.items():
            acquire(work / name, name, size, digest)
        compiled = work / "compiled"
        compiled.mkdir()
        subprocess.run(["xcrun", "coremlcompiler", "compile", work / "lama/LaMa512.mlpackage", compiled], check=True)
        if not (compiled / "LaMa512.mlmodelc").is_dir():
            raise ValueError("Core ML did not produce LaMa512.mlmodelc")
        shutil.copyfile(work / "LICENSE", compiled / "LICENSE")
        (compiled / "provenance.json").write_text(json.dumps({
            "model": "LaMa512", "repository": REPOSITORY, "revision": REVISION,
            "license": "Apache-2.0", "inputFiles": FILES,
        }, indent=2) + "\n")
        if output.exists():
            parser.error("The output directory appeared during preparation.")
        compiled.rename(output)
    print(output / "LaMa512.mlmodelc")


if __name__ == "__main__":
    main()
