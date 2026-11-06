# Fill a path with options

Choose Fill Path from the Paths context menu, or Option-click the Fill footer. Choose foreground, background, custom colour, black, 50% gray, white or a saved pattern. Set blend mode, opacity, Preserve Transparency, feather and anti-aliasing. Clear changes alpha and is unavailable on Background. History is explicitly unavailable until a history source exists. Cancel leaves the document unchanged; OK uses one prepared Undo. Successful options remain in the session. Ordinary footer fill retains its existing brush-opacity behaviour pending resolution of conflicting Adobe default instructions.

Path coverage multiplies the current selection; selection metadata and the selected path are retained. The existing Core paint engine handles blending, patterns, expanded layer/mask geometry and protection. Clear preserves hidden/linear RGB words. Document/session/path/target/settings changes and cancellation reject obsolete results.

## Optional API

Existing `path.paint` accepts an optional `fill` object. Example: `{"fill":{"contents":"foreground","opacity":0.75,"feather":2,"antiAlias":true}}`. Consult the exposed request schema for colour, pattern placement, mode and preservation fields. Explicit fill cannot mix brush, stroke or pressure. `paths.fill` exposes current options/availability, the request schema and limits. Native/API use the same command builder and transaction path; successful API calls also update session options. Malformed parameters return400, missing patterns404, unavailable History422 and busy state409. Old requests without fill retain their contract.

Actions50 records portable captured path coverage/settings/pattern resources and resolves the replay target/current selection. Older feature minimums41/42/49 remain; native archive86 and settings4 are unchanged. No dedicated Adobe endpoint or proprietary descriptor is asserted.

Checkpoint436 passes60focused Debug cases and354identical ordered optimized cases on each architecture, including all89new426–436methods. Ten new methods cover literal coverage/selection products, all-depth rawRGB Clear preservation/protection, expanded geometry/masks, portable replay, native/API document and PNG equality, session options, Undo/archive, native controls/Cancel, strict API and stale/cancel guards.18old current Actions ceilings were updated49to50; old minimum/header/pixel/fixture/tolerance assertions remain. Failed attempts are retained. Universal macOS14 minimum/signature/extractedZIP checks pass. Intel ran under Rosetta; physical Intel/mac14/live UI and Photoshop exact output/defaults remain unqualified.

Full G04 remains open. Extended Fill currently has RGB raster/mask,16MPcanvas and100pxfeather limits; History, remaining Pen/Stroke/target workflows and larger capacity stay major stillneeded. [Evidence](PATH_FILL_436.json).
