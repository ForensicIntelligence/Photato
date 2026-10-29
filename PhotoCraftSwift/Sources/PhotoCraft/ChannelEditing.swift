import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var editingChannel: ChannelPlaneTarget? {
    if let id = alphaEditingID, document.alphaChannels?.contains(where: { $0.id == id }) == true { return .alpha(id) }
    return document.quickMask == nil ? nil : .quickMask
  }
  var canEditChannels: Bool { !document.colorMode.isRestricted && canSelectComponentTarget && historyOperation == nil }
  func selectAlphaChannel(_ id: UUID?, overlay: Bool = false) throws {
    guard canEditChannels else { throw CraftError.invalid("Finish the current interaction first.") }
    if let id { _ = try document.channel(.alpha(id)) }
    alphaEditingID = id; alphaOverlay = overlay; componentTarget = .composite; modeComponentTargets = []; modeComponentVisibility = nil
    maskEditingLayerID = nil; smartFilterMaskEditing = false; clearMaskView()
    channelView = RGBChannelView(); render()
  }
  func toggleQuickMask() {
    guard canEditChannels else { return }
    alphaEditingID = nil; componentTarget = .composite; modeComponentTargets = []; modeComponentVisibility = nil; maskEditingLayerID = nil; clearMaskView()
    perform(.channel(.quickMask(document.quickMask == nil,quickMaskOptions)))
  }
  func newAlphaChannel() {
    guard canEditChannels else { return }
    do {
      let channel = AlphaChannel(name:document.suggestedChannelName,pixels:try Surface(width:document.width,height:document.height,depth:document.depth,fill:.black))
      try executeEditorCommand(.channel(.create(channel))); try selectAlphaChannel(channel.id)
    } catch { self.error = error.localizedDescription }
  }
  func channelThumbnail(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
    guard canEditChannels else { return }
    if modifiers.contains(.command) {
      let mode: SelectionMode = modifiers.contains(.shift) ? (modifiers.contains(.option) ? .intersect:.add):(modifiers.contains(.option) ? .subtract:.replace)
      perform(.channel(.load(.alpha(id),mode,false)))
    } else { do { try selectAlphaChannel(id,overlay:modifiers.contains(.option)) } catch { self.error = error.localizedDescription } }
  }
  func beginChannelDialog(_ kind: ChannelDialog.Kind) {
    guard canEditChannels else { return }
    channelDialog = ChannelDialog(kind:kind,document:document,target:editingChannel,defaults:quickMaskOptions)
  }
  func commitChannelDialog(_ draft: ChannelDialog) {
    guard channelDialog === draft else { return }
    do {
      let command = try draft.command(document:document)
      if draft.kind == .quickOptions { quickMaskOptions = draft.options }
      channelDialog = nil
      if let command { try executeEditorCommand(command) }
    } catch { draft.error = error.localizedDescription; channelDialog = draft }
  }
  nonisolated static func routeChannel(_ command: Command, target: ChannelPlaneTarget?) throws -> Command {
    guard let target else { return command }
    switch command {
    case .stroke(_,let points,let brush), .maskStroke(_,let points,let brush): return .channel(.stroke(target,points,brush))
    case .fill(_,let color): return .channel(.fill(target,unit(0.2126*color.r+0.7152*color.g+0.0722*color.b),color.a))
    case .maskFill(_,let amount): return .channel(.fill(target,amount,1))
    case .clear: return .channel(.fill(target,1,1))
    case .invertMask: return .channel(.invert(target))
    case .applyAdjustment(_, .invert): return .channel(.invert(target))
    case .applyFilter(_,let filter): return .channel(.filter(target,filter))
    case .channel, .selection, .selectShape, .selectionCoverage, .invertSelection, .featherSelection: return command
    default: throw CraftError.unsupported("Select RGB to use \(command.label) on layer content.")
    }
  }
}

/// Channel coverage is numeric. Only the document composite is color managed.
enum ChannelPresentation {
  static func image(_ composite: Surface, document: CraftDocument,target: ChannelPlaneTarget?,overlay: Bool) throws -> CGImage {
    guard let target else { return try ColorManagement.displayImage(composite,in:document) }
    let channel = try document.channel(target)
    if !overlay {
      var plane = try Surface(width:document.width,height:document.height,depth:.u8,fill:.black)
      try plane.mapPixels(in:.init(x:0,y:0,width:document.width,height:document.height)) { x,y,_ in
        let v = channel.options.display(channel.pixels.pixel(x:x,y:y).r); return Pixel(v,v,v)
      }
      return try RasterIO.displayImage(plane)
    }
    // Convert composite to display sRGB first, then apply the view-only colored mask.
    var display = try RasterIO.surface(ColorManagement.displayImage(composite,in:document))
    try display.mapPixels(in:.init(x:0,y:0,width:document.width,height:document.height)) { x,y,p in
      let k = channel.options.overlay(channel.pixels.pixel(x:x,y:y).r), c = channel.options.color
      return Pixel(p.r*(1-k)+c.r*k,p.g*(1-k)+c.g*k,p.b*(1-k)+c.b*k,max(p.a,k))
    }
    return try RasterIO.displayImage(display)
  }
}

@MainActor extension AppDelegate {
  @objc func toggleQuickMask() { store?.toggleQuickMask() }
  @objc func saveSelectionChannel() { store?.beginChannelDialog(.save) }
  @objc func loadSelectionChannel() { store?.beginChannelDialog(.load) }
}
