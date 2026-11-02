import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class BackgroundLayerDraft:Identifiable {
  let id=UUID(),original:CraftDocument,layerID:UUID
  var options=NewPixelLayerOptions(name:"Layer 0")
  var opacity=100.0
  var error:String?
  init(_ document:CraftDocument,layerID:UUID){original=document;self.layerID=layerID}
}
@MainActor extension EditorStore {
  var canConvertBackground:Bool {
    guard canBeginLayerCreation,!editingComponent,!editingMask,pathTarget==nil,backgroundLayerDraft==nil,
      let id=document.activeLayerID,groupSelectionIDs==[id] else{return false}
    return BackgroundLayer.canConvert(document,layerID:id)
  }
  func beginBackgroundConversion() {
    finishLayerName();guard canConvertBackground,let layer=activeLayer else{return}
    if layer.isBackground{backgroundLayerDraft = .init(document,layerID:layer.id)}
    else{let color=backgroundColor;performGeometry(label:"Background from Layer",prepare:{_ in .backgroundLayer(.fromLayer(layer.id,color))})}
  }
  func convertBackgroundImmediately(_ id:UUID) {
    guard canBeginLayerCreation,!geometryBusy,transformDraft==nil,document.layers.first(where:{$0.id==id})?.isBackground == true else{return}
    perform(.backgroundLayer(.toLayer(id,.init(name:"Layer 0"))))
  }
  func commitBackgroundConversion(_ draft:BackgroundLayerDraft) {
    guard backgroundLayerDraft === draft,document==draft.original,!geometryBusy,transformDraft==nil else{draft.error="The document changed. Reopen Layer from Background.";return}
    var options=draft.options;options.opacity=Float(draft.opacity/100)
    do{_ = try options.layer(in:document)}catch{draft.error=error.localizedDescription;return}
    backgroundLayerDraft=nil;perform(.backgroundLayer(.toLayer(draft.layerID,options)))
  }
}
struct BackgroundLayerSheet:View {
  @Bindable var store:EditorStore
  @Bindable var draft:BackgroundLayerDraft
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("New Layer").font(.headline)
      Form {
        TextField("Name",text:$draft.options.name)
        Picker("Color",selection:$draft.options.color){ForEach(LayerColorLabel.allCases,id:\.self){Text($0.title).tag($0)}}
        Picker("Mode",selection:$draft.options.mode){ForEach(BlendMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        HStack{Text("Opacity");Slider(value:$draft.opacity,in:0...100);TextField("Percent",value:$draft.opacity,format:.number).frame(width:55);Text("%")}
      }
      if let error=draft.error{Text(error).foregroundStyle(.red)}
      HStack{Spacer();Button("Cancel"){store.backgroundLayerDraft=nil}.keyboardShortcut(.cancelAction);Button("OK"){store.commitBackgroundConversion(draft)}.keyboardShortcut(.defaultAction)}
    }.padding(20).frame(width:390)
  }
}
extension AppDelegate {
  @objc func backgroundLayerConversion(){store?.beginBackgroundConversion()}
}
