import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class RelightWorkspace {
  nonisolated static let maximumPreviewSide=192
  struct State:Equatable {var settings:RelightSettings;var opacity:Float;var mode:PhotoCraftCore.BlendMode}
  var settings=RelightSettings()
  var opacity:Float=1
  var mode:PhotoCraftCore.BlendMode = .normal
  var state:State{.init(settings:settings,opacity:opacity,mode:mode)}
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var rendering=false
  var error:String?
  var undoStates=[State]()
  var redoStates=[State]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var generation=0
  private var closed=false
  private var input:Surface?
  private var reference:(Int,Int)=(1,1)
  private var document:CraftDocument?
  private var gestureStart:State?
  var ready:Bool{image != nil && !rendering && error==nil}
  var apiState:[String:Any]{["settings":BrushAPI.json(settings),"preview":preview,"opacity":opacity,"blendMode":mode.rawValue,"rendering":rendering,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"maximumPreviewSide":Self.maximumPreviewSide,"error":error as Any? ?? NSNull()]}
  func prepare(document:CraftDocument,draft:FilterDraft)async {
    close();closed=false;input=nil;image=nil;originalImage=nil;undoStates=[];redoStates=[];gestureStart=nil;preview=true;settings=draft.filter.relight ?? .init();opacity=draft.opacity;mode=draft.blendMode;self.document=document;rendering=true;error=nil;generation+=1;let token=generation
    task=Task{[weak self] in
      do {
        let worker=Task.detached(priority:.userInitiated){()throws->(Surface,(Int,Int)) in
          let layer=try draft.inputLayer(in:document),source=try Renderer.layerSurface(layer,in:document)
          let scale=max(1,Double(max(source.width,source.height))/Double(Self.maximumPreviewSide)),width=max(1,Int(Double(source.width)/scale)),height=max(1,Int(Double(source.height)/scale))
          var small=try Surface(width:width,height:height,depth:source.depth)
          for y in 0..<height{try Task.checkCancellation();for x in 0..<width{
            let xx=min(source.width-1,Int((Double(x)+0.5)*scale)),yy=min(source.height-1,Int((Double(y)+0.5)*scale)),p=source.depth == .f32 ? source.linearPixel(x:xx,y:yy):source.pixel(x:xx,y:yy)
            if source.depth == .f32{small.setLinearPixel(x:x,y:y,p)}else{small.setPixel(x:x,y:y,p)}
          }}
          return (small,(max(1,Int(Double(document.width)/scale)),max(1,Int(Double(document.height)/scale))))
        }
        let result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,!self.closed,self.generation==token else{return};self.input=result.0;self.reference=result.1;self.originalImage=try ColorManagement.displayImage(result.0,in:document);self.refresh()
      }catch{guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled{self.error=error.localizedDescription}}
    };await task?.value;await task?.value
  }
  func change(_ value:RelightSettings,remember:Bool=true){
    do{try value.validate()}catch{self.error=error.localizedDescription;return}
    guard value != settings else{if error != nil{error=nil;refresh()};return};if remember && gestureStart==nil{undoStates.append(state);if undoStates.count>100{undoStates.removeFirst()};redoStates=[]};settings=value;refresh()
  }
  func beginGesture(){if gestureStart==nil{gestureStart=state}}
  func endGesture(){if let old=gestureStart,old != state{undoStates.append(old);redoStates=[]};gestureStart=nil}
  func undo(){endGesture();guard let value=undoStates.popLast() else{return};redoStates.append(state);settings=value.settings;opacity=value.opacity;mode=value.mode;refresh()}
  func redo(){endGesture();guard let value=redoStates.popLast() else{return};undoStates.append(state);settings=value.settings;opacity=value.opacity;mode=value.mode;refresh()}
  func blending(opacity:Float,mode:PhotoCraftCore.BlendMode){guard opacity.isFinite,(0...1).contains(opacity) else{return};guard opacity != self.opacity || mode != self.mode else{return};if gestureStart==nil{undoStates.append(state);redoStates=[]};self.opacity=opacity;self.mode=mode;refresh()}
  func refresh(){
    guard !closed,let input,let document else{return};task?.cancel();generation+=1;let token=generation,value=settings,size=reference,opacity=opacity,mode=mode;rendering=true;error=nil
    task=Task{[weak self] in
      do{try await Task.sleep(for:.milliseconds(60));let worker=Task.detached(priority:.userInitiated){()throws->CGImage in
          var rendered=try RelightEngine.render(input,settings:value,canvasWidth:size.0,canvasHeight:size.1)
          if opacity != 1 || mode != .normal{for y in 0..<input.height{try Task.checkCancellation();for x in 0..<input.width{
            let a=input.depth == .f32 ? input.linearPixel(x:x,y:y):input.pixel(x:x,y:y),b=rendered.depth == .f32 ? rendered.linearPixel(x:x,y:y):rendered.pixel(x:x,y:y),p=mode.composite(backdrop:a,source:b,opacity:opacity,x:x,y:y)
            if rendered.depth == .f32{rendered.setLinearPixel(x:x,y:y,p)}else{rendered.setPixel(x:x,y:y,p)}
          }}};return try ColorManagement.displayImage(rendered,in:document)
        }
        let result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation();guard let self,!self.closed,self.generation==token else{return};self.image=result;self.rendering=false
      }catch{guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled{self.error=error.localizedDescription}}
    }
  }
  func close(){closed=true;generation+=1;task?.cancel();task=nil;rendering=false}
}

