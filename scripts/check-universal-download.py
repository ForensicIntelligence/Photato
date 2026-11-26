#!/usr/bin/env python3
"""Check that the tracked Universal preview and the published source agree."""

from hashlib import file_digest
import json
from pathlib import Path
import plistlib
import struct
from zipfile import BadZipFile, ZipFile


def check(root: Path) -> str:
    project = root / "PhotoCraftSwift"
    source_info = plistlib.loads((project / "scripts/Info.plist").read_bytes())
    build = source_info["CFBundleVersion"]
    receipt = json.loads((project / f"docs/SOURCE_PUBLICATION_{build}.json").read_text())
    archive_path = root / "downloads/Photato-universal.zip"
    with archive_path.open("rb") as stream:
        digest = file_digest(stream, "sha256").hexdigest()
    if digest != receipt["preview"]["archiveSHA256"]:
        raise ValueError(f"The download SHA-256 does not match source checkpoint {build}.")

    with ZipFile(archive_path) as archive:
        info_files = [name for name in archive.namelist() if name.endswith(".app/Contents/Info.plist")
                      and name.count("/") == 2]
        if len(info_files) != 1:
            raise ValueError("The download must contain one macOS app bundle.")
        info_file = info_files[0]
        info = plistlib.loads(archive.read(info_file))
        contents = info_file.rsplit("/", 1)[0]
        if info["CFBundleVersion"] != build or info["LSMinimumSystemVersion"] != "14.0":
            raise ValueError(f"The download must target macOS 14.0 and match source build {build}.")
        with archive.open(f"{contents}/MacOS/{info['CFBundleExecutable']}") as executable:
            magic, count = struct.unpack(">II", executable.read(8))
            if magic != 0xCAFEBABE or count != 2:
                raise ValueError("The executable must be a two-slice Universal Mach-O.")
            cpu_types = {struct.unpack(">IIIII", executable.read(20))[0] for _ in range(count)}
            if cpu_types != {0x01000007, 0x0100000C}:
                raise ValueError("The executable must include x86_64 and arm64.")
    return build


if __name__ == "__main__":
    try:
        print(f"Universal download matches source build {check(Path(__file__).resolve().parents[1])}.")
    except (BadZipFile, KeyError, OSError, ValueError, struct.error) as error:
        raise SystemExit(str(error)) from error
