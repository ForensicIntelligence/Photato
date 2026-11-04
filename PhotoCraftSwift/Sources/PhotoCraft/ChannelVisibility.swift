import AppKit
import PhotoCraftCore
import PhotoCraftImaging

/// View state stays out of the document, Undo and persisted channel samples.
struct SavedChannelVisibility:Equatable {
  let documentID:UUID
  var imageVisible:Bool
  var alphaIDs:Set<UUID>
}
struct AuxiliaryChannelView:Equatable,Sendable {
  var imageVisible:Bool
  var targets:[ChannelPlaneTarget]
  var masks:[MaskPaintTarget]=[]
  var planeCount:Int {targets.count+masks.count}
  var needsPresentation:Bool {!imageVisible || planeCount>0}
}
enum ChannelEyeTarget:Hashable {
  case rgb(RGBChannelPreview),mode(Int?),ink(InkChannelTarget),alpha(UUID),quickMask,mask(MaskPaintTarget)
}
struct ChannelVisibilitySnapshot {
  let saved:SavedChannelVisibility?
  let rgb:RGBChannelView
  let mode:Set<Int>?
  let ink:Set<InkChannelTarget>?
  let overlay:Bool
  let hiddenDocument:UUID?
  let hiddenMask:UUID?
  let masks:TemporaryMaskChannelVisibility?
  let maskView:LayerMaskView?
}
struct ChannelVisibilitySweep {
  let id=UUID()
  let document:CraftDocument
  let generation:UUID
  let before:ChannelVisibilitySnapshot
  let visible:Bool
  var visited:Set<ChannelEyeTarget>=[]
}

