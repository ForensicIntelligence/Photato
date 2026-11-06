import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

struct PathFillSheet:View {
  @Bindable var store:EditorStore
  @Bindable var draft:PathFillDraft
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Fill Path").font(.headline)
      Picker("Contents",selection:Binding(get:{draft.options.contents},set:{draft.choose($0)})) {
        ForEach(PathFillOptions.Contents.allCases,id:\.self){item in Text(item.title).tag(item).disabled(item == .history || item == .pattern && (draft.context.patternBusy || draft.context.patterns.isEmpty))}
      }
      if draft.options.contents == .color {
        ColorPicker("Color",selection:Binding(get:{let p=draft.options.color;return Color(red:Double(p.r),green:Double(p.g),blue:Double(p.b),opacity:Double(p.a))},set:{if let color=NSColor($0).usingColorSpace(.sRGB){draft.options.color=Pixel(Float(color.redComponent),Float(color.greenComponent),Float(color.blueComponent),Float(color.alphaComponent))}}))
      }
      if draft.options.contents == .pattern {
        Picker("Custom Pattern",selection:$draft.options.patternID){ForEach(draft.context.patterns){Text($0.displayName).tag(Optional($0.id))}}
      }
      Picker("Mode",selection:Binding(get:{draft.options.clear ? "Clear":draft.options.mode.rawValue},set:{value in draft.options.clear=value=="Clear";draft.options.mode=BlendMode(rawValue:value) ?? .normal})) {
        ForEach(BlendMode.allCases,id:\.self){Text($0.rawValue).tag($0.rawValue)}
        Text("Clear").tag("Clear").disabled(draft.original.layers.first(where:{$0.id==draft.layerID})?.isBackground == true)
      }
      HStack {Text("Opacity");Slider(value:Binding(get:{Double(draft.options.opacity)*100},set:{draft.options.opacity=Float($0/100)}),in:1...100);TextField("%",value:Binding(get:{Double(draft.options.opacity)*100},set:{draft.options.opacity=Float($0/100)}),format:.number).frame(width:65);Text("%")}
      Toggle("Preserve Transparency",isOn:$draft.options.preserveTransparency)
      HStack {Text("Feather Radius");TextField("px",value:$draft.options.feather,format:.number);Text("px")}
      Toggle("Anti-alias",isOn:$draft.options.antiAlias)
      if let error=draft.error{Text(error).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
      HStack {Spacer();Button("Cancel"){store.cancelPathFill()}.keyboardShortcut(.cancelAction);Button("OK"){store.commitPathFill(draft)}.keyboardShortcut(.defaultAction).disabled(!draft.valid)}
    }.textFieldStyle(.roundedBorder).padding(20).frame(width:420)
  }
}
