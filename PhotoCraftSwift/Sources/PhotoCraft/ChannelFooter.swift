import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum ChannelFooterRequest: Sendable {
  case save
  case load(SelectionChannelSource)
}
enum ChannelFooterPreparation {
  static func prepare(_ request: ChannelFooterRequest, document: CraftDocument,
    colorSettings: ColorSettings) throws -> Command {
    try Task.checkCancellation()
    switch request {
    case .save: return .channel(.saveSelection(nil,nil,.replace))
    case .load(let source):
      return try .channel(.loadCoverage(source.selection(in:document,colorSettings:colorSettings),.replace))
    }
  }
}
extension EditorStore {
  var channelFooterLoadSource: SelectionChannelSource? {
    if let target = selectedMaskPaintTarget {
      return target.smartFilter ? .smartFilterMask(target.layerID):.layerMask(target.layerID)
    }
    if let id = alphaEditingID {
      return document.alphaChannels?.contains(where:{$0.id==id}) == true ? .alpha(id):nil
    }
    if editingChannel == .quickMask { return .quickMask }
    if document.inkMode != nil {
      guard effectiveInkTargets.count == 1, let target = effectiveInkTargets.first else { return nil }
      switch target {case .duotone:return .duotone;case .plate(let id):return .plate(id)}
    }
    let targets = effectiveComponentTargets
    if targets.count == 1, let index = targets.first { return .component(index) }
    if targets.isEmpty || targets.count == document.colorMode.componentCount {
      return document.colorMode.componentCount > 0 ? .composite:nil
    }
    return nil
  }
  var canQuickSaveChannel: Bool {
    canSaveSelectionChannel && (document.alphaChannels?.count ?? 0)<CraftDocument.maximumAlphaChannels
  }
  var canLoadChannelFooter: Bool { canEditChannels && channelFooterLoadSource != nil }
  func saveChannelFooter(modifiers: NSEvent.ModifierFlags = []) {
    guard canSaveSelectionChannel else { return }
    if modifiers.contains(.option) { beginChannelDialog(.save); return }
    guard canQuickSaveChannel else {
      error = "The saved-channel limit has been reached. Option-click Save Selection to choose an existing channel or a new document."
      return
    }
    runChannelFooter(.save)
  }
  func loadChannelFooter() {
    guard canLoadChannelFooter, let source = channelFooterLoadSource else { return }
    runChannelFooter(.load(source))
  }
  private func runChannelFooter(_ request: ChannelFooterRequest) {
    let settings = workingColorSettings, prepare = channelFooterPreparation
    performPreparedGeometry(label:request.label,allowAuxiliary:true,prepare:{ document in
      try PreparedEdit(command:prepare(request,document,settings),document:document)
    },validateCommit:{
      guard self.workingColorSettings==settings else {throw CraftError.invalid("Color Settings changed during channel loading.")}
    })
  }
  var channelFooterState: [String:Any] {
    ["canQuickSave":canQuickSaveChannel,"canSaveOptions":canSaveSelectionChannel,
      "canLoad":canLoadChannelFooter,
      "loadSource":channelFooterLoadSource.map(SelectionChannelSourceAPI.state) as Any? ?? NSNull()]
  }
}
private extension ChannelFooterRequest {
  var label: String {switch self {case .save:"Save Selection";case .load:"Load Selection"}}
}
enum ChannelFooterAPI {
  static var stateSchema: [String:Any] {
    BrushAPI.object(["canQuickSave":BrushAPI.flag,"canSaveOptions":BrushAPI.flag,
      "canLoad":BrushAPI.flag,"loadSource":["anyOf":[SelectionChannelSourceAPI.schema,["type":"null"]]]],
      required:["canQuickSave","canSaveOptions","canLoad","loadSource"])
  }
  static var capabilities: [String:Any] {
    ["state":"selectionChannels.footer",
      "save":"Click saves the current selection to a new automatically named alpha channel. Option-click opens existing Save Selection options. Other modifier flags do not add a new save action; combined Photoshop gestures remain unqualified.",
      "load":"Click directly replaces selection from the current saved/QuickMask/component/composite/layer-mask/SmartFilter-mask or single ink target. Ambiguous partial multi-component/multi-ink sets are unavailable; no arbitrary first target is loaded. Edit target, visibility, image pixels and source masks are retained.",
      "API":["command":"channel.edit","save":["action":"saveSelection"],"load":["action":"loadSelection","source":"Use footer.loadSource descriptor"]],
      "history":"Shared native channel commands and prepared source/session/revision guards; one Undo or no-op. Menus retain their existing dialogs. New-alpha UUIDs are intentionally independent across requests.",
      "limits":"Existing channel capacity and source/profile/paged sampling limits retained. Exact Photoshop contextual defaults, modified Load gestures, multi-target combinations, physical UI and full C01 remain open. No dedicated Adobe endpoint or unqualified descriptor invented."]
  }
}
