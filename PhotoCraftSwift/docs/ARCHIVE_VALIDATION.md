Checkpoint482 changes tool discovery to `test_*.py` and retains separate archive/inventory fixtures. All37developer-tool tests pass locally,21new. The actual archive and104editing checks perarchitecture documented below are from481on unchanged native product inputs; no fresh full482pipeline or hosted execution is claimed. [Inventory guide](INVENTORY_RECONCILIATION.md).

# Archive validation

The full local pipeline passes at checkpoint 481: 16 new archive-tool tests, all 104 selected editing checks on Apple Silicon and translated Intel, and 34 checks on a fresh universal Xcode archive. Executable and dSYM UUIDs match for both architectures. The extracted ZIP matches every verified archive file, and all 7 controlled lookup cases retain 1,474,560 original Photoshop RGB bytes on each architecture.

The application remains build 480; this work changes release tooling and one test's output routing. The archive is unsigned and non-distributable. The hosted workflow has not been installed or dispatched, and the wider REL01 scope remains open. [Evidence](ARCHIVE_VALIDATION_481.json).

The old `verify-app-package.py` is retained as historical tooling. It uses fixed paths and old test counts. New archive checks use explicit paths, a source manifest and a new report file, with no dependency on those old logs.

## Commands

Run the complete local pipeline from the native project:

```sh
python3 scripts/ci-archive.py --output /private/tmp/photato-validation-unique-name
```

The output directory must be new. The pipeline runs the archive-tool tests, the selected editing tests on Apple Silicon and translated Intel, and an unsigned universal Xcode archive using the existing AppStore configuration. It verifies the archive, preserves its dSYMs, creates a ZIP and compares every extracted file with the verified original. A manifest identifies the source inputs; any input change stops qualification. Logs and failed outputs remain available.

`--archive-only` explicitly omits editing tests and records that omission. It still runs the archive-tool tests. It is intended for inspecting packaging, not replacing editing qualification.

To inspect an existing archive:

```sh
python3 scripts/verify-xcode-archive.py /path/Photato.xcarchive \
  --source-manifest /path/source-inputs.json --report /path/new-report.json
```

The default mode requires a strict FI team signature, the requested sandbox entitlements and hardened runtime. `--mode ci-unsigned` is an explicit non-distributable mode. Neither mode proves Apple server validation, distribution provisioning, privacy declarations, actual sandbox behavior or approval to release.

Checks include production identity and source version/build, both architectures targeting macOS 14, matching executable/dSYM UUIDs for each architecture, Apple runtime dependencies, required license/privacy/link/gray-table resources, optional-model bytes/provenance and the local free/manual-release policy. Source-policy checks do not reverify App Store Connect settings.

## CI workflow

`ci/github-archive-validation.yml` is a JSON-compatible YAML template. In the public fork, copy it to the repository root as `.github/workflows/photato-archive-validation.yml`. The native project is under `PhotoCraftSwift` there; the template also recognizes a standalone native-project checkout.

The workflow uses manual dispatch, read-only repository contents permission, pinned official checkout/artifact actions and the documented `xcode-27` runner with Xcode 27.2. It does not retain checkout credentials or use signing secrets. Its only upload is CI evidence and an unsigned archive artifact, retained for seven days. It has no App Store upload, review, TestFlight distribution or release step.

The template has not been installed in the public repository or dispatched by this checkpoint. Local execution and hosted execution are separate qualification gates. The archive does not establish bit-reproducible compiler output across SDK versions or machines.

## Preservation and capacity

Existing output directories and reports are refused. The pipeline does not install the application or replace the current builds. It requires 12 GiB free before starting, stops before another step below 4 GiB, and reserves space for both ZIP copies. It does not delete old builds to make room. Menu-test reports use the existing capture-directory environment variable, preserving the original assertions and local convenience report.

Apple explains the required binary/dSYM UUID pairing in [Building your app to include debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information). Runner availability and toolchain versions are recorded by [GitHub's runner images](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md); the workflow follows GitHub's [workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).