extension EditorStore {
  var savedChannelView:SavedChannelVisibility {
    if let savedChannelVisibility,savedChannelVisibility.documentID==document.id {
      var value=savedChannelVisibility
      value.imageVisible = (value.imageVisible || !hasAuxiliaryChannelRows) && !document.isChannelOnly
      return value
    }
    let selected=alphaEditingID.flatMap {id in document.alphaChannels?.contains(where:{$0.id==id})==true ? id:nil}
    return .init(documentID:document.id,imageVisible:!document.isChannelOnly && (selected==nil || alphaOverlay),
      alphaIDs:Set(selected.map{[$0]} ?? []))
  }
  var hasAuxiliaryChannelRows:Bool {!(document.alphaChannels ?? []).isEmpty || document.quickMask != nil || !temporaryMaskChannels.isEmpty}
  var colorChannelsVisible:Bool {currentMaskView?.mode == .gray ? false:savedChannelView.imageVisible}
  var visibleAlphaIDs:Set<UUID> {currentMaskView?.mode == .gray ? []:savedChannelView.alphaIDs.intersection(document.alphaChannels?.map(\.id) ?? [])}
  func isAlphaVisible(_ id:UUID)->Bool {visibleAlphaIDs.contains(id)}
  var auxiliaryChannelView:AuxiliaryChannelView {
    let targets=(document.alphaChannels ?? []).filter {visibleAlphaIDs.contains($0.id)}.map {ChannelPlaneTarget.alpha($0.id)}
    return .init(imageVisible:savedChannelView.imageVisible,targets:targets+(isQuickMaskVisible ? [.quickMask]:[]),masks:currentMaskView == nil ? visibleTemporaryMaskChannels:[])
  }
  var channelVisibilityState:[String:Any] {
    let view=channelPreviewView
    return ["imageVisible":view.imageVisible,"visibleAlphaIDs":(document.alphaChannels ?? []).filter{visibleAlphaIDs.contains($0.id)}.map{$0.id.uuidString},
      "temporaryMaskChannels":temporaryMaskChannels.map {target in ["kind":target.smartFilter ? "smartFilterMask":"layerMask","layerID":target.layerID.uuidString,"visible":isTemporaryMaskVisible(target),"selected":selectedMaskPaintTarget==target] as [String:Any]},
      "orderedTargets":view.masks.map {($0.smartFilter ? "smartFilterMask:":"layerMask:")+$0.layerID.uuidString}+view.targets.map {if case .alpha(let id)=$0{return id.uuidString};return "quickMask"},
      "quickMaskVisible":isQuickMaskVisible,"grayscale":!view.imageVisible && view.planeCount==1,"sweepActive":channelVisibilitySweep != nil]
  }
  func showColorChannelsKeepingAlphas() {
    var value=savedChannelView;value.imageVisible = !document.isChannelOnly;savedChannelVisibility=value
    if alphaEditingID != nil {alphaOverlay=value.imageVisible}
  }
  /// Selecting an image row restores its isolated process view. Eye toggles
  /// use a separate path and keep the selected target and visible saved masks.
  func selectColorChannelVisibility() {
    showColorChannelsKeepingAlphas()
    var value=savedChannelView;value.alphaIDs=[];savedChannelVisibility=value
    temporaryMaskChannelVisibility=nil
  }
  func selectAlphaVisibility(_ id:UUID?,overlay:Bool) {
    temporaryMaskChannelVisibility=nil
    savedChannelVisibility = .init(documentID:document.id,imageVisible:!document.isChannelOnly && (id==nil || overlay),alphaIDs:Set(id.map{[$0]} ?? []))
  }
  func setAlphaVisibility(_ id:UUID,_ visible:Bool)throws {try setChannelEye(.alpha(id),visible:visible)}
  func setColorChannelsVisibility(_ visible:Bool)throws {
    guard !visible || !document.isChannelOnly else {throw CraftError.invalid("This document has no image color channels.")}
    guard canSelectComponentTarget,historyOperation==nil else {throw CraftError.invalid("Finish the current interaction before changing channel visibility.")}
    if !visible && !hasAuxiliaryChannelRows {return}
    let before=channelVisibilitySnapshot
    materializeTemporaryMaskView()
    if visible {
      if document.inkMode != nil {inkVisibility=nil}
      else if usesModeChannels {modeComponentVisibility=nil}
      else {channelView.setVisible(.composite,true)}
    }
    var value=savedChannelView;value.imageVisible=visible;savedChannelVisibility=value
    if alphaEditingID != nil {alphaOverlay=visible}
    if before != channelVisibilitySnapshot {render()}
  }
  func channelEyeVisible(_ target:ChannelEyeTarget)->Bool {
    switch target {
    case .mask(let target):return isTemporaryMaskVisible(target)
    case .alpha(let id):return isAlphaVisible(id)
    case .quickMask:return currentMaskView?.mode == .gray ? false:isQuickMaskVisible
    case .rgb(let channel):return colorChannelsVisible && channelView.isVisible(channel)
    case .mode(let component):guard colorChannelsVisible else{return false};let values=component.map{Set([$0])} ?? Set(0..<document.colorMode.componentCount);return !values.isEmpty && values.isSubset(of:modeVisibleComponents)
    case .ink(let target):return colorChannelsVisible && visibleInkTargets.contains(target)
    }
  }
  func setChannelEye(_ target:ChannelEyeTarget,visible:Bool,withinSweep:Bool=false)throws {
    guard canSelectComponentTarget(excludingChannelDialog:false,excludingChannelVisibilitySweep:withinSweep),historyOperation==nil else {
      throw CraftError.invalid("Finish the current interaction before changing channel visibility.")
    }
    // Validate before converting a legacy isolated view so invalid requests are atomic.
    if case .mask(let mask)=target, !temporaryMaskChannels.contains(mask) {throw CraftError.invalid("Select the layer that owns this available mask first.")}
    if case .alpha(let id)=target,document.alphaChannels?.contains(where:{$0.id==id}) != true {throw CraftError.invalid("The alpha channel is unavailable.")}
    if case .quickMask=target,document.quickMask==nil {throw CraftError.invalid("Enter Quick Mask before changing its visibility.")}
    if case .rgb=target,document.colorMode != .rgb || document.inkMode != nil {throw CraftError.invalid("Choose a color component of this document.")}
    if case .mode(let component)=target,!usesModeChannels || (component != nil && !(0..<document.colorMode.componentCount).contains(component!)) {throw CraftError.invalid("The mode channel is unavailable.")}
    if case .ink(let ink)=target,!document.inkChannelTargets.contains(ink) {throw CraftError.invalid("The printing channel is unavailable.")}
    let aggregate:Bool
    switch target {case .rgb(.composite),.mode(nil):aggregate=true;default:aggregate=false}
    if channelEyeVisible(target)==visible && (!aggregate || currentMaskView?.mode == .gray) {return}
    let before=channelVisibilitySnapshot
    materializeTemporaryMaskView()
    var state=savedChannelView
    switch target {
    case .mask(let mask):
      var eyes=temporaryMaskChannelState
      if visible {eyes.targets.insert(mask)}else{eyes.targets.remove(mask)}
      temporaryMaskChannelVisibility=eyes
    case .alpha(let id):
      guard document.alphaChannels?.contains(where:{$0.id==id})==true else {throw CraftError.invalid("The alpha channel is unavailable.")}
      if visible {state.alphaIDs.insert(id)}else{state.alphaIDs.remove(id)}
    case .quickMask:
      guard let mask=document.quickMask else{throw CraftError.invalid("Enter Quick Mask before changing its visibility.")}
      hiddenQuickMaskDocumentID=visible ? nil:document.id;hiddenQuickMaskID=visible ? nil:mask.id
    case .rgb(let channel):
      guard document.colorMode == .rgb,document.inkMode==nil else{throw CraftError.invalid("Choose a color component of this document.")}
      if usesModeChannels {
        let targets=channel == .composite ? Set(0..<3):[channel.rawValue-1]
        let prior=state.imageVisible ? modeVisibleComponents:[]
        let proposed=visible ? prior.union(targets):prior.subtracting(targets)
        if !proposed.isEmpty {modeComponentVisibility=proposed.count==3 ? nil:proposed}
        state.imageVisible = !proposed.isEmpty
      }else{
        let targets=channel == .composite ? RGBChannelView.components:[channel]
        let prior=state.imageVisible ? channelView.visible:[]
        let proposed=visible ? prior.union(targets):prior.subtracting(targets)
        if !proposed.isEmpty {
          var view=RGBChannelView(preview:channelView.preview)
          view.setVisible(.composite,true)
          for component in RGBChannelView.components.subtracting(proposed) {view.setVisible(component,false)}
          // Keep the existing preview label independent of the visible set.
          channelView=view
        }
        state.imageVisible = !proposed.isEmpty
      }
    case .mode(let component):
      guard usesModeChannels,component==nil || (0..<document.colorMode.componentCount).contains(component!) else {throw CraftError.invalid("The mode channel is unavailable.")}
      let targets=component.map{Set([$0])} ?? Set(0..<document.colorMode.componentCount)
      let prior=state.imageVisible ? modeVisibleComponents:[]
      let proposed=visible ? prior.union(targets):prior.subtracting(targets)
      if !proposed.isEmpty {modeComponentVisibility=document.colorMode.componentCount>1 && proposed.count==document.colorMode.componentCount ? nil:proposed}
      state.imageVisible = !proposed.isEmpty
    case .ink(let target):
      guard document.inkChannelTargets.contains(target) else{throw CraftError.invalid("The printing channel is unavailable.")}
      var proposed=state.imageVisible ? visibleInkTargets:[]
      if visible {proposed.insert(target)}else{proposed.remove(target)}
      if !proposed.isEmpty {inkVisibility=proposed}
      state.imageVisible = !proposed.isEmpty
    }
    // Preserve the established last-process-channel invariant without auxiliary rows.
    if !state.imageVisible && !hasAuxiliaryChannelRows {return}
    savedChannelVisibility=state
    if alphaEditingID != nil {alphaOverlay=state.imageVisible}
    if before != channelVisibilitySnapshot {render()}
  }
  var channelVisibilitySnapshot:ChannelVisibilitySnapshot {
    .init(saved:savedChannelView,rgb:channelView,mode:modeComponentVisibility,ink:inkVisibility,overlay:alphaOverlay,
      hiddenDocument:hiddenQuickMaskDocumentID,hiddenMask:hiddenQuickMaskID,masks:temporaryMaskChannelVisibility,maskView:currentMaskView)
  }
  @discardableResult func beginChannelVisibilitySweep(_ target:ChannelEyeTarget)->UUID? {
    guard canSelectComponentTarget,historyOperation==nil else{return nil}
    let draft=ChannelVisibilitySweep(document:document,generation:sessionGeneration,before:channelVisibilitySnapshot,visible:!channelEyeVisible(target))
    channelVisibilitySweep=draft;extendChannelVisibilitySweep(draft.id,over:[target]);return channelVisibilitySweep?.id
  }
  func extendChannelVisibilitySweep(_ id:UUID,over targets:[ChannelEyeTarget]) {
    guard var draft=channelVisibilitySweep,draft.id==id else{return}
    guard document==draft.document,sessionGeneration==draft.generation else{finishChannelVisibilitySweep(id,cancel:true);return}
    for target in targets where !draft.visited.contains(target) {
      do {try setChannelEye(target,visible:draft.visible,withinSweep:true);draft.visited.insert(target)}
      catch {self.error=error.localizedDescription;finishChannelVisibilitySweep(id,cancel:true);return}
    }
    channelVisibilitySweep=draft
  }
  func finishChannelVisibilitySweep(_ id:UUID,cancel:Bool=false) {
    guard let draft=channelVisibilitySweep,draft.id==id else{return};channelVisibilitySweep=nil
    guard cancel,document==draft.document,sessionGeneration==draft.generation else{return}
    let saved=draft.before;savedChannelVisibility=saved.saved;channelView=saved.rgb;modeComponentVisibility=saved.mode;inkVisibility=saved.ink
    alphaOverlay=saved.overlay;hiddenQuickMaskDocumentID=saved.hiddenDocument;hiddenQuickMaskID=saved.hiddenMask
    temporaryMaskChannelVisibility=saved.masks;layerMaskView=saved.maskView;render()
  }
}
extension ChannelVisibilitySnapshot:Equatable {}

