# Large image stacks

File > Scripts > Statistics and Load Files into Stack use the existing eleven Stack Mode operators with sparse/file-backed preparation. Statistics evaluates source pixels at their original working resolution. The dialog reduces only the finished image for display.

The old combined 16-megapixel and 16-frame preparation checks no longer limit unaligned stacks. Native source/sample admission follows the existing document-layer target (currently 8,000, a development target rather than a qualified physical ceiling). The logical canvas allows 300,000 pixels per side. Layer visibility, root groups, masks, maximum alpha and transparent-sample exclusion retain their previous behavior. Each source remains available in the embedded Smart Object; mode changes, None, editing, native persistence and Undo retain the existing contracts.

Automatic alignment still has its own 16-source and pixel budgets. Smart Objects retain encoded 64 MiB, owned 256 MiB and nesting limits; non-RGB source admission, color conversion, composition and scratch limits remain separate. File-backed tiles keep retained source frames from exhausting the owned-content allowance. Large or complex real-world workloads can still exceed resource limits.

The Photato API uses `document.imageStack`, `document.imageStack.cancel` and `smartObject.stackMode`. HTTP creation retains two to seven explicitly shared sources, with an eighth slot for the output. The supported Adobe execute-actions stack renderer descriptors use the same engine. No dedicated Adobe stack-creation endpoint, arbitrary plug-in host or new UXP runtime is claimed.

The selected tests cover all eleven operators at three depths, visibility/masks/groups, 65 frames, a 17-source editable stack, sparse maximum dimensions, an allocated 8.39 MP input and an owned raster above 256 MiB. All 99 programs captured before production changes retain their 152,064 sample bytes exactly. These are regression samples made from owned data, not independently captured Photoshop statistics output. Full RAW02, exact Photoshop output/defaults, physical capacity, live controls and 60 fps remain open.

See [checkpoint evidence](PAGED_IMAGE_STATISTICS_472.json) and [development record](DEVLOG.md#dev-step-472).
