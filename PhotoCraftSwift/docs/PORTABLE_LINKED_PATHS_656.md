# Portable linked Smart Object paths

## 20 November 2026

The prior PSD and PSB reader kept the absolute path when both absolute and relative positions were present. Photato’s folder picker only recognized the two-component `Links/<filename>` paths from its own packages. Imported files could lose their relative locator on a round trip, and the native folder picker could skip a complete folder after a move.

Adobe documents a lookup order of relative path, absolute path, saved macOS alias, and a file beside the document. The installed Photoshop session timed out during a read-only version and document-count request. The reference for this change is Adobe’s public workflow and the existing document format support, exercised with owned controls. [Adobe package and relink workflow](https://helpx.adobe.com/uk/photoshop/desktop/create-manage-layers/smart-objects/package-linked-smart-objects.html)

## Changes

- `LinkedSmartObjectSource` preserves the optional second path through native archives, and `PSDLinkedSmartObjects` reads and writes the two file locators independently. The old single path representation stays readable. An absent absolute path can fall back to the relative path. A remote descriptor retains its existing credential-stripping behavior.
- **Locate Package Sources…** can grant the folder containing an imported or saved document. The lookup can find a declared relative asset in nested directories, with the matching filename beside the document as a fallback. It uses registered file identities and existing local file approvals. A valid relative source takes precedence over the approved old pathname and its bookmark.
- The folder grant is confined to files in the chosen document folder. A missing or disallowed entry leaves that one source unresolved. Available siblings and other links can still be authorized. Links that point outside the chosen folder can use **Relink to File…**.
- Normal update, refresh, original-source write, embed and Package operations share the lookup. They carry both original locators through an update. A raw asset or source operation through the Photato API still requires current session approval of the resolved file. The capabilities response describes lookup order and availability without returning paths.

The existing native folder picker and its document context were retained. Its prompt now describes the folder and subfolders that will be checked. [Apple file management guidance](https://developer.apple.com/design/human-interface-guidelines/file-management)

## Qualification

All five new Debug checks passed. They cover PSD, PSB and native path round trips, the absence of an absolute path, moved artwork and competing versions, portable approval and API update, Package output, document undo, basename and bookmark fallback, missing siblings and out-of-folder paths.

A separate Debug fixture produced a 33,076-byte PSD and a 33,120-byte PSB. The independent parser read both file locators and a 984-byte external source size in each record. The initial standalone run lacked macOS image type discovery in the restricted shell and stopped during fixture setup. The approved retry generated both files. The evidence is in the local `artifacts/656-portable-links/` directory.

The live Adobe comparison and reproduction of Adobe alias data remain open.

All 1,457 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen.

The owned native, PSD and PSB outputs matched byte for byte across the two compiled architectures. An independent read verified both Photoshop file locators. Both optimized apps also passed the 1.18 GB linked workflow.

The new behavior retains the original application’s source approval workflow. Imported links without a trusted fingerprint can use **Update Modified Content** to load the approved original into an editable layer. Locators outside the chosen folder can still use the individual Relink command. Physical Intel, macOS 14 runtime and interactive Adobe comparison remain open. [Qualification and hashes](SOURCE_PUBLICATION_656.md)
