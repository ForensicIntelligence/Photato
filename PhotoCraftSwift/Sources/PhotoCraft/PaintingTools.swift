import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

extension EditorTool {
  var paintTool:PaintTool? {
    switch self {
    case .brush:.brush;case .pencil:.pencil;case .colorReplacement:.colorReplacement
    case .mixerBrush:.mixerBrush;case .patternStamp:.patternStamp
    case .backgroundEraser:.backgroundEraser;case .magicEraser:.magicEraser
    default:nil
    }
  }
  var usesPaintingStroke:Bool { usesSelectionStroke || self == .adjustmentBrush || self == .eraser || (paintTool != nil && self != .magicEraser) }
}
@MainActor extension EditorStore {
  var currentPaintOptions:PaintToolOptions {
    get {let kind=tool.paintTool ?? .brush;return paintToolOptions[kind] ?? .defaults(for:kind)}
    set {paintToolOptions[tool.paintTool ?? .brush]=newValue}
  }
  func paintingRequest(_ kind:PaintTool,points:[StrokePoint],brush:Brush)throws->PaintToolRequest {
    guard let id=activeLayer?.id else {throw CraftError.invalid("Choose a painting target.")}
    let target:PaintTarget
    if let channel=editingChannel {target = .channel(channel)}
    else if editingMask {target=smartFilterMaskEditing ? .smartFilterMask(id):.layerMask(id)}
    else {target = .pixels(id)}
    var request=PaintToolRequest(tool:kind,target:target,points:points,brush:brush,options:paintToolOptions[kind] ?? .defaults(for:kind))
    request.mixer=mixerPaint
    if kind == .patternStamp {
      request.pattern=patterns.selected
      if let point=points.first {
        let origin=request.options.aligned && patternStampID==request.pattern?.id ? patternStampOrigin ?? PathPoint(point.x,point.y):PathPoint(point.x,point.y)
        request.options.placement.phaseX=Float(origin.x);request.options.placement.phaseY=Float(origin.y)
      }
    }
    try request.validate();return request
  }
  func acceptPainting(_ result:PaintingSessionResult) {
    if result.tool == .mixerBrush {mixerPaint=result.mixer}
    if result.tool == .patternStamp {
      patternStampOrigin=result.patternOrigin
      patternStampID=result.patternID
    }
    if !editingMask && editingChannel==nil {selectedLayerIDs=Set(document.activeLayerID.map{[$0]} ?? [])}
  }
  func loadMixerColor() {
    guard canUseBrush else{return};mixerPaint.load(brush.color)
  }
  func cleanMixer() {guard canUseBrush else{return};mixerPaint.clean()}
  func sampleMixer(at point:PathPoint) {
    guard canUseBrush,let id=activeLayer?.id else{return}
    let original=document,generation=layerPanelGeneration,options=currentPaintOptions,size=brush.size
    geometryBusy=true;status="Load Mixer Brush"
    geometryTask=Task { [weak self] in
      defer {if self?.layerPanelGeneration==generation {self?.geometryBusy=false;self?.geometryTask=nil}}
      let worker=Task.detached(priority:.userInitiated) {try PaintingPreparation.loadMixer(in:original,layerID:id,point:point,size:size,allLayers:options.sampleAllLayers,solid:options.loadSolidColorOnly)}
      do {
        let loaded=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard let self,self.layerPanelGeneration==generation,self.document==original else{return}
        self.mixerPaint=loaded;self.status=loaded.reservoir==nil ? "Mixer Brush sampled transparency":"Mixer Brush loaded"
      } catch {if !Task.isCancelled,self?.layerPanelGeneration==generation {self?.error=error.localizedDescription}}
    }
  }
}

