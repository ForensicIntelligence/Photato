import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class DistortionWorkspace {
  var filter=RasterFilter(.wave)
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var rendering=false
  var fit=true
  var zoom=1.0
  var importing=false
  @ObservationIgnored var importTask:Task<Void,Never>?
  var error:String?
  var undoStates=[RasterFilter]()
  var redoStates=[RasterFilter]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var closed=false
  private var generation=0
  private var gestureStart:RasterFilter?
  var ready:Bool { image != nil && !rendering && !importing && error == nil }
  var apiState:[String:Any] {
    ["filter":filter.apiState,"preview":preview,"zoom":zoom,"fit":fit,"importing":importing,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()] }
  func prepare(document:CraftDocument,draft:FilterDraft) async { self.document=document;self.draft=draft;filter=draft.filter;closed=false;refresh();await task?.value }
  func remember(_ f:RasterFilter) { undoStates.append(f);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ f:RasterFilter,remember:Bool=true) {
    do { guard let settings=f.distortion else { throw CraftError.invalid("Missing distortion settings.") };try settings.validate(kind:f.kind,requireMap:false);guard f.kind==filter.kind else { throw CraftError.invalid("Cannot change distortion workspace kind.") } } catch { self.error=error.localizedDescription;return }
    guard f != filter else{if error != nil {refresh()};return};if remember && gestureStart==nil { self.remember(filter) };filter=f;refresh()
  }
  func update(_ edit:(inout RasterFilter)->Void) { var f=filter;edit(&f);change(f) }
  func beginGesture() { if gestureStart==nil { gestureStart=filter } }
  func endGesture() { if let old=gestureStart,old != filter { remember(old) };gestureStart=nil }
  func undo() { endGesture();guard let f=undoStates.popLast() else{return};redoStates.append(filter);change(f,remember:false) }
  func redo() { endGesture();guard let f=redoStates.popLast() else{return};undoStates.append(filter);change(f,remember:false) }
  func refresh() {
    guard !closed,let document,var draft else{return};task?.cancel();generation+=1;let token=generation,needOriginal=originalImage==nil
    draft.filter=filter;let request=draft;rendering=true;error=nil
    task=Task { [weak self] in
      do { try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { ()throws->(CGImage,CGImage?) in
          var edited=document;if request.filter.kind != .displace || request.filter.distortion?.hasDisplacementMap == true { try request.command(in:document).apply(to:&edited) }
          return (try ColorManagement.displayImage(Renderer.composite(edited),in:document),needOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,!self.closed,self.generation==token else{return};self.image=result.0;if let image=result.1 { self.originalImage=image };self.rendering=false;if self.filter.kind == .displace && self.filter.distortion?.hasDisplacementMap != true { self.error="Choose a displacement map." }
      } catch { guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func loadMap(_ url:URL) async {
    guard !closed,filter.kind == .displace else{return}
    importing=true;error=nil
    do {
      let isSource=filter.distortion?.source != nil
      let worker=Task.detached(priority:.userInitiated) { ()throws->(DisplacementMap?,FloatDisplacementMap?) in
        if isSource{return(nil,try Self.readFloatMap(url))};return(try Self.readMap(url),nil)
      }
      let map=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
      try Task.checkCancellation();guard !closed else{return};importing=false;update{if var source=$0.distortion?.source{source.map=map.1;$0.distortion?.source=source}else{$0.distortion?.map=map.0}}
    } catch { if !closed { importing=false;self.error=error.localizedDescription } }
  }
  nonisolated static func readMap(_ url:URL)throws->DisplacementMap {
    let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
    guard url.isFileURL,size<=64*1024*1024 else{throw CraftError.invalid("Choose a local displacement image up to64 MiB.")}
    let data=try Data(contentsOf:url),document=try DocumentIO.decode(data,native:DocumentIO.isNativeFile(url),name:url.lastPathComponent,rasterByteLimit:64*1024*1024)
    guard document.width<=DisplacementMap.maximumPixels/document.height else {throw CraftError.invalid("Displacement maps support up to1,048,576 pixels.")}
    let pixels=try Renderer.composite(document);var red=[UInt8](),green=[UInt8](),gray=true
    red.reserveCapacity(document.width*document.height);green.reserveCapacity(document.width*document.height)
    for y in 0..<document.height {try Task.checkCancellation();for x in 0..<document.width {
      let p=pixels.pixel(x:x,y:y);guard p.isFinite else{throw CraftError.invalid("Nonfinite displacement map.")}
      func byte(_ v:Float)->UInt8 {UInt8((min(1,max(0,v))*255).rounded())}
      let r=byte(p.r),g=byte(p.g),b=byte(p.b);red.append(r);green.append(g);if r != g || r != b{gray=false}
    }}
    var samples=Data();samples.reserveCapacity(red.count*(gray ? 1:2))
    for i in red.indices {samples.append(red[i]);if !gray {samples.append(green[i])}}
    let map=DisplacementMap(width:document.width,height:document.height,channels:gray ? 1:2,samples:samples,name:String(url.lastPathComponent.prefix(80)));try map.validate();return map
  }
  nonisolated static func readFloatMap(_ url:URL)throws->FloatDisplacementMap {
    guard url.isFileURL else{throw CraftError.invalid("Choose a local displacement map.")}
    let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? Int.max
    guard url.isFileURL,size<=64*1024*1024 else{throw CraftError.invalid("Choose a local displacement image up to64MiB.")}
    let data=try Data(contentsOf:url),document=try DocumentIO.decode(data,native:DocumentIO.isNativeFile(url),name:url.lastPathComponent,rasterByteLimit:64*1024*1024)
    guard document.width<=FloatDisplacementMap.maximumPixels/document.height else{throw CraftError.unsupported("Displacement maps retain their1,048,576-pixel limit.")}
    return try FloatDisplacementMap.read(Renderer.composite(document),name:url.lastPathComponent)
  }
  func chooseMap() {
    let panel=NSOpenPanel();panel.title="Choose Displacement Map";panel.allowsMultipleSelection=false;panel.canChooseDirectories=false;panel.allowedContentTypes=DocumentIO.readableContentTypes
    panel.begin { [weak self] response in guard response == .OK,let url=panel.url,let self,!self.closed else{return};self.importTask?.cancel();self.importTask=Task { [weak self] in await self?.loadMap(url) } }
  }
  func close() { importTask?.cancel();importTask=nil;importing=false;closed=true;generation+=1;task?.cancel();task=nil;rendering=false }
}

struct DistortionSheet:View {
  @Bindable var store:EditorStore
  @State private var model:DistortionWorkspace
  @State private var selectedPoint=0
  @State private var draggingPoint:Int?
  init(store:EditorStore,model:DistortionWorkspace?=nil) {self.store=store;_model=State(initialValue:model ?? DistortionWorkspace())}
  var settings:DistortionSettings {model.filter.distortion ?? .init(kind:.wave)}
  var body:some View {
    VStack(spacing:12) {
      HStack {Text(model.filter.kind.title).font(.headline);Spacer();if model.rendering || model.importing {ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView {VStack(alignment:.leading,spacing:12) {
          controls
          if [.displace,.wave,.shear].contains(model.filter.kind) {
            Divider();Picker("Undefined Areas",selection:choice(\.edge)) {ForEach(DistortionSettings.Edge.allCases,id:\.self){Text($0.title).tag($0)}}.pickerStyle(.radioGroup)
          }
          Divider();Button("Reset") {var f=RasterFilter(model.filter.kind);f.distortion?.map=settings.map;f.distortion?.source=settings.source;model.change(f)}
        }.padding(.trailing,5)}.frame(width:275)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−"){model.fit=false;model.zoom=max(0.125,model.zoom/1.5)};Button("+"){model.fit=false;model.zoom=min(8,model.zoom*1.5)}
        Button("100%") {model.fit=false;model.zoom=1};Button("Fit"){model.fit=true}
        Button("Undo"){model.undo()}.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo"){model.redo()}.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel"){model.close();store.cancelFilter()}.keyboardShortcut(.cancelAction)
        Button("OK"){model.endGesture();store.filterDraft?.filter=model.filter;model.close();store.commitFilter()}.disabled(!model.ready).keyboardShortcut(.defaultAction)
      }.controlSize(.small)
      if let error=model.error {Text(error).foregroundStyle(.red).font(.caption)}
    }.padding(16).frame(width:840,height:620)
    .task {store.distortionWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft)}
    .onDisappear {model.close();if store.distortionWorkspace === model {store.distortionWorkspace=nil}}
  }
  var preview:some View {
    GeometryReader {g in ScrollView([.horizontal,.vertical]) {
      if let image=model.preview ? model.image:model.originalImage {
        let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
        Image(decorative:image,scale:1).resizable().interpolation(.none).frame(width:Double(image.width)*scale,height:Double(image.height)*scale).padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
      }
    }.background(Color(white:0.12)).accessibilityLabel("Distortion preview")}
  }
  func choice<T>(_ key:WritableKeyPath<DistortionSettings,T>)->Binding<T> {
    Binding(get:{settings[keyPath:key]},set:{v in model.update{$0.distortion?[keyPath:key]=v}})
  }
  func number(_ title:String,_ key:WritableKeyPath<DistortionSettings,Double>,_ range:ClosedRange<Double>)->some View {
    numeric(title,choice(key),range)
  }
  func numeric(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
    VStack(spacing:3) {
      HStack{Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(0...((model.filter.kind == .displace && settings.source != nil) ? 8:0)))).frame(width:65).textFieldStyle(.roundedBorder)}
      Slider(value:value,in:range,step:(model.filter.kind == .displace && settings.source != nil) ? 0.01:1,onEditingChanged:{editing in if editing{model.beginGesture()}else{model.endGesture()}}).accessibilityLabel(title)
    }
  }
  @ViewBuilder var controls:some View {
    switch model.filter.kind {
    case .displace:
      number("Horizontal Scale",\.horizontalScale,-999...999);number("Vertical Scale",\.verticalScale,-999...999)
      Picker("Displacement Map",selection:choice(\.fit)){Text("Stretch To Fit").tag(DistortionSettings.Fit.stretchToFit);Text("Tile").tag(DistortionSettings.Fit.tile)}.pickerStyle(.radioGroup)
      Button(settings.hasDisplacementMap ? "Replace Map…":"Choose Map…"){model.chooseMap()}.disabled(model.importing)
      if let map=settings.map {Text(map.name).lineLimit(2);Text("\(map.width) × \(map.height) · \(map.channels) channel(s)").font(.caption).foregroundStyle(.secondary)}
      if let source=settings.source {
        Text(source.map==nil ? "Original map required":"Original map bound").font(.caption).foregroundStyle(source.map==nil ? .orange:.secondary)
        Text(source.reference.label).font(.caption).lineLimit(3).textSelection(.enabled)
        if let map=source.map {Text(map.name).lineLimit(2);Text("\(map.width) × \(map.height) · Float32 · \(map.channels) channel(s)").font(.caption).foregroundStyle(.secondary)}
        Text(source.map==nil ? "Choose the map image used for this filter.":"The chosen map is saved with this document.").font(.caption).foregroundStyle(.secondary)
      }

    case .wave:
      numeric("Number of Generators",Binding(get:{Double(settings.generators)},set:{v in guard v.isFinite,(1...999).contains(v) else{return};model.update{$0.distortion?.generators=Int(v.rounded())}}),1...999)
      Picker("Type",selection:choice(\.waveType)){ForEach(DistortionSettings.Wave.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
      number("Wavelength Min.",\.wavelengthMin,1...998);number("Wavelength Max.",\.wavelengthMax,2...999)
      number("Amplitude Min.",\.amplitudeMin,1...998);number("Amplitude Max.",\.amplitudeMax,2...999)
      number("Horizontal Scale (%)",\.horizontalScale,1...100);number("Vertical Scale (%)",\.verticalScale,1...100)
      Button("Randomize"){model.update{$0.distortion?.seed=UInt32.random(in:.min ... .max)}}
    case .shear: shearControls
    case .twirl:number("Angle",\.angle,-999...999)
    case .pinch:number("Amount (%)",\.amount,-100...100)
    case .spherize:
      number("Amount (%)",\.amount,-100...100)
      Picker("Mode",selection:choice(\.sphereMode)){Text("Normal").tag(DistortionSettings.Sphere.normal);Text("Horizontal Only").tag(DistortionSettings.Sphere.horizontalOnly);Text("Vertical Only").tag(DistortionSettings.Sphere.verticalOnly)}
    case .ripple:
      number("Amount (%)",\.amount,-999...999)
      Picker("Size",selection:choice(\.rippleSize)){ForEach(DistortionSettings.Ripple.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
    case .polarCoordinates:
      Picker("Conversion",selection:choice(\.polarMode)){Text("Rectangular to Polar").tag(DistortionSettings.Polar.rectangularToPolar);Text("Polar to Rectangular").tag(DistortionSettings.Polar.polarToRectangular)}.pickerStyle(.radioGroup)
    case .zigzag:
      number("Amount (%)",\.amount,-100...100);number("Ridges",\.ridges,0...20)
      Picker("Style",selection:choice(\.zigzagStyle)){Text("Around Center").tag(DistortionSettings.ZigZag.aroundCenter);Text("Out From Center").tag(DistortionSettings.ZigZag.outFromCenter);Text("Pond Ripples").tag(DistortionSettings.ZigZag.pondRipples)}
    default:EmptyView()
    }
  }
  var shearControls:some View {
    VStack(alignment:.leading,spacing:10) {
      Text("Shear Curve").font(.headline)
      Canvas {ctx,size in
        var grid=Path();for i in 0...4 {let t=Double(i)/4;grid.move(to:CGPoint(x:t*size.width,y:0));grid.addLine(to:CGPoint(x:t*size.width,y:size.height));grid.move(to:CGPoint(x:0,y:t*size.height));grid.addLine(to:CGPoint(x:size.width,y:t*size.height))};ctx.stroke(grid,with:.color(.gray.opacity(0.4)),lineWidth:1)
        var curve=Path();for i in 0...160 {let t=Double(i)/160,x=(DistortionEngine.curve(settings.points,at:t)+1)/2*size.width,q=CGPoint(x:x,y:t*size.height);if i==0{curve.move(to:q)}else{curve.addLine(to:q)}};ctx.stroke(curve,with:.color(.accentColor),lineWidth:2)
        for (i,p) in settings.points.enumerated(){let rect=CGRect(x:(p.offset+1)/2*size.width-4,y:p.position*size.height-4,width:8,height:8);ctx.fill(Path(ellipseIn:rect),with:.color(i==selectedPoint ? .orange:.primary))}
      }.frame(width:250,height:210).background(.quaternary).clipped().contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:0).onChanged{e in dragCurve(e)}.onEnded{_ in model.endGesture();draggingPoint=nil})
        .accessibilityLabel("Shear curve. Click to add a point; drag to change the curve. Numeric point controls follow.")
      Picker("Point",selection:$selectedPoint){ForEach(settings.points.indices,id:\.self){Text("Point \($0+1)").tag($0)}}
      if settings.points.indices.contains(selectedPoint) {
        numeric("Offset (%)",Binding(get:{settings.points[selectedPoint].offset*100},set:{v in model.update{$0.distortion?.points[selectedPoint].offset=min(1,max(-1,v/100))}}),-100...100)
        HStack {Button("Add Point"){let pts=settings.points;guard pts.count<64 else{return};let gap=(0..<(pts.count-1)).max{pts[$0+1].position-pts[$0].position<pts[$1+1].position-pts[$1].position} ?? 0;var f=model.filter;f.distortion?.points.insert(.init((pts[gap].position+pts[gap+1].position)/2,0),at:gap+1);model.change(f);selectedPoint=gap+1};Button("Remove"){model.update{$0.distortion?.points.remove(at:selectedPoint)};selectedPoint=0}.disabled(selectedPoint==0 || selectedPoint>=settings.points.count-1)}
      }
    }
  }
  func dragCurve(_ e:DragGesture.Value) {
    if draggingPoint==nil {
      model.beginGesture();let p=e.startLocation
      if let i=settings.points.indices.min(by:{a,b in hypot((settings.points[a].offset+1)*125-p.x,settings.points[a].position*210-p.y)<hypot((settings.points[b].offset+1)*125-p.x,settings.points[b].position*210-p.y)}),hypot((settings.points[i].offset+1)*125-p.x,settings.points[i].position*210-p.y)<12 {draggingPoint=i}
      else if settings.points.count<64 {let t=min(0.999,max(0.001,p.y/210));if settings.points.allSatisfy({abs($0.position-t)>0.000001}) {let i=settings.points.firstIndex{$0.position>t} ?? 1;model.update{$0.distortion?.points.insert(.init(t,0),at:i)};draggingPoint=i}}
    }
    guard let i=draggingPoint,settings.points.indices.contains(i) else{return};selectedPoint=i
    model.update {f in f.distortion?.points[i].offset=min(1,max(-1,e.location.x/125-1));if i>0 && i<settings.points.count-1 {f.distortion?.points[i].position=min(settings.points[i+1].position-0.00001,max(settings.points[i-1].position+0.00001,e.location.y/210))}}
  }
}
