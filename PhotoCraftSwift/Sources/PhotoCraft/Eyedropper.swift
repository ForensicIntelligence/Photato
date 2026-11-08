import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class EyedropperPreferences {
  private(set) var settings=ColorSampleSettings()
  private(set) var revision=UUID()
  @ObservationIgnored private let defaults:UserDefaults?
  static let key="Photato.eyedropper.v1"
  init(defaults:UserDefaults? = nil) {
    self.defaults=defaults
    if let data=defaults?.data(forKey:Self.key),let value=try? JSONDecoder().decode(ColorSampleSettings.self,from:data),(try? value.validate()) != nil {settings=value}
  }
  func set(_ value:ColorSampleSettings)throws {
    try value.validate();guard value != settings else{return}
    settings=value;revision=UUID();if let data=try? JSONEncoder().encode(value){defaults?.set(data,forKey:Self.key)}
  }
}
struct EyedropperGesture {
  let id=UUID()
  let settings:ColorSampleSettings
  let target:ColorSampleTarget
  let original:PaintColorPair
  let context:PaintColorContext
  var finishing=false
  var lastPaletteRevision:Int
}
struct ColorSamplingInput:Sendable {
  let document:CraftDocument
  let displayed:Surface?
  func sample(x:Double,y:Double,settings:ColorSampleSettings,layerID:UUID?)throws->ColorSampleResult {
    if let displayed {let area=try ColorAveraging.region(x:x,y:y,width:displayed.width,height:displayed.height,size:settings.size);return try ColorAveraging.sample(region:area,depth:document.depth){displayed.pixel(x:$0,y:$1)}}
    return try ColorSampling.sample(document,x:x,y:y,settings:settings,layerID:layerID)
  }
}
extension EditorStore {
  var eyedropperSettings:ColorSampleSettings {
    get{eyedropperPreferences.settings}
    set{try? eyedropperPreferences.set(newValue)}
  }
  var eyedropperUsesDisplayedTarget:Bool {editingMask || editingComponent || document.colorMode != .rgb || document.isChannelOnly}
  var canUseEyedropper:Bool {!geometryBusy && !aiBusy && !hasToneDraft && !coalescingChanges && transformDraft == nil && unavailableToolID == nil}
  func adoptEyedropperPreferences(_ value:EyedropperPreferences){cancelEyedropper();eyedropperPreferences=value}
  func detachEyedropperPreferences(){let p=EyedropperPreferences();try? p.set(eyedropperSettings);adoptEyedropperPreferences(p)}
  func colorSamplingInput()throws->ColorSamplingInput {
    if eyedropperUsesDisplayedTarget {
      guard let surface else{throw CraftError.invalid("Wait for the channel preview before sampling.")}
      return .init(document:document,displayed:surface)
    }
    return .init(document:document,displayed:nil)
  }
  func setSampledColor(_ color:Pixel,target:ColorSampleTarget) {
    guard target != .none else{return};var pair=activePaintColorPair
    if target == .background {pair.background=color}else{pair.foreground=color};activePaintColorPair=pair
  }
  func beginEyedropper(at point:CGPoint,modifiers:NSEvent.ModifierFlags) {
    guard canUseEyedropper,!modifiers.contains(.shift),point.x>=0,point.y>=0,point.x<Double(document.width),point.y<Double(document.height)else{return}
    cancelEyedropper()
    eyedropperGesture=EyedropperGesture(settings:eyedropperSettings,target:modifiers.contains(.option) ? .background:.foreground,original:activePaintColorPair,context:paintColorContext,lastPaletteRevision:paintPalette.revision)
    requestEyedropper(at:point)
  }
  func requestEyedropper(at point:CGPoint,finishing:Bool = false) {
    guard var gesture=eyedropperGesture else{return}
    gesture.finishing=finishing;eyedropperGesture=gesture
    guard point.x>=0,point.y>=0,point.x<Double(document.width),point.y<Double(document.height)else {if finishing{eyedropperGesture=nil};return}
    eyedropperTask?.cancel();let generation=UUID();eyedropperGeneration=generation
    let input:ColorSamplingInput
    do{input=try colorSamplingInput()}catch{status=error.localizedDescription;if finishing{eyedropperGesture=nil};return}
    let sessionID=sessionGeneration,paletteRevision=paintPalette.revision,displayRevision=channelCompositeRevision,settingsRevision=eyedropperPreferences.revision
    let settings=gesture.settings
    eyedropperTask=Task{[weak self]in
      do {
        let worker=Task.detached(priority:.userInitiated){try input.sample(x:point.x,y:point.y,settings:settings,layerID:input.document.activeLayerID)}
        let result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard let self else{return}
        guard self.eyedropperGeneration==generation,self.eyedropperGesture?.id==gesture.id,self.sessionGeneration==sessionID,self.document==input.document,self.tool == .eyedropper,self.paintColorContext==gesture.context,self.paintPalette.revision==paletteRevision,self.eyedropperPreferences.revision==settingsRevision,input.displayed==nil || self.channelCompositeRevision==displayRevision else{if self.eyedropperGeneration==generation,self.eyedropperGesture?.id==gesture.id{self.cancelEyedropper()};return}
        self.setSampledColor(result.color,target:gesture.target);self.eyedropperResult=result
        self.eyedropperGesture?.lastPaletteRevision=self.paintPalette.revision
        if finishing{self.eyedropperGesture=nil}
      }catch{if !Task.isCancelled,let self,self.eyedropperGeneration==generation{self.status=error.localizedDescription;if finishing{self.eyedropperGesture=nil}}}
    }
  }
  func cancelEyedropper(restore:Bool = false) {
    eyedropperTask?.cancel();eyedropperTask=nil;eyedropperGeneration=UUID()
    if restore,let g=eyedropperGesture,paintColorContext==g.context,paintPalette.revision==g.lastPaletteRevision {activePaintColorPair=g.original}
    eyedropperGesture=nil;eyedropperResult=nil
  }
}
struct EyedropperOptions:View {
  @Bindable var store:EditorStore
  func option<T>(_ key:WritableKeyPath<ColorSampleSettings,T>)->Binding<T>{Binding(get:{store.eyedropperSettings[keyPath:key]},set:{var v=store.eyedropperSettings;v[keyPath:key]=$0;store.eyedropperSettings=v})}
  var body:some View {
    HStack {
      Picker("Sample Size",selection:option(\.size)){ForEach(ColorSampleSettings.sizes,id:\.self){Text($0==1 ? "Point Sample":"\($0) by \($0) Average").tag($0)}}.frame(width:225).accessibilityIdentifier("eyedropper.size")
      Picker("Sample",selection:option(\.source)){ForEach(ColorSampleSource.allCases,id:\.self){Text($0.rawValue).tag($0)}}.frame(width:265).disabled(store.eyedropperUsesDisplayedTarget).accessibilityIdentifier("eyedropper.source")
      Toggle("Show Sampling Ring",isOn:option(\.showRing)).accessibilityIdentifier("eyedropper.ring")
      if store.eyedropperUsesDisplayedTarget{Text("Sampling displayed channel").foregroundStyle(.secondary)}
    }.controlSize(.small).disabled(store.eyedropperGesture != nil)
  }
}
extension CraftCanvas {
  func drawEyedropperRing(in context:CGContext) {
    guard store.tool == .eyedropper,let gesture=store.eyedropperGesture,!gesture.finishing,gesture.settings.showRing,let point=cursorLocationInView else{return}
    let old=gesture.target == .background ? gesture.original.background:gesture.original.foreground
    let picked=store.eyedropperResult?.color ?? old
    let ring=CGMutablePath();ring.addEllipse(in:CGRect(x:point.x-40,y:point.y-40,width:80,height:80));ring.addEllipse(in:CGRect(x:point.x-23,y:point.y-23,width:46,height:46))
    context.saveGState();defer{context.restoreGState()};context.saveGState();context.addPath(ring);context.clip(using:.evenOdd)
    for (upper,color)in [(true,picked),(false,old)] {
      let c=NSColor(srgbRed:Double(unit(color.r)),green:Double(unit(color.g)),blue:Double(unit(color.b)),alpha:1)
      context.setFillColor(c.cgColor);context.fill(CGRect(x:point.x-40,y:upper ? point.y-40:point.y,width:80,height:40))
    }
    context.restoreGState();context.clip(to:bounds);context.setStrokeColor(NSColor.gray.cgColor);context.setLineWidth(6);context.strokeEllipse(in:CGRect(x:point.x-43,y:point.y-43,width:86,height:86))
  }
}
