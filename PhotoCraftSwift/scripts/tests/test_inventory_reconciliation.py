"""Owned synthetic inventories exercise drift, stale captures and refusal paths."""
import copy
import csv
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from archive_validation import digest, input_manifest
spec = importlib.util.spec_from_file_location("inventory_reconciliation", SCRIPTS / "reconcile-inventories.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class InventoryReconciliationTests(unittest.TestCase):
    def setUp(self):
        output = os.environ.get("PHOTATO_INVENTORY_TEST_OUTPUT")
        if output is not None:
            Path(output).mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix="inventory-", dir=output))
        for folder in ["Sources/App", "docs", "Tests/PhotoCraftAppTests/Fixtures", "captures"]:
            (self.root / folder).mkdir(parents=True)
        (self.root / "Package.swift").write_text("// Owned test source\n")
        (self.root / "Sources/App/App.swift").write_text("// Owned test source\n")
        self.menu = {"alternative_shortcuts": 0, "bound_leaf_commands": 1, "default_preset": "Photoshop Defaults",
                     "entries": 2, "entries_with_actions": 2, "full_photoshop_parity": False, "menus": ["File"],
                     "primary_shortcuts": 1, "unavailable_leaf_commands": 0,
                     "rows": [{"path": "File", "title": "File", "key": "", "modifiers": 0, "action": "submenuAction:", "submenu": True},
                              {"path": "File > New…", "title": "New…", "key": "n", "modifiers": 1 << 20, "action": "newFile", "submenu": False}]}
        self.save("Tests/PhotoCraftAppTests/Fixtures/photoshop-menu-inventory.json",
                  [{"path": ["File"], "key": "", "modifiers": []}, {"path": ["File", "New…"], "key": "n", "modifiers": ["command"]}])
        self.policy = {"menu_additions": [], "alternative_shortcuts": 0, "external_boundaries": []}
        self.save("policy.json", self.policy)
        self.ledger = {"counts": {"work_packages": 1, "commands": 1}, "work_packages": [{"id": "D01"}],
                       "command_mapping": [{"id": "file.new", "work_packages": ["D01"], "current_status": "partial"}]}
        self.save("phases.json", self.ledger)
        self.write_csv("docs/COMMAND_PARITY.csv", [{"id": "file.new", "swift_status": "partial"}])
        self.write_csv("docs/WORKFLOW_ACCEPTANCE.csv", [{"id": "WF-001", "acceptance": "Owned expected output", "steps": "Open", "fixture_required": "Owned fixture", "status": "planned"}])
        (self.root / "docs/MENU_PARITY.csv").write_text(audit.menu_csv(self.menu["rows"]))
        self.save("captures/source.json", input_manifest(self.root))
        tools = [{"tool": "Brush", "modifierBits": i, "cursor": "owned-cursor"} for i in range(16)]
        for arch in ["arm64", "x86_64"]:
            self.save("captures/menu-" + arch + ".json", self.menu)
            self.save("captures/tools-" + arch + ".json", tools)
        self.snapshot = {"schema": 1, "source_manifest": self.ref("captures/source.json"),
                         "menus": {a: self.ref("captures/menu-" + a + ".json") for a in ["arm64", "x86_64"]},
                         "tools": {a: self.ref("captures/tools-" + a + ".json") for a in ["arm64", "x86_64"]}}
        self.save("snapshot.json", self.snapshot)

    def save(self, name, value):
        (self.root / name).write_text(json.dumps(value, indent=2) + "\n")

    def ref(self, name):
        return {"path": name, "sha256": digest(self.root / name)}

    def write_csv(self, name, rows):
        with (self.root / name).open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)

    def run_audit(self):
        return audit.reconcile(self.root, self.root / "snapshot.json", self.root / "phases.json", self.root / "policy.json")

    def replace_capture(self, kind, value):
        for arch in ["arm64", "x86_64"]:
            name = self.snapshot[kind][arch]["path"]
            self.save(name, value); self.snapshot[kind][arch] = self.ref(name)
        self.save("snapshot.json", self.snapshot)

    def testValidInventoriesRetainPartialAndPlannedStatesWithoutParityClaim(self):
        report, text = self.run_audit()
        self.assertTrue(report["passed"]); self.assertFalse(report["full_Photoshop_parity"])
        self.assertEqual(report["commands"], {"identities": 1, "statuses": {"partial": 1}})
        self.assertEqual(report["workflows"], {"scenarios": 1, "statuses": {"planned": 1}})
        self.assertEqual(text, (self.root / "docs/MENU_PARITY.csv").read_text())

    def testMissingMenuProducesExplicitDrift(self):
        (self.root / "docs/MENU_PARITY.csv").write_text(audit.menu_csv(self.menu["rows"][:1]))
        report, _ = self.run_audit()
        self.assertFalse(report["passed"]); self.assertEqual(report["menu_csv_drift"]["missing"], ["File > New…"])

    def testChangedSelectorIsNotSilentlyPromoted(self):
        rows = copy.deepcopy(self.menu["rows"]); rows[1]["action"] = ""
        (self.root / "docs/MENU_PARITY.csv").write_text(audit.menu_csv(rows))
        report, _ = self.run_audit(); self.assertFalse(report["passed"])
        self.assertIn("native_action", report["menu_csv_drift"]["changed"][0]["fields"])

    def testMenuCSVOrderDriftIsRejected(self):
        (self.root / "docs/MENU_PARITY.csv").write_text(audit.menu_csv(list(reversed(self.menu["rows"]))))
        self.assertFalse(self.run_audit()[0]["passed"])

    def testCommandStatusMismatchIsRejected(self):
        self.ledger["command_mapping"][0]["current_status"] = "verified"; self.save("phases.json", self.ledger)
        with self.assertRaisesRegex(audit.InventoryError, "Command/package/status mismatch"): self.run_audit()

    def testDuplicateCommandIdentityIsRejected(self):
        self.write_csv("docs/COMMAND_PARITY.csv", [{"id": "file.new", "swift_status": "partial"}] * 2)
        with self.assertRaisesRegex(audit.InventoryError, "Duplicate CSV identity"): self.run_audit()

    def testUnknownPackageIsRejected(self):
        self.ledger["command_mapping"][0]["work_packages"] = ["missing"]; self.save("phases.json", self.ledger)
        with self.assertRaisesRegex(audit.InventoryError, "Command/package/status mismatch"): self.run_audit()

    def testModifiedProductMakesCaptureStale(self):
        (self.root / "Sources/App/App.swift").write_text("// Changed\n")
        with self.assertRaisesRegex(audit.InventoryError, "capture is stale"): self.run_audit()

    def testAddedProductFileMakesCaptureStale(self):
        (self.root / "Sources/App/Extra.swift").write_text("// New\n")
        with self.assertRaisesRegex(audit.InventoryError, "capture is stale"): self.run_audit()

    def testCaptureHashMismatchIsRejected(self):
        self.save("captures/menu-arm64.json", {})
        with self.assertRaisesRegex(audit.InventoryError, "hash differs"): self.run_audit()

    def testArchitectureMismatchIsRejected(self):
        menu = copy.deepcopy(self.menu); menu["rows"][1]["action"] = "wrong"
        self.save("captures/menu-x86_64.json", menu); self.snapshot["menus"]["x86_64"] = self.ref("captures/menu-x86_64.json"); self.save("snapshot.json", self.snapshot)
        with self.assertRaisesRegex(audit.InventoryError, "Architecture menu reports differ"): self.run_audit()

    def testFabricatedSummaryCountIsRejected(self):
        menu = copy.deepcopy(self.menu); menu["entries"] = 99; self.replace_capture("menus", menu)
        with self.assertRaisesRegex(audit.InventoryError, "summary differs"): self.run_audit()

    def testFactoryShortcutChangeIsRejected(self):
        menu = copy.deepcopy(self.menu); menu["rows"][1]["key"] = "m"; self.replace_capture("menus", menu)
        with self.assertRaisesRegex(audit.InventoryError, "Factory path/order/shortcut changed"): self.run_audit()

    def testMissingToolModifierIsRejected(self):
        tools = json.loads((self.root / "captures/tools-arm64.json").read_text()); self.replace_capture("tools", tools[:-1])
        with self.assertRaisesRegex(audit.InventoryError, "Missing tool modifier"): self.run_audit()

    def testDuplicateToolModifierIsRejected(self):
        tools = json.loads((self.root / "captures/tools-arm64.json").read_text()); self.replace_capture("tools", tools + tools[:1])
        with self.assertRaisesRegex(audit.InventoryError, "Duplicate tool/modifier"): self.run_audit()

    def testPathEscapeIsRejected(self):
        self.snapshot["source_manifest"]["path"] = "../outside.json"; self.save("snapshot.json", self.snapshot)
        with self.assertRaisesRegex(audit.InventoryError, "project-relative"): self.run_audit()

    def testDuplicateJSONKeysAreRejected(self):
        (self.root / "snapshot.json").write_text('{"schema":1,"schema":2}')
        with self.assertRaisesRegex(audit.InventoryError, "Duplicate JSON key"): self.run_audit()

    def testExternalBoundaryCannotWithdrawOriginalScope(self):
        self.policy["external_boundaries"] = [{"id": "beta", "classification": "beta", "reference": "owned-reference", "remaining": "Still open", "work_packages": ["D01"], "original_scope_retained": False}]
        self.save("policy.json", self.policy)
        with self.assertRaisesRegex(audit.InventoryError, "retain original scope"): self.run_audit()

    def testCLIProposalDoesNotReplaceTrackedInventory(self):
        target = self.root / "docs/MENU_PARITY.csv"; target.write_text(audit.menu_csv(self.menu["rows"][:1])); before = target.read_bytes()
        args = ["--root", str(self.root), "--snapshot", str(self.root / "snapshot.json"), "--phases", str(self.root / "phases.json"), "--policy", str(self.root / "policy.json"), "--report", str(self.root / "report.json"), "--write-menu-csv", str(self.root / "proposal.csv")]
        self.assertEqual(audit.main(args), 1); self.assertEqual(target.read_bytes(), before)
        self.assertEqual((self.root / "proposal.csv").read_text(), audit.menu_csv(self.menu["rows"]))
        self.assertEqual(audit.main(args), 2); self.assertEqual(target.read_bytes(), before)

    def testUnknownAlternateCountIsRejected(self):
        menu = copy.deepcopy(self.menu); menu["alternative_shortcuts"] = 1; self.replace_capture("menus", menu)
        with self.assertRaisesRegex(audit.InventoryError, "Alternate shortcut count differs"): self.run_audit()

    def testCLIOutputsCannotCreateProductOrToolingInputs(self):
        before = input_manifest(self.root)
        for folder in ["Sources", "Tests", "Assets", "Photato.xcodeproj", "scripts", "ci"]:
            for option in ["--report", "--write-menu-csv"]:
                path = self.root / folder / "new-output.json"
                args = ["--root", str(self.root), "--snapshot", str(self.root / "snapshot.json"), "--phases", str(self.root / "phases.json"), "--policy", str(self.root / "policy.json"), "--report", str(path if option == "--report" else self.root / "unused-report.json")]
                if option == "--write-menu-csv": args += [option, str(path)]
                self.assertEqual(audit.main(args), 2); self.assertFalse(path.exists())
        self.assertEqual(input_manifest(self.root), before)
