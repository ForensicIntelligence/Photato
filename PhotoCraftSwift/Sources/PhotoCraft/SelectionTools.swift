import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

enum ObjectSelectionMode:String,CaseIterable {case rectangle="Rectangle",lasso="Lasso",point="Object Click"}
extension EditorTool {
  var selectionToolKind:SelectionToolKind? {switch self {case .objectSelection:.object;case .quickSelection:.quick;case .selectionBrush:.brush;default:nil}}
  var usesSelectionStroke:Bool {self == .quickSelection || self == .selectionBrush}
}
@MainActor extension EditorStore {
  var canUseSelectionTools:Bool {canUseBrush && !editingComponent && !aiBusy && document.width<=SelectionSegmentation.maximumPixels/max(1,document.height)}
  var canSelectSubjectFromToolOptions:Bool {
    let sourceTool = [.objectSelection,.quickSelection].contains(tool) ? canUseSelectionTools
      : (tool == .magicWand && canUseMagicWand)
    return sourceTool && canDetectSubject() && brushGesture == nil
  }
  func selectSubjectFromToolOptions() {
    guard canSelectSubjectFromToolOptions else{return}
    detectSubject(sampleAllLayers:tool == .magicWand ? wandSampleAllLayers:selectionSampleAllLayers)
  }
  func selectionToolMode(modifiers:NSEvent.ModifierFlags)->SelectionMode {
    if modifiers.contains([.shift,.option]) {return .intersect}
    if modifiers.contains(.option){return .subtract};if modifiers.contains(.shift){return .add}
    return tool == .objectSelection ? selectionMode:selectionPaintMode
  }
  func selectionToolRequest(_ kind:SelectionToolKind,points:[StrokePoint]=[],brush:Brush?=nil,mode:SelectionMode?=nil)->SelectionToolRequest {
    var request=SelectionToolRequest(kind:kind);request.layerID=activeLayer?.id;request.points=points;request.brush=brush ?? self.brush
    request.mode=mode ?? (kind == .object ? selectionMode:selectionPaintMode);request.sampleAllLayers=selectionSampleAllLayers;request.enhanceEdge=selectionEnhanceEdge
    request.hardEdge = kind == .object && objectFinderHardEdge
    return request
  }
  func selectObject(shape:SelectionShape?=nil,point:PathPoint?=nil,mode:SelectionMode) {
    guard canUseSelectionTools else{return}
    if shape == nil, let point, objectFinderEnabled {selectFoundObject(at:point,mode:mode);return}
    var request=selectionToolRequest(.object,mode:mode);request.region=shape
    if let point{request.points=[.init(x:point.x,y:point.y)]}
    let final=request,detector=objectDetector
    performGeometry(label:"Object Selection",prepare:{original in try await SelectionToolPreparation.command(final,in:original,detector:detector)})
  }
}
struct SelectionToolOptionsView:View {
  @Bindable var store:EditorStore
  private var mode:Binding<SelectionMode> {store.tool == .objectSelection ? $store.selectionMode:$store.selectionPaintMode}
  var body:some View {
    HStack(spacing:10) {
      Picker("Selection",selection:mode){ForEach(SelectionMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}.frame(width:140)
      if store.tool == .objectSelection {
        Picker("Mode:",selection:$store.objectSelectionMode){ForEach(ObjectSelectionMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}.frame(width:160)
      } else {
        number("Size:",$store.brush.size,1...2048)
        if store.tool == .selectionBrush {
          number("Hardness:",Binding(get:{Double(store.brush.hardness)*100},set:{store.brush.hardness=Float($0/100)}),0...100)
          number("Opacity:",Binding(get:{Double(store.brush.opacity)*100},set:{store.brush.opacity=Float($0/100)}),0...100)
          ColorPicker("Overlay:",selection:Binding(get:{Color(red:Double(store.selectionOverlayColor.r),green:Double(store.selectionOverlayColor.g),blue:Double(store.selectionOverlayColor.b),opacity:Double(store.selectionOverlayColor.a))},set:{v in guard let color=NSColor(v).usingColorSpace(.sRGB) else{return};store.selectionOverlayColor=Pixel(Float(color.redComponent),Float(color.greenComponent),Float(color.blueComponent),Float(color.alphaComponent));store.render()})).frame(width:110)
        }
      }
      if store.tool != .selectionBrush {
        Toggle("Sample All Layers",isOn:$store.selectionSampleAllLayers)
        if store.tool == .objectSelection {
          Button("Select People"){store.openPeoplePicker()}.popover(isPresented:Binding(get:{store.peopleWorkspace.presented},set:{store.peopleWorkspace.presented=$0})){PeoplePickerView(store:store)}
          Toggle("Hard Edge",isOn:$store.objectFinderHardEdge)
          Toggle("Object Finder",isOn:$store.objectFinderEnabled)
          Button {store.requestObjectFinder(force:true)} label: {Image(systemName:"arrow.clockwise")}.help("Refresh detected objects")
          if store.objectFinder.busy {ProgressView().controlSize(.small)}
          Menu {
            ColorPicker("Highlight Color",selection:Binding(get:{Color(red:Double(store.objectFinderColor.r),green:Double(store.objectFinderColor.g),blue:Double(store.objectFinderColor.b),opacity:Double(store.objectFinderColor.a))},set:{v in guard let c=NSColor(v).usingColorSpace(.sRGB) else{return};store.objectFinderColor=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent),Float(c.alphaComponent))}))
            if let error=store.objectFinder.error {Text(error)}
            if store.objectFinder.busy {Button("Cancel Detection"){store.stopObjectFinder()}}
          } label: {Image(systemName:"gearshape")}.help(store.objectFinder.error ?? "Object Finder options")
        } else {Toggle("Enhance Edge",isOn:$store.selectionEnhanceEdge)}
      }
      if [.objectSelection,.quickSelection].contains(store.tool) {
        Button("Select Subject"){store.selectSubjectFromToolOptions()}
          .disabled(!store.canSelectSubjectFromToolOptions)
          .accessibilityIdentifier("selection.options.subject")
          .help("Select the main subjects using on-device processing.")
      }
      Button("Select and Mask…"){store.beginSelectMask()}.disabled(!store.canBeginSelectMask)
    }.toggleStyle(.checkbox).controlSize(.small).disabled(!store.canUseSelectionTools)
  }
  private func number(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
    HStack(spacing:3){Text(title);TextField(title,value:Binding(get:{value.wrappedValue},set:{if $0.isFinite{value.wrappedValue=min(range.upperBound,max(range.lowerBound,$0))}}),format:.number.precision(.fractionLength(0...1))).labelsHidden().textFieldStyle(.roundedBorder).frame(width:50)}
  }
}
