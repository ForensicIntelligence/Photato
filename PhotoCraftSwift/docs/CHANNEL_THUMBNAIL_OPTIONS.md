# Channel thumbnail options

Double-clicking an alpha, spot or temporary Quick Mask thumbnail now selects that channel and opens its existing Options dialog. The thumbnail uses a native button with a captured editor, document, session and channel identity. Its context-menu Options action uses the same guard. The name button keeps its current selection behavior. With thumbnails hidden, the existing context-menu route remains available.

Opening and cancelling do not change pixels or add Undo history. Committing uses the existing channel options command. Plain single clicks and clicks with Control, Command, Option or Shift retain their existing selection, load and overlay behavior. Busy, modal, stale, deleted, replaced-session/document and foreign contexts cannot redirect an old thumbnail to another channel.

The existing Photato channel.view/channel.edit interfaces still implement the underlying selection and configure/quickMaskOptions operations. Capability metadata describes native thumbnail access. There is no new command, parameter, serialization version or invented Adobe endpoint. No image mathematics changed.

All56focused Debug tests pass, including3new methods with9RGB8/16/32alpha/spot/QuickMask native/API document/archive/pixel/Undo/Redo cases and64modifier/click cases. A hosted native button receives the double mouseDown event. Fifty existing reference/channel/warp/typography tests pass per architecture on the preserved420normal binaries; independent statistics checks match70Float32words each. These retained-binary tests do not qualify current421normal.

Adobe documents thumbnail Options for alpha channels and the existing Quick Mask mode-button Options action. Current temporary-channel-row behavior, physical interaction, complete S05semantics and supported platforms remain unqualified. The Mac is still locked. The earlier selected-gray/initially-empty/explicit-full conflict and all broader output/shortcut/default requirements remain open.

The remaining quick-win audits found represented reference, archive configuration, inventory, warp and typography controls already present. Their full scope is retained. The major quick-win sweep is finished; major stillneeded work starts with L01, then D01. This is a scheduling transition, not a package-completion or parity percentage.
