import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

/// Temporary view state is scoped to the selected owner, never the archived mask samples.
struct TemporaryMaskChannelVisibility:Equatable {
  let documentID:UUID
  let layerID:UUID?
  var targets:Set<MaskPaintTarget>
}

extension EditorStore {
  var temporaryMaskChannels:[MaskPaintTarget] {
    guard let layer=document.layers.first(where:{$0.id==document.activeLayerID}) else{return []}
    return (layer.mask == nil ? []:[MaskPaintTarget(layerID:layer.id,smartFilter:false)])
      + (layer.smartFilters?.mask == nil ? []:[MaskPaintTarget(layerID:layer.id,smartFilter:true)])
  }
  var temporaryMaskChannelState:TemporaryMaskChannelVisibility {
    if let state=temporaryMaskChannelVisibility,state.documentID==document.id,state.layerID==document.activeLayerID {return state}
    return .init(documentID:document.id,layerID:document.activeLayerID,targets:[])
  }
  var visibleTemporaryMaskChannels:[MaskPaintTarget] {
    if let legacy=currentMaskView {return [.init(layerID:legacy.layerID,smartFilter:legacy.smartFilter)]}
    return temporaryMaskChannels.filter{temporaryMaskChannelState.targets.contains($0)}
  }
  func isTemporaryMaskVisible(_ target:MaskPaintTarget)->Bool {visibleTemporaryMaskChannels.contains(target)}
  /// Legacy Option-click rendering remains compatible; API captures its same effective view.
  var channelPreviewView:AuxiliaryChannelView {
    var view=auxiliaryChannelView
    if let legacy=currentMaskView {
      if legacy.mode == .gray {view.imageVisible=false;view.targets=[]}
      view.masks=[.init(layerID:legacy.layerID,smartFilter:legacy.smartFilter)]
    }
    return view
  }
  func materializeTemporaryMaskView() {
    guard let view=currentMaskView else{return}
    var base=savedChannelView
    if view.mode == .gray {
      base.imageVisible=false;base.alphaIDs=[]
      if let quick=document.quickMask {hiddenQuickMaskDocumentID=document.id;hiddenQuickMaskID=quick.id}
    }
    savedChannelVisibility=base
    temporaryMaskChannelVisibility = .init(documentID:document.id,layerID:document.activeLayerID,
      targets:[.init(layerID:view.layerID,smartFilter:view.smartFilter)])
    clearMaskView()
  }
  func selectTemporaryMaskChannel(_ target:MaskPaintTarget)throws {
    guard canSelectComponentTarget,canBeginLayerCreation,
      let owner=document.layers.first(where:{$0.id==target.layerID}),
      target.smartFilter ? owner.smartFilters?.mask != nil:owner.mask != nil
    else {throw CraftError.invalid("Finish the interaction and choose an available mask.")}
    let sameOwner=target.layerID==document.activeLayerID,view=channelPreviewView
    clearMaskView()
    if target.smartFilter {selectSmartFilterMask(target.layerID)}else{selectMask(target.layerID)}
    if sameOwner {
      var base=savedChannelView;base.imageVisible=view.imageVisible;savedChannelVisibility=base
      temporaryMaskChannelVisibility = .init(documentID:document.id,layerID:document.activeLayerID,targets:Set(view.masks))
    }
    render()
  }
  @discardableResult func handleMaskOverlayShortcut(_ event:NSEvent)->Bool {
    guard event.type == .keyDown,event.charactersIgnoringModifiers == "\\",
      event.modifierFlags.intersection([.command,.control,.option,.shift,.function]).isEmpty,
      canSelectComponentTarget,let target=temporaryMaskChannels.first else{return false}
    if !event.isARepeat {
      do {try setChannelEye(.mask(target),visible:!isTemporaryMaskVisible(target))}
      catch {self.error=error.localizedDescription}
    }
    return true
  }
  func temporaryMaskName(_ target:MaskPaintTarget)->String {
    let owner=document.layers.first(where:{$0.id==target.layerID})?.name ?? "Layer"
    return owner+(target.smartFilter ? " Filter Mask":" Mask")
  }
}

struct TemporaryMaskChannelRow:View {
  @Bindable var store:EditorStore
  let target:MaskPaintTarget
  let eyeTracking:ChannelEyeTracking
  @State private var thumbnail:CGImage?
  var body:some View {
    HStack(spacing:6) {
      ChannelEyeControl(store:store,channel:.mask(target),tracking:eyeTracking,
        label:"Visibility of \(store.temporaryMaskName(target))",identifier:"channels.visibility.\(target.smartFilter ? "smartFilterMask":"layerMask").\(target.layerID.uuidString)",height:40)
        .frame(width:26,height:40)
      Button {
        do {try store.selectTemporaryMaskChannel(target)}catch{store.error=error.localizedDescription}
      } label: {
        HStack {
          if store.workspaceLibrary.channelPanelOptions.thumbnailSize != .none {
            Group {if let thumbnail {Image(decorative:thumbnail,scale:1).resizable().scaledToFit()}else{Color.black}}
              .frame(width:32,height:32).border(.black)
          }
          Text(store.temporaryMaskName(target)).lineLimit(1);Spacer()
        }.contentShape(Rectangle())
      }.accessibilityLabel("Select \(store.temporaryMaskName(target)) channel")
        .accessibilityValue(store.selectedMaskPaintTarget==target ? "Selected editing target":"")
        .accessibilityIdentifier("channels.select.\(target.smartFilter ? "smartFilterMask":"layerMask").\(target.layerID.uuidString)")
        .disabled(!store.canSelectComponentTarget)
    }.buttonStyle(.plain).font(.system(size:11)).padding(.vertical,4).padding(.trailing,8)
      .background(store.selectedMaskPaintTarget==target ? StudioTheme.selected:StudioTheme.chrome)
      .task(id:store.canvasPresentationRevision) {
        let document=store.document
        guard let owner=document.layers.first(where:{$0.id==target.layerID}) else{thumbnail=nil;return}
        let target=target
        thumbnail=try? await Task.detached(priority:.utility) {
          let layer=target.smartFilter ? try owner.filterMaskProjection():owner
          return try RasterIO.displayImage(Renderer.maskPresentation(layer,mode:.gray,
            request:.init(region:.init(x:0,y:0,width:document.width,height:document.height),
              width:max(1,Int(Double(document.width)*min(1,64/Double(max(document.width,document.height))))),
              height:max(1,Int(Double(document.height)*min(1,64/Double(max(document.width,document.height))))))))
        }.value
      }
  }
}
