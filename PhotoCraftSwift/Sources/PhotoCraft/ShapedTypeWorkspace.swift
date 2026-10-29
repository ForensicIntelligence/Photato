import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class ShapedTypeWorkspace:Identifiable {
  let id=UUID(),source:CraftDocument,layer:Layer
  var content:TextContent
  var settings:TextGeometry
  var enabled=true
  var preview=true
  var rendering=false
  var image:CGImage?
  var previewDocument:CraftDocument?
  var command:Command?
  var error:String?
  var overset=false
  var undoStates:[TextGeometry]=[]
  var redoStates:[TextGeometry]=[]
  @ObservationIgnored var task:Task<Void,Never>?
  private var generation=0
  var paths:[NamedPath]{source.paths ?? []}
  let toLocal:Transform2D
  init(source:CraftDocument,layer:Layer,mode:TextGeometry.Mode?,path:VectorPath?)throws {
    self.source=source;self.layer=layer
    guard case .text(let original)=layer.content else{throw CraftError.invalid("Select a type layer.")}
    let promoted=original.promoted(dpi:source.pixelsPerInch)
    content=promoted;settings=promoted.typography?.geometry ?? TextGeometry()
    let origin=try NativeTextLayout.metrics(original,dpi:source.pixelsPerInch).origin
    toLocal=try .translation(origin.x,origin.y) * layer.coordinateTransform.inverted()
    if let mode{settings.mode=mode;if [.circle,.arch,.bow,.block].contains(mode){settings.fit=true};if mode == .path || mode == .inside{settings.path=path?.transformed(toLocal)}else{settings.path=nil}}
  }
  var ready:Bool{command != nil && !rendering && error==nil}
  func change(_ next:TextGeometry,remember:Bool=true){if remember && next != settings{undoStates.append(settings);if undoStates.count>100{undoStates.removeFirst()};redoStates=[]};settings=next;refresh()}
  func choose(_ mode:TextGeometry.Mode){var next=settings;next.mode=mode;next.warp=TypeWarp();next.path=(mode == .path || mode == .inside) ? next.path ?? paths.first?.path.transformed(toLocal):nil;next.fit=[.circle,.arch,.bow,.block].contains(mode);change(next)}
  func undo(){guard let old=undoStates.popLast() else{return};redoStates.append(settings);change(old,remember:false)}
  func redo(){guard let next=redoStates.popLast() else{return};undoStates.append(settings);change(next,remember:false)}
  func refresh(){
    task?.cancel();generation += 1;let current=generation;rendering=true;error=nil;command=nil
    var edited=content;edited.typography?.geometry=enabled ? settings:nil
    let text=edited
    let original=source,target=layer
    task=Task{[weak self] in
      do{
        let worker=Task.detached(priority:.userInitiated){() throws ->(Command,CraftDocument,CGImage,Bool) in
          let cmd=try ShapedTextLayout.replacement(target,content:text,document:original);var document=original;try cmd.apply(to:&document)
          let surface=try NativeTextLayout.render(text,document:document),metrics=try NativeTextLayout.metrics(text,dpi:document.pixelsPerInch)
          return(cmd,document,try RasterIO.displayImage(surface),metrics.overset)
        }
        let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
        guard let self,current==self.generation,!Task.isCancelled else{return}
        self.command=result.0;self.previewDocument=result.1;self.image=result.2;self.overset=result.3;self.rendering=false
      }catch{guard let self,current==self.generation,!Task.isCancelled else{return};self.error=error.localizedDescription;self.rendering=false}
    }
  }
  func close(){generation += 1;task?.cancel();task=nil}
}
extension EditorStore {
  func beginShapedType(_ mode:TextGeometry.Mode?=nil){
    if typeEditingDraft != nil,!finishType(){return}
    guard canEditType,let layer=activeLayer,case .text=layer.content else{return}
    do{shapedTypeDraft=try ShapedTypeWorkspace(source:document,layer:layer,mode:mode,path:selectedVectorPath);shapedTypeDraft?.refresh()}catch{self.error=error.localizedDescription}
  }
  func cancelShapedType(){shapedTypeDraft?.close();shapedTypeDraft=nil;render()}
  func commitShapedType(){guard let draft=shapedTypeDraft,draft.ready,let command=draft.command else{return};guard draft.source==document else{draft.error="The document changed. Cancel and reopen this edit.";return};cancelShapedType();perform(command)}
}
struct ShapedTypeSheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:ShapedTypeWorkspace
  func binding<T>(_ key:WritableKeyPath<TextGeometry,T>)->Binding<T>{Binding(get:{model.settings[keyPath:key]},set:{var value=model.settings;value[keyPath:key]=$0;model.change(value)})}
  func number(_ label:String,_ key:WritableKeyPath<TextGeometry,Double>)->some View{HStack{Text(label).frame(width:100,alignment:.leading);TextField(label,value:binding(key),format:.number).textFieldStyle(.roundedBorder)}}
  var body:some View {
    VStack(alignment:.leading,spacing:12){
      Text("Shaped Text").font(.headline)
      HStack(alignment:.top,spacing:18){
        VStack{
          ZStack{Color(nsColor:.white);if let image=model.image{Image(decorative:image,scale:1).resizable().scaledToFit().padding(12)}}.frame(width:400,height:280).accessibilityLabel("Shaped text preview")
          ShapedTextEditor(model:model).frame(width:400,height:100)
          Text("Edit the text here; the preview retains its curve and formatting.").font(.caption).foregroundStyle(.secondary)
        }
        ScrollView{VStack(alignment:.leading,spacing:10){
          Toggle("Enable Layout",isOn:$model.enabled).onChange(of:model.enabled){_,_ in model.refresh()}
          Picker("Layout",selection:Binding(get:{model.settings.mode},set:{model.choose($0)})){ForEach(TextGeometry.Mode.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
          if model.settings.mode == .warp {
            Picker("Style",selection:Binding(get:{model.settings.warp.style},set:{var g=model.settings;g.warp.style=$0;model.change(g)})){ForEach(WarpStyle.allCases.filter{$0 != .custom},id:\.self){Text($0.title).tag($0)}}
            Toggle("Vertical warp axis",isOn:binding(\.warp.vertical))
            number("Bend %",\.warp.bend);number("Horizontal %",\.warp.horizontalDistortion);number("Vertical %",\.warp.verticalDistortion)
          }else{
            if [.path,.inside].contains(model.settings.mode){Menu("Use saved path"){ForEach(model.paths){path in Button(path.name){var g=model.settings;g.path=path.path.transformed(model.toLocal);model.change(g)}}}.disabled(model.paths.isEmpty)}
            else{number("Width (px)",\.width);number("Height (px)",\.height)}
            Toggle("Dynamic Fit",isOn:binding(\.fit))
            if [.path,.circle,.arch,.bow].contains(model.settings.mode){number("Start (0–1)",\.start);number("End (0–1)",\.end);number("Baseline (px)",\.offset);Toggle("Reverse direction",isOn:binding(\.reverse))}
            else{number("Word spacing",\.wordSpacing);number("Line spacing",\.lineSpacing)}
          }
          HStack{Button("Undo Layout"){model.undo()}.disabled(model.undoStates.isEmpty);Button("Redo"){model.redo()}.disabled(model.redoStates.isEmpty)}
        }.frame(width:270)}.frame(height:400)
      }
      if model.overset{Label("Some text does not fit. Enable Dynamic Fit or enlarge the layout.",systemImage:"plus.square").foregroundStyle(.orange)}
      if let error=model.error{Text(error).foregroundStyle(.red).textSelection(.enabled)}
      HStack{Toggle("Preview on canvas",isOn:$model.preview).onChange(of:model.preview){_,_ in store.render()};if model.rendering{ProgressView().controlSize(.small)};Spacer();Button("Cancel"){store.cancelShapedType()}.keyboardShortcut(.cancelAction);Button("OK"){store.commitShapedType()}.keyboardShortcut(.defaultAction).disabled(!model.ready)}
    }.padding(20).onChange(of:model.rendering){_,running in if !running{store.render()}}.onDisappear{model.close()}
  }
}
private final class ShapedEditorView:NSTextView {
  let localUndo=UndoManager()
  override var undoManager:UndoManager?{localUndo}
}
private struct ShapedTextEditor:NSViewRepresentable {
  let model:ShapedTypeWorkspace
  func makeCoordinator()->Coordinator{Coordinator(model)}
  func makeNSView(context:Context)->NSScrollView {
    let scroll=NSScrollView();scroll.hasVerticalScroller=true
    let view=ShapedEditorView(frame:.init(x:0,y:0,width:400,height:100));view.backgroundColor = .white;view.textColor = .black;view.isRichText=true;view.importsGraphics=false;view.allowsUndo=true;view.isVerticallyResizable=true;view.isHorizontallyResizable=false;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true;view.textContainer?.containerSize=NSSize(width:400,height:32768)
    view.textStorage?.setAttributedString((try? NativeTextLayout.attributed(model.content,dpi:model.source.pixelsPerInch)) ?? NSAttributedString(string:model.content.text))
    view.delegate=context.coordinator;view.setAccessibilityLabel("Shaped text content");scroll.documentView=view;return scroll
  }
  func updateNSView(_ view:NSScrollView,context:Context){}
  @MainActor final class Coordinator:NSObject,NSTextViewDelegate {
    let model:ShapedTypeWorkspace
    init(_ model:ShapedTypeWorkspace){self.model=model}
    func textDidChange(_ notification:Notification){guard let view=notification.object as? NSTextView,let storage=view.textStorage else{return};do{model.content=try NativeTextLayout.content(storage,template:model.content,dpi:model.source.pixelsPerInch);model.refresh()}catch{model.error=error.localizedDescription}}
  }
}
@MainActor extension AppDelegate {@objc func warpType(){store?.beginShapedType(.warp)}}
