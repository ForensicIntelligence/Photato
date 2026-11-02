import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class LightingWorkspace {
  nonisolated static let maximumPreviewSide=192
  struct State:Equatable {var settings:LightingSettings;var opacity:Float;var mode:PhotoCraftCore.BlendMode;var selected:Int}
  var settings=LightingSettings()
  var selected=0
  var opacity:Float=1
  var mode:PhotoCraftCore.BlendMode = .normal
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var rendering=false
  var error:String?
  var undoStates=[State]()
  var redoStates=[State]()
  @ObservationIgnored var task:Task<Void,Never>?
  @ObservationIgnored var previewToDocument:Transform2D = .identity
  @ObservationIgnored var reference=IntRect(x:0,y:0,width:1,height:1)
  private var generation=0
  private var closed=false
  private var input:Surface?
  private var document:CraftDocument?
  private var gestureStart:State?
  var state:State{.init(settings:settings,opacity:opacity,mode:mode,selected:selected)}
  var light:LightingSettings.Light?{settings.lights.indices.contains(selected) ? settings.lights[selected]:nil}
  var canAdd:Bool{settings.lights.count<LightingSettings.maximumLights}
  var ready:Bool{image != nil && !rendering && error==nil}
  var apiState:[String:Any]{["settings":BrushAPI.json(settings),"selectedLight":selected,"preview":preview,"opacity":opacity,"blendMode":mode.rawValue,"rendering":rendering,"canAddLight":canAdd,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"maximumPreviewSide":Self.maximumPreviewSide,"error":error as Any? ?? NSNull()]}
  func prepare(document:CraftDocument,draft:FilterDraft)async {
    close();closed=false;input=nil;image=nil;originalImage=nil;undoStates=[];redoStates=[];gestureStart=nil;preview=true;selected=0;settings=draft.filter.lighting ?? .init();opacity=draft.opacity;mode=draft.blendMode;self.document=document;rendering=true;error=nil;generation+=1;let token=generation
    let full=IntRect(x:0,y:0,width:document.width,height:document.height),smart=document.layers.first{$0.id==draft.id}?.smartObject != nil
    reference=smart ? full:(document.selection.flatMap{$0.width>0 && $0.height>0 ? $0:nil} ?? full)
    task=Task{[weak self] in
      do{
        try (draft.filter.lighting ?? LightingSettings()).validateReferences(in:document)
        let worker=Task.detached(priority:.userInitiated){()throws->(Surface,Transform2D) in
          let layer=try draft.inputLayer(in:document),source=try Renderer.layerSurface(layer,in:document),scale=max(1,Double(max(source.width,source.height))/Double(Self.maximumPreviewSide)),width=max(1,Int(Double(source.width)/scale)),height=max(1,Int(Double(source.height)/scale))
          var small=try Surface(width:width,height:height,depth:source.depth,colorEncoding:source.colorEncoding)
          for y in 0..<height{try Task.checkCancellation();for x in 0..<width{let xx=min(source.width-1,Int((Double(x)+0.5)*scale)),yy=min(source.height-1,Int((Double(y)+0.5)*scale)),p=source.depth == .f32 ? source.linearPixel(x:xx,y:yy):source.pixel(x:xx,y:yy);if source.depth == .f32{small.setLinearPixel(x:x,y:y,p)}else{small.setPixel(x:x,y:y,p)}}}
          return(small,layer.coordinateTransform * .scale(scale,scale))
        }
        let result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation();guard let self,!self.closed,self.generation==token else{return}
        self.input=result.0;self.previewToDocument=result.1;self.originalImage=try ColorManagement.displayImage(result.0,in:document);self.refresh()
      }catch{guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled{self.error=error.localizedDescription}}
    };await task?.value;await task?.value
  }
  func change(_ value:LightingSettings,remember:Bool=true){
    guard !closed else{return}
    do{if let document{try value.validateReferences(in:document)}else{try value.validate()}}catch{self.error=error.localizedDescription;return}
    guard value != settings else{if error != nil{error=nil;refresh()};return};if remember && gestureStart==nil{rememberState()};settings=value;selected=min(selected,max(0,value.lights.count-1));refresh()
  }
  private func rememberState(){undoStates.append(state);if undoStates.count>100{undoStates.removeFirst()};redoStates=[]}
  func select(_ index:Int){guard settings.lights.indices.contains(index) else{return};selected=index}
  func editLight(_ value:LightingSettings.Light){guard settings.lights.indices.contains(selected) else{return};var s=settings;s.lights[selected]=value;change(s)}
  func add(_ kind:LightingSettings.Kind){guard canAdd else{return};var s=settings;s.lights.append(.init(kind:kind));change(s);selected=s.lights.count-1}
  @discardableResult func duplicate(_ index:Int)->Int?{guard canAdd,settings.lights.indices.contains(index) else{return nil};var s=settings;s.lights.append(s.lights[index]);change(s);selected=s.lights.count-1;return selected}
  func delete(){guard settings.lights.indices.contains(selected) else{return};var s=settings;s.lights.remove(at:selected);change(s)}
  func toggle(_ index:Int){guard settings.lights.indices.contains(index) else{return};var s=settings;s.lights[index].enabled.toggle();change(s)}
  func beginGesture(){if gestureStart==nil{gestureStart=state}}
  func endGesture(){if let old=gestureStart,old != state{undoStates.append(old);redoStates=[]};gestureStart=nil}
  private func restore(_ value:State){settings=value.settings;opacity=value.opacity;mode=value.mode;selected=value.selected;refresh()}
  func undo(){endGesture();guard let old=undoStates.popLast() else{return};redoStates.append(state);restore(old)}
  func redo(){endGesture();guard let next=redoStates.popLast() else{return};undoStates.append(state);restore(next)}
  func blending(opacity:Float,mode:PhotoCraftCore.BlendMode){guard opacity.isFinite,(0...1).contains(opacity),opacity != self.opacity || mode != self.mode else{return};if gestureStart==nil{rememberState()};self.opacity=opacity;self.mode=mode;refresh()}
  func refresh(){
    guard !closed,let input,let document else{return};task?.cancel();generation+=1;let token=generation,value=settings,bounds=reference,matrix=previewToDocument,opacity=opacity,mode=mode
    let texture=value.textureChannelID.flatMap{id in document.alphaChannels?.first{$0.id==id}?.pixels};rendering=true;error=nil
    task=Task{[weak self] in
      do{try await Task.sleep(for:.milliseconds(40));let worker=Task.detached(priority:.userInitiated){()throws->CGImage in
          var rendered=try LightingEngine.render(input,settings:value,referenceBounds:bounds,pixelToDocument:matrix,texture:texture)
          if opacity != 1 || mode != .normal{for y in 0..<input.height{try Task.checkCancellation();for x in 0..<input.width{let a=input.depth == .f32 ? input.linearPixel(x:x,y:y):input.pixel(x:x,y:y),b=rendered.depth == .f32 ? rendered.linearPixel(x:x,y:y):rendered.pixel(x:x,y:y),p=mode.composite(backdrop:a,source:b,opacity:opacity,x:x,y:y);if rendered.depth == .f32{rendered.setLinearPixel(x:x,y:y,p)}else{rendered.setPixel(x:x,y:y,p)}}}}
          return try ColorManagement.displayImage(rendered,in:document)
        };let result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation();guard let self,!self.closed,self.generation==token else{return};self.image=result;self.rendering=false
      }catch{guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled{self.error=error.localizedDescription}}
    }
  }
  func close(){closed=true;generation+=1;task?.cancel();task=nil;rendering=false;gestureStart=nil}
  func loadPreset(){let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false;panel.begin{[weak self] result in guard result == .OK,let url=panel.url,let self,!self.closed else{return};do{let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<=LightingSettings.maximumPresetBytes else{throw CraftError.invalid("Lighting preset exceeds256KiB.")};self.change(try LightingSettings.decodeJSON(Data(contentsOf:url)))}catch{self.error=error.localizedDescription}}}
  func savePreset(){let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="Lighting Effects.json";panel.begin{[weak self] result in guard result == .OK,let url=panel.url,let self,!self.closed else{return};do{try self.settings.presetData().write(to:url,options:.atomic)}catch{self.error=error.localizedDescription}}}
}

