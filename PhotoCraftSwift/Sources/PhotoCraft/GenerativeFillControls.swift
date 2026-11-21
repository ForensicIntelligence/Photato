import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

enum GenerativeFillModelPreference {
  static let key = "localGenerativeFillModel"

  static func url(defaults: UserDefaults = .standard) -> URL? {
    guard let data = defaults.data(forKey: key) else { return nil }
    for options: URL.BookmarkResolutionOptions in [
      [.withSecurityScope, .withoutUI, .withoutMounting], [.withoutUI, .withoutMounting]
    ] {
      var stale = false
      if let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale), !stale {
        return url
      }
    }
    return nil
  }

  static func bookmark(for url: URL) throws -> Data {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    if let scoped = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) {
      return scoped
    }
    return try url.bookmarkData()
  }
}

@Observable @MainActor final class GenerativeFillDraft: Identifiable {
  var model = GenerativeFillModelPreference.url()
  var selectingModel = false
  var generating = false
  var error: String?
}

extension EditorStore {
  var canBeginGenerativeFill: Bool {
    LocalGenerativeFill.supported && generativeFillDraft == nil && !geometryBusy && !aiBusy
      && !hasToneDraft && !coalescingChanges && transformDraft == nil && !editingComponent && !editingMask
      && LocalGenerativeFill.selection(in: document) != nil
  }

  func beginGenerativeFill() {
    finishLayerName()
    guard canBeginGenerativeFill else { return }
    generativeFillDraft = GenerativeFillDraft()
  }

  func cancelGenerativeFill() {
    guard let draft = generativeFillDraft else { return }
    if draft.generating { geometryTask?.cancel() }
    generativeFillDraft = nil
  }

  func generateFill(_ draft: GenerativeFillDraft, prepare: @escaping @Sendable (CraftDocument, URL) throws -> Command = {
    try LocalGenerativeFill.prepare($0, model: $1)
  }) {
    guard generativeFillDraft === draft, !geometryBusy, !draft.selectingModel, !draft.generating,
      !editingComponent, !editingMask, let url = draft.model else { return }
    let original = document, generation = layerPanelGeneration, sessionID = sessionGeneration
    geometryBusy = true
    draft.error = nil
    draft.generating = true
    geometryTask = Task { [weak self, weak draft] in
      let worker = Task.detached(priority: .userInitiated) {
        try PreparedEdit(command: prepare(original, url), document: original)
      }
      defer {
        draft?.generating = false
        if let self, self.layerPanelGeneration == generation {
          self.geometryBusy = false
          self.geometryTask = nil
          self.render()
        }
      }
      do {
        let edit = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, let draft, self.generativeFillDraft === draft,
          self.layerPanelGeneration == generation, self.sessionGeneration == sessionID,
          self.document == original, !self.editingMask, !self.editingComponent else { return }
        try self.executeCompositePreparedEdit(edit)
        self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
        self.onChange?(.changeDone)
        self.status = edit.label
        self.generativeFillDraft = nil
      } catch is CancellationError {
        return
      } catch {
        draft?.error = error.localizedDescription
      }
    }
  }
}

extension AppDelegate {
  @objc func generativeFill() { store?.beginGenerativeFill() }
}

struct GenerativeFillSheet: View {
  let store: EditorStore
  @Bindable var draft: GenerativeFillDraft

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Generative Fill").font(.headline)
      Text("Fill the selection from surrounding pixels. The result is added on a layer with an editable mask.")
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        LabeledContent("Local model", value: draft.model?.deletingPathExtension().lastPathComponent ?? "Choose LaMa512")
        Button(draft.model == nil ? "Choose Model…" : "Change…", action: chooseModel)
          .disabled(draft.selectingModel || draft.generating)
      }
      if draft.selectingModel || draft.generating {
        ProgressView(draft.generating ? "Filling selection on this Mac…" : "Checking model…")
          .controlSize(.small)
      }
      if let error = draft.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Spacer()
        Button("Cancel") { store.cancelGenerativeFill() }.keyboardShortcut(.cancelAction)
        Button("Generate") { store.generateFill(draft) }
          .keyboardShortcut(.defaultAction)
          .disabled(draft.model == nil || draft.selectingModel || draft.generating)
      }
    }
    .padding(20)
    .frame(width: 410)
    .interactiveDismissDisabled(draft.generating)
  }

  private func chooseModel() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Model"
    panel.message = "Select the compiled LaMa512.mlmodelc package."
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        guard store.generativeFillDraft === draft, !draft.generating, !draft.selectingModel else { return }
        guard url.pathExtension.lowercased() == "mlmodelc" else {
          draft.error = "Choose a compiled .mlmodelc package."; return
        }
        draft.selectingModel = true
        draft.error = nil
        defer { draft.selectingModel = false }
        do {
          let bookmark = try GenerativeFillModelPreference.bookmark(for: url)
          try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try LocalGenerativeFill.validateModel(url)
          }.value
          guard store.generativeFillDraft === draft else { return }
          UserDefaults.standard.set(bookmark, forKey: GenerativeFillModelPreference.key)
          draft.model = GenerativeFillModelPreference.url()
        } catch { draft.error = error.localizedDescription }
      }
    }
  }
}
