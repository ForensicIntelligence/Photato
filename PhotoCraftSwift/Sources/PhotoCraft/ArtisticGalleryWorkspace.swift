import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class ArtisticGalleryWorkspace {
  var settings=ArtisticGallerySettings()
  var selected=0
  var category="Artistic"
  var image:CGImage?
  var originalImage:CGImage?
  var thumbnails=[GalleryFilter:CGImage]()
  var preview=true
  var rendering=false
  var zoom=1.0
  var error:String?
  var undoStates=[ArtisticGallerySettings]()
  var redoStates=[ArtisticGallerySettings]()
  @ObservationIgnored var task:Task<Void,Never>?
  @ObservationIgnored var thumbnailTask:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var closed=false
  private var generation=0
  private var gestureStart:ArtisticGallerySettings?
  var effect:GalleryEffect? { settings.effects.indices.contains(selected) ? settings.effects[selected]:nil }
  var ready:Bool { image != nil && !rendering && error == nil }
  var apiState:[String:Any] { ["settings":(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(settings))) ?? NSNull(),"selectedEffect":selected,"category":category,"preview":preview,"zoom":zoom,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()] }
  func prepare(document:CraftDocument,draft:FilterDraft) async {
    self.document=document;self.draft=draft;settings=draft.filter.artistic ?? .init();selected=0;category=effect?.filter.category ?? "Artistic";closed=false
    refresh();prepareThumbnails();await task?.value
  }
  func remember(_ value:ArtisticGallerySettings) { undoStates.append(value);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ value:ArtisticGallerySettings,remember:Bool=true) {
    do { try value.validate() } catch { self.error=error.localizedDescription;return }
    guard value != settings else { return };if remember && gestureStart==nil { self.remember(settings) };settings=value;selected=max(0,min(selected,value.effects.count-1));refresh()
  }
  func beginGesture() { if gestureStart==nil { gestureStart=settings } }
  func endGesture() { if let before=gestureStart,before != settings { remember(before) };gestureStart=nil }
  func undo() { endGesture();guard let s=undoStates.popLast() else{return};redoStates.append(settings);change(s,remember:false) }
  func redo() { endGesture();guard let s=redoStates.popLast() else{return};undoStates.append(settings);change(s,remember:false) }
  func update(_ edit:(inout GalleryEffect)->Void) { guard settings.effects.indices.contains(selected) else{return};var s=settings;edit(&s.effects[selected]);change(s) }
  func choose(_ filter:GalleryFilter) {
    category=filter.category
    var e=GalleryEffect(filter);e.foreground=effect?.foreground ?? draft?.filter.artistic?.effects.first?.foreground ?? .black;e.background=effect?.background ?? draft?.filter.artistic?.effects.first?.background ?? .white
    if settings.effects.indices.contains(selected) { update{$0=e} } else { var s=settings;s.effects.append(e);change(s) }
  }
  func add() { guard settings.effects.count<32 else{return};var s=settings;s.effects.append(effect ?? .init(.coloredPencil));selected=s.effects.count-1;change(s) }
  func remove() { guard settings.effects.indices.contains(selected) else{return};var s=settings;s.effects.remove(at:selected);change(s) }
  func move(_ delta:Int) { let target=selected+delta;guard settings.effects.indices.contains(selected),settings.effects.indices.contains(target) else{return};var s=settings;s.effects.swapAt(selected,target);selected=target;change(s) }
  func reset() { if let kind=effect?.filter { choose(kind) } }
  func refresh() {
    guard !closed,let document,var draft else{return};task?.cancel();generation+=1;let token=generation,needOriginal=originalImage==nil
    draft.filter.artistic=settings;let request=draft;rendering=true;error=nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { () throws -> (CGImage,CGImage?) in
          var edited=document;try request.command(in:document).apply(to:&edited)
          return (try ColorManagement.displayImage(Renderer.composite(edited),in:document),needOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation==token else{return};self.image=result.0;if let original=result.1{self.originalImage=original};self.rendering=false
      } catch { guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled{self.error=error.localizedDescription} }
    }
  }
  func prepareThumbnails() {
    guard let document,let draft else{return};thumbnailTask?.cancel()
    thumbnailTask=Task { [weak self] in
      let worker=Task.detached(priority:.utility) { () throws -> [GalleryFilter:CGImage] in
        let layer=try draft.inputLayer(in:document);guard case .raster(let source)=layer.content else{return [:]}
        let scale=min(1,96.0/Double(max(source.width,source.height))),small=try Renderer.resize(source,width:max(1,Int(Double(source.width)*scale)),height:max(1,Int(Double(source.height)*scale)))
        var images=[GalleryFilter:CGImage]()
        for kind in GalleryFilter.allCases { try Task.checkCancellation();var s=ArtisticGallerySettings(),e=GalleryEffect(kind);e.foreground=draft.filter.artistic?.effects.first?.foreground ?? .black;e.background=draft.filter.artistic?.effects.first?.background ?? .white;s.effects=[e];images[kind]=try ColorManagement.displayImage(ArtisticGalleryEngine.render(small,settings:s),in:document) }
        return images
      }
      do { let images=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()};try Task.checkCancellation();guard let self,!self.closed else{return};self.thumbnails=images } catch { /* Main preview reports actionable render failures. */ }
    }
  }
  func close() { closed=true;generation+=1;task?.cancel();thumbnailTask?.cancel();task=nil;thumbnailTask=nil;rendering=false }
}

