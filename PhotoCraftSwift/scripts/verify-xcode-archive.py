#!/usr/bin/env python3
"""Verify a supplied archive without relying on fixed build paths or old test logs."""
import argparse
import json
import sys
from pathlib import Path

from archive_validation import ArchiveError, verify_archive, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--source-manifest", type=Path)
    parser.add_argument("--mode", choices=["signed", "ci-unsigned"], default="signed")
    parser.add_argument("--report", type=Path, required=True, help="New JSON file; existing reports are never overwritten.")
    options = parser.parse_args()
    if options.report.exists():
        parser.error("The report already exists; choose a new path.")
    try:
        source = json.loads(options.source_manifest.read_text()) if options.source_manifest else None
        result = verify_archive(options.archive, options.source_root, mode=options.mode, source=source)
    except (ArchiveError, OSError, ValueError, KeyError) as error:
        result = {"schema": 1, "passed": False, "mode": options.mode, "error": str(error),
                  "software_release": False, "release_qualified": False}
    write_json(options.report, result)
    print(json.dumps({key: value for key, value in result.items() if key not in {"payload", "checks"}}, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
