# Inventory reconciliation

Checkpoint482 corrects the menu CSV from802 to809 entries. Seven paths were missing and88selector bindings were stale. The prior CSV and proposed replacement are retained. Factory keys and native application code are unchanged. [Recorded evidence](INVENTORY_RECONCILIATION_482.json).

The current inventory has461bound leaf entries,270unavailable leaf entries and78submenus. A binding means that a selector is installed, not that the entire command or its Photoshop behavior is qualified. The separate command ledger has652identities:459partial and193pending. The40professional acceptance scenarios remain planned. These inventories have different granularity; their counts must not be converted to a completion percentage.

The801-entry independent Photoshop27.2 golden fixture is unchanged. Eight later/documented or Photato-specific menu additions are listed separately in [INVENTORY_POLICY.json](INVENTORY_POLICY.json). Both source-matched481captures have809entries,102primary shortcuts,8alternate shortcuts and55main tools across880modifier contexts. This reuses verified native captures; no new native execution or physical-key delivery is claimed at482.

## Reproduce the check

Use Python3.11+ from the native project directory:

```sh
python3 scripts/reconcile-inventories.py \
  --snapshot /path/to/capture-inputs.json \
  --phases docs/FUNCTION_PHASES_482.json \
  --policy docs/INVENTORY_POLICY.json \
  --report /new/output/inventory.json
```

The snapshot has schema1, a `source_manifest` and two `menus` and `tools` records keyed by `arm64` and `x86_64`. Each record supplies a project-relative `path` and SHA-256. Generate current native captures with the selected menu/cursor tests and `PHOTATO_TEST_CAPTURE_DIR`, or the archive pipeline, and record the source inputs from that same run. Local482evidence retains the exact481input references. The script refuses stale native code, tests, fixtures, assets, project or package files; capture hashes and architecture reports must agree.

Exit0 means the supplied inventories reconcile. Exit1 means the menu CSV differs. Exit2 means invalid or stale inputs, an unsafe output location or overwrite refusal. `--write-menu-csv /new/path/proposal.csv` writes a proposal without replacing the tracked CSV; inspect and preserve the old inventory before applying it. Outputs inside product/tooling directories are rejected. `--rust-root /path/to/upstream` optionally hashes and summarizes the eight upstream TOML scorecards. Upstream statuses do not establish Photoshop acceptance.

```sh
python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
```

All37developer-tool methods pass locally:16archive checks and21new reconciliation checks. Set `PHOTATO_ARCHIVE_TEST_OUTPUT` and `PHOTATO_INVENTORY_TEST_OUTPUT` to separate new fixture directories to retain test products. The CI template now discovers both test files and retains both fixture folders. Hosted CI and a fresh full pipeline run at482remain unqualified; the actual104-per-architecture editing run and archive belong to481.

## External target boundaries

The installed executable is Photoshop27.2. Adobe's [current feature notes](https://helpx.adobe.com/photoshop/desktop/whats-new/whats-new-in-adobe-photoshop-on-desktop.html) describe27.11. The release-notes page also retains a conflicting27.0banner. Installed behavior, later documentation and beta features remain separately identified rather than being treated as one verified reference version.

[INVENTORY_POLICY.json](INVENTORY_POLICY.json) records the AI Assisted Editor beta, later Enhance Edge/model features, Windows-specific optimization, retired Substance Viewer integration, generative-service dependencies, plug-in runtimes and optional Apple AI. These classifications do not delete requirements or qualify Photato implementations. The full original AUD01scope and all104package acceptance criteria remain open. Current work continues with AUT02, thenS05.
