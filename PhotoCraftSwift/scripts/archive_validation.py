"""Source-bound local Xcode archive checks; never export, upload or release."""
from __future__ import annotations

import hashlib
import json
import plistlib
import re
import subprocess
from decimal import Decimal, InvalidOperation
from pathlib import Path


class ArchiveError(ValueError):
    pass


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def write_json(path: Path, value: object) -> None:
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def input_manifest(root: Path) -> dict[str, str]:
    root = root.resolve()
    files: set[Path] = set()
    for folder in ["Sources", "Tests", "Assets", "scripts", "Photato.xcodeproj", "ci", "docs/contracts"]:
        base = root / folder
        if base.is_dir():
            files.update(path for path in base.rglob("*") if path.is_file())
    for name in [".gitignore", "Package.swift", "Package.resolved", "project.yml", "LICENSE-MIT",
                 "LICENSE-APACHE", "LICENSE-psd-tools", "NOTICE", "ATTRIBUTION.md",
                 "distribution/app-store/release-policy.json"]:
        path = root / name
        if path.is_file():
            files.add(path)
    result = {}
    for path in sorted(files):
        if path.name == ".DS_Store" or path.suffix == ".pyc" or any(
            part in {"__pycache__", "xcuserdata"} for part in path.parts
        ):
            continue
        if not path.resolve().is_relative_to(root):
            raise ArchiveError("Source input escapes the project: " + str(path.relative_to(root)))
        result[path.relative_to(root).as_posix()] = digest(path)
    return result


def unchanged(root: Path, expected: dict[str, str]) -> None:
    if not isinstance(expected, dict) or not expected or any(
        not isinstance(key, str) or not isinstance(value, str)
        or Path(key).is_absolute() or ".." in Path(key).parts
        or not re.fullmatch(r"[0-9a-f]{64}", value)
        for key, value in expected.items()
    ):
        raise ArchiveError("Invalid source-input manifest.")
    actual = input_manifest(root)
    changed = sorted(key for key in set(expected) | set(actual) if expected.get(key) != actual.get(key))
    if changed:
        raise ArchiveError("Source inputs changed: " + ", ".join(changed[:12]))


def release_policy(root: Path) -> dict:
    path = root / "distribution/app-store/release-policy.json"
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ArchiveError("Invalid release policy.")
    flags = {"automaticRelease": False, "automaticTestFlightDistribution": False,
             "preOrder": False, "submitForReview": False, "releaseRequiresHumanApproval": True}
    if value.get("releaseType") != "MANUAL" or any(
        type(value.get(key)) is not bool or value[key] is not expected
        for key, expected in flags.items()
    ):
        raise ArchiveError("Release policy must remain manual, without automatic distribution or review.")
    try:
        free = Decimal(str(value["price"]["amount"])) == 0
    except (KeyError, TypeError, InvalidOperation):
        free = False
    if not free:
        raise ArchiveError("Photato must remain completely free.")
    return value


def run_tool(arguments: list[str]) -> str:
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode:
        raise ArchiveError("Tool failed: " + arguments[0] + ": " + result.stderr[-1600:])
    return result.stdout


def uuids(output: str) -> dict[str, str]:
    rows = re.findall(r"^UUID: ([0-9A-Fa-f-]{36}) \(([^)]+)\) ", output, re.MULTILINE)
    result = {arch: value.upper() for value, arch in rows}
    if len(rows) != 2 or len(result) != 2 or set(result) != {"arm64", "x86_64"}:
        raise ArchiveError("Expected exactly one ARM and one Intel build UUID.")
    return result


def inside(root: Path, path: Path) -> Path:
    if not path.resolve().is_relative_to(root.resolve()):
        raise ArchiveError("Archive path escapes its container: " + str(path))
    return path