/// Display-only composition. One numeric plane is reduced at a time, so memory
/// depends on the requested viewport, not the number or logical size of masks.
enum AuxiliaryChannelPresentation {
  static func image(_ source:Surface,document:CraftDocument,view:AuxiliaryChannelView,
    colorManaged:Bool=true,request:RasterPreviewRequest?=nil)throws->CGImage {
    let request=try request ?? (document.width*document.height>Surface.maximumDensePixels ? RasterPreviewRequest.overview(width:document.width,height:document.height):nil)
    let width=request?.width ?? document.width,height=request?.height ?? document.height
    func plane(_ channel:AlphaChannel,gray:Bool)throws->Surface {
      if let request {
        return try channel.pixels.reducedPreview(in:request.region,width:request.width,height:request.height,encoding:.sRGB,projectingStoredSamples:{p in
          let v=gray ? channel.display(p.r):p.r,numeric=Pixel(v,v,v)
          return gray ? numeric.quantized(.u8):numeric
        })
      }
      return try channel.pixels.mappedStoredSamples {p in let v=gray ? channel.display(p.r):p.r;return Pixel(v,v,v)}.quantizedStoredDepth(gray ? .u8:channel.pixels.depth)
    }
    func maskPlane(_ target:MaskPaintTarget)throws->Surface {
      guard let owner=document.layers.first(where:{$0.id==target.layerID}) else {throw CraftError.invalid("Mask owner unavailable.")}
      let layer=target.smartFilter ? try owner.filterMaskProjection():owner
      return try request.map {try Renderer.maskPresentation(layer,mode:.gray,request:$0)} ?? Renderer.maskPresentation(layer,mode:.gray,width:document.width,height:document.height)
    }
    if !view.imageVisible,view.planeCount==1,let mask=view.masks.first {return try RasterIO.displayImage(maskPlane(mask))}
    if !view.imageVisible,view.planeCount==1 {
      return try RasterIO.displayImage(plane(document.channel(view.targets[0]),gray:true))
    }
    var display:Surface
    if view.imageVisible {
      let reduced=try request.map{try $0.reducing(source)} ?? source
      display=try RasterIO.surface(colorManaged ? ColorManagement.displayImage(reduced,in:document):RasterIO.displayImage(reduced))
    } else {display=try Surface(width:width,height:height,depth:.u8,fill:view.planeCount==0 ? .clear:.white)}
    for target in view.masks {
      try Task.checkCancellation();let coverage=try maskPlane(target)
      try display.mapPixels(in:.init(x:0,y:0,width:width,height:height)) {x,y,p in
        let alpha=0.5*(1-unit(coverage.pixel(x:x,y:y).r)),inverse=1-alpha
        return Pixel(alpha+p.r*inverse,p.g*inverse,p.b*inverse,alpha+p.a*inverse)
      }
    }
    for target in view.targets {
      try Task.checkCancellation();let channel=try document.channel(target),coverage=try plane(channel,gray:false)
      try display.mapPixels(in:.init(x:0,y:0,width:width,height:height)) {x,y,p in channel.preview(coverage.pixel(x:x,y:y).r,over:p)}
    }
    return try RasterIO.displayImage(display)
  }
}

