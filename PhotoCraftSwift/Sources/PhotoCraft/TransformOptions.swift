import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  func transformBinding(_ key: WritableKeyPath<TransformDraft, Double>) -> Binding<Double> {
    Binding(
      get: {guard let draft=store.transformDraft else{return 0};if key == \TransformDraft.centerX{return draft.transformReferencePoint.x};if key == \TransformDraft.centerY{return draft.transformReferencePoint.y};return draft[keyPath:key]},
      set: { value in
        guard value.isFinite, let draft = store.transformDraft else { return }
        store.updateTransform(draft.transformNumeric(key, value))
      })
  }
  var transformOptions: some View {
    Group {
      if store.transformDraft?.contentAware == true { contentAwareScaleOptions } else {
      Text(store.transformDraft?.selection == true && store.transformDraft?.selectedPixels != true ? "Transform Selection":"Free Transform").fontWeight(.medium)
      if store.transformDraft?.selection == true {selectionTransformModeOptions} else {TransformReferenceOptions(store: store)}
      numberField(
        "X", value: transformBinding(\.centerX), range: -1_000_000...1_000_000, suffix: "px")
      numberField(
        "Y", value: transformBinding(\.centerY), range: -1_000_000...1_000_000, suffix: "px")
      numberField("W", value: transformBinding(\.scaleX), range: -10_000...10_000, suffix: "%")
      Button {
        guard var draft = store.transformDraft else { return }
        draft.proportional.toggle()
        store.updateTransform(draft)
      } label: {
        Image(systemName: store.transformDraft?.proportional == true ? "link" : "link.slash")
      }
      .buttonStyle(.plain).help("Maintain aspect ratio · Shift temporarily toggles")
      numberField("H", value: transformBinding(\.scaleY), range: -10_000...10_000, suffix: "%")
      numberField("∠", value: transformBinding(\.angle), range: -3600...3600, suffix: "°")
      Picker(
        "Interpolation",
        selection: Binding(
          get: { store.transformDraft?.interpolation ?? .bicubic },
          set: { value in
            guard var draft = store.transformDraft else { return }
            draft.interpolation = value
            store.updateTransform(draft)
          })
      ) { ForEach(Resampling.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
        .frame(width: 105).controlSize(.mini)
      Button("Cancel") { store.cancelTransform() }.controlSize(.small).keyboardShortcut(
        .cancelAction)
      Button("Apply") { store.commitTransform() }.disabled(store.geometryBusy).controlSize(.small).keyboardShortcut(
        .defaultAction)
      }
    }
  }
}
