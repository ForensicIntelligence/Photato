import AppKit
import Observation
import PhotoCraftCore

@MainActor @Observable final class FilterRecall {
  private(set) var filter: RasterFilter?
  private(set) var revision = UUID()
  var lensDefaults: LensDefaultLibrary
  var liquifyMeshes: LiquifyMeshLibrary

  init(_ filter: RasterFilter? = nil, liquifyMeshes: LiquifyMeshLibrary? = nil, lensDefaults: LensDefaultLibrary? = nil) {
    self.filter = filter
    self.lensDefaults = lensDefaults ?? LensDefaultLibrary()
    self.liquifyMeshes = liquifyMeshes ?? LiquifyMeshLibrary()
    if let filter, filter.kind == .liquify { self.liquifyMeshes.remember(filter.liquify ?? .init()) }
  }
  func remember(_ value: RasterFilter) {
    if value.kind == .lensCorrection { lensDefaults.remember(value.lens ?? .init()) }
    if value.kind == .liquify { liquifyMeshes.remember(value.liquify ?? .init()) }
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
    let channel = currentMaskFilterTarget == nil ? editingChannel:nil
    let inks = currentMaskFilterTarget == nil && document.inkMode != nil && channel == nil ? effectiveInkTargets : []
    let id: UUID
    if currentMaskFilterTarget != nil,let active=document.activeLayerID {id=active}
    else if channel != nil || document.inkMode != nil { id = document.id }
    else if let active = document.activeLayerID { id = active }
    else { throw CraftError.invalid("Select a filter target first.") }
    return .init(draft: .init(id: id, filter: filter, channelTarget: channel, maskTarget:currentMaskFilterTarget,
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
      "lastLiquifyMesh": ["anyOf": [["type": "null"], LiquifySettings.apiSchema]],
      "lastLiquifyMeshError": ["type": ["string", "null"]],
    ], required: ["filter", "name", "canRepeat", "lastLiquifyMesh", "lastLiquifyMeshError"])
  }
  static var capabilities: [String: Any] {
    ["command": name, "stateSchema": stateSchema,
      "behavior": "Repeat the last successfully applied native raster-filter settings on the current editing target and selection. Native Filter menu uses the captured Control-Command-F shortcut; Option invocation reopens copied settings for preview/Cancel/commit. Existing mode/depth/lock/target/filter limits apply.",
      "scope": "Recall is shared by documents attached to one application controller and lasts for that application session. Standalone stores have isolated recall. Closing the source document does not discard it. Undo/Redo, previews, Cancel, failed/stale/revoked requests and non-filter edits do not replace it. Filter-state changes invalidate revisions of attached documents.",
      "history": "One cancellable native edit. Recording captures the resolved self-contained filter payload and portable target using existing Actions support, without depending on later recall. Native archive89 and Actions58 maxima are unchanged. Mask-filter recording is explicitly unsupported; it never records a color-layer filter instead. Recall is not saved into documents or preferences.",
      "coverage": "Native/direct/API raster, layer-mask, Smart Filter-mask, auxiliary, component and ink filter commands and added/changed enabled Smart Filter payloads update recall after successful publication. Smart Filter toggles/reorder/blend-only edits do not. Multi-step Actions/Batch recall, isolated Adobe jobs, RAW-source development, third-party plugins, exact Photoshop recent-list/Smart Object dialog/random-color policy and full output/platform fidelity remain unqualified or open.",
      "lastLiquifyMesh": ["state": "filterRecall.lastLiquifyMesh", "applyCommand": "filter.apply",
        "filterKind": "liquify", "meshFormat": "PhotatoLiquify version1",
        "behavior": "Load Last Mesh copies the last successfully published Liquify program into the native draft, with local Undo/Redo and Cancel. API clients copy the state program to filter.apply parameters.filter.liquify; ordinary shared validation, prepared edits, document Undo/Redo and portable Actions apply.",
        "lifetime": "Independent of later filters and document Undo/Redo. The default application retains it across launches; isolated stores remain memory-only. Closing a source document retains the controller copy. Atomic saves run in order and are drained on normal Quit; unreadable files are preserved. lastLiquifyMeshError reports persistence failure without reverting a committed image edit.",
        "coordinates": "The exact existing Liquify program is retained. Explicit width/height preserve the original mesh coordinate space; zero retains the existing API current-target semantics. Freeze and face parameters are retained. Source image pixels are not cached.",
        "limits": "Existing4MiBprogram/8,388,608pixel/computation limits remain. Photoshop .msh/last-mesh persistence, freeze/face/size/default/numerical and full platform equivalence remain unqualified."],
      "adobe": "No new Adobe route or unqualified repeat descriptor. Existing supported filter actionJSON jobs retain their isolated semantics."]
  }
  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    ["filter": store.filterRecall.filter?.apiState as Any? ?? NSNull(),
      "name": store.filterRecall.filter?.kind.title as Any? ?? NSNull(),
      "canRepeat": store.canRepeatFilter,
      "lastLiquifyMesh": store.filterRecall.liquifyMeshes.settings.flatMap {
        try? JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
      } ?? NSNull(),
      "lastLiquifyMeshError": store.filterRecall.liquifyMeshes.error as Any? ?? NSNull()]
  }
}