enum ChannelVisibilityAPI {
  static var stateSchema:[String:Any] {BrushAPI.object([
    "imageVisible":BrushAPI.flag,"quickMaskVisible":BrushAPI.flag,"grayscale":BrushAPI.flag,"sweepActive":BrushAPI.flag,
    "visibleAlphaIDs":["type":"array","uniqueItems":true,"maxItems":56,"items":["type":"string","format":"uuid"]],
    "temporaryMaskChannels":["type":"array","maxItems":2,"items":BrushAPI.object(["kind":["type":"string","enum":["layerMask","smartFilterMask"]],"layerID":["type":"string","format":"uuid"],"visible":BrushAPI.flag,"selected":BrushAPI.flag],required:["kind","layerID","visible","selected"])],
    "orderedTargets":["type":"array","maxItems":58,"items":["type":"string"]]],
    required:["imageVisible","quickMaskVisible","grayscale","visibleAlphaIDs","orderedTargets","sweepActive","temporaryMaskChannels"])}
  static var capabilities:[String:Any] {[
    "commands":["channel.view","view.channelVisibility","mode.channel.visibility","ink.channel.visibility"],
    "state":"auxiliaryVisibility","stateSchema":stateSchema,
    "temporaryMasks":["targets":["layerMask","smartFilterMask"],"owner":"layerID; visible requires the active owner, omitted visible selects its mask without forcing an isolated view","state":"temporaryMaskChannels {kind,layerID,visible,selected}","shortcut":"Unmodified backslash toggles the available pixel mask, or Filter Mask when it is the only mask, without changing the edit target. Other factory variants remain unqualified.","cursor":"Existing native eye control uses standard arrow;16 Control/Command/Option/Shift combinations preserve the ordinary action. No new canvas tool."],
    "behavior":"visible changes an image, temporary layer/Smart Filter mask, alpha/spot or Quick Mask eye without selecting a painting target. Several saved masks remain visible in document order; Quick Mask follows them. A single auxiliary plane alone is gray, multiple planes without image use overlays on white. All-hidden view with auxiliary rows is transparent; image-only documents retain their last visible process component. Image channel row selection and factory shortcuts clear saved alpha/spot eyes; eye toggles preserve them and the edit target. Quick Mask keeps its separate temporary visibility.",
    "history":"Document-local session state; no Undo/dirty/archive/export mutation. Deletion filters missing IDs without discarding their visibility memory, allowing Undo restoration. Reopen/revert and document/mode replacement reset the view.",
    "preview":"Canvas and channel-preview.png share bounded numeric reduction, selected component base and ordered overlay composition. Large API views use2048-side overviews. preview.png and normal exports ignore visibility.",
    "interaction":"Native eye click and sweep apply the first eye's desired state once per visited row. Escape/focus/window loss cancels and restores the captured view. Busy/stale API requests reject; a sweep blocks API edits. Legacy isolated mask views convert to independent eyes when visibility changes, preserving the painting target. Escape restores the captured view. No new painting tool/cursor or Adobe route.",
    "limits":"Full Photoshop overlay/default/profile/order, alternate eye gestures, multi-edit selection, exact temporary-row creation ordering, physical dense/60fps/platform/live UI remain unqualified. Hidden Quick Mask painting retains its observed rejection policy; other hidden-target policies are not inferred from visibility."]}
}