struct PaintingToolOptionsView:View {
  @Bindable var store:EditorStore
  var kind:PaintTool {store.tool.paintTool ?? .pencil}
  func option<T>(_ key:WritableKeyPath<PaintToolOptions,T>)->Binding<T> {
    Binding(get:{store.currentPaintOptions[keyPath:key]},set:{store.currentPaintOptions[keyPath:key]=$0})
  }
  func percentage(_ label:String,_ key:WritableKeyPath<PaintToolOptions,Double>)->some View {
    field(label,value:Binding(get:{store.currentPaintOptions[keyPath:key]*100},set:{if $0.isFinite{store.currentPaintOptions[keyPath:key]=min(1,max(0,$0/100))}}),suffix:"%")
  }
  func field(_ label:String,value:Binding<Double>,suffix:String="")->some View {
    HStack(spacing:3){Text(label);TextField(label,value:value,format:.number.precision(.fractionLength(0...1))).labelsHidden().textFieldStyle(.roundedBorder).frame(width:46);if !suffix.isEmpty{Text(suffix)}}
  }
  var body:some View {
    HStack(spacing:10) {
      if kind != .magicEraser {
        field("Size:",value:Binding(get:{store.brush.size},set:{if $0.isFinite{store.brush.size=min(2048,max(0.5,$0))}}),suffix:"px")
        if kind != .pencil {field("Hardness:",value:Binding(get:{Double(store.brush.hardness)*100},set:{if $0.isFinite{store.brush.hardness=Float(min(100,max(0,$0))/100)}}),suffix:"%")}
        Button("Brush Settings"){NSApp.sendAction(#selector(AppDelegate.showBrushSettings),to:nil,from:nil)}
      }
      if kind == .pencil || kind == .patternStamp {
        Picker("Mode:",selection:$store.brushOptions.mode){ForEach(BlendMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}.frame(width:145)
      }
      if [.pencil,.patternStamp,.magicEraser].contains(kind) {
        field("Opacity:",value:Binding(get:{Double(store.brush.opacity)*100},set:{if $0.isFinite{store.brush.opacity=Float(min(100,max(0,$0))/100)}}),suffix:"%")
      }
      if kind == .pencil {Toggle("Auto Erase",isOn:option(\.autoErase))}
      if kind == .colorReplacement {
        Picker("Mode:",selection:option(\.replacementMode)){ForEach([BlendMode.hue,.saturation,.color,.luminosity],id:\.self){Text($0.rawValue).tag($0)}}.frame(width:150)
      }
      if kind == .colorReplacement || kind == .backgroundEraser {
        Picker("Sampling:",selection:option(\.sampling)){Text("Continuous").tag(PaintSampling.continuous);Text("Once").tag(PaintSampling.once);Text("Background Swatch").tag(PaintSampling.backgroundSwatch)}.frame(width:195)
        Picker("Limits:",selection:option(\.limits)){Text("Discontiguous").tag(PaintLimits.discontiguous);Text("Contiguous").tag(PaintLimits.contiguous);Text("Find Edges").tag(PaintLimits.findEdges)}.frame(width:175)
        percentage("Tolerance:",\.tolerance)
        if kind == .backgroundEraser {Toggle("Protect Foreground Color",isOn:option(\.protectForeground))}
      }
      if kind == .colorReplacement || kind == .magicEraser {Toggle("Anti-alias",isOn:option(\.antiAlias))}
      if kind == .magicEraser {
        field("Tolerance:",value:Binding(get:{store.currentPaintOptions.tolerance*255},set:{if $0.isFinite{store.currentPaintOptions.tolerance=min(255,max(0,$0.rounded()))/255}}))
        Toggle("Contiguous",isOn:option(\.contiguous));Toggle("Sample All Layers",isOn:option(\.sampleAllLayers))
      }
      if kind == .mixerBrush {
        let color=store.mixerPaint.reservoir ?? .clear
        Rectangle().fill(Color(red:Double(color.r),green:Double(color.g),blue:Double(color.b),opacity:store.mixerPaint.reservoir==nil ? 0:1)).frame(width:22,height:22).overlay(Rectangle().stroke(.gray)).help("Current brush load")
        Button("Load"){store.loadMixerColor()};Button("Clean"){store.cleanMixer()}
        Toggle("Load After Stroke",isOn:option(\.loadAfterStroke));Toggle("Clean After Stroke",isOn:option(\.cleanAfterStroke))
        percentage("Wet:",\.wet);percentage("Load:",\.load);percentage("Mix:",\.mix);percentage("Flow:",\.flow)
        Toggle("Sample All Layers",isOn:option(\.sampleAllLayers));Toggle("Load Solid Colors Only",isOn:option(\.loadSolidColorOnly))
        Text("⌥ Click to sample paint").foregroundStyle(.secondary)
      }
      if kind == .patternStamp {
        Menu(store.patterns.selected?.displayName ?? "Choose Pattern") {
          ForEach(store.patterns.items){p in Button(p.displayName){store.patterns.selectedID=p.id;store.patternStampOrigin=nil;store.patternStampID=nil}}
          Divider();Button("Patterns…"){store.colorTab = .patterns}
        }.frame(width:160)
        field("Scale:",value:Binding(get:{Double(store.currentPaintOptions.placement.scale)},set:{if $0.isFinite{store.currentPaintOptions.placement.scale=Float(min(1000,max(1,$0)))}}),suffix:"%")
        Toggle("Aligned",isOn:option(\.aligned));Toggle("Impressionist",isOn:option(\.impressionist))
      }
    }.controlSize(.small).toggleStyle(.checkbox).disabled(store.geometryBusy || store.hasToneDraft)
  }
}
