#!/usr/bin/env python3
"""Compare recorded menus with source-bound native captures; never infer parity."""
from __future__ import annotations

import argparse
import collections
import csv
import io
import json
import re
import sys
from pathlib import Path

from archive_validation import ArchiveError, digest, input_manifest, write_json


MENU_FIELDS = ["menu_path", "kind", "native_action", "key_equivalent", "modifier_flags", "functionality_claim"]
PRODUCT_ROOTS = ("Sources/", "Tests/", "Assets/", "Photato.xcodeproj/")
PRODUCT_FILES = {"Package.swift", "Package.resolved", "project.yml"}
FLAGS = {"command": 1 << 20, "option": 1 << 19, "shift": 1 << 17, "control": 1 << 18}


class InventoryError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise InventoryError(message)


def unique_pairs(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key: " + key)
        result[key] = value
    return result


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_pairs)


def relative_file(root: Path, name: str) -> Path:
    require(isinstance(name, str) and bool(name) and not Path(name).is_absolute()
            and ".." not in Path(name).parts, "Expected a project-relative file path.")
    path = root / name
    require(path.resolve().is_relative_to(root.resolve()) and path.is_file(), "Missing or escaping input: " + name)
    return path


def captured(root: Path, record: dict):
    require(isinstance(record, dict) and set(record) == {"path", "sha256"}, "Invalid captured-input record.")
    path = relative_file(root, record["path"])
    require(isinstance(record["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", record["sha256"])
            and digest(path) == record["sha256"], "Captured input hash differs: " + record["path"])
    return read_json(path)


def product_inputs(manifest: dict) -> dict:
    require(isinstance(manifest, dict) and bool(manifest), "Empty source manifest.")
    for key, value in manifest.items():
        require(isinstance(key, str) and not Path(key).is_absolute() and ".." not in Path(key).parts
                and isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value), "Invalid source manifest.")
    result = {k: v for k, v in manifest.items() if k.startswith(PRODUCT_ROOTS) or k in PRODUCT_FILES}
    require(any(k.startswith("Sources/") for k in result) and "Package.swift" in result, "Missing product inputs.")
    return result


def source_matches(root: Path, expected: dict) -> None:
    actual = product_inputs(input_manifest(root))
    changed = sorted(k for k in actual.keys() | expected.keys() if actual.get(k) != expected.get(k))
    require(not changed, "Native capture is stale for current source: " + ", ".join(changed[:8]))


def menu_rows(report: dict) -> list[dict]:
    require(isinstance(report, dict) and isinstance(report.get("rows"), list) and report["rows"], "Missing native menu rows.")
    rows = report["rows"]
    paths = set()
    for row in rows:
        require(isinstance(row, dict) and set(row) == {"path", "title", "key", "modifiers", "action", "submenu"}, "Malformed menu row.")
        require(all(isinstance(row[k], str) for k in ["path", "title", "key", "action"])
                and row["title"] and row["path"].split(" > ")[-1] == row["title"], "Malformed menu path/title.")
        require(type(row["submenu"]) is bool and type(row["modifiers"]) is int
                and 0 <= row["modifiers"] < 2 ** 64, "Invalid submenu or modifier flags.")
        require(row["path"] not in paths, "Duplicate native menu path.")
        paths.add(row["path"])
        require((row["action"] == "submenuAction:") == row["submenu"], "Inconsistent submenu selector.")
    for row in rows:
        if " > " in row["path"]:
            parent = row["path"].rsplit(" > ", 1)[0]
            require(any(x["path"] == parent and x["submenu"] for x in rows), "Missing parent submenu.")
    counts = {"entries": len(rows), "entries_with_actions": sum(bool(x["action"]) for x in rows),
              "primary_shortcuts": sum(bool(x["key"]) for x in rows),
              "bound_leaf_commands": sum(bool(x["action"]) and not x["submenu"] for x in rows),
              "unavailable_leaf_commands": sum(not x["action"] and not x["submenu"] for x in rows)}
    require(all(type(report.get(k)) is int and report[k] == v for k, v in counts.items()), "Native menu summary differs from its rows.")
    require(report.get("menus") == [x["title"] for x in rows if " > " not in x["path"]], "Top-level menu order differs.")
    require(report.get("default_preset") == "Photoshop Defaults" and report.get("full_photoshop_parity") is False,
            "Capture must retain factory defaults and an explicit non-parity claim.")
    require(type(report.get("alternative_shortcuts")) is int and report["alternative_shortcuts"] >= 0, "Invalid alternate shortcut count.")
    return rows


