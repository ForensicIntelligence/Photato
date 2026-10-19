import SwiftUI

@MainActor extension EditorStore {
  var historyStateLabels: [String] {
    ["Earliest available state"] + session.undoStack.map(\.label)
      + session.redoStack.reversed().map(\.label)
  }

  var canNavigateHistory: Bool {
    !geometryBusy && !hasToneDraft && transformDraft == nil
  }

  func selectHistoryState(_ index: Int) {
    guard canNavigateHistory, historyStateLabels.indices.contains(index) else { return }
    let current = session.undoStack.count
    // Count transitions before moving: the memory budget can discard older states en route.
    if index < current {
      for _ in index..<current { undo() }
    } else if index > current {
      for _ in current..<index { redo() }
    }
  }
}

struct HistoryPanel: View {
  @Bindable var store: EditorStore

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(Array(store.historyStateLabels.enumerated()), id: \.offset) { index, label in
              Button {
                store.selectHistoryState(index)
              } label: {
                HStack(spacing: 8) {
                  Image(systemName: index == 0 ? "doc" : "clock.arrow.circlepath")
                  Text(label).lineLimit(1)
                  Spacer(minLength: 0)
                }.padding(.horizontal, 10).frame(height: 28)
                  .contentShape(Rectangle())
                  .foregroundStyle(index > store.session.undoStack.count ? .secondary : .primary)
                  .background(
                    index == store.session.undoStack.count ? StudioTheme.selected : .clear)
              }.buttonStyle(.plain).disabled(!store.canNavigateHistory)
                .accessibilityLabel(label)
                .accessibilityValue(index == store.session.undoStack.count ? "Current state" : "")
                .id(index)
            }
          }
        }.onChange(of: store.session.undoStack.count) { _, index in proxy.scrollTo(index) }
      }
      HStack {
        Button("Undo") { store.undo() }
          .disabled(!store.canNavigateHistory || store.session.undoStack.isEmpty)
        Button("Redo") { store.redo() }
          .disabled(!store.canNavigateHistory || store.session.redoStack.isEmpty)
        Spacer()
      }.buttonStyle(.borderless).padding(8)
    }.background(StudioTheme.panel)
  }
}
