import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  var selectionTransformModeOptions:some View {
    Group {
      Picker("Mode",selection:Binding(get:{store.transformDraft?.selectionMode ?? .free},set:{store.chooseSelectionTransformMode($0)})) {ForEach(store.selectionTransformModes,id:\.self){Text($0.rawValue).tag($0)}}.labelsHidden().frame(width:110)
      Grid(horizontalSpacing:2,verticalSpacing:2) {ForEach(0..<3){row in GridRow{ForEach(0..<3){column in
        let anchor=CanvasAnchor.allCases[row*3+column]
        Button {if var draft=store.transformDraft {draft.referenceAnchor=anchor;store.updateTransform(draft)}} label:{Image(systemName:store.transformDraft?.referenceAnchor == anchor ? "square.fill":"square").font(.system(size:6))}.buttonStyle(.plain).accessibilityLabel("Reference point \(anchor.rawValue)")
      }}}}.frame(width:28)
      if store.selectionTransform?.loading == true || store.selectionTransform?.committing == true {ProgressView().controlSize(.mini)}
      if let error=store.selectionTransform?.error {Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange).help(error)}
    }.disabled(store.geometryBusy)
  }
}
