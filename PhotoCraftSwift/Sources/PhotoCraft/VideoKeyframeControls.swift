import AppKit
import SwiftUI
import PhotoCraftCore

struct VideoLayerKeyframeControls:View {
  @Bindable var store:EditorStore
  let layer:Layer
  @State private var expanded=false
  var body:some View {
    DisclosureGroup(isExpanded:$expanded) {
      VStack(alignment:.leading,spacing:5) {
        ForEach(VideoProperty.allCases,id:\.self){property in VideoPropertyTrack(store:store,layer:layer,property:property)}
      }.padding(.leading,8)
    } label:{
      Button{store.select(layer.id)} label:{HStack{Image(systemName:layer.video==nil ? "square.stack":"film");Text(layer.name).lineLimit(1);Spacer();Text("\(layer.videoKeyframes?.count ?? 0) keys").foregroundStyle(.secondary)}}.buttonStyle(.plain)
    }.padding(5).background(StudioTheme.field)
  }
}
private struct VideoPropertyTrack:View {
  @Bindable var store:EditorStore
  let layer:Layer
  let property:VideoProperty
  @State private var showKeys=false
  var keys:[VideoKeyframe]{(layer.videoKeyframes ?? []).filter{$0.property==property}.sorted{$0.time<$1.time}}
  var time:Double{store.document.videoTimeline?.seconds ?? 0}
  var current:VideoKeyframe?{keys.first{abs($0.time-time)<1e-9}}
  var locked:Bool{
    if property == .content,layer.video != nil{return true}
    let converted=keys.contains{$0.frameComposition == true}
    if case .adjustment = layer.content,property != .opacity,property != .visibility,!converted{return true}
    return store.document.isLocked(layer.id) || (property.isGeometry && (store.document.isPositionLocked(layer.id) || (!converted && (layer.isGroup || layer.smartFilters != nil || layer.warp != nil))))
  }
  var body:some View {
    HStack(spacing:7) {
      Button{store.editVideo(.keyframe(keys.isEmpty ? .enable(layer.id,property):.disable(layer.id,property)))} label:{Image(systemName:keys.isEmpty ? "stopwatch":"stopwatch.fill")}.help(keys.isEmpty ? "Enable \(property.title) animation":"Disable \(property.title) animation and remove its keys").accessibilityLabel("\(property.title) animation")
      Text(property.title).frame(width:72,alignment:.leading)
      Button{seek(previous:true)} label:{Image(systemName:"chevron.left")}.disabled(!keys.contains{$0.time<time-1e-9}).accessibilityLabel("Previous \(property.title) keyframe")
      Button{if let current{store.editVideo(.keyframe(.delete(layer.id,current.id)))}else{store.editVideo(.keyframe(.set(layer.id,property,time)))}} label:{Image(systemName:current==nil ? "diamond":"diamond.fill")}.help(current==nil ? "Add keyframe":"Delete keyframe")
      Button{seek(previous:false)} label:{Image(systemName:"chevron.right")}.disabled(!keys.contains{$0.time>time+1e-9}).accessibilityLabel("Next \(property.title) keyframe")
      values
      Spacer(minLength:0)
      Button("\(keys.count) keys…"){showKeys=true}.disabled(keys.isEmpty).popover(isPresented:$showKeys){VideoKeyframeList(store:store,layerID:layer.id,property:property).padding().frame(width:390,height:260)}
    }.buttonStyle(.borderless).disabled(locked)
  }
  @ViewBuilder var values:some View {
    switch property {
    case .content:Text("Edit layer content at the playhead").font(.caption).foregroundStyle(.secondary)
    case .visibility:Toggle("Visible",isOn:Binding(get:{layer.visible},set:{store.perform(.visibility(layer.id,$0))}))
    case .position:
      Text("X");TextField("X",value:Binding(get:{layer.x},set:{store.perform(.move(layer.id,$0,layer.y))}),format:.number).frame(width:65)
      Text("Y");TextField("Y",value:Binding(get:{layer.y},set:{store.perform(.move(layer.id,layer.x,$0))}),format:.number).frame(width:65)
    case .opacity:
      TextField("Opacity",value:Binding(get:{Double(layer.opacity)*100},set:{store.perform(.opacity(layer.id,Float($0/100)))}),format:.number).frame(width:65);Text("%")
    case .transform:Text("Use Free Transform to edit scale, rotation and position").font(.caption).foregroundStyle(.secondary)
    case .style:Button("Layer Style…"){store.select(layer.id);store.beginLayerStyle()}
    }
  }
  func seek(previous:Bool) {
    let key=previous ? keys.last{$0.time<time-1e-9}:keys.first{$0.time>time+1e-9}
    guard let key,let timeline=store.document.videoTimeline else{return}
    do{try store.selectVideoFrame(min(timeline.durationFrames-1,Int((key.time*timeline.frameRate).rounded())))}catch{store.error=error.localizedDescription}
  }
}
private struct VideoKeyframeList:View {
  @Bindable var store:EditorStore
  let layerID:UUID
  let property:VideoProperty
  var keys:[VideoKeyframe]{(store.document.layers.first{$0.id==layerID}?.videoKeyframes ?? []).filter{$0.property==property}.sorted{$0.time<$1.time}}
  var body:some View {
    VStack(alignment:.leading) {
      Text("\(property.title) Keyframes").font(.headline)
      Text("Time in seconds; interpolation applies until the next key.").font(.caption).foregroundStyle(.secondary)
      ScrollView {
        ForEach(keys){key in
          HStack {
            Image(systemName:key.interpolation == .hold ? "square.fill":"diamond.fill")
            TextField("Time",value:Binding(get:{key.time},set:{store.editVideo(.keyframe(.move(layerID,key.id,$0)))}),format:.number).frame(width:80)
            Picker("Interpolation",selection:Binding(get:{key.interpolation},set:{store.editVideo(.keyframe(.interpolation(layerID,key.id,$0)))})){
              if property != .visibility && property != .content {Text("Linear").tag(KeyframeInterpolation.linear)};Text("Hold").tag(KeyframeInterpolation.hold)
            }.labelsHidden().frame(width:120)
            Button{store.editVideo(.keyframe(.delete(layerID,key.id)))} label:{Image(systemName:"trash")}.accessibilityLabel("Delete keyframe")
          }
        }
      }
    }
  }
}
