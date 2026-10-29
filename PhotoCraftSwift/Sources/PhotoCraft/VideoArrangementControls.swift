import AppKit
import SwiftUI
import PhotoCraftCore

struct VideoArrangementControls: View {
  @Bindable var store: EditorStore
  var body: some View {
    HStack(spacing:8) {
      Button {store.editVideo(.arrange(.split(store.layoutSelection)))} label:{Image(systemName:"scissors")}.help("Split At Playhead")
      Menu("Video Group") {
        Button("New Video Group") {store.editVideo(.arrange(.group("Video Group",[])))}
        Button("New Video Group from Selected Clips") {store.editVideo(.arrange(.group("Video Group",Array(store.layoutSelection))))}
      }
      if let layer = store.document.layers.first(where:{$0.id==store.document.activeLayerID}) {
        Text(layer.name).lineLimit(1).frame(maxWidth:140,alignment:.leading)
        if let start=layer.group?.videoStartTime {
          Text("Start (sec.)")
          TextField("Group start",value:Binding(get:{start},set:{store.editVideo(.arrange(.groupStart(layer.id,$0)))}),format:.number).frame(width:60)
          Button("Ungroup") {store.perform(.ungroup(layer.id))}
        } else {
          Menu("Move to Track") {
            Button("Independent Track") {store.editVideo(.arrange(.move(layer.id,group:nil,position:store.document.children(of:nil).count)))}
            ForEach(store.document.layers.filter{$0.group?.videoStartTime != nil}) {group in
              Button(group.name) {store.editVideo(.arrange(.move(layer.id,group:group.id,position:store.document.children(of:group.id).count)))}
            }
          }
          if let parent=layer.parentID,store.document.layers.first(where:{$0.id==parent})?.group?.videoStartTime != nil,
            let index=store.document.children(of:parent).firstIndex(where:{$0.id==layer.id}) {
            Button {store.editVideo(.arrange(.move(layer.id,group:parent,position:index-1)))} label:{Image(systemName:"arrow.left")}.disabled(index==0).help("Move Clip Earlier")
            Button {store.editVideo(.arrange(.move(layer.id,group:parent,position:index+1)))} label:{Image(systemName:"arrow.right")}.disabled(index+1==store.document.children(of:parent).count).help("Move Clip Later")
          }
          if layer.video == nil,let timeline=store.document.videoTimeline {
            let timing=layer.videoTiming ?? VideoLayerTiming(startTime:0,duration:Double(timeline.durationFrames)/timeline.frameRate)
            Text("Start")
            TextField("Clip start seconds",value:Binding(get:{timing.startTime},set:{store.editVideo(.arrange(.stillTiming(layer.id,startTime:$0,duration:timing.duration)))}),format:.number).frame(width:55).disabled(store.document.layers.first{$0.id==layer.parentID}?.group?.videoStartTime != nil)
            Text("Duration")
            TextField("Clip duration seconds",value:Binding(get:{timing.duration},set:{store.editVideo(.arrange(.stillTiming(layer.id,startTime:timing.startTime,duration:$0)))}),format:.number).frame(width:55)
          }
        }
      }
      Spacer(minLength:0)
    }.controlSize(.small)
  }
}