struct RelightSheet:View {
  @Bindable var store:EditorStore
  @State private var model:RelightWorkspace
  init(store:EditorStore,model:RelightWorkspace?=nil){self.store=store;_model=State(initialValue:model ?? RelightWorkspace())}
  func value(_ key:WritableKeyPath<RelightSettings,Double>)->Binding<Double>{.init(get:{model.settings[keyPath:key]},set:{var s=model.settings;s[keyPath:key]=$0;model.change(s)})}
  var body:some View {
    VStack(spacing:14){
      HStack{Text("Relight").font(.headline);Spacer();if model.rendering{ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:18){
        Group{if let image=model.preview ? model.image:model.originalImage{Image(decorative:image,scale:1).resizable().interpolation(.high).scaledToFit()}else{Color(white:0.15)}}.frame(width:380,height:340).background(Color(white:0.12)).accessibilityLabel("Relight preview")
        VStack(alignment:.leading,spacing:12){
          control(0,\.angle);control(1,\.elevation);control(2,\.intensity);control(3,\.ambient);control(4,\.warmth);control(5,\.softness)
          if store.filterDraft?.filterID != nil {
            Divider();Picker("Mode",selection:Binding(get:{model.mode},set:{model.blending(opacity:model.opacity,mode:$0)})){ForEach(PhotoCraftCore.BlendMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
            HStack{Text("Opacity");Slider(value:Binding(get:{Double(model.opacity)},set:{model.blending(opacity:Float($0),mode:model.mode)}),in:0...1,onEditingChanged:{if $0{model.beginGesture()}else{model.endGesture()}});Text("\(Int(model.opacity*100))%")}
          }
          Button("Reset"){model.change(.init())};Text("Processed locally. Preview is scaled to fit.").font(.caption).foregroundStyle(.secondary)
        }.frame(width:270)
      }
      if let error=model.error{Text(error).foregroundStyle(.red).font(.caption)}
      HStack{Toggle("Preview",isOn:$model.preview);Button("Undo"){model.undo()}.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command);Button("Redo"){model.redo()}.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.shift,.command]);Spacer();Button("Cancel"){model.close();store.cancelFilter()}.keyboardShortcut(.cancelAction);Button("OK"){model.endGesture();store.filterDraft?.filter.relight=model.settings;store.filterDraft?.opacity=model.opacity;store.filterDraft?.blendMode=model.mode;model.close();store.commitFilter()}.disabled(!model.ready).keyboardShortcut(.defaultAction)}.controlSize(.small)
    }.padding(16).frame(width:720)
    .task{store.relightWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft)}
    .onDisappear{model.close();if store.relightWorkspace === model{store.relightWorkspace=nil}}
  }
  func control(_ index:Int,_ key:WritableKeyPath<RelightSettings,Double>)->some View {
    let p=RelightSettings.controls[index]
    return VStack(spacing:3){HStack{Text(p.title);Spacer();TextField(p.title,value:value(key),format:.number.precision(.fractionLength(0...2))).frame(width:62).textFieldStyle(.roundedBorder)};Slider(value:value(key),in:p.bounds,onEditingChanged:{if $0{model.beginGesture()}else{model.endGesture()}}).accessibilityLabel(p.title)}
  }
}
