import AppKit
import PhotoCraftCore

extension EditorStore {
  var canCreateBlankVideoLayer:Bool {
    guard canUseTimeline,timelineTask==nil,isCompositeColorTarget,!editingMask,!smartFilterMaskEditing,
      let timeline=document.videoTimeline,document.animation==nil,!document.hasArtboards,!document.hasAuthoritativeModeStorage,
      Double(timeline.durationFrames)/timeline.frameRate<=86_400,document.layers.count<LayerLimits.maximumLayers else{return false}
    if let layer=activeLayer,let parent=layer.isGroup ? layer.id:layer.parentID,document.isLocked(parent){return false}
    return true
  }
  func createBlankVideoLayer() {
    guard canCreateBlankVideoLayer else{return}
    timelineVisible=true;editVideo(.blankLayer)
  }
}
@MainActor extension AppDelegate {
  @objc func newBlankVideoLayer(){store?.createBlankVideoLayer()}
}
