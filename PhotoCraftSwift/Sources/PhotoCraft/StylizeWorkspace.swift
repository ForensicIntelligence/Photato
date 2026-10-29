import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class StylizeWorkspace {
  var filter=RasterFilter(.diffuse)
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var rendering=false
  var fit=true
  var zoom=1.0
  var error:String?
  var undoStates=[RasterFilter]()
  var redoStates=[RasterFilter]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var closed=false
  private var generation=0
  private var gestureStart:RasterFilter?
  var ready:Bool { image != nil && !rendering && error == nil }
  var apiState:[String:Any] {
    ["filter":filter.apiState,"preview":preview,"zoom":zoom,"fit":fit,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()] }
  func prepare(document:CraftDocument,draft:FilterDraft) async { self.document=document;self.draft=draft;filter=draft.filter;closed=false;refresh();await task?.value }
  func remember(_ f:RasterFilter) { undoStates.append(f);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ f:RasterFilter,remember:Bool=true) {
    do { guard f.kind.isStylize else {throw CraftError.invalid("Missing Stylize kind.")};try f.validate();guard f.kind==filter.kind else { throw CraftError.invalid("Cannot change Stylize workspace kind.") } } catch { self.error=error.localizedDescription;return }
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
          var edited=document;try request.command(in:document).apply(to:&edited)
          return (try ColorManagement.displayImage(Renderer.composite(edited),in:document),needOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,!self.closed,self.generation==token else{return};self.image=result.0;if let image=result.1 { self.originalImage=image };self.rendering=false
      } catch { guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation+=1;task?.cancel();task=nil;rendering=false }
}

struct StylizeSheet: View {
  @Bindable var store: EditorStore
  @State private var model: StylizeWorkspace
  init(store:EditorStore,model:StylizeWorkspace?=nil) {self.store=store;_model=State(initialValue:model ?? StylizeWorkspace())}
  var settings:StylizeSettings {model.filter.stylize ?? .init(kind:.diffuse)}
  var body: some View {
    VStack(spacing:12) {
      HStack {Text(model.filter.kind.title).font(.headline);Spacer();if model.rendering {ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView { VStack(alignment:.leading,spacing:14) {
          controls
          if !model.filter.kind.isImmediateStylize {
            Divider();Button("Reset") {var f=RasterFilter(model.filter.kind);f.stylize?.background=settings.background;f.stylize?.foreground=settings.foreground;model.change(f)}
          }
        }.padding(.trailing,5)}.frame(width:275)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−"){model.fit=false;model.zoom=max(0.125,model.zoom/1.5)}
        Button("+"){model.fit=false;model.zoom=min(8,model.zoom*1.5)}
        Button("100%"){model.fit=false;model.zoom=1};Button("Fit"){model.fit=true}
        Button("Undo"){model.undo()}.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo"){model.redo()}.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel"){model.close();store.cancelFilter()}.keyboardShortcut(.cancelAction)
        Button("OK"){model.endGesture();store.filterDraft?.filter=model.filter;model.close();store.commitFilter()}.disabled(!model.ready).keyboardShortcut(.defaultAction)
      }.controlSize(.small)
      if let error=model.error {Text(error).foregroundStyle(.red).font(.caption)}
    }.padding(16).frame(width:840,height:620)
    .task {store.stylizeWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft)}
    .onDisappear {model.close();if store.stylizeWorkspace === model {store.stylizeWorkspace=nil}}
  }
  var preview: some View {
    GeometryReader {g in ScrollView([.horizontal,.vertical]) {
      if let image=model.preview ? model.image:model.originalImage {
        let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
        Image(decorative:image,scale:1).resizable().interpolation(.none).frame(width:Double(image.width)*scale,height:Double(image.height)*scale).padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
      }
    }.background(Color(white:0.12)).clipped().accessibilityLabel("Stylize preview")}
  }
  func choice<T>(_ key:WritableKeyPath<StylizeSettings,T>)->Binding<T> {
    Binding(get:{settings[keyPath:key]},set:{value in model.update{$0.stylize?[keyPath:key]=value}})
  }
  func number(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,step:Double=1)->some View {
    VStack(spacing:4) {
      HStack {Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(step<1 ? 1:0))).frame(width:65).textFieldStyle(.roundedBorder)}
      Slider(value:value,in:range,step:step,onEditingChanged:{editing in if editing {model.beginGesture()} else {model.endGesture()}}).accessibilityLabel(title)
    }
  }
  func color(_ key:WritableKeyPath<StylizeSettings,Pixel>)->Binding<Color> {
    Binding(get:{let p=settings[keyPath:key];return Color(red:Double(p.r),green:Double(p.g),blue:Double(p.b))},set:{value in
      guard let c=NSColor(value).usingColorSpace(.sRGB) else{return}
      model.update{$0.stylize?[keyPath:key]=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent))}
    })
  }
  @ViewBuilder var controls:some View {
    switch model.filter.kind {
    case .diffuse:
      Picker("Mode",selection:choice(\.mode)){ForEach(StylizeSettings.DiffuseMode.allCases,id:\.self){Text($0.title).tag($0)}}.pickerStyle(.radioGroup)
      randomize
    case .emboss:
      number("Angle (degrees)",choice(\.angle),-180...180)
      number("Height (pixels)",choice(\.height),1...100)
      number("Amount (%)",choice(\.amount),1...500)
    case .extrude:
      Picker("Type",selection:choice(\.type)){ForEach(StylizeSettings.ExtrudeType.allCases,id:\.self){Text($0.title).tag($0)}}.pickerStyle(.radioGroup)
      number("Size (pixels)",choice(\.size),2...255);number("Depth",choice(\.depth),1...255)
      Picker("Depth",selection:choice(\.depthMode)){ForEach(StylizeSettings.DepthMode.allCases,id:\.self){Text($0.title).tag($0)}}.pickerStyle(.radioGroup)
      Toggle("Solid Front Faces",isOn:choice(\.solidFrontFaces)).disabled(settings.type == .pyramids)
      Toggle("Mask Incomplete Blocks",isOn:choice(\.maskIncompleteBlocks))
      randomize.disabled(settings.depthMode == .levelBased)
    case .oilPaint:
      Text("Brush").font(.headline)
      number("Stylization",choice(\.stylization),0...10,step:0.1)
      number("Cleanliness",choice(\.cleanliness),0...10,step:0.1)
      number("Scale",choice(\.scale),0...10,step:0.1)
      number("Bristle Detail",choice(\.bristleDetail),0...10,step:0.1)
      Toggle("Lighting",isOn:choice(\.lighting))
      number("Angle (degrees)",choice(\.angle),-360...360).disabled(!settings.lighting)
      number("Shine",choice(\.shine),0...10,step:0.1).disabled(!settings.lighting)
    case .tiles:
      number("Number of Tiles",choice(\.count),1...99)
      number("Maximum Offset (%)",choice(\.maxOffset),1...99)
      Picker("Fill Empty Area With",selection:choice(\.fill)){ForEach(StylizeSettings.TileFill.allCases,id:\.self){Text($0.title).tag($0)}}.pickerStyle(.radioGroup)
      ColorPicker("Foreground",selection:color(\.foreground),supportsOpacity:false)
      ColorPicker("Background",selection:color(\.background),supportsOpacity:false)
      randomize
    case .traceContour:
      number("Level",choice(\.level),0...255)
      Picker("Edge",selection:choice(\.edge)){ForEach(StylizeSettings.ContourEdge.allCases,id:\.self){Text($0.title).tag($0)}}.pickerStyle(.radioGroup)
    case .wind:
      Picker("Method",selection:choice(\.method)){ForEach(StylizeSettings.WindMethod.allCases,id:\.self){Text($0.title).tag($0)}}.pickerStyle(.radioGroup)
      Picker("Direction",selection:choice(\.direction)){ForEach(StylizeSettings.WindDirection.allCases,id:\.self){Text($0.title).tag($0)}}.pickerStyle(.radioGroup)
      randomize
    case .findEdges,.solarize:Text("This filter has no adjustable settings.").foregroundStyle(.secondary)
    default:EmptyView()
    }
  }
  var randomize:some View {Button("Randomize"){model.update{$0.stylize?.seed=UInt32.random(in:.min ... .max)}}}
}
