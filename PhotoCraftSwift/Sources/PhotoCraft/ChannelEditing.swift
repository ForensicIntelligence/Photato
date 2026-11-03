import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  static let hiddenQuickMaskBrushMessage = "Could not use the brush tool because the target channel is hidden."
  var hasHiddenQuickMaskEditingTarget: Bool { editingChannel == .quickMask && !isQuickMaskVisible }
  var editingChannel: ChannelPlaneTarget? {
    if let id = alphaEditingID, document.alphaChannels?.contains(where: { $0.id == id }) == true { return .alpha(id) }
    return document.quickMask == nil ? nil : .quickMask
  }
  var isQuickMaskVisible: Bool {
    guard let mask = document.quickMask else { return false }
    return hiddenQuickMaskDocumentID != document.id || hiddenQuickMaskID != mask.id
  }
  var displayedAuxiliaryChannel: ChannelPlaneTarget? {
    editingChannel == .quickMask && !isQuickMaskVisible ? nil : editingChannel
  }
  func setQuickMaskVisibility(_ visible: Bool) throws {
    guard canEditChannels, let mask = document.quickMask else {
      throw CraftError.invalid("Select an available Quick Mask after finishing the current interaction.")
    }
    guard isQuickMaskVisible != visible else { return }
    hiddenQuickMaskDocumentID = visible ? nil : document.id
    hiddenQuickMaskID = visible ? nil : mask.id
    render()
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
    do {
      try executeEditorCommand(.channel(.quickMask(document.quickMask == nil,quickMaskOptions)))
      resetQuickMaskEditingContext();render()
    } catch {self.error=error.localizedDescription}
  }
  func resetQuickMaskEditingContext() {
    alphaEditingID=document.isChannelOnly && document.quickMask == nil ? document.alphaChannels?.first?.id:nil;componentTarget = .composite;modeComponentTargets=[];modeComponentVisibility=nil
    maskEditingLayerID=nil;smartFilterMaskEditing=false;clearMaskView();channelView=RGBChannelView()
  }
  func reverseQuickMaskIndication() {
    guard canEditChannels else{return}
    var options=document.quickMask?.options ?? quickMaskOptions
    options.indicates=options.indicates == .maskedAreas ? .selectedAreas:.maskedAreas
    do {
      if document.quickMask != nil {try executeEditorCommand(.channel(.options(.quickMask,options)))}
      try quickMaskPreferences.set(options);render()
    } catch {self.error=error.localizedDescription}
  }
  var canSaveSelectionChannel:Bool {canEditChannels && document.quickMask == nil && (document.selection != nil || document.selectionMask != nil)}
  var canLoadSelectionChannel:Bool {canEditChannels && selectionChannelDocuments.contains {!SelectionChannelSource.choices(in:$0).isEmpty}}
  var selectionChannelDocuments:[CraftDocument] {
    let others=documentController?.documents.compactMap {($0 as? CraftNSDocument)?.store.document} ?? []
    return [document]+others.filter {$0.id != document.id && $0.width==document.width && $0.height==document.height && !$0.colorMode.isRestricted}
  }
  var selectionChannelDocumentNames:[UUID:String] {
    var names:[UUID:String]=[:]
    for case let file as CraftNSDocument in documentController?.documents ?? [] {
      names[file.store.document.id]=file.displayName ?? file.store.document.name
    }
    return names
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
    if kind == .save && !canSaveSelectionChannel {return}
    if kind == .load && !canLoadSelectionChannel {return}
    channelDialog = ChannelDialog(kind:kind,document:document,target:editingChannel,defaults:quickMaskOptions,sources:selectionChannelDocuments,documentNames:selectionChannelDocumentNames,colorSettings:workingColorSettings)
  }
  func commitChannelDialog(_ draft: ChannelDialog) {
    guard channelDialog === draft,!draft.committing else { return }
    if draft.kind == .save || draft.kind == .load {commitSelectionChannelDialog(draft);return}
    do {
      guard document==draft.source else{throw CraftError.invalid("The document changed. Cancel and reopen Channel Options.")}
      let command = try draft.command(document:document)
      if draft.kind == .quickOptions { quickMaskOptions = draft.options }
      channelDialog = nil
      if let command {
        try executeEditorCommand(command)
        if case .channel(.create(let channel))=command {try selectAlphaChannel(channel.id,overlay:channel.spot != nil)}
      }
    } catch { draft.error = error.localizedDescription; channelDialog = draft }
  }
  nonisolated static func routeChannel(_ command: Command, target: ChannelPlaneTarget?) throws -> Command {
    guard let target else { return command }
    switch command {
    case .transformChannel(let request):guard request.target==target else{throw CraftError.invalid("Transform must match the selected channel.")};return command
    case .stroke(_,let points,let brush), .maskStroke(_,let points,let brush): return .channel(.stroke(target,points,brush))
    case .fill(_,let color): return .channel(.fill(target,unit(0.2126*color.r+0.7152*color.g+0.0722*color.b),color.a))
    case .maskFill(_,let amount): return .channel(.fill(target,amount,1))
    case .clear: return .channel(.fill(target,1,1))
    case .invertMask: return .channel(.invert(target))
    case .applyAdjustment(_, .invert): return .channel(.invert(target))
    case .applyFilter(_,let filter): return .channel(.filter(target,filter))
    case .layerComp, .documentMetadata, .guides, .channel, .selection, .selectShape, .selectionCoverage, .invertSelection, .featherSelection: return command
    default: throw CraftError.unsupported("Select RGB to use \(command.label) on layer content.")
    }
  }
}

