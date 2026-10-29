import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class OtherVideoWorkspace {
  var filter=RasterFilter(.customFilter)
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
    do { guard f.kind.isOtherVideo else {throw CraftError.invalid("Missing Other/Video kind.")};try f.validate();guard f.kind==filter.kind else { throw CraftError.invalid("Cannot change Other/Video workspace kind.") } } catch { self.error=error.localizedDescription;return }
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
  var documentWidth:Int {document?.width ?? 1}
  var documentHeight:Int {document?.height ?? 1}
  func loadPreset(_ data:Data) {
    guard !closed,filter.kind == .customFilter else{return}
    do {let settings=try OtherVideoSettings.decodeCustomPreset(data);update{$0.otherVideo=settings}}
    catch {self.error=error.localizedDescription}
  }
  func choosePreset() {
    let panel=NSOpenPanel();panel.title="Load Custom Filter";panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
    panel.begin { [weak self] response in
      guard response == .OK,let self,!self.closed,let url=panel.url else{return}
      do {let file=try FileHandle(forReadingFrom:url);defer{try? file.close()};self.loadPreset(try file.read(upToCount:16_385) ?? Data())}
      catch {self.error=error.localizedDescription}
    }
  }
  func savePreset() {
    guard filter.kind == .customFilter,let settings=filter.otherVideo else{return}
    do {
      let data=try settings.encodedCustomPreset(),panel=NSSavePanel();panel.title="Save Custom Filter";panel.nameFieldStringValue="Custom Filter.json";panel.allowedContentTypes=[.json]
      panel.begin { [weak self] response in
        guard response == .OK,let self,!self.closed,let url=panel.url else{return}
        do {let writer=try AtomicFileWriter(to:url,maximumBytes:16_384);try writer.append(data);try writer.commit()}
        catch {self.error=error.localizedDescription}
      }
    } catch {self.error=error.localizedDescription}
  }
  func close() { closed=true;generation+=1;task?.cancel();task=nil;rendering=false }
}

struct OtherVideoSheet:View {
  @Bindable var store:EditorStore
  @State private var model:OtherVideoWorkspace
  init(store:EditorStore,model:OtherVideoWorkspace?=nil) {self.store=store;_model=State(initialValue:model ?? OtherVideoWorkspace())}
  var settings:OtherVideoSettings {model.filter.otherVideo ?? .init()}
  var body:some View {
    VStack(spacing:12) {
      HStack {Text(model.filter.kind.title).font(.headline);Spacer();if model.rendering {ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView {VStack(alignment:.leading,spacing:14) {controls;Divider();Button("Reset"){model.change(RasterFilter(model.filter.kind))}}.padding(.trailing,5)}.frame(width:275)
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
    .task {store.otherVideoWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft)}
    .onDisappear {model.close();if store.otherVideoWorkspace === model {store.otherVideoWorkspace=nil}}
  }
  var preview:some View {
    GeometryReader {g in ScrollView([.horizontal,.vertical]) {
      if let image=model.preview ? model.image:model.originalImage {
        let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
        Image(decorative:image,scale:1).resizable().interpolation(.none).frame(width:Double(image.width)*scale,height:Double(image.height)*scale).padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
      }
    }.background(Color(white:0.12)).clipped().accessibilityLabel("Filter preview")}
  }
  func choice<T>(_ key:WritableKeyPath<OtherVideoSettings,T>)->Binding<T> {
    Binding(get:{settings[keyPath:key]},set:{value in model.update{$0.otherVideo?[keyPath:key]=value}})
  }
  func integer(_ key:WritableKeyPath<OtherVideoSettings,Int>)->Binding<Double> {
    Binding(get:{Double(settings[keyPath:key])},set:{value in guard value.isFinite,(-600000...600000).contains(value),value.rounded()==value else {model.error="Enter a whole pixel offset within the supported range.";return};model.update{$0.otherVideo?[keyPath:key]=Int(value)}})
  }
  func number(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,step:Double=1)->some View {
    VStack(spacing:4) {
      HStack {Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:70).textFieldStyle(.roundedBorder)}
      Slider(value:value,in:range,step:step,onEditingChanged:{editing in if editing {model.beginGesture()} else {model.endGesture()}}).accessibilityLabel(title)
    }
  }
  @ViewBuilder var controls:some View {
    switch model.filter.kind {
    case .customFilter:
      Text("Custom Kernel").font(.headline)
      Grid(horizontalSpacing:4,verticalSpacing:4) {
        ForEach(0..<5,id:\.self) {row in GridRow {ForEach(0..<5,id:\.self) {col in
          TextField("",value:Binding(get:{settings.kernel[row*5+col]},set:{value in model.update{$0.otherVideo?.kernel[row*5+col]=value}}),format:.number)
            .frame(width:46).textFieldStyle(.roundedBorder).multilineTextAlignment(.center).accessibilityLabel("Kernel row \(row+1), column \(col+1)")
        }}}
      }
      number("Scale",choice(\.scale),1...9999)
      number("Offset",choice(\.offset),-9999...9999)
      HStack {Button("Load…"){model.choosePreset()};Button("Save…"){model.savePreset()}}
      Text("Save and load Photato Custom filter presets.").font(.caption).foregroundStyle(.secondary)
    case .hsbHsl:
      Picker("Input Mode",selection:choice(\.inputMode)){ForEach(OtherVideoSettings.ColorModel.allCases,id:\.self){Text($0.rawValue.uppercased()).tag($0)}}.pickerStyle(.radioGroup)
      Picker("Row Order",selection:choice(\.outputMode)){ForEach(OtherVideoSettings.ColorModel.allCases,id:\.self){Text($0.rawValue.uppercased()).tag($0)}}.pickerStyle(.radioGroup)
    case .maximum,.minimum:
      number("Radius (pixels)",choice(\.radius),settings.preserve == .roundness ? 0.2...500:1...500,step:settings.preserve == .roundness ? 0.1:1)
      Picker("Preserve",selection:Binding(get:{settings.preserve},set:{value in model.update{$0.otherVideo?.preserve=value;if value == .squareness {$0.otherVideo?.radius=max(1,settings.radius.rounded())}}})) {ForEach(OtherVideoSettings.Preserve.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
    case .offset:
      number("Horizontal (pixels)",integer(\.horizontal),Double(-2*model.documentWidth)...Double(2*model.documentWidth))
      number("Vertical (pixels)",integer(\.vertical),Double(-2*model.documentHeight)...Double(2*model.documentHeight))
      Picker("Undefined Areas",selection:choice(\.undefinedAreas)) {
        Text("Set to Transparent").tag(OtherVideoSettings.UndefinedAreas.transparent)
        Text("Repeat Edge Pixels").tag(OtherVideoSettings.UndefinedAreas.repeatEdge)
        Text("Wrap Around").tag(OtherVideoSettings.UndefinedAreas.wrap)
      }.pickerStyle(.radioGroup)
    case .deInterlace:
      Picker("Eliminate",selection:choice(\.eliminate)){Text("Odd Fields").tag(OtherVideoSettings.Field.odd);Text("Even Fields").tag(OtherVideoSettings.Field.even)}.pickerStyle(.radioGroup)
      Picker("Create New Fields By",selection:choice(\.createBy)){Text("Duplication").tag(OtherVideoSettings.Creation.duplication);Text("Interpolation").tag(OtherVideoSettings.Creation.interpolation)}.pickerStyle(.radioGroup)
    case .ntscColors:Text("Constrain colors to the NTSC composite-signal range.").foregroundStyle(.secondary)
    default:EmptyView()
    }
  }
}
