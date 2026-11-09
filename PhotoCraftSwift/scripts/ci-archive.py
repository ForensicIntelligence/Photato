#!/usr/bin/env python3
"""Build a new, source-bound unsigned archive. Never install, export or publish."""
from __future__ import annotations

import argparse
import datetime
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

from archive_validation import (ArchiveError, input_manifest, payload_manifest,
                                release_policy, unchanged, verify_archive, write_json)


def test_ids(path: Path) -> list[str]:
    value = json.loads(path.read_text())
    if not isinstance(value, list) or not value or any(
        not isinstance(item, str) or not re.fullmatch(
            r"PhotoCraft(?:Core|Imaging|AI|App)Tests\.[A-Za-z0-9_]+/test[A-Za-z0-9_]+", item)
        for item in value
    ) or len(set(value)) != len(value):
        raise ArchiveError("Test manifest must contain unique explicit XCTest selectors.")
    return value


def xctest_result(text: str, expected: list[str]) -> dict:
    rows = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed) \(([\d.]+) seconds\)\.", text)
    actual = [a + "/" + b for a, b, _, _ in rows]
    result = {"expected": len(expected), "executed": len(rows),
              "passed": sum(state == "passed" for _, _, state, _ in rows),
              "missing": sorted(set(expected) - set(actual)),
              "extra": sorted(set(actual) - set(expected)),
              "failed": [a + "/" + b for a, b, state, _ in rows if state == "failed"],
              "duplicate_cases": len(actual) != len(set(actual)),
              "signals": re.findall(r"unexpected signal code\s*(\d+)", text),
              "skipped": bool(re.search(r"Test Case .* skipped", text))}
    result["passed_all"] = (result["passed"] == len(expected) == result["executed"]
                            and not any(result[key] for key in
                                        ["missing", "extra", "failed", "duplicate_cases", "signals", "skipped"]))
    return result