/// Channel coverage is numeric. Only the document composite is color managed.
enum ChannelPresentation {
  static func image(_ composite: Surface, document: CraftDocument,target: ChannelPlaneTarget?,overlay: Bool,
    request: RasterPreviewRequest? = nil
  ) throws -> CGImage {
    guard let target else { return try ColorManagement.displayImage(request.map { try $0.reducing(composite) } ?? composite,in:document) }
    let channel = try document.channel(target)
    if let request {
      let plane = try channel.pixels.reducedPreview(in: request.region, width: request.width,
        height: request.height, encoding: .sRGB, projectingStoredSamples: { p in
          let v = overlay ? p.r : channel.display(p.r)
          let numeric = Pixel(v,v,v)
          return overlay ? numeric : numeric.quantized(.u8)
        })
      if !overlay { return try RasterIO.displayImage(plane) }
      var display = try RasterIO.surface(ColorManagement.displayImage(request.reducing(composite),in:document))
      try display.mapPixels(in: .init(x: 0, y: 0, width: request.width, height: request.height)) { x,y,p in
        return channel.preview(plane.pixel(x:x,y:y).r,over:p)
      }
      return try RasterIO.displayImage(display)
    }
    if !overlay {
      var plane = try Surface(width:document.width,height:document.height,depth:.u8,fill:.black)
      try plane.mapPixels(in:.init(x:0,y:0,width:document.width,height:document.height)) { x,y,_ in
        let v = channel.display(channel.pixels.pixel(x:x,y:y).r); return Pixel(v,v,v)
      }
      return try RasterIO.displayImage(plane)
    }
    // Convert composite to display sRGB first, then apply the view-only colored mask.
    var display = try RasterIO.surface(ColorManagement.displayImage(composite,in:document))
    try display.mapPixels(in:.init(x:0,y:0,width:document.width,height:document.height)) { x,y,p in
      return channel.preview(channel.pixels.pixel(x:x,y:y).r,over:p)
    }
    return try RasterIO.displayImage(display)
  }
}

@MainActor extension AppDelegate {
  @objc func toggleQuickMask() { store?.toggleQuickMask() }
  @objc func saveSelectionChannel() { store?.beginChannelDialog(.save) }
  @objc func loadSelectionChannel() { store?.beginChannelDialog(.load) }
}