def payload_manifest(root: Path) -> dict:
    result = {}
    for path in sorted(root.rglob("*")):
        inside(root, path)
        key = path.relative_to(root).as_posix()
        if path.is_symlink():
            result[key] = {"symlink": str(path.readlink())}
        elif path.is_file():
            result[key] = {"sha256": digest(path), "bytes": path.stat().st_size}
    return result


def verify_archive(archive: Path, root: Path, *, mode: str = "signed",
                   source: dict[str, str] | None = None) -> dict:
    """Signed mode checks a local team-signed archive, not Apple server approval.

    ci-unsigned is explicitly non-distributable and cannot prove sandbox runtime.
    """
    if mode not in {"signed", "ci-unsigned"}:
        raise ArchiveError("Unknown signature mode.")
    root, archive = root.resolve(), archive.resolve()
    checks = []

    def require(name: str, value: bool) -> None:
        checks.append({"name": name, "passed": bool(value)})
        if not value:
            raise ArchiveError(name)

    policy = release_policy(root)
    if source is not None:
        unchanged(root, source)
    require("Xcode archive exists", archive.is_dir() and archive.suffix == ".xcarchive")
    metadata = plistlib.loads((archive / "Info.plist").read_bytes())
    require("Archive metadata dictionary", isinstance(metadata, dict)
            and isinstance(metadata.get("ApplicationProperties"), dict))
    relative = metadata.get("ApplicationProperties", {}).get("ApplicationPath", "")
    require("Canonical application path", relative == "Applications/Photato.app")
    app = inside(archive, archive / "Products" / relative)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = plistlib.loads((root / "scripts/Info.plist").read_bytes())
    require("Application metadata dictionaries", isinstance(info, dict) and isinstance(expected, dict))
    for key in ["CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString", "CFBundleVersion"]:
        require("Source-bound " + key, info.get(key) == expected.get(key))
    for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"]:
        require("Archive metadata " + key, metadata["ApplicationProperties"].get(key) == info[key])
    require("Requested production identifier", info.get("CFBundleIdentifier") == policy.get("bundleID")
            == "ca.forensicintelligence.photato")
    require("macOS 14 deployment metadata", info.get("LSMinimumSystemVersion") == "14.0")
    require("Graphics category", info.get("LSApplicationCategoryType") == "public.app-category.graphics-design")
    executable = inside(archive, app / "Contents/MacOS" / info["CFBundleExecutable"])
    require("Universal ARM and Intel executable", set(run_tool(["lipo", "-archs", str(executable)]).split())
            == {"arm64", "x86_64"})
    versions = run_tool(["xcrun", "vtool", "-show-build", str(executable)])
    require("Both Mach-O slices target macOS 14", re.findall(r"\bminos\s+(\S+)", versions) == ["14.0", "14.0"])
    symbols = inside(archive, archive / "dSYMs/Photato.app.dSYM/Contents/Resources/DWARF" / info["CFBundleExecutable"])
    require("Crash symbols retained", symbols.is_file())
    binary_uuids = uuids(run_tool(["xcrun", "dwarfdump", "--uuid", str(executable)]))
    symbol_uuids = uuids(run_tool(["xcrun", "dwarfdump", "--uuid", str(symbols)]))
    require("Exact binary/dSYM UUID match on both architectures", binary_uuids == symbol_uuids)
    links = run_tool(["otool", "-L", str(executable)])
    dependencies = [line.strip().split(" (")[0] for line in links.splitlines() if line.startswith("\t")]
    require("Apple runtime dependencies", bool(dependencies) and all(
        item.startswith(("/System/Library/", "/usr/lib/", "@rpath/libswift")) for item in dependencies))
    resources = inside(archive, app / "Contents/Resources")
    for name in ["LICENSE-MIT", "LICENSE-APACHE", "LICENSE-psd-tools", "NOTICE", "ATTRIBUTION.md",
                 "scripts/PrivacyInfo.xcprivacy", "scripts/ProjectLinks.json",
                 "Sources/PhotoCraftImaging/Resources/FactoryRGB8Gray20.zlib"]:
        reference, bundled = root / name, inside(archive, resources / Path(name).name)
        require("Exact bundled " + Path(name).name, reference.is_file() and bundled.is_file()
                and digest(reference) == digest(bundled))
    require("App icon included", (resources / "Photato.icns").is_file())
    require("No test bundles or document fixtures", not any(
        path.name == "Tests" or path.name.endswith("Tests.bundle")
        or path.suffix.lower() in {".psd", ".psb", ".pcraft", ".storekit", ".grd"}
        for path in app.rglob("*")))
    model = root / "Assets/GeneratedModels/PeopleParts.mlmodelc"
    bundled_model = resources / "PeopleParts.mlmodelc"
    require("Optional model presence matches inputs", model.is_dir() == bundled_model.is_dir())
    if model.is_dir():
        require("Optional model bytes match inputs", payload_manifest(model) == payload_manifest(bundled_model))
        original_provenance = model.parent / "PeopleParts.provenance.json"
        bundled_provenance = resources / original_provenance.name
        require("Optional model provenance retained", original_provenance.is_file() and bundled_provenance.is_file()
                and digest(original_provenance) == digest(bundled_provenance))
    expected_entitlements = plistlib.loads((root / "scripts/Photato-AppStore.entitlements").read_bytes())
    require("Source requests sandbox", expected_entitlements.get("com.apple.security.app-sandbox") is True)
    description = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)], capture_output=True, text=True)
    team = re.search(r"^TeamIdentifier=(.+)$", description.stderr, re.MULTILINE)
    actual_entitlements = None
    if mode == "signed":
        run_tool(["codesign", "--verify", "--deep", "--strict", str(app)])
        require("FI team signature", team is not None and team[1] == policy.get("teamID")
                and "Signature=adhoc" not in description.stderr)
        require("Hardened runtime", re.search(r"flags=0x[0-9a-f]+\([^)]*runtime", description.stderr) is not None)
        actual_entitlements = plistlib.loads(run_tool(["codesign", "-d", "--entitlements", ":-", str(app)]).encode())
        require("Complete requested sandbox entitlements", all(actual_entitlements.get(k) == v
                for k, v in expected_entitlements.items()))
        forbidden = ["com.apple.security.cs.disable-library-validation",
                     "com.apple.security.cs.allow-unsigned-executable-memory",
                     "com.apple.security.cs.allow-dyld-environment-variables"]
        require("No hardened-runtime bypasses", all(not actual_entitlements.get(k, False) for k in forbidden))
    else:
        require("Unsigned CI mode is not a team-signed release", description.returncode != 0
                or "Signature=adhoc" in description.stderr or team is None or team[1] == "not set")
    payload = payload_manifest(archive)
    if source is not None:
        unchanged(root, source)
    return {"schema": 1, "passed": True, "mode": mode, "archive": str(archive),
            "application_build": info["CFBundleVersion"], "version": info["CFBundleShortVersionString"],
            "bundle_id": info["CFBundleIdentifier"], "architectures": sorted(binary_uuids),
            "minimum_macos": "14.0", "binary_sha256": digest(executable), "symbol_sha256": digest(symbols),
            "binary_UUIDs": binary_uuids, "symbol_UUIDs": symbol_uuids, "checks": checks,
            "source_bound": source is not None, "source_inputs": len(source or {}),
            "requested_entitlements": expected_entitlements, "embedded_entitlements": actual_entitlements,
            "payload": payload, "optional_model_included": model.is_dir(),
            "local_manual_release_policy_verified": True, "App_Store_Connect_policy_reverified": False,
            "Apple_server_validation": False,
            "sandbox_runtime_verified": False, "software_release": False, "release_qualified": False,
            "limits": "Local archive checks only. CI-unsigned is non-distributable; signed mode does not prove distribution provisioning, Apple validation, privacy approval or runtime acceptance."}
