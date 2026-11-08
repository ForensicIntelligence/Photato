import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
PROJECT = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))
from archive_validation import (ArchiveError, input_manifest, payload_manifest,
                                release_policy, unchanged, uuids, verify_archive)

spec = importlib.util.spec_from_file_location("photato_ci_archive", SCRIPTS / "ci-archive.py")
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class ArchiveValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if "PHOTATO_ARCHIVE_TEST_OUTPUT" in os.environ:
            cls.output = Path(os.environ["PHOTATO_ARCHIVE_TEST_OUTPUT"])
            cls.output.mkdir()
        else:
            cls.output = Path(tempfile.mkdtemp(prefix="photato-archive-tests-"))
        cls.source = cls.output / "source"
        cls.source.mkdir()
        for name in ["LICENSE-MIT", "LICENSE-APACHE", "LICENSE-psd-tools", "NOTICE", "ATTRIBUTION.md",
                     "scripts/Info.plist", "scripts/PrivacyInfo.xcprivacy", "scripts/ProjectLinks.json",
                     "scripts/Photato-AppStore.entitlements", "distribution/app-store/release-policy.json",
                     "Sources/PhotoCraftImaging/Resources/FactoryRGB8Gray20.zlib"]:
            destination = cls.source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(PROJECT / name, destination)
        cls.golden = cls.output / "golden.xcarchive"
        application = cls.golden / "Products/Applications/Photato.app"
        resources = application / "Contents/Resources"
        resources.mkdir(parents=True)
        (application / "Contents/MacOS").mkdir()
        info = plistlib.loads((cls.source / "scripts/Info.plist").read_bytes())
        (application / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        properties = {key: info[key] for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"]}
        properties["ApplicationPath"] = "Applications/Photato.app"
        (cls.golden / "Info.plist").write_bytes(plistlib.dumps({"ArchiveVersion": 2, "Name": "Photato", "ApplicationProperties": properties}))
        for path in cls.source.rglob("*"):
            if path.is_file() and path.name not in {"Info.plist", "release-policy.json", "Photato-AppStore.entitlements"}:
                shutil.copy2(path, resources / path.name)
        (resources / "Photato.icns").write_bytes(b"icns\x00\x00\x00\x08")
        cls.commands = []

        def execute(command):
            cls.commands.append(command)
            with (cls.output / "fixture-build.log").open("a") as log:
                subprocess.run(command, stdout=log, stderr=log, check=True)

        for variant in ["golden", "other"]:
            swift = cls.output / (variant + ".swift")
            swift.write_text('print("' + variant + '")\n')
            slices = []
            for arch in ["arm64", "x86_64"]:
                binary = cls.output / (variant + "-" + arch)
                execute(["xcrun", "swiftc", "-g", "-target", arch + "-apple-macosx14.0", str(swift), "-o", str(binary)])
                slices.append(binary)
            binary = cls.output / variant
            execute(["lipo", "-create", *(str(path) for path in slices), "-output", str(binary)])
            symbols = cls.output / (variant + ".dSYM")
            execute(["xcrun", "dsymutil", str(binary), "-o", str(symbols)])
            if variant == "golden":
                shutil.copy2(binary, application / "Contents/MacOS/Photato")
                destination = cls.golden / "dSYMs/Photato.app.dSYM/Contents/Resources/DWARF"
                destination.mkdir(parents=True)
                shutil.copy2(symbols / "Contents/Resources/DWARF" / variant, destination / "Photato")
        (cls.output / "fixture-commands.json").write_text(json.dumps(cls.commands, indent=2) + "\n")

    def setUp(self):
        self.case = self.output / self.id().split(".")[-1]
        self.case.mkdir()

    def archive(self, ignore=None):
        result = self.case / "Photato.xcarchive"
        shutil.copytree(self.golden, result, ignore=ignore)
        return result

    def copied_source(self):
        destination = self.case / "source"
        shutil.copytree(self.source, destination)
        return destination

    def test_unsigned_archive_matches_real_universal_UUIDs_and_source_resources(self):
        result = verify_archive(self.golden, self.source, mode="ci-unsigned", source=input_manifest(self.source))
        self.assertTrue(result["passed"])
        self.assertEqual(result["binary_UUIDs"], result["symbol_UUIDs"])
        self.assertEqual(result["architectures"], ["arm64", "x86_64"])
        self.assertTrue(all(check["passed"] for check in result["checks"]))
        self.assertFalse(result["release_qualified"])
        self.assertFalse(result["sandbox_runtime_verified"])

    def test_unsigned_archive_is_not_accepted_in_default_signed_mode(self):
        with self.assertRaises(ArchiveError):
            verify_archive(self.golden, self.source)

    def test_actual_mismatched_symbols_reject(self):
        archive = self.archive()
        destination = archive / "dSYMs/Photato.app.dSYM/Contents/Resources/DWARF/Photato"
        shutil.copy2(self.output / "other.dSYM/Contents/Resources/DWARF/other", destination)
        with self.assertRaisesRegex(ArchiveError, "UUID match"):
            verify_archive(archive, self.source, mode="ci-unsigned")

    def test_missing_symbols_reject(self):
        archive = self.archive(ignore=shutil.ignore_patterns("dSYMs"))
        with self.assertRaisesRegex(ArchiveError, "Crash symbols"):
            verify_archive(archive, self.source, mode="ci-unsigned")

    def test_thin_executable_rejects_without_changing_original(self):
        archive = self.archive()
        original = payload_manifest(self.golden)
        binary = archive / "Products/Applications/Photato.app/Contents/MacOS/Photato"
        subprocess.run(["lipo", str(self.output / "golden"), "-thin", "arm64", "-output", str(binary)], check=True)
        with self.assertRaisesRegex(ArchiveError, "Universal ARM"):
            verify_archive(archive, self.source, mode="ci-unsigned")
        self.assertEqual(payload_manifest(self.golden), original)

    def test_stale_build_metadata_rejects(self):
        archive = self.archive()
        path = archive / "Products/Applications/Photato.app/Contents/Info.plist"
        value = plistlib.loads(path.read_bytes()); value["CFBundleVersion"] = "1"
        path.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(ArchiveError, "Source-bound CFBundleVersion"):
            verify_archive(archive, self.source, mode="ci-unsigned")

    def test_stale_archive_index_rejects(self):
        archive = self.archive()
        path = archive / "Info.plist"
        value = plistlib.loads(path.read_bytes()); value["ApplicationProperties"]["CFBundleVersion"] = "1"
        path.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(ArchiveError, "Archive metadata CFBundleVersion"):
            verify_archive(archive, self.source, mode="ci-unsigned")

    def test_changed_license_and_missing_privacy_reject(self):
        archive = self.archive()
        resources = archive / "Products/Applications/Photato.app/Contents/Resources"
        (resources / "NOTICE").write_text("Changed")
        with self.assertRaisesRegex(ArchiveError, "Exact bundled NOTICE"):
            verify_archive(archive, self.source, mode="ci-unsigned")
        missing = self.case / "missing-privacy.xcarchive"
        shutil.copytree(self.golden, missing, ignore=shutil.ignore_patterns("PrivacyInfo.xcprivacy"))
        with self.assertRaisesRegex(ArchiveError, "Exact bundled PrivacyInfo"):
            verify_archive(missing, self.source, mode="ci-unsigned")

    def test_archive_escape_and_external_symlink_reject(self):
        archive = self.archive()
        path = archive / "Info.plist"
        value = plistlib.loads(path.read_bytes()); value["ApplicationProperties"]["ApplicationPath"] = "../../outside.app"
        path.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(ArchiveError, "Canonical application path"):
            verify_archive(archive, self.source, mode="ci-unsigned")
        escape = self.case / "escape.xcarchive"
        shutil.copytree(self.golden, escape)
        (escape / "outside").symlink_to(self.source / "NOTICE")
        with self.assertRaisesRegex(ArchiveError, "escapes"):
            payload_manifest(escape)

    def test_source_mutations_and_malformed_manifests_reject(self):
        root = self.copied_source(); before = input_manifest(root)
        (root / "Sources/New.swift").write_text("// Added input\n")
        with self.assertRaisesRegex(ArchiveError, "Source inputs changed"):
            unchanged(root, before)
        for value in [[], {}, {"../secret": "a" * 64}, {"NOTICE": None}, {"NOTICE": "bad"}]:
            with self.assertRaises(ArchiveError):
                unchanged(root, value)

    def test_automatic_distribution_nonzero_price_and_wrong_flag_types_reject(self):
        root = self.copied_source(); path = root / "distribution/app-store/release-policy.json"
        original = json.loads(path.read_text())
        changes = [{"automaticRelease": True}, {"automaticTestFlightDistribution": True},
                   {"releaseRequiresHumanApproval": False}, {"submitForReview": "false"},
                   {"releaseType": "AFTER_APPROVAL"}, {"price": {"amount": "1.00"}}]
        for change in changes:
            path.write_text(json.dumps(original | change))
            with self.assertRaises(ArchiveError):
                release_policy(root)

    def test_UUID_parser_rejects_missing_duplicate_or_unsupported_architectures(self):
        a = "UUID: 12345678-1234-1234-1234-123456789ABC (arm64) binary\n"
        b = a.replace("arm64", "x86_64")
        self.assertEqual(set(uuids(a + b)), {"arm64", "x86_64"})
        for value in [a, a + a, a + b.replace("x86_64", "arm64e"), "not UUID output"]:
            with self.assertRaises(ArchiveError):
                uuids(value)

    def test_output_guard_preserves_existing_files_and_rejects_source_directories(self):
        original = self.case / "existing"; original.mkdir(); (original / "keep").write_text("keep")
        with self.assertRaises(ArchiveError):
            ci.output_path(self.source, original)
        self.assertEqual((original / "keep").read_text(), "keep")
        with self.assertRaises(ArchiveError):
            ci.output_path(self.source, self.source / "scripts/new-build")
        link = self.case / "symlink"; link.symlink_to(original)
        with self.assertRaises(ArchiveError):
            ci.output_path(self.source, link)

    def test_missing_skipped_duplicate_and_signalled_XCTests_never_pass(self):
        selector = "PhotoCraftCoreTests.ExampleTests/testWorks"
        line = "Test Case '-[PhotoCraftCoreTests.ExampleTests testWorks]' passed (0.001 seconds).\n"
        self.assertTrue(ci.xctest_result(line, [selector])["passed_all"])
        for text in ["", line + line, line + "unexpected signal code 10", line.replace("passed", "skipped")]:
            self.assertFalse(ci.xctest_result(text, [selector])["passed_all"])

    def test_selector_manifest_is_strict_and_reports_are_not_overwritten(self):
        path = self.case / "selectors.json"
        for value in [[], ["wrong"], [None], [{"_obj": "noop"}], ["PhotoCraftCoreTests.A/testA"] * 2]:
            path.write_text(json.dumps(value))
            with self.assertRaises(ArchiveError):
                ci.test_ids(path)
        report = self.case / "report.json"
        command = [sys.executable, str(SCRIPTS / "verify-xcode-archive.py"), str(self.golden), "--source-root",
                   str(self.source), "--mode", "ci-unsigned", "--report", str(report)]
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        before = report.read_bytes()
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
        self.assertEqual(report.read_bytes(), before)

    def test_manual_workflow_template_and_selected_editing_inventory(self):
        template = json.loads((PROJECT / "ci/github-archive-validation.yml").read_text())
        self.assertEqual(template["on"], {"workflow_dispatch": {}})
        self.assertEqual(template["permissions"], {"contents": "read"})
        self.assertEqual(template["jobs"]["archive"]["runs-on"], "xcode-27")
        for step in template["jobs"]["archive"]["steps"]:
            if "uses" in step:
                self.assertRegex(step["uses"], r"^actions/(checkout|upload-artifact)@[0-9a-f]{40}$")
            self.assertNotIn("secrets", step)
        self.assertEqual(len(ci.test_ids(PROJECT / "ci/archive-validation-tests.json")), 104)
