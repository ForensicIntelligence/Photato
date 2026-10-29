import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class PhotoDetailWorkspace {
  var filter=RasterFilter(.smartSharpen)
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var rendering=false
  var fit=true
  var zoom=1.0
  var channel="overall"
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
    let encoded=(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(filter))) as? [String:Any] ?? [:]
    let parameters=encoded.filter { filter.kind.parameters.contains($0.key) || $0.key == "kind" }
    return ["filter":parameters,"preview":preview,"zoom":zoom,"fit":fit,"channel":channel,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()] }
  func prepare(document:CraftDocument,draft:FilterDraft) async { self.document=document;self.draft=draft;filter=draft.filter;closed=false;refresh();await task?.value }
  func remember(_ f:RasterFilter) { undoStates.append(f);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ f:RasterFilter,remember:Bool=true) {
    do { try f.validate();guard f.kind==filter.kind else { throw CraftError.invalid("Cannot change photo detail workspace kind.") } } catch { self.error=error.localizedDescription;return }
    guard f != filter else{return};if remember && gestureStart==nil { self.remember(filter) };filter=f;refresh()
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

struct PhotoDetailSheet:View {
  @Bindable var store:EditorStore
  @State private var model:PhotoDetailWorkspace
  init(store:EditorStore,model:PhotoDetailWorkspace?=nil) { self.store=store;_model=State(initialValue:model ?? PhotoDetailWorkspace()) }
  var body:some View {
    VStack(spacing:12) {
      HStack { Text(model.filter.kind.title).font(.headline);Spacer();if model.rendering { ProgressView().controlSize(.small);Text("Rendering…").foregroundStyle(.secondary) } }
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView { VStack(alignment:.leading,spacing:12) {
          if model.filter.kind == .smartSharpen { sharpenControls } else { noiseControls }
          Divider();Button("Reset") { model.change(RasterFilter(model.filter.kind)) }
        }.padding(.trailing,5) }.frame(width:275)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−") { model.fit=false;model.zoom=max(0.125,model.zoom/1.5) };Button("+") { model.fit=false;model.zoom=min(8,model.zoom*1.5) }
        Button("100%") { model.fit=false;model.zoom=1 };Button("Fit") { model.fit=true }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { model.close();store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") { model.endGesture();store.filterDraft?.filter=model.filter;model.close();store.commitFilter() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
      if let error=model.error { Text(error).foregroundStyle(.red).font(.caption) }
    }.padding(16).frame(width:840,height:620)
    .task { store.photoDetailWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft) }
    .onDisappear { model.close();if store.photoDetailWorkspace === model { store.photoDetailWorkspace=nil } }
  }
  var preview:some View {
    GeometryReader { g in
      ScrollView([.horizontal,.vertical]) {
        if let image=model.preview ? model.image:model.originalImage {
          let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
          Image(decorative:image,scale:1).resizable().interpolation(.none).frame(width:Double(image.width)*scale,height:Double(image.height)*scale).padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
        }
      }.background(Color(white:0.12)).accessibilityLabel("Photo detail preview")
    }
  }
  func control(_ p:DetailControl,_ value:Binding<Double>)->some View {
    VStack(spacing:3) {
      HStack { Text(p.title);Spacer();TextField(p.title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:60).textFieldStyle(.roundedBorder) }
      Slider(value:value,in:p.bounds,onEditingChanged:{editing in if editing { model.beginGesture() } else { model.endGesture() } }).accessibilityLabel(p.title)
    }
  }
  func sharpen(_ key:WritableKeyPath<SmartSharpenSettings,Double>)->Binding<Double> { .init(get:{model.filter.sharpen?[keyPath:key] ?? 0},set:{v in model.update{$0.sharpen?[keyPath:key]=v}}) }
  var sharpenControls:some View {
    VStack(alignment:.leading,spacing:12) {
      control(SmartSharpenSettings.controls[0],sharpen(\.amount))
      control(SmartSharpenSettings.controls[1],sharpen(\.radius))
      control(SmartSharpenSettings.controls[2],sharpen(\.reduceNoise))
      Picker("Remove",selection:Binding(get:{model.filter.sharpen?.remove ?? .gaussian},set:{v in model.update{$0.sharpen?.remove=v}})) { ForEach(SmartSharpenSettings.Removal.allCases,id:\.self) { Text($0.title).tag($0) } }
      if model.filter.sharpen?.remove == .motion { control(SmartSharpenSettings.controls[3],sharpen(\.angle)) }
      DisclosureGroup("Shadows") { tonal(\.shadows) }
      DisclosureGroup("Highlights") { tonal(\.highlights) }
    }
  }
  func tonal(_ area:WritableKeyPath<SmartSharpenSettings,TonalSharpenSettings>)->some View {
    let keys:[WritableKeyPath<TonalSharpenSettings,Double>]=[\.fadeAmount,\.tonalWidth,\.radius]
    return VStack(spacing:10) { ForEach(0..<3,id:\.self) { i in control(TonalSharpenSettings.controls[i],Binding(get:{model.filter.sharpen?[keyPath:area][keyPath:keys[i]] ?? 0},set:{v in model.update{$0.sharpen?[keyPath:area][keyPath:keys[i]]=v}})) } }.padding(.top,8)
  }
  func noise(_ key:WritableKeyPath<ReduceNoiseSettings,Double>)->Binding<Double> { .init(get:{model.filter.denoise?[keyPath:key] ?? 0},set:{v in model.update{$0.denoise?[keyPath:key]=v}}) }
  var noiseControls:some View {
    VStack(alignment:.leading,spacing:12) {
      Picker("Controls",selection:$model.channel) { Text("Overall").tag("overall");ForEach(ReduceNoiseSettings.channels,id:\.self) { Text($0.capitalized+" Channel").tag($0) } }
      if model.channel=="overall" {
        control(ReduceNoiseSettings.controls[0],noise(\.strength));control(ReduceNoiseSettings.controls[1],noise(\.preserveDetails));control(ReduceNoiseSettings.controls[2],noise(\.reduceColorNoise));control(ReduceNoiseSettings.controls[3],noise(\.sharpenDetails))
        Toggle("Remove JPEG Artifact",isOn:Binding(get:{model.filter.denoise?.removeJpegArtifact ?? false},set:{v in model.update{$0.denoise?.removeJpegArtifact=v}}))
      } else {
        control(ReduceNoiseSettings.controls[0],channel(\.strength));control(ReduceNoiseSettings.controls[1],channel(\.preserveDetails))
      }
    }
  }
  func channel(_ key:WritableKeyPath<ChannelNoiseSettings,Double>)->Binding<Double> { .init(get:{(model.filter.denoise?.perChannel[model.channel] ?? .init())[keyPath:key]},set:{v in model.update { f in var c=f.denoise?.perChannel[model.channel] ?? .init();c[keyPath:key]=v;f.denoise?.perChannel[model.channel]=c }}) }
}
