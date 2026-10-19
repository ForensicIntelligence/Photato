import AppKit
import PhotoCraftAI
import SwiftUI

extension WorkspaceView {
  var aiSheet: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: "sparkles").font(.title2).foregroundStyle(StudioTheme.accent)
        Text("Create with Apple Intelligence").font(.title2.weight(.semibold))
        Spacer()
      }
      Text(
        "Create an illustration with Image Playground and add it as a new image layer."
      ).font(.callout).foregroundStyle(.secondary)
      TextEditor(text: $store.prompt).font(.body).frame(height: 110).padding(8).background(
        .quaternary, in: RoundedRectangle(cornerRadius: 8))
      Label(LocalAI.imageCapability.message, systemImage: "photo").font(.caption)
        .foregroundStyle(.secondary)
      Label(LocalAI.textCapability.message, systemImage: "text.bubble").font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Button("Refine prompt") { store.refinePrompt() }.disabled(
          store.aiBusy || !LocalAI.textCapability.available || store.prompt.isEmpty)
        Spacer()
        if store.aiBusy {
          ProgressView().controlSize(.small)
          Button("Cancel") { store.aiTask?.cancel() }
        } else {
          Button("Done") { store.showAI = false }
          Button("Generate") { store.beginImageCreation() }.buttonStyle(.borderedProminent)
            .disabled(!LocalAI.imageCapability.available || store.prompt.isEmpty)
        }
      }
      if let error = store.aiError {
        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(
          .orange
        ).textSelection(.enabled)
      }
      Text(
        "Images use on-device models on macOS 26 and Apple's Private Cloud Compute on macOS 27 and later. Prompt refinement runs on-device."
      )
      .font(
        .caption2
      ).foregroundStyle(.tertiary)
    }.padding(26).frame(width: 500).preferredColorScheme(.dark)
      .sheet(isPresented: $store.showImagePlayground) {
        if #available(macOS 26.0, *), LocalAI.imageCapability.available {
          SystemImagePlayground(store: store).frame(width: 700, height: 650)
        }
      }
  }
}
