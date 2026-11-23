import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct RemoveRelatedControls: View {
  @Bindable var store: EditorStore
  var close: () -> Void
  @State private var validating = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Remove Related Elements").font(.headline)
      if validating || store.removeRelatedID != nil {
        ProgressView(validating ? "Checking the model…" : "Finding related elements…").controlSize(.small)
      } else if let review = store.removeDraft?.relatedReview {
        if review.groups.isEmpty { Text("No related elements found.").foregroundStyle(.secondary) }
        ForEach(review.groups, id: \.element) { group in
          Toggle(group.element.title, isOn: Binding(get: {
            store.removeDraft?.relatedReview?.enabled.contains(group.element) == true
          }, set: { enabled in
            guard var elements = store.removeDraft?.relatedReview?.enabled else { return }
            if enabled { elements.insert(group.element) } else { elements.remove(group.element) }
            do { try store.updateRelatedElements(elements) } catch { self.error = error.localizedDescription }
          })).toggleStyle(.checkbox)
        }
        Text("Refine the highlighted areas with the Remove brush before applying.")
          .foregroundStyle(.secondary)
      } else if store.removeRelatedArmed {
        Text("Mark one object on the canvas, then review its related elements.").foregroundStyle(.secondary)
        Button("Find Related Elements") { store.findRelatedElements() }
          .disabled(!store.canFindRelatedElements)
      } else {
        if store.localRemoveModel == nil { Text("Choose the local Remove model in the processing menu.").foregroundStyle(.secondary) }
        Button(store.removeRelatedModelURL == nil ? "Choose Detection Model…" : "Change Detection Model…", action: chooseModel)
        Button("Mark Object") {
          do { try store.armRelatedElements(); close() } catch { self.error = error.localizedDescription }
        }.disabled(!store.canStartRelatedElements)
      }
      if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Spacer()
        Button(store.removeRelatedArmed ? "Cancel" : "Close") {
          if store.removeRelatedArmed { store.cancelRemove() }
          close()
        }.keyboardShortcut(.cancelAction)
        if store.removeDraft?.relatedReview != nil {
          Button("Apply") { store.applyRemove(); close() }.keyboardShortcut(.defaultAction)
            .disabled(store.geometryBusy || store.removeStroke != nil)
        }
      }
    }.padding(14).frame(width: 274).controlSize(.small)
  }

  private func chooseModel() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
    panel.prompt = "Choose Model"
    panel.message = "Select the compiled RelatedElementsV1.mlmodelc package."
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        validating = true
        defer { validating = false }
        do {
          guard url.pathExtension.lowercased() == "mlmodelc" else { throw CraftError.invalid("Choose a compiled .mlmodelc package.") }
          let bookmark = try GenerativeFillModelPreference.bookmark(for: url)
          try await Task.detached(priority: .userInitiated) {
            let read = url.startAccessingSecurityScopedResource()
            defer { if read { url.stopAccessingSecurityScopedResource() } }
            _ = try CoreMLRelatedElements(url: url)
          }.value
          guard !store.removeRelatedArmed, store.removeDraft == nil else { return }
          UserDefaults.standard.set(bookmark, forKey: RemoveRelatedPreference.key)
          store.removeRelatedBookmark = bookmark; store.removeRevision = UUID(); error = nil
        } catch { self.error = error.localizedDescription }
      }
    }
  }
}
