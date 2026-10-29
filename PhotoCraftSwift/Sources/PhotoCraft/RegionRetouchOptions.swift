import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  func retouchOption<T>(_ key: WritableKeyPath<RegionRetouchRequest,T>) -> Binding<T> {
    Binding(get:{ store.regionRetouchSettings[keyPath:key] },set:{ value in var r = store.regionRetouchSettings;r[keyPath:key] = value;store.updateRegionRetouchSettings(r) })
  }
  func retouchInteger(_ key: WritableKeyPath<RegionRetouchRequest,Int>) -> Binding<Double> {
    Binding(get:{ Double(store.regionRetouchSettings[keyPath:key]) },set:{ value in guard value.isFinite else { return };var r = store.regionRetouchSettings;r[keyPath:key] = Int(value.rounded());store.updateRegionRetouchSettings(r) })
  }
  func retouchTransform(_ key: WritableKeyPath<TransformDraft,Double>) -> Binding<Double> {
    Binding(get:{ store.regionRetouchDraft?.frame[keyPath:key] ?? 0 },set:{ value in guard value.isFinite,var d = store.regionRetouchDraft else { return };d.frame[keyPath:key] = value;store.updateRegionRetouch(d) })
  }
  var regionRetouchOptions: some View {
    Group {
      if store.tool == .redEye {
        numberField("Pupil Size",value:retouchOption(\.pupilSize),range:1...100,suffix:"%")
        numberField("Darken Amount",value:retouchOption(\.darken),range:0...100,suffix:"%")
      } else {
        if store.tool == .patch {
          Picker("Patch",selection:retouchOption(\.patchType)) { Text("Normal").tag(RegionRetouchRequest.PatchType.normal);Text("Content-Aware").tag(RegionRetouchRequest.PatchType.contentAware) }.frame(width:175)
          Picker("Mode",selection:retouchOption(\.patchMode)) { Text("Source").tag(RegionRetouchRequest.PatchMode.source);Text("Destination").tag(RegionRetouchRequest.PatchMode.destination) }.frame(width:165)
          if store.regionRetouchSettings.patchType == .normal {
            Toggle("Transparent",isOn:retouchOption(\.transparent)).toggleStyle(.checkbox)
            numberField("Diffusion",value:retouchInteger(\.diffusion),range:1...7,suffix:"")
          }
        } else {
          Picker("Mode",selection:retouchOption(\.moveMode)) { Text("Move").tag(RegionRetouchRequest.MoveMode.move);Text("Extend").tag(RegionRetouchRequest.MoveMode.extend) }.frame(width:145)
          Toggle("Transform On Drop",isOn:$store.regionRetouchTransformOnDrop).toggleStyle(.checkbox)
        }
        if store.tool == .contentAwareMove || store.regionRetouchSettings.patchType == .contentAware {
          numberField("Structure",value:retouchInteger(\.structure),range:1...7,suffix:"")
          numberField("Color",value:retouchInteger(\.color),range:0...10,suffix:"")
          Toggle("Sample All Layers",isOn:retouchOption(\.sampleAllLayers)).toggleStyle(.checkbox)
        }
        if store.tool == .contentAwareMove,store.regionRetouchDraft != nil {
          numberField("W",value:retouchTransform(\.scaleX),range:1...1000,suffix:"%")
          numberField("H",value:retouchTransform(\.scaleY),range:1...1000,suffix:"%")
          numberField("Angle",value:retouchTransform(\.angle),range:-360...360,suffix:"°")
        }
      }
      if store.regionRetouchBusy { ProgressView().controlSize(.small) }
      if let error = store.regionRetouchError { Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange).help(error).accessibilityLabel(error) }
      if store.regionRetouchDraft != nil {
        Button("Cancel") { store.cancelRegionRetouch() }.keyboardShortcut(.cancelAction)
        Button("Apply") { store.commitRegionRetouch() }.keyboardShortcut(.defaultAction).disabled(store.regionRetouchPrepared == nil || store.regionRetouchBusy)
      } else { Text(store.tool == .redEye ? "Click or drag around an eye" : "Select an area, then drag inside it").foregroundStyle(.secondary) }
    }.controlSize(.small)
  }
}
