#!/usr/bin/env python3
"""Optional external reference acquisition; this asset is not redistributed."""
from pathlib import Path
import argparse, hashlib, os, urllib.request

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "Tests/PhotoCraftImagingTests/Fixtures/layer-comps/ag-psd-layer-comps.psd"
URL = "https://raw.githubusercontent.com/Agamnentzar/ag-psd/a74425db6584cc07b1cc135e370916cb4eccfb32/test/read-write/layer-comps/src.psd"
SHA256 = "d6b4daeed5856d1fcfd6f4ae72cf10c9ac91a415d6e9db26da483027b6ded366"
SIZE = 36014

def verify(data):
    if len(data) != SIZE or hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError("Reference does not match the pinned size and SHA-256.")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify a locally available reference without networking.")
    parser.add_argument("--download", action="store_true", help="Download only if you are permitted under the upstream asset terms.")
    args = parser.parse_args()
    if args.check:
        verify(DESTINATION.read_bytes())
        print("Pinned local reference verified.")
        return
    if not args.download:
        parser.print_help()
        print("The upstream license excludes image assets. Obtain permission or applicable rights before downloading; this repository does not redistribute this PSD.")
        return
    if DESTINATION.exists():
        verify(DESTINATION.read_bytes())
        print("Pinned reference already present; no overwrite.")
        return
    with urllib.request.urlopen(URL, timeout=30) as response:
        data = response.read(SIZE + 1)
    verify(data)
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    temporary = DESTINATION.with_suffix(".psd.download")
    with temporary.open("xb") as output:
        output.write(data)
    os.replace(temporary, DESTINATION)
    print("Pinned external reference saved locally; keep it out of source distributions.")

if __name__ == "__main__":
    main()
