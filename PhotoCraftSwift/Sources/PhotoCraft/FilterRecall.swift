import AppKit
import Observation
import PhotoCraftCore

@MainActor @Observable final class FilterRecall {
  private(set) var filter: RasterFilter?
  private(set) var revision = UUID()

  init(_ filter: RasterFilter? = nil) { self.filter = filter }
  func remember(_ value: RasterFilter) {
    guard value != filter else { return }
    filter = value
    revision = UUID()
  }
}

struct FilterRepeatTarget: Equatable, Sendable {
  let documentID: UUID
  let layerID: UUID?
  let channel: ChannelPlaneTarget?
  let components: Set<Int>
  let inks: [InkChannelTarget]
  let mask: UUID?
  let smartFilterMask: Bool
}

struct FilterRepeatRequest: Sendable {
  let draft: FilterDraft
  let target: FilterRepeatTarget
  func command(in document: CraftDocument) throws -> Command { try draft.command(in: document) }
}

@MainActor extension EditorStore {
  var filterRepeatTarget: FilterRepeatTarget {
    .init(documentID: document.id, layerID: document.activeLayerID, channel: editingChannel,
      components: effectiveComponentTargets, inks: effectiveInkTargets,
      mask: maskEditingLayerID, smartFilterMask: smartFilterMaskEditing)
  }
  var canRepeatFilter: Bool {
    guard let filter = filterRecall.filter else { return false }
    return canBeginFilterKind(filter.kind)
  }
  func filterRepeatRequest() throws -> FilterRepeatRequest {
    guard canRepeatFilter, let filter = filterRecall.filter else {
      throw CraftError.invalid("No previous filter is available for the current editing target.")
    }
    let channel = editingChannel
    let inks = document.inkMode != nil && channel == nil ? effectiveInkTargets : []
    let id: UUID
    if channel != nil || document.inkMode != nil { id = document.id }
    else if let active = document.activeLayerID { id = active }
    else { throw CraftError.invalid("Select a filter target first.") }
    return .init(draft: .init(id: id, filter: filter, channelTarget: channel,
      modeComponents: effectiveComponentTargets, inkTargets: inks), target: filterRepeatTarget)
  }
  func repeatLastFilter(showDialog: Bool = false) {
    finishNumericField()
    finishLayerName()
    guard canRepeatFilter else { return }
    do {
      let request = try filterRepeatRequest()
      if showDialog {
        filterDraft = request.draft
        render()
        return
      }
      let prepare = repeatFilterPreparation
      performPreparedGeometry(label: request.draft.filter.kind.title,
        allowAuxiliary: request.draft.channelTarget != nil,
        allowModeComponents: !request.draft.modeComponents.isEmpty,
        prepare: { try PreparedEdit(command: prepare($0, request), document: $0) },
        validateCommit: { [weak self] in
          guard self?.filterRepeatTarget == request.target else {
            throw CraftError.invalid("The filter editing target changed. Try again.")
          }
        })
    } catch { self.error = error.localizedDescription }
  }
}

@MainActor extension AppDelegate {
  @objc func repeatLastFilter(_ sender: NSMenuItem) {
    store?.repeatLastFilter(showDialog: NSEvent.modifierFlags.contains(.option))
  }
}

enum FilterRecallAPI {
  static let name = "filter.repeat"
  static var stateSchema: [String: Any] {
    BrushAPI.object([
      "filter": ["anyOf": [["type": "null"], RasterFilter.apiSchema]],
      "name": ["type": ["string", "null"]],
      "canRepeat": BrushAPI.flag,
    ], required: ["filter", "name", "canRepeat"])
  }
  static var capabilities: [String: Any] {
    ["command": name, "stateSchema": stateSchema,
      "behavior": "Repeat the last successfully applied native raster-filter settings on the current editing target and selection. Native Filter menu uses the captured Control-Command-F shortcut; Option invocation reopens copied settings for preview/Cancel/commit. Existing mode/depth/lock/target/filter limits apply.",
      "scope": "Recall is shared by documents attached to one application controller and lasts for that application session. Standalone stores have isolated recall. Closing the source document does not discard it. Undo/Redo, previews, Cancel, failed/stale/revoked requests and non-filter edits do not replace it. Filter-state changes invalidate revisions of attached documents.",
      "history": "One cancellable native edit. Recording captures the resolved self-contained filter payload and portable target using existing Actions support, without depending on later recall. Native archive86 and Actions47 maxima are unchanged. Recall is not saved into documents or preferences.",
      "coverage": "Native/direct/API raster, auxiliary, component and ink filter commands and added/changed enabled Smart Filter payloads update recall after successful publication. Smart Filter toggles/reorder/blend-only edits do not. Multi-step Actions/Batch recall, isolated Adobe jobs, RAW-source development, third-party plugins, exact Photoshop recent-list/Smart Object dialog/random-color policy and full output/platform fidelity remain unqualified or open.",
      "adobe": "No new Adobe route or unqualified repeat descriptor. Existing supported filter actionJSON jobs retain their isolated semantics."]
  }
  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    ["filter": store.filterRecall.filter?.apiState as Any? ?? NSNull(),
      "name": store.filterRecall.filter?.kind.title as Any? ?? NSNull(),
      "canRepeat": store.canRepeatFilter]
  }
}