def menu_csv(rows: list[dict]) -> str:
    out = io.StringIO(newline="")
    writer = csv.DictWriter(out, fieldnames=MENU_FIELDS, lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow({"menu_path": row["path"], "kind": "submenu" if row["submenu"] else "command",
                         "native_action": row["action"] or "unavailable", "key_equivalent": row["key"],
                         "modifier_flags": row["modifiers"], "functionality_claim": "structure only" if row["submenu"]
                         else "partial native operation" if row["action"] else "disabled placeholder"})
    return out.getvalue()


def csv_rows(path: Path, identity: str) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
    require(rows and reader.fieldnames and identity in reader.fieldnames, "Missing inventory rows/identity.")
    require(all(None not in row and all(v is not None for v in row.values()) and row[identity] for row in rows), "Malformed CSV row.")
    require(len({r[identity] for r in rows}) == len(rows), "Duplicate CSV identity: " + identity)
    return rows


def inventory_drift(current: list[dict], expected: list[dict]) -> dict:
    require(set(current[0]) == set(MENU_FIELDS), "Unexpected menu CSV columns.")
    old = {x["menu_path"]: x for x in current}
    new = {x["menu_path"]: x for x in expected}
    changed = [{"path": key, "fields": [k for k in MENU_FIELDS if old[key][k] != new[key][k]]}
               for key in new if key in old and old[key] != new[key]]
    return {"missing": [k for k in new if k not in old], "removed": [k for k in old if k not in new],
            "changed": changed, "order_matches": list(old) == list(new)}


def check_golden(rows: list[dict], golden: list[dict], additions: list[str]) -> None:
    require(isinstance(additions, list) and len(set(additions)) == len(additions)
            and all(isinstance(x, str) and x for x in additions), "Invalid supplemental menu inventory.")
    original = [x for x in rows if x["path"] not in additions]
    require([x["path"] for x in rows if x["path"] in additions] == additions, "Supplemental menu order/membership differs.")
    require(len(original) == len(golden), "Original Photoshop menu inventory count differs.")
    for actual, expected in zip(original, golden):
        require(isinstance(expected, dict) and set(expected) == {"path", "key", "modifiers"}, "Invalid golden menu row.")
        try:
            flags = sum(FLAGS[x] for x in expected["modifiers"])
        except (KeyError, TypeError):
            raise InventoryError("Unknown golden modifier.")
        require(actual["path"] == " > ".join(expected["path"]) and actual["key"] == expected["key"]
                and actual["modifiers"] == flags, "Factory path/order/shortcut changed: " + actual["path"])


def tool_matrix(rows: list[dict]) -> dict:
    require(isinstance(rows, list) and bool(rows), "Empty tool capture.")
    tools = collections.defaultdict(set)
    for row in rows:
        require(isinstance(row, dict) and set(row) == {"tool", "modifierBits", "cursor"}
                and isinstance(row["tool"], str) and row["tool"] and isinstance(row["cursor"], str) and row["cursor"]
                and type(row["modifierBits"]) is int and 0 <= row["modifierBits"] < 16, "Malformed tool capture row.")
        require(row["modifierBits"] not in tools[row["tool"]], "Duplicate tool/modifier capture.")
        tools[row["tool"]].add(row["modifierBits"])
    require(all(x == set(range(16)) for x in tools.values()), "Missing tool modifier combinations.")
    return {"tools": len(tools), "tool_modifier_contexts": len(rows), "tool_names": sorted(tools),
            "scope": "Main-tool captured cursor matrix; not complete tool functionality, physical key delivery or Photoshop cursor fidelity."}


def reconcile(root: Path, snapshot: Path, phases: Path, policy: Path, rust_root: Path | None = None) -> tuple[dict, str]:
    root = root.resolve()
    capture = read_json(snapshot)
    require(capture.get("schema") == 1, "Unsupported capture snapshot.")
    expected = product_inputs(captured(root, capture["source_manifest"]))
    source_matches(root, expected)
    require(set(capture["menus"]) == set(capture["tools"]) == {"arm64", "x86_64"}, "Both architecture captures are required.")
    menus = [captured(root, capture["menus"][arch]) for arch in ["arm64", "x86_64"]]
    require(menus[0] == menus[1], "Architecture menu reports differ.")
    rows = menu_rows(menus[0])
    tools = [captured(root, capture["tools"][arch]) for arch in ["arm64", "x86_64"]]
    require(tools[0] == tools[1], "Architecture tool reports differ.")
    tool_summary = tool_matrix(tools[0])
    rules = read_json(policy)
    check_golden(rows, read_json(root / "Tests/PhotoCraftAppTests/Fixtures/photoshop-menu-inventory.json"), rules["menu_additions"])
    require(menus[0]["alternative_shortcuts"] == rules["alternative_shortcuts"], "Alternate shortcut count differs.")
    ledger = read_json(phases)
    packages = {x["id"] for x in ledger["work_packages"]}
    require(len(packages) == len(ledger["work_packages"]) == ledger["counts"]["work_packages"], "Duplicate or inconsistent package inventory.")
    commands = csv_rows(root / "docs/COMMAND_PARITY.csv", "id")
    mapping = ledger["command_mapping"]
    require(len(mapping) == len({x["id"] for x in mapping}) == len(commands) == ledger["counts"]["commands"], "Command identity counts differ.")
    mapped = {x["id"]: x for x in mapping}
    for row in commands:
        target = mapped.get(row["id"], {})
        require(target.get("current_status") == row["swift_status"] and bool(target.get("work_packages"))
                and len(target["work_packages"]) == len(set(target["work_packages"]))
                and set(target["work_packages"]) <= packages, "Command/package/status mismatch: " + row["id"])
    workflows = csv_rows(root / "docs/WORKFLOW_ACCEPTANCE.csv", "id")
    require(all(x.get("acceptance") and x.get("steps") and x.get("fixture_required") and x.get("status") for x in workflows), "Incomplete workflow acceptance row.")
    for boundary in rules["external_boundaries"]:
        require(boundary.get("id") and boundary.get("classification") and boundary.get("reference")
                and boundary.get("remaining") and set(boundary["work_packages"]) <= packages
                and boundary.get("original_scope_retained") is True, "External boundary must retain original scope and evidence.")
    text = menu_csv(rows)
    expected_csv = list(csv.DictReader(io.StringIO(text)))
    drift = inventory_drift(csv_rows(root / "docs/MENU_PARITY.csv", "menu_path"), expected_csv)
    scorecards = []
    if rust_root is not None:
        import tomllib
        for path in sorted((rust_root / "scorecard").glob("*.toml")):
            data = tomllib.loads(path.read_text())
            items = data.get("item", [])
            scorecards.append({"file": path.name, "sha256": digest(path), "items": len(items),
                               "statuses": dict(collections.Counter(x["status"] for x in items))})
        require(bool(scorecards), "No upstream scorecards found.")
    source_matches(root, expected)
    passed = not drift["missing"] and not drift["removed"] and not drift["changed"] and drift["order_matches"]
    return {"schema": 1, "passed": passed, "native_capture_source_matches": True, "product_inputs": len(expected),
            "snapshot_sha256": digest(snapshot), "policy_sha256": digest(policy), "phase_ledger_sha256": digest(phases),
            "menu": {k: v for k, v in menus[0].items() if k != "rows"}, "menu_csv_drift": drift,
            "tools": tool_summary, "commands": {"identities": len(commands), "statuses": dict(collections.Counter(x["swift_status"] for x in commands))},
            "packages": len(packages), "workflows": {"scenarios": len(workflows), "statuses": dict(collections.Counter(x["status"] for x in workflows))},
            "upstream_scorecards": scorecards, "upstream_is_Photoshop_acceptance": False,
            "external_boundaries": rules["external_boundaries"], "full_Photoshop_parity": False,
            "limits": "Reconciliation of supplied captures and current inventories. A selector binding is not enabled-context, output, preference, API or full workflow qualification. No percentage or full-package closure is inferred."}, text


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--snapshot", required=True, type=Path)
    parser.add_argument("--phases", required=True, type=Path)
    parser.add_argument("--policy", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--write-menu-csv", type=Path, help="Write a NEW proposed CSV; never replace the tracked inventory.")
    parser.add_argument("--rust-root", type=Path)
    args = parser.parse_args(arguments)
    outputs = [args.report] + ([args.write_menu_csv] if args.write_menu_csv is not None else [])
    protected = [args.root.resolve() / folder for folder in ["Sources", "Tests", "Assets", "Photato.xcodeproj", "scripts", "ci"]]
    if any(path.resolve().is_relative_to(folder) for path in outputs for folder in protected):
        print("Reports and proposals must be outside product and tooling input directories.", file=sys.stderr)
        return 2
    if args.report.exists() or (args.write_menu_csv is not None and args.write_menu_csv.exists()):
        print("Refusing to overwrite an existing report or CSV.", file=sys.stderr)
        return 2
    try:
        report, text = reconcile(args.root, args.snapshot, args.phases, args.policy, args.rust_root)
        if args.write_menu_csv is not None:
            with args.write_menu_csv.open("x", encoding="utf-8", newline="") as handle:
                handle.write(text)
        write_json(args.report, report)
        print(json.dumps({"passed": report["passed"], "entries": report["menu"]["entries"], "report": str(args.report)}))
        return 0 if report["passed"] else 1
    except (InventoryError, ArchiveError, OSError, ValueError, KeyError, TypeError) as error:
        write_json(args.report, {"passed": False, "error": str(error), "full_Photoshop_parity": False})
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
