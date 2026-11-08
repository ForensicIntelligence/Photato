import AppKit
import PhotoCraftAI
import SwiftUI

enum AIWorkspaceSection: String {
  case image, editPlan
}

extension WorkspaceView {
  var aiSheet: some View {
    VStack(spacing: 0) {
      Picker("Workflow", selection: $store.aiWorkspaceSection) {
        Text("Create Image").tag(AIWorkspaceSection.image)
        Text("Edit Plan").tag(AIWorkspaceSection.editPlan)
      }.pickerStyle(.segmented).accessibilityLabel("AI workflow")
        .disabled(store.aiBusy || store.editPlanBusy).padding(.horizontal, 20).padding(.vertical, 12)
      Divider()
      if store.aiWorkspaceSection == .image {
        ScrollView { aiImageSheet }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        EditPlanControls(store: store)
      }
    }.frame(width: 800, height: 660)
      .onAppear { store.aiWorkspaceSection = .image }
      .onDisappear { store.cancelReviewedEditPlan() }
  }
  var aiImageSheet: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: "sparkles").font(.title2).foregroundStyle(StudioTheme.accent)
        Text("Create with Apple Intelligence").font(.title2.weight(.semibold))
        Spacer()
      }
      Text(
        store.imageGenerationIntent == .background
          ? "Create a background with Image Playground. Your selected masked layer stays unchanged above it."
          : "Create an image with Image Playground and add it as a new image layer."
      ).font(.callout).foregroundStyle(.secondary)
      Picker("Destination",selection:$store.imageGenerationIntent) {
        ForEach(ImageGenerationIntent.allCases,id:\.self) { Text($0.title).tag($0) }
      }.disabled(store.aiBusy)
      if store.imageGenerationIntent == .image {
        GroupBox("Reference image") {
          HStack(spacing: 12) {
            if let reference = store.imageReference {
              Image(nsImage: NSImage(cgImage: reference.image, size: .zero))
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .accessibilityLabel("Selected visual reference")
              VStack(alignment: .leading, spacing: 4) {
                Text("\(reference.record.width) × \(reference.record.height) pixels").font(.caption)
                Button("Remove Reference") { store.removeImageReference() }
              }
            }
            Button(store.imageReference == nil ? "Choose Image…" : "Replace Image…") { store.chooseImageReference() }
            Spacer()
          }.frame(maxWidth: .infinity, alignment: .leading).disabled(store.aiBusy)
          Text("Used as visual inspiration. The system may change the reference; exact identity, style and composition are not guaranteed.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if store.imageGenerationIntent == .background {
        Text("The masked subject is provided to Image Playground as a visual reference. The new background fills the canvas without changing its size.")
          .font(.caption).foregroundStyle(.secondary)
        if GeneratedBackground.foreground(in:store.document) == nil {
          Text("Select a visible pixel layer with an enabled mask outside a group. Use Remove Background first.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      TextEditor(text: $store.prompt).font(.body).frame(height: 110).padding(8).background(
        .quaternary, in: RoundedRectangle(cornerRadius: 8))
      Label(LocalAI.imageCapability.message, systemImage: "photo").font(.caption)
        .foregroundStyle(.secondary)
      Label(LocalAI.textCapability.message, systemImage: "text.bubble").font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Button("Refine prompt") { store.refinePrompt() }.disabled(
          store.aiBusy || !LocalAI.textCapability.available || store.prompt.isEmpty)
        Button("Saved Results…") {NSApp.sendAction(#selector(AppDelegate.generatedResults),to:nil,from:nil)}
        Spacer()
        if store.aiBusy {
          ProgressView().controlSize(.small).accessibilityLabel(
            store.imageReferenceImportID != nil ? "Loading reference image" : store.imageGenerationJob?.phase == .preparingReference ? "Preparing subject reference" : "Creating image")
          Button("Cancel") { store.cancelAIWork() }
        } else {
          Button("Done") { store.showAI = false }
          Button("Generate") { store.beginImageCreation() }.buttonStyle(.borderedProminent)
            .disabled(!LocalAI.imageCapability.available || store.prompt.isEmpty || !store.canStartSelectedImageGeneration)
        }
      }
      if let layer=store.activeLayer,let record=try? GeneratedImageStorage.record(layer) {
        GroupBox("Selected generated layer") {
          VStack(alignment:.leading,spacing:6) {
            ScrollView {Text(record.initialPrompt).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)}.frame(height:64)
            Text(record.provider).font(.caption)
            Text("Model and seed have not been identified for this result.").font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth:.infinity,alignment:.leading)
        }
      }
      Text("Accepted originals and initial prompts are also kept locally in Generated Results.").font(.caption).foregroundStyle(.secondary)
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
    }.padding(26).frame(maxWidth: .infinity)
      .sheet(isPresented: $store.showImagePlayground) {
        if #available(macOS 26.0, *), LocalAI.imageCapability.available,let job=store.imageGenerationJob {
          SystemImagePlayground(store: store,job:job).frame(width: 700, height: 650)
        }
      }
      .onChange(of:store.showImagePlayground) { _,visible in
        if !visible,let job=store.imageGenerationJob {store.imageSystemInterfaceDismissed(job.id)}
      }
      .onDisappear {store.cancelAIWork()}
  }
}
