import PhotoCraftCore
import SwiftUI

extension WorkspaceView {
  func transformBinding(_ key: WritableKeyPath<TransformDraft, Double>) -> Binding<Double> {
    Binding(
      get: { store.transformDraft?[keyPath: key] ?? 0 },
      set: { value in
        guard value.isFinite, var draft = store.transformDraft else { return }
        let old = draft[keyPath: key]
        draft[keyPath: key] = value
        if draft.proportional && old != 0 {
          if key == \TransformDraft.scaleX { draft.scaleY *= value / old }
          if key == \TransformDraft.scaleY { draft.scaleX *= value / old }
        }
        store.updateTransform(draft)
      })
  }
  var transformOptions: some View {
    Group {
      Text("Free Transform").fontWeight(.medium)
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
      Button("Apply") { store.commitTransform() }.controlSize(.small).keyboardShortcut(
        .defaultAction)
    }
  }
}