struct ArtisticGallerySheet:View {
  @Bindable var store:EditorStore
  @State private var model:ArtisticGalleryWorkspace
  init(store:EditorStore,model:ArtisticGalleryWorkspace?=nil) { self.store=store;_model=State(initialValue:model ?? ArtisticGalleryWorkspace()) }
  func value(_ p:GalleryParameter)->Binding<Double> { .init(get:{model.effect?.values[p.key] ?? p.defaultValue},set:{v in model.update{$0.values[p.key]=v}}) }
  func color(_ key:WritableKeyPath<GalleryEffect,Pixel>)->Binding<Color> { .init(get:{let p=model.effect?[keyPath:key] ?? .black;return Color(red:Double(p.r),green:Double(p.g),blue:Double(p.b))},set:{v in guard let c=NSColor(v).usingColorSpace(.sRGB) else{return};model.update{$0[keyPath:key]=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent))}}) }
  var body:some View {
    VStack(spacing:12) {
      HStack { Text("Filter Gallery").font(.headline);Spacer();if model.rendering { ProgressView().controlSize(.small);Text("Rendering…").foregroundStyle(.secondary) } }
      HStack(alignment:.top,spacing:14) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        browser.frame(width:220)
        VStack(spacing:12) { controls;Divider();stack }.frame(width:245)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview);Button("−") { model.zoom=max(0.25,model.zoom/1.5) };Button("+") { model.zoom=min(8,model.zoom*1.5) };Button("Fit") { model.zoom=1 }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { model.close();store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") { model.endGesture();store.filterDraft?.filter.artistic=model.settings;model.close();store.commitFilter() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
      if let error=model.error { Text(error).font(.caption).foregroundStyle(.red) }
    }.padding(16).frame(width:960,height:660)
    .task { store.artisticGalleryWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft) }
    .onDisappear { model.close();if store.artisticGalleryWorkspace === model { store.artisticGalleryWorkspace=nil } }
  }
  var preview:some View {
    GeometryReader { g in
      let image=model.preview ? model.image:model.originalImage
      ScrollView([.horizontal,.vertical]) {
        if let image { let scale=min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height))*model.zoom
          Image(decorative:image,scale:1).resizable().interpolation(.high).frame(width:Double(image.width)*scale,height:Double(image.height)*scale).padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
        }
      }.background(Color(white:0.12)).accessibilityLabel("Filter Gallery image preview")
    }
  }
  var browser:some View {
    VStack(alignment:.leading) {
      Picker("Category",selection:$model.category) { ForEach(GalleryFilter.categories,id:\.self) { Text($0).tag($0) } }.labelsHidden()
      ScrollView {
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
          ForEach(GalleryFilter.allCases.filter{$0.category==model.category},id:\.self) { kind in
            Button { model.choose(kind) } label: {
              VStack(spacing:4) {
                if let image=model.thumbnails[kind] { Image(decorative:image,scale:1).resizable().scaledToFit().frame(height:67) } else { Rectangle().fill(.quaternary).frame(height:67).overlay(Image(systemName:"photo")) }
                Text(kind.title).font(.caption).lineLimit(2).frame(height:28)
              }.padding(4).frame(maxWidth:.infinity).background(model.effect?.filter==kind ? Color.accentColor.opacity(0.22):Color.clear).clipShape(RoundedRectangle(cornerRadius:5))
            }.buttonStyle(.plain).accessibilityLabel(kind.title)
          }
        }
      }
    }
  }
  var controls:some View {
    ScrollView { VStack(alignment:.leading,spacing:9) {
      if let effect=model.effect {
        HStack { Text(effect.filter.title).font(.headline);Spacer();Button("Reset") { model.reset() }.controlSize(.small) }
        ForEach(effect.filter.parameters,id:\.key) { p in parameter(p) }
        Divider();ColorPicker("Foreground",selection:color(\.foreground),supportsOpacity:false);ColorPicker("Background",selection:color(\.background),supportsOpacity:false)
        if effect.filter == .neonGlow { ColorPicker("Glow Color",selection:color(\.glowColor),supportsOpacity:false) }
      } else { Text("Choose an effect to start.").foregroundStyle(.secondary) }
    }.padding(.trailing,4) }.frame(maxHeight:.infinity)
  }
  @ViewBuilder func parameter(_ p:GalleryParameter)->some View {
    if !p.choices.isEmpty {
      Picker(p.title,selection:value(p)) { ForEach(Array(p.choices.enumerated()),id:\.offset) { i,label in Text(label).tag(Double(i)) } }
    } else if p.boolean {
      Toggle(p.title,isOn:Binding(get:{value(p).wrappedValue != 0},set:{value(p).wrappedValue=$0 ? 1:0}))
    } else {
      VStack(spacing:2) {
        HStack { Text(p.title);Spacer();TextField(p.title,value:value(p),format:.number.precision(.fractionLength(0))).frame(width:48) }
        Slider(value:value(p),in:p.minimum...p.maximum,step:1,onEditingChanged:{editing in if editing { model.beginGesture() } else { model.endGesture() } }).accessibilityLabel(p.title)
      }
    }
  }
  var stack:some View {
    VStack(alignment:.leading,spacing:6) {
      HStack { Text("Effect Layers").font(.subheadline.bold());Spacer();Text("\(model.settings.effects.count)/32").foregroundStyle(.secondary) }
      ScrollView { VStack(spacing:3) {
        ForEach(Array(model.settings.effects.indices.reversed()),id:\.self) { i in
          HStack {
            Button { var s=model.settings;s.effects[i].visible.toggle();model.change(s) } label:{Image(systemName:model.settings.effects[i].visible ? "eye":"eye.slash")}.buttonStyle(.plain).accessibilityLabel("Toggle \(model.settings.effects[i].filter.title)")
            Button { model.selected=i;model.category=model.settings.effects[i].filter.category } label:{Text(model.settings.effects[i].filter.title).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)
          }.padding(6).background(model.selected==i ? Color.accentColor.opacity(0.22):Color.clear).clipShape(RoundedRectangle(cornerRadius:4))
        }
      } }.frame(height:118)
      HStack {
        Button { model.add() } label:{Image(systemName:"plus.square")}.help("New effect layer").disabled(model.settings.effects.count>=32)
        Button { model.remove() } label:{Image(systemName:"trash")}.help("Delete effect layer").disabled(model.effect==nil)
        Spacer();Button { model.move(1) } label:{Image(systemName:"arrow.up")}.help("Move effect up").disabled(model.selected>=model.settings.effects.count-1)
        Button { model.move(-1) } label:{Image(systemName:"arrow.down")}.help("Move effect down").disabled(model.selected<=0)
      }.controlSize(.small)
    }
  }
}
