import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

@MainActor extension EditorStore {
  var adjustmentBrushLayer:Layer? {
    guard !adjustmentBrushNewLayer,let layer=activeLayer,case .adjustment=layer.content,layer.mask != nil,layer.smartObject==nil else {return nil};return layer
  }
  var currentAdjustmentBrushKind:AdjustmentBrushKind {
    if let layer=adjustmentBrushLayer,case .adjustment(let value)=layer.content,let kind=AdjustmentBrushKind(adjustment:value) {return kind};return adjustmentBrushKind
  }
  var canUseAdjustmentBrush:Bool {canUseBrush && !editingComponent && !aiBusy}
  func adjustmentBrushRequest(points:[StrokePoint],brush:Brush,alternate:Bool=false)->AdjustmentBrushRequest {
    let layer=adjustmentBrushLayer
    let value:Adjustment;if let layer,case .adjustment(let existing)=layer.content {value=existing}else{value=adjustmentBrushKind.initial}
    return .init(layerID:layer?.id,adjustment:value,points:points,brush:brush,subtract:adjustmentBrushSubtract != alternate)
  }
  func acceptAdjustmentBrush(_ id:UUID) {
    guard document.layers.contains(where:{$0.id==id}) else {return}
    adjustmentBrushNewLayer=false;selectedLayerIDs=[id];maskEditingLayerID=id;smartFilterMaskEditing=false
    propertiesTab = .properties
  }
  func newAdjustmentBrush() {guard canUseAdjustmentBrush else{return};cancelBrush();adjustmentBrushNewLayer=true;adjustmentBrushSubtract=false;clearMaskView();render()}
  func replaceAdjustmentBrush(_ kind:AdjustmentBrushKind) {
    guard canUseAdjustmentBrush else{return};adjustmentBrushKind=kind
    if let layer=adjustmentBrushLayer {performGeometry(.replaceContent(layer.id,.adjustment(kind.initial)))}
  }
  func applyAdjustmentObject(at point:PathPoint,alternate:Bool=false) {
    guard canUseAdjustmentBrush else{return}
    let request=adjustmentBrushRequest(points:[],brush:brush,alternate:alternate),detector=objectDetector
    performGeometry(label:"Adjustment Brush — Object",prepare:{original in try await AdjustmentBrushPreparation.object(request,at:point,in:original,detector:detector)})
  }
  var adjustmentBrushMaskView:LayerMaskView? {
    guard tool == .adjustmentBrush,adjustmentBrushOverlay else {return nil}
    if let request=brushGesture?.adjustmentRequest {return .init(layerID:request.layerID ?? request.newLayerID,generation:layerPanelGeneration,mode:.overlay)}
    guard let id=adjustmentBrushLayer?.id else{return nil};return .init(layerID:id,generation:layerPanelGeneration,mode:.overlay)
  }
}

struct AdjustmentBrushOptionsView:View {
  @Bindable var store:EditorStore
  func number(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
    HStack(spacing:3){Text(title);TextField(title,value:Binding(get:{value.wrappedValue},set:{if $0.isFinite{value.wrappedValue=min(range.upperBound,max(range.lowerBound,$0))}}),format:.number.precision(.fractionLength(0...1))).labelsHidden().textFieldStyle(.roundedBorder).frame(width:45)}
  }
  var body:some View {
    HStack(spacing:10) {
      Picker("Adjustment:",selection:Binding(get:{store.currentAdjustmentBrushKind},set:{store.replaceAdjustmentBrush($0)})){ForEach(AdjustmentBrushKind.allCases,id:\.self){Text($0.title).tag($0)}}.frame(width:220)
      Button("New Adjustment"){store.newAdjustmentBrush()}
      Picker("Brush",selection:$store.adjustmentBrushSubtract){Text("Add").tag(false);Text("Subtract").tag(true)}.pickerStyle(.segmented).frame(width:130)
      number("Size:",$store.brush.size,0.5...2048)
      number("Hardness:",Binding(get:{Double(store.brush.hardness)*100},set:{store.brush.hardness=Float($0/100)}),0...100)
      number("Opacity:",Binding(get:{Double(store.brush.opacity)*100},set:{store.brush.opacity=Float($0/100)}),0...100)
      number("Flow:",Binding(get:{store.brushOptions.flow*100},set:{store.brushOptions.flow=$0/100}),0...100)
      Toggle("Apply to Object",isOn:$store.adjustmentBrushObject)
      Toggle("Overlay",isOn:Binding(get:{store.adjustmentBrushOverlay},set:{store.adjustmentBrushOverlay=$0;store.render()}))
      Button("Invert Mask"){if let id=store.adjustmentBrushLayer?.id{store.performGeometry(.invertMask(id))}}.disabled(store.adjustmentBrushLayer==nil)
      if let layer=store.adjustmentBrushLayer {
        number("Feather:",Binding(get:{layer.effectiveMaskProperties.feather},set:{v in store.updateMask(layer.id){$0.feather=v}}),0...100)
        number("Density:",Binding(get:{Double(layer.effectiveMaskProperties.density)*100},set:{v in store.updateMask(layer.id){$0.density=Float(v/100)}}),0...100)
      }
      Button("Properties"){store.propertiesTab = .properties;store.reveal(PropertiesTab.properties)}
      Button("Brush Settings"){NSApp.sendAction(#selector(AppDelegate.showBrushSettings),to:nil,from:nil)}
    }.controlSize(.small).toggleStyle(.checkbox).disabled(!store.canUseAdjustmentBrush)
  }
}
