import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class SkyRenameDraft: Identifiable {
  let id = UUID()
  let skyID: UUID
  let libraryRevision: Int
  let sourceState: SkyState
  var name: String
  var error: String?
  init(preset: SkyPreset, revision: Int, state: SkyState) {
    skyID = preset.id; name = preset.name; libraryRevision = revision; sourceState = state
  }
}

@MainActor extension SkyWorkspace {
  func beginSkyRename() {
    guard canRenameSky, let id = state.skyID, let preset = try? library.preset(id) else { return }
    renameDraft = SkyRenameDraft(preset: preset, revision: library.revision, state: state)
  }
  func cancelSkyRename(_ draft: SkyRenameDraft) {
    if renameDraft === draft { renameDraft = nil }
  }
  @discardableResult func confirmSkyRename(_ draft: SkyRenameDraft) -> Bool {
    guard renameDraft === draft else { return false }
    guard ready, state == draft.sourceState, library.revision == draft.libraryRevision else {
      renameDraft = nil
      error = "The sky library or selection changed. Rename the sky again."
      return false
    }
    do {
      try library.rename(draft.skyID, draft.name)
      renameDraft = nil
      // A prepared replacement also carries the preset name. Cancel the older preview.
      refresh()
      return true
    } catch {
      draft.error = error.localizedDescription
      return false
    }
  }
}

struct SkyRenameSheet: View {
  @Bindable var model: SkyWorkspace
  @Bindable var draft: SkyRenameDraft
  @FocusState private var editingName: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Rename Sky").font(.headline)
      TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
        .focused($editingName)
        .onSubmit { if !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.confirmSkyRename(draft) } }
      if let error = draft.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Spacer()
        Button("Cancel") { model.cancelSkyRename(draft) }.keyboardShortcut(.cancelAction)
        Button("OK") { model.confirmSkyRename(draft) }.keyboardShortcut(.defaultAction)
          .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(20).frame(width: 380)
      .task { editingName = true }
      .onDisappear { model.cancelSkyRename(draft) }
  }
}
