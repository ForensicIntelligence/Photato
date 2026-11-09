import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class BlurGalleryWorkspace {
  var settings=BlurGallerySettings()
  var mode:BlurGallerySettings.Mode = .field
  var selected=0
  var selectedPoint=0
  var image:CGImage?
  var originalImage:CGImage?
  var maskImage:CGImage?
  var documentSize=CGSize(width:1,height:1)
  var sourceSize=CGSize(width:1,height:1)
  var sourceTransform=Transform2D.identity
  var preview=true
  var showMask=false
  var showControls=true
  var saveMaskToChannels=false
  var rendering=false
  var zoom=1.0
  var error:String?
  var maskError:String?
  var undoStates=[BlurGallerySettings]()
  var redoStates=[BlurGallerySettings]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var gestureStart:BlurGallerySettings?
  private var closed=false
  private var generation=0
  var ready:Bool { image != nil && !rendering && error == nil }
  var canSaveMask:Bool {
    guard let document else{return false}
    return maskError==nil && (document.alphaChannels?.count ?? 0)<document.auxiliaryChannelLimit && document.quickMask==nil && !document.colorMode.isRestricted && document.inkMode==nil
  }
  var pins:[BlurGallerySettings.Pin] { settings.pins(mode) }
  var pin:BlurGallerySettings.Pin? { pins.indices.contains(selected) ? pins[selected]:nil }
  var path:BlurGallerySettings.MotionPath? { settings.paths.indices.contains(selected) ? settings.paths[selected]:nil }
  func prepare(document:CraftDocument,draft:FilterDraft) async {
    self.document=document;self.draft=draft;settings=draft.filter.gallery ?? .init();mode=settings.enabled.first ?? .field
    documentSize=CGSize(width:document.width,height:document.height)
    let input=try? draft.inputLayer(in:document)
    if let input,case .raster(let pixels)=input.content {sourceSize=CGSize(width:pixels.width,height:pixels.height);sourceTransform=input.coordinateTransform}
    saveMaskToChannels=draft.saveMaskToChannels
    closed=false;refresh();await task?.value
  }
  func point(_ p:PathPoint)->PathPoint { p.transformed(.scale(sourceSize.width,sourceSize.height)).transformed(sourceTransform) }
  func normalized(_ p:PathPoint)->PathPoint { let q=p.transformed((try? sourceTransform.inverted()) ?? .identity);return PathPoint(q.x/sourceSize.width,q.y/sourceSize.height) }
  func remember(_ s:BlurGallerySettings) { undoStates.append(s);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ s:BlurGallerySettings,remember:Bool=true) {
    do { try s.validate() } catch { self.error=error.localizedDescription;return }
    guard s != settings else { error=nil;return }
    if remember && gestureStart == nil { self.remember(settings) };settings=s;refresh()
  }
  func beginGesture() { if gestureStart==nil { gestureStart=settings } }
  func endGesture() { if let before=gestureStart,before != settings { remember(before) };gestureStart=nil }
  func undo() { endGesture();guard let value=undoStates.popLast() else { return };redoStates.append(settings);change(value,remember:false) }
  func redo() { endGesture();guard let value=redoStates.popLast() else { return };undoStates.append(settings);change(value,remember:false) }
  func choose(_ mode:BlurGallerySettings.Mode) { self.mode=mode;selected=0;selectedPoint=0;var s=settings;if !s.enabled.contains(mode) { s.enabled.append(mode);change(s) } }
  func updatePin(_ changePin:(inout BlurGallerySettings.Pin)->Void) { guard pins.indices.contains(selected) else { return };var s=settings,p=pins;changePin(&p[selected]);s.setPins(p,for:mode);change(s) }
  func updatePath(_ changePath:(inout BlurGallerySettings.MotionPath)->Void) { guard settings.paths.indices.contains(selected) else { return };var s=settings;changePath(&s.paths[selected]);change(s) }
  func add(at p:PathPoint) {
    var s=settings
    if mode == .path {
      if NSEvent.modifierFlags.contains(.option),s.paths.indices.contains(selected) { s.paths[selected].points.append(p);selectedPoint=s.paths[selected].points.count-1 }
      else { var path=BlurGallerySettings.MotionPath();path.points=[p,PathPoint(min(5,p.x+0.2),p.y)];s.paths.append(path);selected=s.paths.count-1;selectedPoint=0 }
    } else { var pin=BlurGallerySettings.Pin();pin.x=p.x;pin.y=p.y;var pins=s.pins(mode);pins.append(pin);selected=pins.count-1;s.setPins(pins,for:mode) }
    change(s)
  }
  func remove() { var s=settings;if mode == .path { guard s.paths.indices.contains(selected) else { return };s.paths.remove(at:selected) } else { var p=s.pins(mode);guard p.indices.contains(selected) else { return };p.remove(at:selected);s.setPins(p,for:mode) };selected=0;selectedPoint=0;change(s) }
  func refresh() {
    guard !closed,let document,var draft else { return };task?.cancel();generation+=1;let token=generation,needOriginal=originalImage==nil,s=settings
    draft.filter.gallery=s;draft.saveMaskToChannels=false;let request=draft;rendering=true;error=nil;maskError=nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { () throws -> (CGImage,CGImage?,CGImage?,String?) in
          var edited=document;try request.command(in:document).apply(to:&edited)
          let image=try ColorManagement.displayImage(Renderer.composite(edited),in:document)
          let original=needOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil
          do {
            let layer=try request.inputLayer(in:document)
            let mask=try BlurGalleryMask.surface(in:document,layer:layer,settings:s)
            var model=document;let target=Layer(name:"Blur Mask",content:.raster(mask));model.layers=[target];model.activeLayerID=target.id
            return (image,original,try ColorManagement.displayImage(Renderer.composite(model),in:model),nil)
          } catch {
            try Task.checkCancellation()
            return (image,original,nil,error.localizedDescription)
          }
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation==token else { return };self.image=result.0;if let original=result.1 { self.originalImage=original };self.maskImage=result.2;self.maskError=result.3;self.rendering=false
      } catch { guard let self,!self.closed,self.generation==token else { return };self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation+=1;task?.cancel();task=nil;rendering=false }
}
struct BlurGallerySheet:View {
  @Bindable var store:EditorStore
  @State private var model:BlurGalleryWorkspace
  init(store:EditorStore,model:BlurGalleryWorkspace?=nil) { self.store=store;_model=State(initialValue:model ?? BlurGalleryWorkspace()) }
  func pinBinding(_ key:WritableKeyPath<BlurGallerySettings.Pin,Double>)->Binding<Double> { .init(get:{model.pin?[keyPath:key] ?? 0},set:{n in model.updatePin{$0[keyPath:key]=n}}) }
  func setting(_ key:WritableKeyPath<BlurGallerySettings,Double>)->Binding<Double> { .init(get:{model.settings[keyPath:key]},set:{n in var s=model.settings;s[keyPath:key]=n;model.change(s)}) }
  func field(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
    VStack(spacing:3) { HStack { Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:64) };Slider(value:value,in:range) }
  }
  var body:some View {
    VStack(spacing:12) {
      HStack { Text("Blur Gallery").font(.headline);Toggle("Save Mask to Channels",isOn:$model.saveMaskToChannels).controlSize(.small).disabled(!model.canSaveMask);Spacer();if model.rendering { ProgressView().controlSize(.small) };Text(model.mode.title).foregroundStyle(.secondary) }
      HStack(alignment:.top,spacing:16) {
        BlurGalleryPreview(model:model).frame(minWidth:500,minHeight:440).clipped()
        ScrollView { VStack(alignment:.leading,spacing:12) {
          Picker("Tool",selection:Binding(get:{model.mode},set:{model.choose($0)})) { ForEach(BlurGallerySettings.Mode.allCases,id:\.self) { Text($0.title).tag($0) } }
          ForEach(BlurGallerySettings.Mode.allCases,id:\.self) { mode in Toggle(mode.title,isOn:Binding(get:{model.settings.enabled.contains(mode)},set:{ on in var s=model.settings;s.enabled.removeAll{$0==mode};if on { s.enabled.append(mode) };model.change(s) })) }
          Divider()
          if model.mode == .path { pathControls } else if model.pin != nil { pinControls }
          HStack { Button("Add") { model.add(at:.init(0.5,0.5)) };Button("Delete") { model.remove() }.keyboardShortcut(.delete,modifiers:[]) }
          Text(model.mode == .path ? "Drag path nodes. Option-click adds a control point; click elsewhere adds a path.":"Click to add a pin. Drag centers or outer handles; use numeric controls for precision.").font(.caption).foregroundStyle(.secondary)
          Divider();effectsControls
          if let error=model.error { Text(error).font(.caption).foregroundStyle(.red) }
          if let error=model.maskError {Text("Mask unavailable: "+error).font(.caption).foregroundStyle(.secondary)}
        }.frame(width:260) }.frame(width:275)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Toggle("Mask",isOn:$model.showMask).keyboardShortcut("m",modifiers:[]).disabled(model.maskImage==nil)
        Toggle("Controls",isOn:$model.showControls).keyboardShortcut("h",modifiers:[])
        Button("−") { model.zoom=max(0.25,model.zoom/1.5) };Button("+") { model.zoom=min(4,model.zoom*1.5) };Button("Fit") { model.zoom=1 }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { model.close();store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") { model.endGesture();store.filterDraft?.filter.gallery=model.settings;store.filterDraft?.saveMaskToChannels=model.saveMaskToChannels;model.close();store.commitFilter() }.keyboardShortcut(.defaultAction).disabled(!model.ready || model.saveMaskToChannels && !model.canSaveMask)
      }.controlSize(.small)
    }.padding(18).frame(width:900,height:680)
    .task { store.blurGalleryWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else { return };await model.prepare(document:store.document,draft:draft) }
    .onDisappear { model.close();if store.blurGalleryWorkspace === model { store.blurGalleryWorkspace=nil } }
  }
  @ViewBuilder var pinControls:some View {
    Picker("Pin",selection:$model.selected) { ForEach(model.pins.indices,id:\.self) { Text("Pin \($0+1)").tag($0) } }
    HStack { Text("X");TextField("X",value:pinBinding(\.x),format:.number);Text("Y");TextField("Y",value:pinBinding(\.y),format:.number) }
    if model.mode == .spin { field("Blur Angle",pinBinding(\.blurAngle),0...360) } else { field("Blur (px)",pinBinding(\.blur),0...500) }
    if model.mode == .iris || model.mode == .spin {
      field("Radius X",pinBinding(\.radiusX),0.001...2);field("Radius Y",pinBinding(\.radiusY),0.001...2)
      field("Rotation",pinBinding(\.angle),-180...180);field("Feather",pinBinding(\.feather),0...0.999)
      if model.mode == .iris { field("Roundness",pinBinding(\.roundness),0...100) }
    }
    if model.mode == .tiltShift { field("Rotation",pinBinding(\.angle),-180...180);field("Focus",pinBinding(\.focus),0...2);field("Transition",pinBinding(\.transition),0.001...2) }
    if model.mode == .spin {
      field("Strobe Strength",setting(\.strobeStrength),0...100)
      Stepper("Flashes: \(model.settings.strobeFlashes)",value:Binding(get:{model.settings.strobeFlashes},set:{n in var s=model.settings;s.strobeFlashes=n;model.change(s)}),in:1...30)
      field("Flash Duration (°)",setting(\.strobeDuration),0...360)
    }
  }
  @ViewBuilder var pathControls:some View {
    if model.path != nil {
      Picker("Path",selection:$model.selected) { ForEach(model.settings.paths.indices,id:\.self) { Text("Path \($0+1)").tag($0) } }
      field("Speed (px)",Binding(get:{model.path?.speed ?? 0},set:{n in model.updatePath{$0.speed=n}}),0...500)
      field("Taper (%)",Binding(get:{model.path?.taper ?? 0},set:{n in model.updatePath{$0.taper=n}}),0...100)
      Toggle("Centered Blur",isOn:Binding(get:{model.path?.centered ?? true},set:{n in model.updatePath{$0.centered=n}}))
      Toggle("Curved",isOn:Binding(get:{model.path?.curved ?? true},set:{n in model.updatePath{$0.curved=n}}))
    }
  }
  var effectsControls:some View {
    Group {
      Text("Blur Effects").font(.subheadline.bold())
      field("Light Bokeh",setting(\.lightBokeh),0...100);field("Bokeh Color",setting(\.bokehColor),0...100)
      field("Light Range Low",setting(\.lightMin),0...1);field("Light Range High",setting(\.lightMax),0...1)
      Divider();Text("Noise").font(.subheadline.bold())
      Picker("Type",selection:Binding(get:{model.settings.noise},set:{n in var s=model.settings;s.noise=n;model.change(s)})) { ForEach(BlurGallerySettings.Noise.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }
      field("Amount",setting(\.noiseAmount),0...100)
      if model.settings.noise == .grain { field("Size",setting(\.noiseSize),0.1...10);field("Roughness",setting(\.noiseRoughness),0...100) }
      field("Color",setting(\.noiseColor),0...100);field("Highlights",setting(\.noiseHighlights),0...100)
    }
  }
}
