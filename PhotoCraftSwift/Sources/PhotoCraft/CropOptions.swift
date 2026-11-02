import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  func cropOption<T>(_ key: WritableKeyPath<CropDraft,T>,default value: T) -> Binding<T> {
    Binding(get:{ store.cropDraft?[keyPath:key] ?? value },set:{ value in guard var draft = store.cropDraft else { return };draft[keyPath:key] = value;store.updateCrop(draft) })
  }
  func cropDimension(horizontal: Bool) -> Binding<Double> {
    Binding(get:{ horizontal ? store.cropDraft?.width ?? 0:store.cropDraft?.height ?? 0 },set:{ value in
      guard value.isFinite,value > 0,var d = store.cropDraft else { return }
      if horizontal { let old = d.frame.scaleX;d.frame.scaleX = value/Double(d.frame.bounds.width)*100;if d.frame.proportional,old > 0 { d.frame.scaleY *= d.frame.scaleX/old } }
      else { let old = d.frame.scaleY;d.frame.scaleY = value/Double(d.frame.bounds.height)*100;if d.frame.proportional,old > 0 { d.frame.scaleX *= d.frame.scaleY/old } }
      store.updateCrop(d)
    })
  }
  var cropOptions: some View {
    Group {
      if store.cropDraft == nil {
        Button("New Crop") { store.beginCrop() }.disabled(!store.canBeginCrop)
      } else {
        Picker("Ratio",selection:Binding(get:{ store.cropDraft?.ratio ?? "Free" },set:{ value in guard var d = store.cropDraft else { return };d.setRatio(value,document:store.document);store.updateCrop(d) })) {
          ForEach(["Free","Original","1 : 1","4 : 5","5 : 7","2 : 3","16 : 9"],id:\.self) { Text($0).tag($0) }
        }.labelsHidden().frame(width:100).controlSize(.small)
        numberField("W",value:cropDimension(horizontal:true),range:1...Double(Surface.maxDimension),suffix:"px")
        Button { guard var d = store.cropDraft else { return };let w = d.width,h = d.height;d.frame.scaleX = h/Double(d.frame.bounds.width)*100;d.frame.scaleY = w/Double(d.frame.bounds.height)*100;store.updateCrop(d) } label: { Image(systemName:"arrow.left.arrow.right") }.buttonStyle(.plain).help("Swap crop width and height")
        numberField("H",value:cropDimension(horizontal:false),range:1...Double(Surface.maxDimension),suffix:"px")
        numberField("Angle",value:cropOption(\.frame.angle,default:0),range:-45...45,suffix:"°")
        Toggle("Straighten",isOn:$store.cropStraighten).toggleStyle(.button).help("Draw along a horizontal or vertical feature")
        Toggle("Delete Cropped Pixels",isOn:cropOption(\.deletePixels,default:true)).disabled(!store.canRetainCroppedPixels).help("Convert Background, indexed or ink content to regular component layers to retain cropped pixels.")
        Picker("Fill",selection:cropOption(\.fill,default:.transparent)) {
          Text("Transparent").tag(CropRequest.Fill.transparent);Text("Background Color").tag(CropRequest.Fill.background);Text("Content-Aware Fill").tag(CropRequest.Fill.contentAware)
        }.frame(width:190).controlSize(.small)
        Toggle("Preview",isOn:$store.cropShowPreview)
        if store.cropBusy { ProgressView().controlSize(.small) }
        if let error = store.cropError { Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange).help(error).accessibilityLabel(error) }
        Button("Reset") { store.cancelCrop();store.beginCrop() }.controlSize(.small)
        Button("Cancel") { store.cancelCrop() }.controlSize(.small).keyboardShortcut(.cancelAction)
        Button("Apply") { store.commitCrop() }.controlSize(.small).keyboardShortcut(.defaultAction).disabled(store.cropReadyDraft != store.cropDraft || store.cropPrepared == nil)
      }
    }
  }
}