def output_path(root: Path, destination: Path) -> Path:
    root = root.resolve()
    destination = destination.absolute()
    if destination.exists() or destination.is_symlink():
        raise ArchiveError("Output already exists; choose a new directory. No files were removed.")
    if not destination.parent.is_dir():
        raise ArchiveError("Output parent must already exist.")
    destination = destination.parent.resolve() / destination.name
    if any(destination.is_relative_to(root / item) for item in
           ["Sources", "Tests", "Assets", "scripts", "Photato.xcodeproj", "ci"]):
        raise ArchiveError("Output must be outside source-input directories.")
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", required=True, type=Path, help="New directory; nothing existing is deleted or replaced.")
    parser.add_argument("--test-manifest", type=Path)
    parser.add_argument("--archive-only", action="store_true", help="Explicitly omit unit/editing tests; the report records them as not run.")
    options = parser.parse_args()
    root = options.source_root.resolve()
    try:
        output = output_path(root, options.output)
        release_policy(root)
        if platform.system() != "Darwin":
            raise ArchiveError("Xcode archive validation requires macOS.")
        if not (root / "Photato.xcodeproj/project.pbxproj").is_file():
            raise ArchiveError("Photato.xcodeproj is missing.")
        available = shutil.disk_usage(output.parent).free
        if available < 12 * 1024**3:
            raise ArchiveError("At least 12 GiB free is required before creating this archive. No files were removed.")
        ids = test_ids(options.test_manifest or root / "ci/archive-validation-tests.json")
        version = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, check=True).stdout
        match = re.search(r"Xcode (\d+)", version)
        if not match or int(match[1]) < 27:
            raise ArchiveError("This project requires Xcode 27 or later.")
        if not options.archive_only and platform.machine() != "arm64":
            raise ArchiveError("The two-architecture test path requires an Apple Silicon host and Rosetta.")
    except (ArchiveError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(json.dumps({"passed": False, "stage": "preflight", "error": str(error), "software_release": False}))
        return 1
    output.mkdir()
    inputs = input_manifest(root)
    write_json(output / "source-inputs.json", inputs)
    commands = []
    native_results = []
    permitted = {"PATH", "HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE",
                 "SHELL", "DEVELOPER_DIR", "SDKROOT", "MallocNanoZone", "OSLogRateLimit"}
    environment = {key: value for key, value in os.environ.items() if key in permitted}

    def execute(label: str, command: list[str], extra: dict | None = None) -> str:
        unchanged(root, inputs)
        if shutil.disk_usage(output).free < 4 * 1024**3:
            raise ArchiveError("Less than 4 GiB remains; stopping before another build step. Existing outputs are retained.")
        record = {"label": label, "command": command,
                  "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
        write_json(output / (label + "-command.json"), record)
        print(json.dumps({"stage": label, "state": "running"}), flush=True)
        env = environment | (extra or {})
        with (output / (label + ".log")).open("x") as stdout, (output / (label + "-stderr.log")).open("x") as stderr:
            worker = subprocess.Popen(command, cwd=root, env=env, stdout=stdout, stderr=stderr)
            write_json(output / (label + "-process.json"), {"pid": worker.pid, "label": label})
            record["exit_code"] = worker.wait()
        record["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        commands.append(record)
        unchanged(root, inputs)
        if record["exit_code"]:
            raise ArchiveError(label + " failed; original output and logs are retained.")
        return (output / (label + ".log")).read_text(errors="replace") + (output / (label + "-stderr.log")).read_text(errors="replace")

    try:
        unit_environment = {"PHOTATO_ARCHIVE_TEST_OUTPUT": str(output / "tool-tests"),
                            "PHOTATO_INVENTORY_TEST_OUTPUT": str(output / "inventory-tool-tests")}
        unit_log = execute("archive-tool-tests", [sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests",
                                                "-p", "test_*.py", "-v"], unit_environment)
        unit_match = re.search(r"Ran (\d+) tests? in", unit_log)
        if not unit_match or int(unit_match[1]) == 0 or "skipped=" in unit_log:
            raise ArchiveError("Archive tool tests did not execute completely.")
        if not options.archive_only:
            execute("rosetta-preflight", ["arch", "-x86_64", "/usr/bin/true"])
            pattern = "^(?:" + "|".join(re.escape(item) for item in ids) + ")$"
            captures = output / "editing-captures-arm"; captures.mkdir()
            log = execute("editing-tests-arm", ["swift", "test", "--build-system", "native", "--scratch-path",
                          str(output / "swift-arm"), "-c", "release", "--jobs", "4",
                          "--disable-build-manifest-caching", "--filter", pattern], {"PHOTATO_TEST_CAPTURE_DIR": str(captures)})
            native_results.append(xctest_result(log, ids))
            if not native_results[-1]["passed_all"]:
                raise ArchiveError("ARM editing tests have failed, skipped, duplicate or missing cases.")
            intel = output / "swift-intel"
            execute("editing-build-intel", ["swift", "build", "--build-tests", "--build-system", "native", "--scratch-path",
                    str(intel), "--triple", "x86_64-apple-macosx14.0", "-c", "release", "--jobs", "4", "-Xswiftc", "-enable-testing"])
            captures = output / "editing-captures-intel"; captures.mkdir()
            xctest = subprocess.check_output(["xcrun", "--find", "xctest"], env=environment, text=True).strip()
            log = execute("editing-tests-intel", ["arch", "-x86_64", xctest,
                          "-XCTest", ",".join(ids), str(intel / "x86_64-apple-macosx/release/PhotatoPackageTests.xctest")],
                          {"PHOTATO_TEST_CAPTURE_DIR": str(captures)})
            native_results.append(xctest_result(log, ids))
            if not native_results[-1]["passed_all"]:
                raise ArchiveError("Intel editing tests have failed, skipped, duplicate or missing cases.")
        archive = output / "Photato.xcarchive"
        command = ["xcodebuild", "-project", "Photato.xcodeproj", "-scheme", "Photato", "-configuration", "AppStore",
                   "-destination", "generic/platform=macOS", "-derivedDataPath", str(output / "DerivedData"),
                   "-archivePath", str(archive), "-jobs", "4", "archive", "CODE_SIGNING_ALLOWED=NO",
                   "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO",
                   "DEBUG_INFORMATION_FORMAT=dwarf-with-dsym"]
        execute("xcode-archive", command)
        verification = verify_archive(archive, root, mode="ci-unsigned", source=inputs)
        write_json(output / "archive-verification.json", verification)
        archive_bytes = sum(item.get("bytes", 0) for item in verification["payload"].values())
        if shutil.disk_usage(output).free < 2 * archive_bytes + 4 * 1024**3:
            raise ArchiveError("Insufficient space to retain and verify both archive ZIP copies. The archive is preserved.")
        bundle = output / "Photato-CI-Archive.zip"
        execute("archive-zip", ["ditto", "-c", "-k", "--keepParent", "--noextattr", "--norsrc", str(archive), str(bundle)])
        extracted = output / "zip-verification"
        execute("archive-extract", ["ditto", "-x", "-k", "--noextattr", "--norsrc", str(bundle), str(extracted)])
        if payload_manifest(extracted / archive.name) != verification["payload"]:
            raise ArchiveError("Extracted archive content differs from the verified archive.")
        result = {"schema": 1, "passed": True, "stage": "complete", "xcode": version,
                  "source_inputs": len(inputs), "source_unchanged": True, "archive_only": options.archive_only,
                  "archive_tool_tests": int(unit_match[1]), "editing_tests": native_results,
                  "archive_verification": "archive-verification.json", "archive_ZIP": bundle.name,
                  "ZIP_extraction_exact": True, "software_release": False, "release_qualified": False}
    except (ArchiveError, OSError, ValueError, KeyError) as error:
        result = {"schema": 1, "passed": False, "error": str(error), "archive_only": options.archive_only,
                  "editing_tests": native_results, "software_release": False, "release_qualified": False}
    result["commands"] = commands
    write_json(output / "result.json", result)
    print(json.dumps(result, indent=2), flush=True)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
