import AppKit
import SwiftUI
import PhotoCraftCore

struct VideoTransitionControls:View {
  @Bindable var store:EditorStore
  @State private var kind:VideoTransitionKind = .fade
  @State private var edge:VideoTransitionEdge = .start
  @State private var duration:Double = 1
  @State private var color:Color = .black
  var selected:VideoTransition?{store.document.videoTimeline?.transitions?.first{$0.id==store.videoSelectedTransitionID}}
  var active:Layer?{store.document.layers.first{$0.id==(selected?.layerID ?? store.document.activeLayerID)}}
  var previous:Layer? {
    guard let active else{return nil};let siblings=store.document.children(of:active.parentID).filter{!$0.isClipped}
    guard let index=siblings.firstIndex(where:{$0.id==active.id}),index>0 else{return nil};return siblings[index-1]
  }
  var proposal:VideoTransition? {
    guard let active else{return nil}
    let c=NSColor(color).usingColorSpace(.sRGB) ?? .black
    return .init(id:selected?.id ?? UUID(),layerID:active.id,previousLayerID:kind == .crossFade ? previous?.id:nil,kind:kind,edge:kind == .crossFade ? .start:edge,duration:duration,color:kind == .color ? Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent)):nil)
  }
  var body:some View {
    Button {store.videoTransitionEditorVisible.toggle()} label:{Image(systemName:"square.on.square")}.help("Transitions")
      .popover(isPresented:$store.videoTransitionEditorVisible) {
        VStack(alignment:.leading,spacing:12) {
          Text("Transitions").font(.headline)
          Text(active?.name ?? "Select a clip").foregroundStyle(.secondary)
          Picker("Transition",selection:$kind){ForEach(VideoTransitionKind.allCases,id:\.self){Text($0.title).tag($0)}}
          if kind != .crossFade {Picker("Edge",selection:$edge){Text("Beginning").tag(VideoTransitionEdge.start);Text("End").tag(VideoTransitionEdge.end)}.pickerStyle(.segmented)}
          else{Text(previous.map{"Crossfade from \($0.name)"} ?? "Select the second of two adjacent clips.").font(.caption)}
          HStack{Text("Duration");TextField("Seconds",value:$duration,format:.number).frame(width:80);Text("seconds")}
          if kind == .color{ColorPicker("Color",selection:$color,supportsOpacity:false)}
          HStack {
            if let selected{Button("Delete Transition"){store.editVideo(.transition(.remove(selected.id)));store.videoSelectedTransitionID=nil;store.videoTransitionEditorVisible=false}}
            Spacer()
            Button(selected == nil ? "Apply":"Update") {
              guard let proposal else{return}
              store.editVideo(.transition(.set(proposal)))
              if store.document.videoTimeline?.transitions?.contains(proposal) == true{store.videoSelectedTransitionID=proposal.id;store.videoTransitionEditorVisible=false}
            }.disabled(active==nil || !duration.isFinite || duration<=0 || (kind == .crossFade && previous==nil))
          }
        }.padding(16).frame(width:330).onAppear{load()}.onChange(of:store.videoSelectedTransitionID){_,_ in load()}
      }
  }
  func load() {
    if let selected{kind=selected.kind;edge=selected.edge;duration=selected.duration;if let p=selected.color{color=Color(red:Double(p.r),green:Double(p.g),blue:Double(p.b))}}
    else{kind = .fade;edge = .start;duration=min(1,active?.videoInterval?.duration ?? 1)}
  }
}
