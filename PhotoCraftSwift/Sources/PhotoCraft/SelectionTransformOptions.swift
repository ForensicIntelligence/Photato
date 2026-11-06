import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  var selectionTransformModeOptions:some View {
    Group {
      Picker("Mode",selection:Binding(get:{store.transformDraft?.selectionMode ?? .free},set:{store.chooseSelectionTransformMode($0)})) {ForEach(store.selectionTransformModes,id:\.self){Text($0.rawValue).tag($0)}}.labelsHidden().frame(width:110)
      TransformReferenceOptions(store: store)
      if store.selectionTransform?.loading == true || store.selectionTransform?.committing == true {ProgressView().controlSize(.mini)}
      if let error=store.selectionTransform?.error {Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange).help(error)}
    }.disabled(store.geometryBusy)
  }
}
