import AppKit
import PhotoCraftCore
import SwiftUI

struct ModernAdjustmentEditor: View {
  @Bindable var store:EditorStore
  let layerID:UUID
  private var value:ModernAdjustment? {
    if case .adjustment(.modern(let value))=store.document.layers.first(where:{$0.id==layerID})?.content {return value}
    return nil
  }
  var body:some View {
    if let value {
      VStack(alignment:.leading,spacing:12) {
        Text(value.kind.title).font(.headline)
        if store.lightEditingPreview.pausedLayerIDs.contains(layerID) { LightPreviewNotice(count: 1) }
        ForEach(ModernAdjustment.controls(for:value.kind)) {control in
          let title=control.key == "grainAmount" ? "Amount":control.key == "grainSize" ? "Size":control.key == "grainRoughness" ? "Roughness":control.title
          let binding=Binding<Double>(get:{Double(self.value?.values[control.key] ?? control.initial)},set:{number in
            guard number.isFinite,var changed=self.value else{return}
            changed.values[control.key]=Float(min(Double(control.maximum),max(Double(control.minimum),number)))
            store.setModernAdjustment(layerID,changed)
          })
          VStack(spacing:3) {
            HStack {Text(title);Spacer();TextField(title,value:binding,format:.number.precision(.fractionLength(control.key == "exposure" ? 2:0))).textFieldStyle(.roundedBorder).monospacedDigit().frame(width:64)}
            Slider(value:binding,in:Double(control.minimum)...Double(control.maximum),step:control.key == "exposure" ? 0.01:1,onEditingChanged:{store.coalesce($0)}).accessibilityLabel(title)
          }.disabled(value.kind == .grain && control.key != "grainAmount" && value.values["grainAmount",default:0] == 0)
        }
        Button("Reset") {store.setModernAdjustment(layerID,.init(value.kind))}
        if value.kind == .light {
          Button("Use legacy Brightness/Contrast") {store.perform(.replaceContent(layerID,.adjustment(.brightnessContrast(0,1))))}
            .help("Replace these settings with the existing Brightness/Contrast controls. Undo restores this Light layer.")
        }
      }.disabled(store.document.isLocked(layerID))
    }
  }
}

extension EditorStore {
  func canAddModernAdjustment(_ kind:ModernAdjustment.Kind)->Bool {
    !geometryBusy && transformDraft==nil && !hasToneDraft && !editingComponent && (try? ModernAdjustment(kind).validate(in:document)) != nil
  }
  func addModernAdjustment(_ kind:ModernAdjustment.Kind) {
    guard canAddModernAdjustment(kind) else{return}
    do {perform(.addLayer(try ModernAdjustment(kind).layer(in:document)));propertiesTab = .properties}
    catch {self.error=error.localizedDescription}
  }
  func setModernAdjustment(_ id:UUID,_ value:ModernAdjustment) {
    guard case .adjustment(.modern(let old))=document.layers.first(where:{$0.id==id})?.content,old.kind==value.kind else{return}
    do {try value.validate(in:document);perform(.replaceContent(id,.adjustment(.modern(value))))}
    catch {self.error=error.localizedDescription}
  }
}
extension AppDelegate {
  @objc func newColorVibrance() {store?.addModernAdjustment(.colorVibrance)}
  @objc func newLight() {store?.addModernAdjustment(.light)}
  @objc func newClarityDehaze() {store?.addModernAdjustment(.clarityDehaze)}
  @objc func newGrain() {store?.addModernAdjustment(.grain)}
}
