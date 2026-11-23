# Source checkpoint 722

Relinking a projected Smart Object to the same source preserves its rendered appearance in the tested PSD and PSB files. The original placement, editable Smart Filters and their mask stay with the layer.

The test moves a linked PSB, opens the document from its saved preview and relinks the same source bytes. Photato matches every rendered byte in the initial cache, resolved link and edited reopen at RGB8, RGB16 and RGB32. A filter-mask stroke and a filter reorder retain separate Undo steps. The authenticated Photato API matches the native rebind and Undo. An independent reader recovered the external filenames, projected corners and filter order in twelve files per configuration. It decompressed the painted filter mask and found the marked center at zero coverage in each edited file.

717 of 718 selected tests passed on each optimized architecture, with Intel tested under Rosetta. Debug passed 716 of 718. The new regression passed in all three configurations. The existing PSD layer-effect test repeated the same 118 assertions as build 721. The Adobe-compatible Smart Filter export exhausted the Debug worker stack in both builds 721 and 722. That case passed on both optimized slices. Xcode built the checked-in project. Both signed preview slices target macOS 14.0 and opened offscreen.

The verified case uses an unchanged local linked file and two native filters. The outputs compare Photato before and after reopening and relinking. Direct Photoshop comparisons, other deformation geometries and the full Smart Filter and linked-source acceptance workflows remain open.

Photoshop 27.2.0 returned its version and exposed zero accessible windows and menu bars.

Build inputs **9,421**. Source digest `bd6d3310cd8bb076ae3fb500054d375ce6d2ea9457dee7658a06d49c7523a69f`. Local universal preview SHA-256 `165ebc0117826c7da2bbef56119738ece2ad1bf38333dc101fe43928682c3ab0`.

[Linked artwork guide](LINKED_FILTER_EDGE_EXCHANGE.md) · [Development record](DEVLOG.md#dev-step-722) · [Evidence hashes](SOURCE_PUBLICATION_722.json)
