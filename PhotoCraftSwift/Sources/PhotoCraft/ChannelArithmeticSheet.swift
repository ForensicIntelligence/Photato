import SwiftUI
import PhotoCraftCore

struct ChannelArithmeticSheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:ChannelArithmeticWorkspace
  private func binding<T>(_ path:WritableKeyPath<ChannelArithmeticRequest,T>)->Binding<T> {Binding(get:{model.request[keyPath:path]},set:{value in model.update{$0[keyPath:path]=value}})}
  private func sourceBinding(_ path:WritableKeyPath<ChannelArithmeticRequest,ChannelArithmeticSource>)->Binding<ChannelArithmeticSource> {binding(path)}
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text(model.request.title).font(.title2.bold())
      HStack(alignment:.top,spacing:20) {
        ZStack {
          Color.black.opacity(0.28)
          if let image=model.preview ? model.image:model.originalImage {Image(decorative:image,scale:1).resizable().scaledToFit().padding(12)}
          if model.rendering {ProgressView().padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:10))}
        }.frame(width:420,height:440).clipped()
        ScrollView {
          VStack(alignment:.leading,spacing:14) {
            source("Source 1",value:sourceBinding(\.source1))
            if model.request.kind == .calculations {source("Source 2",value:sourceBinding(\.source2))}
            Picker("Blending",selection:binding(\.options.blending)) {ForEach(ChannelArithmeticOptions.modes,id:\.self){Text(ChannelArithmeticOptions.title($0)).tag($0)}}
            HStack {Text("Opacity");Slider(value:binding(\.options.opacity),in:0...1);Text(model.request.options.opacity,format:.percent.precision(.fractionLength(0))).monospacedDigit().frame(width:42)}
            if ["add","subtract"].contains(model.request.options.blending) {
              HStack {Text("Scale");TextField("Scale",value:binding(\.options.scale),format:.number)}
              HStack {Text("Offset");TextField("Offset",value:binding(\.options.offset),format:.number)}
            }
            if model.request.kind == .applyImage {Toggle("Preserve Transparency",isOn:binding(\.options.preserveTransparency))}
            Toggle("Mask",isOn:Binding(get:{model.request.mask != nil},set:{enabled in model.update{$0.mask=enabled ? .init(channel:.gray):nil}}))
            if model.request.mask != nil {source("Mask source",value:Binding(get:{model.request.mask ?? .init(channel:.gray)},set:{value in model.update{$0.mask=value}}))}
            if model.request.kind == .calculations {
              Picker("Result",selection:binding(\.result)) {ForEach(ChannelCalculationResult.allCases,id:\.self){Text($0.title).tag($0)}}
              if model.request.result != .selection {TextField("Result name",text:Binding(get:{model.request.name ?? ""},set:{value in model.update{$0.name=value.isEmpty ? nil:value}}))}
            }
          }.padding(2)
        }.frame(width:330,height:440)
      }
      if let error=model.error {Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal:false,vertical:true)}
      HStack {Toggle("Preview",isOn:$model.preview);Spacer();Button("Cancel"){store.cancelChannelArithmetic()}.keyboardShortcut(.cancelAction).disabled(model.committing);Button("OK"){store.commitChannelArithmetic()}.keyboardShortcut(.defaultAction).disabled(!model.ready)}
    }.padding(20).frame(width:810)
  }
  private func source(_ title:String,value:Binding<ChannelArithmeticSource>)->some View {
    let document=model.document(for:value.wrappedValue)
    return GroupBox(title) {
      VStack(alignment:.leading,spacing:8) {
        Picker("Document",selection:Binding(get:{value.wrappedValue.documentID ?? model.source.id},set:{id in var next=value.wrappedValue;next.documentID=id;next.layerID=nil;next.channel=model.request.kind == .calculations ? .component(0):.composite;value.wrappedValue=next})) {ForEach(model.documents,id:\.id){Text($0.name).tag($0.id)}}
        Picker("Layer",selection:Binding(get:{value.wrappedValue.layerID},set:{value.wrappedValue.layerID=$0})) {
          Text("Merged").tag(UUID?.none);ForEach(document.layers,id:\.id){Text($0.name).tag(Optional($0.id))}
        }
        Picker("Channel",selection:Binding(get:{value.wrappedValue.channel},set:{value.wrappedValue.channel=$0})) {
          if model.request.kind == .applyImage {Text("Composite").tag(ChannelArithmeticChannel.composite)}
          Text("Gray").tag(ChannelArithmeticChannel.gray)
          ForEach(Array(document.colorChannelNames.prefix(document.colorMode.componentCount).enumerated()),id:\.offset){index,name in Text(name).tag(ChannelArithmeticChannel.component(index))}
          ForEach(document.alphaChannels ?? [],id:\.id){Text($0.name).tag(ChannelArithmeticChannel.alpha($0.id))}
          if document.quickMask != nil {Text("Quick Mask").tag(ChannelArithmeticChannel.quickMask)}
          Text("Selection").tag(ChannelArithmeticChannel.selection)
          if let id=value.wrappedValue.layerID,let layer=document.layers.first(where:{$0.id==id}) {
            Text("Transparency").tag(ChannelArithmeticChannel.transparency)
            if layer.mask != nil {Text("Layer Mask").tag(ChannelArithmeticChannel.layerMask)}
            if layer.vectorMask != nil {Text("Vector Mask").tag(ChannelArithmeticChannel.vectorMask)}
          }
          ForEach(document.inkChannelTargets,id:\.self){target in Text("Printing plate: \(String(describing:target))").tag(ChannelArithmeticChannel.ink(target))}
        }
        Toggle("Invert",isOn:Binding(get:{value.wrappedValue.invert},set:{value.wrappedValue.invert=$0}))
      }.padding(5)
    }
  }
}
