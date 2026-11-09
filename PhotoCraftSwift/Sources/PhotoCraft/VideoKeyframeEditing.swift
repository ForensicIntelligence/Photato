import AppKit
import Observation
import SwiftUI
import PhotoCraftCore

@MainActor @Observable final class VideoKeyframePasteboard {
  static let shared=VideoKeyframePasteboard()
  var value:VideoKeyframeClipboard?
}

extension EditorStore {
  var validVideoKeyframeSelection:Set<VideoKeyframeReference> {
    videoKeyframeSelection.intersection(Set(document.layers.flatMap { layer in
      (layer.videoKeyframes ?? []).map { VideoKeyframeReference(layerID:layer.id,keyframeID:$0.id) }
    }))
  }
  func selectAllVideoKeyframes(layerID:UUID?=nil,property:VideoProperty?=nil) {
    guard canUseTimeline,document.videoTimeline != nil else{return}
    videoKeyframeSelection=Set(document.layers.filter{layerID==nil || $0.id==layerID}.flatMap { layer in
      (layer.videoKeyframes ?? []).filter{property==nil || $0.property==property}.map { VideoKeyframeReference(layerID:layer.id,keyframeID:$0.id) }
    })
  }
  func selectVideoKeyframe(_ key:VideoKeyframeReference,additive:Bool) {
    guard canUseTimeline else{return}
    if additive {
      var selected=validVideoKeyframeSelection
      if !selected.insert(key).inserted {selected.remove(key)}
      videoKeyframeSelection=selected
    } else {videoKeyframeSelection=[key]}
  }
  func copySelectedVideoKeyframes() {
    guard canUseTimeline else{return}
    do { videoKeyframePasteboard.value=try VideoKeyframeClipboard.capture(validVideoKeyframeSelection,in:document) }
    catch {self.error=error.localizedDescription}
  }
  var videoKeyframeDestinations:[UUID] {
    let selected=layoutSelection
    if !selected.isEmpty {return document.layers.filter{selected.contains($0.id)}.map(\.id)}
    return document.activeLayerID.map{[$0]} ?? []
  }
  func selectPastedVideoKeyframes(_ clipboard:VideoKeyframeClipboard,layers:[UUID],time:Double) {
    var selected=Set<VideoKeyframeReference>()
    for (index,id) in layers.enumerated() {
      guard clipboard.tracks.count==1 || clipboard.tracks.indices.contains(index) else{continue}
      for value in clipboard.tracks[clipboard.tracks.count==1 ? 0:index].keys {
        if let key=document.layers.first(where:{$0.id==id})?.videoKeyframes?.first(where:{$0.property==value.property && abs($0.time-(time+value.time-clipboard.origin))<1e-9}) {
          selected.insert(.init(layerID:id,keyframeID:key.id))
        }
      }
    }
    videoKeyframeSelection=selected
  }
  func editSelectedVideoKeyframes(_ edit:VideoKeyframeEdit) {
    guard canUseTimeline,document.videoTimeline != nil else{return}
    stopTimelinePlayback(render:false)
    let before=Set(document.layers.flatMap{($0.videoKeyframes ?? []).map(\.id)})
    performGeometry(.video(.keyframes(edit)),onSuccess:{
      switch edit {
      case .paste(let clipboard,let layers,let time):self.selectPastedVideoKeyframes(clipboard,layers:layers,time:time)
      case .move(_,_,true):self.videoKeyframeSelection=Set(self.document.layers.flatMap{layer in (layer.videoKeyframes ?? []).filter{!before.contains($0.id)}.map{VideoKeyframeReference(layerID:layer.id,keyframeID:$0.id)}})
      default:self.videoKeyframeSelection=self.validVideoKeyframeSelection
      }
    })
  }
  func pasteVideoKeyframes() {
    guard let clipboard=videoKeyframePasteboard.value,let timeline=document.videoTimeline else{return}
    editSelectedVideoKeyframes(.paste(clipboard,layers:videoKeyframeDestinations,time:timeline.seconds))
  }
}

struct VideoKeyframeEditingMenu:View {
  @Bindable var store:EditorStore
  var layerID:UUID?
  var property:VideoProperty?
  var body:some View {
    Menu("Keyframes") { actions }.disabled(!store.canUseTimeline || store.document.videoTimeline==nil)
  }
  @ViewBuilder var actions:some View {
    let selection=store.validVideoKeyframeSelection
    Button("Delete"){store.editSelectedVideoKeyframes(.delete(selection))}.disabled(selection.isEmpty)
    Button("Copy"){store.copySelectedVideoKeyframes()}.disabled(selection.isEmpty)
    Button("Paste"){store.pasteVideoKeyframes()}.disabled(store.videoKeyframePasteboard.value==nil || store.videoKeyframeDestinations.isEmpty)
    Divider()
    Button("Select All"){store.selectAllVideoKeyframes(layerID:layerID,property:property)}
    Button("Deselect All"){store.videoKeyframeSelection=[]}.disabled(selection.isEmpty)
    Divider()
    Button("Linear Interpolation"){store.editSelectedVideoKeyframes(.interpolation(selection,.linear))}.disabled(selection.isEmpty)
    Button("Hold Interpolation"){store.editSelectedVideoKeyframes(.interpolation(selection,.hold))}.disabled(selection.isEmpty)
  }
}

struct VideoKeyframeSelectionControls:View {
  @Bindable var store:EditorStore
  @State private var seconds=1.0
  var body:some View {
    HStack {
      Text("\(store.validVideoKeyframeSelection.count) selected").monospacedDigit()
      Spacer()
      TextField("Offset in seconds",value:$seconds,format:.number).frame(width:65)
      Text("sec.")
      Button("Move"){store.editSelectedVideoKeyframes(.move(store.validVideoKeyframeSelection,seconds:seconds,duplicate:false))}
      Button("Duplicate"){store.editSelectedVideoKeyframes(.move(store.validVideoKeyframeSelection,seconds:seconds,duplicate:true))}
    }.disabled(!store.canUseTimeline || store.validVideoKeyframeSelection.isEmpty)
  }
}
