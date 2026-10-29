import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct ShapeToolOptions:View {
  @Bindable var store:EditorStore
  var body:some View {
    Picker("Mode",selection:$store.shapeMode){ForEach(ShapeOutputMode.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}.frame(width:115)
    Picker("Operation",selection:$store.shapeOperation){Text("New Layer").tag(PathOperation?.none);ForEach(PathOperation.allCases.filter{$0 != .join},id:\.self){Text($0.rawValue.capitalized).tag(Optional($0))}}.frame(width:155).disabled(store.shapeMode != .shape)
    if store.tool == .customShape{Picker("Shape",selection:$store.selectedShapeID){Text("Choose…").tag(UUID?.none);ForEach(store.shapes.shapes){Text($0.name).tag(Optional($0.id))}}.frame(width:160)}
    Button("Tool Settings…"){store.beginShapeProperties(editLayer:false)}
    Button("Properties…"){store.beginShapeProperties(editLayer:true)}.disabled(store.activeLayer?.shape == nil)
    Text("⇧ Proportions · ⌥ Center").foregroundStyle(.secondary)
  }
}
struct ShapePaintControls:View {
  let title:String
  @Binding var paint:ShapePaint
  @Bindable var store:EditorStore
  var body:some View {
    GroupBox(title){VStack(alignment:.leading){
      Picker("Paint",selection:Binding(get:{paint.kind},set:{kind in
        paint.kind=kind;paint.gradient=kind == .gradient ? .init():nil
        paint.pattern=kind == .pattern ? (store.patterns.selected.map{.init(patternID:$0.id)}):nil
      })){ForEach(ShapePaint.Kind.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
      if paint.kind == .solid{ColorPicker("Color",selection:Binding(get:{Color(red:Double(paint.color.r),green:Double(paint.color.g),blue:Double(paint.color.b),opacity:Double(paint.color.a))},set:{if let color=NSColor($0).usingColorSpace(.deviceRGB){paint.color=Pixel(Float(color.redComponent),Float(color.greenComponent),Float(color.blueComponent),Float(color.alphaComponent))}}))}
      if paint.kind == .gradient,paint.gradient != nil {
        Menu("Gradient: \(paint.gradient!.gradient.name)"){
          ForEach(Array(store.gradients.state.presets.keys).sorted{$0.uuidString<$1.uuidString},id:\.self){id in
            if let gradient=store.gradients.state.presets[id]?.gradient{Button(gradient.name){paint.gradient?.gradient=(try? gradient.resolved(foreground:store.brush.color,background:.white)) ?? .blackToWhite}}
          }
        }
        Picker("Style",selection:Binding(get:{paint.gradient!.placement.style},set:{paint.gradient?.placement.style=$0})){ForEach(GradientStyle.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        HStack{Text("Angle");TextField("Degrees",value:Binding(get:{paint.gradient!.placement.angle},set:{paint.gradient?.placement.angle=$0}),format:.number);Text("Scale");TextField("Factor",value:Binding(get:{paint.gradient!.placement.scale},set:{paint.gradient?.placement.scale=$0}),format:.number)}
        Toggle("Reverse",isOn:Binding(get:{paint.gradient!.placement.reverse},set:{paint.gradient?.placement.reverse=$0}))
        Toggle("Align with Shape",isOn:Binding(get:{paint.gradient!.aligned},set:{paint.gradient?.aligned=$0}))
      }
      if paint.kind == .pattern,paint.pattern != nil {
        Picker("Pattern",selection:Binding(get:{paint.pattern!.patternID},set:{paint.pattern?.patternID=$0})){ForEach(store.patterns.items){Text($0.displayName).tag($0.id)}}
        HStack{Text("Scale %");TextField("Percent",value:Binding(get:{paint.pattern!.placement.scale},set:{paint.pattern?.placement.scale=$0}),format:.number);Text("Angle");TextField("Degrees",value:Binding(get:{paint.pattern!.placement.angle},set:{paint.pattern?.placement.angle=$0}),format:.number)}
        Toggle("Link with Shape",isOn:Binding(get:{paint.pattern!.linked},set:{paint.pattern?.linked=$0}))
      }
    }.padding(6)}
  }
}
struct ShapeSheet:View {
  @Bindable var store:EditorStore
  @Bindable var draft:ShapeDraft
  var geometry:Binding<ShapeGeometry>{Binding(get:{draft.definition.components[min(draft.component,draft.definition.components.count-1)].geometry},set:{draft.definition.components[min(draft.component,draft.definition.components.count-1)].geometry=$0})}
  var body:some View {
    VStack(alignment:.leading,spacing:12){
      Text(draft.layerID==nil ? "Shape Tool Settings":"Live Shape Properties").font(.headline)
      ScrollView{VStack(alignment:.leading,spacing:12){
        if draft.definition.components.count>1{HStack{
          Picker("Component",selection:$draft.component){ForEach(draft.definition.components.indices,id:\.self){Text("\($0+1): \(draft.definition.components[$0].geometry.kind.rawValue)").tag($0)}}
          Button("Delete"){draft.definition.components.remove(at:draft.component);draft.component=0}
        }}
        Picker("Shape",selection:geometry.kind){ForEach(ShapeGeometry.Kind.allCases,id:\.self){kind in if kind != .custom || geometry.wrappedValue.customPath != nil{Text(kind.rawValue.capitalized).tag(kind)}}}
          .onChange(of:geometry.wrappedValue.kind){_,kind in if kind != .custom{geometry.wrappedValue.customPath=nil}}
        HStack{Text("Width");TextField("Pixels",value:geometry.width,format:.number);Text("Height");TextField("Pixels",value:geometry.height,format:.number)}
        if geometry.wrappedValue.kind == .rectangle{HStack{Text("Corners");ForEach(0..<4,id:\.self){i in TextField(["Top left","Top right","Bottom right","Bottom left"][i],value:Binding(get:{geometry.wrappedValue.radii[i]},set:{geometry.wrappedValue.radii[i]=$0}),format:.number).help(["Top left","Top right","Bottom right","Bottom left"][i])}}}
        if [.triangle,.polygon,.star].contains(geometry.wrappedValue.kind){HStack{
          if geometry.wrappedValue.kind != .triangle{Stepper("Points: \(geometry.wrappedValue.sides)",value:geometry.sides,in:3...100)}
          Text("Corner radius");TextField("Pixels",value:geometry.cornerRadius,format:.number)
        }}
        if geometry.wrappedValue.kind == .star{HStack{Text("Inner radius ratio");Slider(value:geometry.starRatio,in:0.01...1);TextField("Ratio",value:geometry.starRatio,format:.number).frame(width:70)}}
        if geometry.wrappedValue.kind == .line{VStack{HStack{Text("Weight");TextField("Pixels",value:geometry.lineWeight,format:.number);Toggle("Start arrow",isOn:geometry.arrowStart);Toggle("End arrow",isOn:geometry.arrowEnd)};HStack{Text("Arrow width");TextField("Pixels",value:geometry.arrowWidth,format:.number);Text("Length");TextField("Pixels",value:geometry.arrowLength,format:.number);Text("Concavity");TextField("Ratio",value:geometry.arrowConcavity,format:.number)}}}
        if draft.definition.components.count>1{Picker("Combine",selection:Binding(get:{draft.definition.components[draft.component].operation},set:{draft.definition.components[draft.component].operation=$0})){ForEach(PathOperation.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}}
        ShapePaintControls(title:"Fill",paint:$draft.definition.fill,store:store)
        ShapePaintControls(title:"Stroke",paint:$draft.definition.stroke.paint,store:store)
        if draft.definition.stroke.paint.kind != .none{VStack{
          HStack{Text("Width");TextField("Pixels",value:$draft.definition.stroke.width,format:.number);Picker("Align",selection:$draft.definition.stroke.alignment){ForEach(ShapeStroke.Alignment.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}}
          HStack{Picker("Caps",selection:$draft.definition.stroke.cap){ForEach(ShapeStroke.Cap.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}};Picker("Join",selection:$draft.definition.stroke.join){ForEach(ShapeStroke.Join.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}};TextField("Miter limit",value:$draft.definition.stroke.miterLimit,format:.number)}
          HStack{Toggle("Dashed",isOn:Binding(get:{!draft.definition.stroke.dash.isEmpty},set:{draft.definition.stroke.dash=$0 ? [8,4]:[]}));if !draft.definition.stroke.dash.isEmpty{ForEach(draft.definition.stroke.dash.indices,id:\.self){i in TextField("Dash/gap px",value:Binding(get:{draft.definition.stroke.dash[i]},set:{draft.definition.stroke.dash[i]=$0}),format:.number)};TextField("Phase",value:$draft.definition.stroke.phase,format:.number)}}
        }}
      }.padding(4)}.frame(maxHeight:550)
      if let error=draft.error{Text(error).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
      HStack{if draft.layerID != nil{Toggle("Preview",isOn:$draft.preview)};Spacer();Button("Cancel"){store.cancelShapeProperties()}.keyboardShortcut(.cancelAction);Button("OK"){store.commitShapeProperties(draft)}.keyboardShortcut(.defaultAction).disabled(draft.error != nil)}
    }.padding(20).frame(width:600).onChange(of:draft.definition){_,_ in store.refreshShapePreview()}.onChange(of:draft.preview){_,_ in store.refreshShapePreview()}
  }
}
struct ShapesPanel:View {
  @Bindable var store:EditorStore
  @State var name="Custom Shape"
  @State var error:String?
  func attempt(_ work:()throws->Void){do{try work();error=nil}catch{self.error=error.localizedDescription}}
  var body:some View {
    VStack(alignment:.leading){
      Text("Shapes").font(.headline)
      List(store.shapes.shapes,selection:$store.selectedShapeID){shape in HStack{ShapeSwatch(path:shape.path).frame(width:44,height:36);Text(shape.name)}.tag(shape.id)}.frame(minHeight:220)
      TextField("Name",text:$name)
      HStack{Button("Define…"){attempt{_=try store.defineShape(name:name)}};Button("Use"){store.tool = .customShape}.disabled(store.selectedShapeID==nil)}
      HStack{Button("Rename"){attempt{if let id=store.selectedShapeID{try store.shapes.rename(id,name)}}};Button("Delete"){attempt{if let id=store.selectedShapeID{try store.shapes.remove(id);store.selectedShapeID=nil}}}}.disabled(store.selectedShapeID==nil)
      HStack{
        Button("Import…"){let panel=NSOpenPanel();panel.allowedContentTypes=[UTType(filenameExtension:"photatoshapes") ?? .json];panel.begin{result in if result == .OK,let url=panel.url{attempt{try store.shapes.importData(ShapeLibrary.read(url))}}}}
        Button("Export…"){let panel=NSSavePanel();panel.nameFieldStringValue="Shapes.photatoshapes";panel.begin{result in if result == .OK,let url=panel.url{attempt{try store.shapes.export().write(to:url,options:.atomic)}}}}
      }
      if let error=error ?? store.shapes.loadError{Text(error).font(.caption).foregroundStyle(.red)}
    }.padding(12).frame(minWidth:320,minHeight:420).disabled(!store.canDrawShapes)
  }
}
struct ShapeSwatch:View {
  let path:VectorPath
  var body:some View{Canvas{context,size in if let path=try? VectorRasterizer.filledPath(path.transformed(.scale(size.width,size.height))){context.fill(Path(path),with:.color(.primary))}}}
}
struct ShapesPanelRoot:View {
  @Bindable var documents:DocumentWindows
  var body:some View{if let document=documents.activeDocument{ShapesPanel(store:document.store).id(ObjectIdentifier(document.store))}else{Text("Open a document to use shapes.").padding(30)}}
}
@MainActor extension AppDelegate {
  @objc func rasterizeShape(){guard store?.activeLayer?.shape != nil else{return};store?.rasterize()}
  @objc func showShapes(){
    if shapesWindow==nil{let panel=FloatingPanelWindow(contentRect:NSRect(x:160,y:160,width:360,height:460),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false);panel.title="Shapes";panel.isReleasedWhenClosed=false;panel.isFloatingPanel=true;panel.hidesOnDeactivate=true;panel.documents=controller.documentWindows;panel.appearance=NSAppearance(named:.darkAqua);panel.tabbingMode = .disallowed;panel.contentView=NSHostingView(rootView:ShapesPanelRoot(documents:controller.documentWindows));shapesWindow=NSWindowController(window:panel)}
    shapesWindow?.showWindow(nil)
  }
  @objc func defineCustomShape(){guard let store,store.canDrawShapes else{return};let alert=NSAlert();alert.messageText="Shape Name";let field=NSTextField(string:"Custom Shape");field.frame=NSRect(x:0,y:0,width:260,height:24);alert.accessoryView=field;alert.addButton(withTitle:"OK");alert.addButton(withTitle:"Cancel");guard alert.runModal() == .alertFirstButtonReturn else{return};do{_=try store.defineShape(name:field.stringValue);showShapes()}catch{store.error=error.localizedDescription}}
}
