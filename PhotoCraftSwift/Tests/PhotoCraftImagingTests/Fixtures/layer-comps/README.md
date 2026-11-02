# Optional external Layer Comp reference

The test code uses ag-psd's layer-comps fixture at commit a74425db6584cc07b1cc135e370916cb4eccfb32. Its LICENSE excludes image assets from the MIT grant. The PSD is therefore not redistributed in this source snapshot; the original license and reference provenance remain. Local qualification used the original pinned fixture, which remains in the maintainer's local checkout.

If you have the necessary rights, run `python3 scripts/fetch-layer-comp-reference.py --download` from PhotoCraftSwift. Use `--check` to verify a local copy without networking. Running the script without options prints instructions and performs no download. The source URL, exact size and SHA-256 are pinned in the helper and in docs/SOURCE_SNAPSHOT_363.json. The PSD remains Git-ignored. It is test data and is not needed to build or run Photato.

The source delivery does not claim a clean-clone full test pass. Tests depending on this optional reference need it locally; the recorded362run passed24new and302of304affected cases, retaining two known Layer Comp failures.
