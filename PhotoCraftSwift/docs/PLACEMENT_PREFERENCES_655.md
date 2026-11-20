# Placement preferences

## 20 November 2026

Photato’s existing Place Embedded and Place Linked called the same preparation code with automatic fitting and always entered Free Transform for an ordinary new layer. The General command already had Photoshop’s Command–K shortcut in the menu catalogue but had no window or settings behind it.

Adobe’s published placement guide describes centered placement, proportional downscaling when artwork is larger than the document, the transform preview, and embedded and linked originals. Adobe also documents placing regular layers through the General preference. Its published General panel names all three switches. [Place a file](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/import-files/place-a-file-in-photoshop.html) · [Linked Smart Objects](https://helpx.adobe.com/uk/photoshop/desktop/create-manage-layers/smart-objects/create-linked-smart-objects.html) · [Adobe’s General panel](https://www.adobe.com/content/dam/cc/hk_en/newsroom/pdf/2021/Adobe_Introduces_Document_Collaboration_Feature_for_Photoshop_Illustrator_and_Fresco_02232021.pdf#page=3)

The installed Photoshop replied with 27.2.0 to a read-only version query. A separate disposable linked placement script timed out before writing a first phase record or test document. The paired Photoshop placement, PPI and sampling measurements are open. The test inputs and attempted script are local, under `artifacts/655-placement-preferences/`.

## Behavior

Open **Photato > Settings… > General…** or press **Command–K**.

- **Resize Image During Place** defaults on. Photato’s existing proportional fit scales oversized artwork down. Turning it off centers artwork at source pixel size.
- **Skip Transform when Placing** defaults off. Turning it on commits the new layer after source preparation and any PDF or Camera Raw choices, with one Undo entry.
- **Always Create Smart Objects when Placing** defaults on. Turning it off bakes the final transform of new embedded artwork into a pixel layer. The preview stays editable until commit. Place Linked, frame artwork and Replace Contents retain their source semantics.

The three values are captured when the selected file starts preparing. A later preference change applies on the next placement. A linked draft checks the original’s current file signature and its approval before committing.

The Photato API has a revisioned `GET` and `POST /v1/preferences/placement`, with a session-local opt-in for persistent writes. New embedded and PDF placement requests can set `rasterize`, with `fit` and `transform` in the same atomic edit. API requests retain their explicit defaults regardless of desktop settings. The Firefly v2 public contract describes separate resource jobs and provides no desktop configuration operation. [Photoshop API v2](https://developer.adobe.com/firefly-services/docs/photoshop/getting-started/v2-ga/) · [Automation API](AUTOMATION_API.md)

The new controls use the existing AppKit window and a SwiftUI grouped form with native checkboxes. The menu position and shortcut come from Photato’s factory catalogue. [Apple Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings)

## Qualification

All 33 Debug tests in the focused suite passed. The six new cases cover persistent defaults and the native General command, fit and immediate commit, in-flight preference changes, real HTTP pixel placement, PDF chooser and cancellation, linked-source retention and revocation, and permissioned preference writes. The existing workflow cases include RAW, frame and replacement placement and the 67,310,374-byte linked PSB control.

The first restricted build reached a default Clang cache outside the build folder. Isolated caches resolved that access. The default Swift Build engine and normal Debug compilation then hit the retained frontend stack fault in predictable dead allocation elimination. A larger compiler stack alone still crashed. The successful Debug build uses the same pass disable as checkpoint 654. The optimized SwiftPM builds succeeded with testability enabled. Both slices of the ad hoc–signed universal preview launched offscreen. Each attempt has a distinct log.

All 1,452 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

Both optimized builds separately passed the 1.18 GB linked PSB workflow. Automatic refresh and package reuse retained the same original and updated SHA-256 values across architectures.

The selected tests include the six new cases. Source-bound receipts record the exact selectors and executable hashes. The optimized builds use the standard optimization pipeline. The signed preview ran in an isolated temporary bundle. Physical Intel, macOS 14 runtime and full interactive accessibility remain open. [Qualification and hashes](SOURCE_PUBLICATION_655.md).