struct LightingSheet:View {
  @Bindable var store:EditorStore
  @State private var model:LightingWorkspace
  init(store:EditorStore,model:LightingWorkspace?=nil){self.store=store;_model=State(initialValue:model ?? LightingWorkspace())}
  func global(_ key:WritableKeyPath<LightingSettings,Double>)->Binding<Double>{.init(get:{model.settings[keyPath:key]},set:{var s=model.settings;s[keyPath:key]=$0;model.change(s)})}
  func light(_ key:WritableKeyPath<LightingSettings.Light,Double>,scale:Double=1)->Binding<Double>{.init(get:{(model.light?[keyPath:key] ?? 0)*scale},set:{guard var l=model.light else{return};l[keyPath:key]=$0/scale;model.editLight(l)})}
  var body:some View {
    VStack(spacing:12){
      HStack{Text("Lighting Effects").font(.headline);Spacer();if model.rendering{ProgressView().controlSize(.small)};Menu("Presets"){ForEach(LightingSettings.Preset.allCases,id:\.self){preset in Button(preset.title){model.change(preset.settings)}};Divider();Button("Load Preset…"){model.loadPreset()};Button("Save Preset…"){model.savePreset()}}}
      HStack(alignment:.top,spacing:16){
        VStack(alignment:.leading,spacing:8){LightingPreview(model:model).frame(width:440,height:400).accessibilityLabel("Lighting Effects preview");Text("Drag a light or target. Option-drag duplicates; Shift constrains or snaps direction.").font(.caption).foregroundStyle(.secondary);Toggle("Preview",isOn:$model.preview)}
        ScrollView{VStack(alignment:.leading,spacing:10){
          HStack{Text("Lights").font(.headline);Spacer();Menu{ForEach(LightingSettings.Kind.allCases,id:\.self){kind in Button(kind.title){model.add(kind)}}}label:{Image(systemName:"plus")}.disabled(!model.canAdd);Button{_ = model.duplicate(model.selected)}label:{Image(systemName:"plus.square.on.square")}.disabled(!model.canAdd || model.light==nil);Button{model.delete()}label:{Image(systemName:"trash")}.disabled(model.light==nil)}
          ScrollView{VStack(spacing:3){ForEach(model.settings.lights.indices,id:\.self){i in HStack{Button{model.toggle(i)}label:{Image(systemName:model.settings.lights[i].enabled ? "eye":"eye.slash")}.buttonStyle(.borderless);Button{model.select(i)}label:{HStack{Text("\(model.settings.lights[i].kind.title) \(i+1)");Spacer()}}.buttonStyle(.plain)}.padding(4).background(i==model.selected ? Color.accentColor.opacity(0.2):.clear)}}}.frame(height:90)
          if let selected=model.light {
            Picker("Type",selection:Binding(get:{selected.kind},set:{var l=selected;l.kind=$0;model.editLight(l)})){ForEach(LightingSettings.Kind.allCases,id:\.self){Text($0.title).tag($0)}}
            ColorPicker("Light Color",selection:Binding(get:{Color(.sRGBLinear,red:Double(selected.color[0]),green:Double(selected.color[1]),blue:Double(selected.color[2]))},set:{let c=NSColor($0).usingColorSpace(.extendedSRGB) ?? .white;var l=selected;l.color=[SRGBTransfer.linear(Float(c.redComponent)),SRGBTransfer.linear(Float(c.greenComponent)),SRGBTransfer.linear(Float(c.blueComponent))];model.editLight(l)}),supportsOpacity:false)
            slider("Intensity",light(\.intensity),-100...100)
            if selected.kind == .infinite{slider("Direction",light(\.angle),-180...180);slider("Elevation",light(\.elevation),0...90)}else{
              HStack{number("X (%)",light(\.x,scale:100));number("Y (%)",light(\.y,scale:100))};slider("Height",light(\.z),0...10)
              if selected.kind == .spot{HStack{number("Target X (%)",light(\.targetX,scale:100));number("Target Y (%)",light(\.targetY,scale:100))};slider("Cone",light(\.cone),1...89);slider("Hotspot",light(\.hotspot),0...100)}else{slider("Reach",light(\.radius),0.01...10)}
            }
          }
          Divider();Text("Surface").font(.headline)
          slider("Gloss",global(\.gloss),-100...100);slider("Metallic",global(\.metallic),-100...100);slider("Exposure",global(\.exposure),-100...100);slider("Ambience",global(\.ambience),-100...100)
          Picker("Texture",selection:Binding(get:{model.settings.texture},set:{var s=model.settings;s.texture=$0;if $0 == .alphaChannel{s.textureChannelID=store.document.alphaChannels?.first?.id}else{s.textureChannelID=nil};model.change(s)})){ForEach(LightingSettings.Texture.allCases,id:\.self){t in Text(t.title).tag(t).disabled(t == .alphaChannel && (store.document.alphaChannels?.isEmpty ?? true))}}
          if model.settings.texture == .alphaChannel{Picker("Channel",selection:Binding(get:{model.settings.textureChannelID},set:{var s=model.settings;s.textureChannelID=$0;model.change(s)})){ForEach(store.document.alphaChannels ?? []){channel in Text(channel.name).tag(Optional(channel.id))}}}
          slider("Texture Height",global(\.height),0...100);Toggle("White Is High",isOn:Binding(get:{model.settings.whiteIsHigh},set:{var s=model.settings;s.whiteIsHigh=$0;model.change(s)}))
          if store.filterDraft?.filterID != nil{Divider();Picker("Mode",selection:Binding(get:{model.mode},set:{model.blending(opacity:model.opacity,mode:$0)})){ForEach(PhotoCraftCore.BlendMode.allCases,id:\.self){Text($0.rawValue).tag($0)}};slider("Opacity (%)",Binding(get:{Double(model.opacity)*100},set:{model.blending(opacity:Float($0/100),mode:model.mode)}),0...100)}
        }.padding(.trailing,8)}.frame(width:410,height:460)
      }
      if let error=model.error{Text(error).font(.caption).foregroundStyle(.red)}
      HStack{Button("Reset"){model.change(.init())};Button("Undo"){model.undo()}.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command);Button("Redo"){model.redo()}.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift]);Spacer();Button("Cancel"){model.close();store.cancelFilter()}.keyboardShortcut(.cancelAction);Button("OK"){model.endGesture();store.filterDraft?.filter.lighting=model.settings;store.filterDraft?.opacity=model.opacity;store.filterDraft?.blendMode=model.mode;model.close();store.commitFilter()}.disabled(!model.ready).keyboardShortcut(.defaultAction)}
    }.padding(16).frame(width:910).controlSize(.small)
    .task{store.lightingWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft)}
    .onDisappear{model.close();if store.lightingWorkspace === model{store.lightingWorkspace=nil}}
  }
  func slider(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View{VStack(spacing:2){HStack{Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:65).textFieldStyle(.roundedBorder)};Slider(value:value,in:min(range.lowerBound,value.wrappedValue)...max(range.upperBound,value.wrappedValue),onEditingChanged:{if $0{model.beginGesture()}else{model.endGesture()}})}}
  func number(_ title:String,_ value:Binding<Double>)->some View{HStack{Text(title);TextField(title,value:value,format:.number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder)}}
}
