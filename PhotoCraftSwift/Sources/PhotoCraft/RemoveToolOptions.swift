import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

struct RemoveToolOptions: View {
  @Bindable var store: EditorStore
  @State private var reviewOpen = false
  @State private var relatedOpen = false
  @State private var validatingModel = false
  @AppStorage(GenerativeFillModelPreference.key) private var modelBookmark: Data?
  private func setting<T>(_ key: WritableKeyPath<RemoveToolSettings,T>) -> Binding<T> {
    Binding(get:{ store.removeSettings[keyPath:key] },set:{ value in
      var settings = store.removeSettings; settings[keyPath:key] = value
      do { try store.updateRemoveSettings(settings) } catch { store.status = error.localizedDescription }
    })
  }
  var body: some View {
    HStack(spacing:10) {
      Text("Size")
      TextField("Size",value:setting(\.size),format:.number)
        .frame(width:48).accessibilityLabel("Remove brush size")
        .disabled(store.geometryBusy || store.removeStroke != nil)
      Picker("Remove marking",selection:setting(\.subtract)) {
        Label("Add",systemImage:"plus").tag(false)
        Label("Subtract",systemImage:"minus").tag(true)
      }.pickerStyle(.segmented).frame(width:100).labelsHidden()
        .disabled(store.geometryBusy || store.removeStroke != nil)
      Menu("Find distractions") {
        Button("Wires and cables") { store.removeWiresAndCables() }.disabled(!store.canRemoveWires)
        Button("People") { store.findRemovePeople() }.disabled(!store.canFindRemovePeople)
        Button("General distractions…") { reviewOpen = true }
          .disabled(!store.canFindGeneralDistractions && store.removeDraft?.distractionReview == nil && store.removeDistractionID == nil)
      }.disabled(!store.canFindRemovePeople && !store.canRemoveWires && store.removeDraft?.distractionReview == nil && store.removeDistractionID == nil)
        .help("Remove wires and cables or review detected distractions.")
        .popover(isPresented: $reviewOpen, arrowEdge: .bottom) {
          RemoveDistractionControls(store: store) { reviewOpen = false }
        }
      Text("Mode")
      RemoveModeControl(selection:store.removeRelatedArmed ? .constant(.generativeOn) : setting(\.mode),
        enabled:store.removeDraft == nil && !store.removeRelatedArmed && !store.geometryBusy && !validatingModel,
        localAvailable: store.localRemoveAvailable)
        .frame(width:205)
      if LocalGenerativeFill.supported {
        Menu {
          Button(modelBookmark == nil ? "Choose Model…" : "Change Model…", action: chooseLocalModel)
            .disabled(store.removeDraft != nil || store.geometryBusy || validatingModel)
          Button("Remove Related Elements…") { relatedOpen = true }
        } label: {
          Text(store.removeProcessing(store.effectiveRemoveSettings(store.removeSettings), in: store.document).title)
        }
        .accessibilityLabel("Remove processing device and model")
        .help("Manage the on-device Remove model used by Auto and Generative AI on.")
        .popover(isPresented: $relatedOpen, arrowEdge: .bottom) {
          RemoveRelatedControls(store: store) { relatedOpen = false }
        }
      } else {
        Text("Traditional").foregroundStyle(.secondary)
          .help("Generative AI on requires Apple Silicon with macOS 26 or later.")
      }
      Toggle("Sample All Layers",isOn:setting(\.sampleAllLayers))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Toggle("Remove after each stroke",isOn:store.removeRelatedArmed ? .constant(false) : setting(\.removeAfterEachStroke))
        .disabled(store.removeDraft != nil || store.removeRelatedArmed || store.geometryBusy)
      Toggle("Create New Layer",isOn:store.removeRelatedArmed ? .constant(true) : setting(\.createNewLayer))
        .disabled(store.removeDraft != nil || store.removeRelatedArmed || store.geometryBusy)
      let clearTitle = store.removeWiresID == nil ? "Clear removal marks" : "Cancel wire removal"
      Button { store.cancelRemove() } label: { Label(clearTitle,systemImage:"xmark") }
        .labelStyle(.iconOnly).help("\(clearTitle) (Escape)")
        .disabled(store.removeDraft == nil && store.removeApplying == nil && store.removeWiresID == nil && !store.removeRelatedArmed)
      Button { store.applyRemove() } label: { Label("Apply removal",systemImage:"checkmark") }
        .labelStyle(.iconOnly).help("Apply removal (Return)")
        .disabled(store.geometryBusy || store.removeDraft?.hasMarks != true || store.removeStroke != nil)
      if validatingModel || store.removeApplying != nil || store.removeDetectionID != nil || store.removeDistractionID != nil || store.removeWiresID != nil || store.removeRelatedID != nil {
        ProgressView().controlSize(.small).accessibilityLabel(progressTitle)
      }
    }.controlSize(.small).toggleStyle(.checkbox)
  }

  private var progressTitle: String {
    if validatingModel { return "Checking the Remove model" }
    if store.removeRelatedID != nil { return "Finding related elements" }
    if store.removeWiresID != nil { return "Removing wires and cables" }
    if store.removeDistractionID != nil { return "Finding general distractions" }
    return store.removeDetectionID != nil ? "Detecting people for removal" : "Removing marked areas"
  }

  private func chooseLocalModel() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true; panel.canChooseFiles = true
    panel.allowsMultipleSelection = false; panel.prompt = "Choose Model"
    panel.message = "Select a compiled LaMa512.mlmodelc model."
    panel.begin { result in
      guard result == .OK, let url = panel.url else { return }
      Task { @MainActor in
        validatingModel = true
        defer { validatingModel = false }
        do {
          guard url.pathExtension.lowercased() == "mlmodelc" else { throw CraftError.invalid("Choose a compiled .mlmodelc package.") }
          let bookmark = try GenerativeFillModelPreference.bookmark(for: url)
          try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try LocalGenerativeFill.validateModel(url)
          }.value
          guard store.removeDraft == nil, !store.geometryBusy else { return }
          modelBookmark = bookmark
          store.removeRevision = UUID()
        } catch { store.status = error.localizedDescription }
      }
    }
  }
}
