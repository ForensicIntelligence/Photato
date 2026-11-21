import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

enum GenerativeFillModelPreference {
  static let key = "localGenerativeFillModel"
  static let promptKey = "localPromptGenerativeFillModel"

  static func url(prompted: Bool = false, defaults: UserDefaults = .standard) -> URL? {
    let key = prompted ? promptKey : Self.key
    guard let data = defaults.data(forKey: key) else { return nil }
    return resolve(data)
  }

  static func resolve(_ data: Data) -> URL? {
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
  var promptModel = GenerativeFillModelPreference.url(prompted: true)
  var promptModelBookmark = UserDefaults.standard.data(forKey: GenerativeFillModelPreference.promptKey)
  var prompt = ""
  var seed = UInt32.random(in: .min ... .max)
  var variationCount = LocalGenerativeFill.maximumVariations
  var maximumVariations = LocalGenerativeFill.maximumVariations
  var targetLayerID: UUID?
  var expandRequest: CropRequest?
  var referenceVariationID: UUID?
  var referenceVariationNumber: Int?
  var selectingModel = false
  var generating = false
  var error: String?

  var hasPrompt: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  var prompted: Bool { targetLayerID != nil || hasPrompt }
  var selectedModel: URL? { prompted ? promptModel : model }
}

extension EditorStore {
  private var canStartLocalFill: Bool {
    LocalGenerativeFill.supported && generativeFillDraft == nil && cropDraft == nil && !geometryBusy && !aiBusy
      && !hasToneDraft && !coalescingChanges && transformDraft == nil && !editingComponent && !editingMask
  }

  var canBeginGenerativeFill: Bool {
    canStartLocalFill && LocalGenerativeFill.selection(in: document) != nil
  }

  func canBeginGenerativeFillBatch(_ id: UUID) -> Bool {
    guard canStartLocalFill, let layer = activeLayer, layer.id == id else { return false }
    return GenerativeFillVariations.canAppend(layer, in: document)
  }

  func beginGenerativeFillBatch(_ id: UUID, referenceVariationID: UUID? = nil) {
    finishLayerName()
    guard canBeginGenerativeFillBatch(id), let layer = activeLayer,
      let record = GenerativeFillVariations.read(layer) else { return }
    let draft = GenerativeFillDraft()
    draft.targetLayerID = id
    if let referenceVariationID {
      guard let index = record.entries.firstIndex(where: { $0.id == referenceVariationID }) else { return }
      draft.referenceVariationID = referenceVariationID
      draft.referenceVariationNumber = index + 1
    }
    draft.prompt = record.prompt(for: referenceVariationID ?? layer.smartObject?.layerComps?.selectedID)
    draft.maximumVariations = min(LocalGenerativeFill.maximumVariations, GenerativeFillVariations.maximumStoredVariations - record.entries.count)
    draft.variationCount = draft.maximumVariations
    generativeFillDraft = draft
  }

  func beginGenerativeFill() {
    finishLayerName()
    guard canBeginGenerativeFill else { return }
    generativeFillDraft = GenerativeFillDraft()
  }

  var canBeginGenerativeExpand: Bool {
    guard LocalGenerativeFill.supported, generativeFillDraft == nil, canUseCropWorkspace,
      let cropDraft, let request = try? cropDraft.request(background: backgroundColor) else { return false }
    return (try? GenerativeExpand.protectedCanvas(for: request, in: document)) != nil
  }

  func beginGenerativeExpand() {
    guard canBeginGenerativeExpand, let request = try? cropDraft?.request(background: backgroundColor) else { return }
    let draft = GenerativeFillDraft()
    draft.expandRequest = request
    generativeFillDraft = draft
  }

  func cancelGenerativeFill() {
    guard let draft = generativeFillDraft else { return }
    if draft.generating { geometryTask?.cancel() }
    generativeFillDraft = nil
  }

  func generateFill(_ draft: GenerativeFillDraft) {
    guard generativeFillDraft === draft, !geometryBusy, !draft.selectingModel, !draft.generating,
      !editingComponent, !editingMask, draft.targetLayerID == nil || draft.hasPrompt,
      let url = draft.selectedModel else { return }
    let prompt = draft.prompt, seed = draft.seed
    let bookmark = draft.prompted ? draft.promptModelBookmark : nil
    let count = draft.prompted ? draft.variationCount : 1
    let target = draft.targetLayerID, prompted = draft.prompted, reference = draft.referenceVariationID
    let expand = draft.expandRequest, capturedCrop = cropDraft
    let original = document, generation = layerPanelGeneration, sessionID = sessionGeneration
    geometryBusy = true
    draft.error = nil
    draft.generating = true
    geometryTask = Task { [weak self, weak draft] in
      let worker = Task.detached(priority: .userInitiated) {
        let command: Command
        if let expand {
          command = try GenerativeExpand.prepare(expand, in: original, model: url, bookmark: bookmark,
            prompt: prompt, seed: seed, count: count)
        } else if let target {
          command = try GenerativeFillVariations.append(to: target, in: original, model: url, bookmark: bookmark,
            prompt: prompt, seed: nil, count: count, referenceVariationID: reference)
        } else {
          command = try GenerativeFillVariations.prepare(original, model: url, bookmark: bookmark, prompt: prompt, seed: seed, count: count)
        }
        return try PreparedEdit(command: command, document: original)
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
          self.document == original, !self.editingMask, !self.editingComponent,
          expand == nil || self.cropDraft == capturedCrop else { return }
        try self.executeCompositePreparedEdit(edit, allowLinkedSmartObject: target != nil)
        self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
        self.onChange?(.changeDone)
        self.status = edit.label
        self.generativeFillDraft = nil
        if expand != nil { self.cancelCrop(); self.fit() }
        if prompted { self.reveal(PropertiesTab.properties) }
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
      Text(draft.expandRequest != nil ? "Generative Expand" : draft.referenceVariationID != nil ? "Generate Similar" : draft.targetLayerID == nil ? "Generative Fill" : "Generate More Variations")
        .font(.headline)
      LabeledContent("Prompt") {
        TextField("Prompt", text: $draft.prompt, prompt: Text("Describe what to add"))
          .labelsHidden()
          .disabled(draft.selectingModel || draft.generating)
          .onChange(of: draft.prompt) { _, _ in draft.error = nil }
      }
      Group {
        if draft.expandRequest != nil {
          Text("Leave the prompt blank to extend the image from its edges. Generated pixels appear on a masked layer outside the original canvas.")
        } else if let number = draft.referenceVariationNumber {
          Text("New results use variation \(number) as a reference and stay in this layer.")
        } else if draft.targetLayerID == nil {
          Text("Leave the prompt blank to fill from surrounding pixels. Results appear on an editable masked layer.")
        } else {
          Text("New results use the original image area and appear in this layer alongside earlier variations.")
        }
      }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LabeledContent(draft.prompted ? "Local prompt model" : "Local context model") {
        HStack(spacing: 8) {
          if let model = draft.selectedModel {
            Text(draft.prompted ? "Stable Diffusion 1.5" : "LaMa512")
              .lineLimit(1)
              .help(model.lastPathComponent)
          }
          Button(draft.selectedModel == nil ? "Choose Model…" : "Change…", action: chooseModel)
            .disabled(draft.selectingModel || draft.generating)
        }
      }
      if draft.selectedModel == nil {
        Link("Model setup", destination: URL(string: "https://github.com/ForensicIntelligence/Photato/blob/main/PhotoCraftSwift/docs/LOCAL_GENERATIVE_FILL.md")!)
      }
      if draft.prompted {
        Picker("Variations", selection: $draft.variationCount) {
          ForEach(1...draft.maximumVariations, id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(draft.selectingModel || draft.generating)
      }
      if draft.selectingModel || draft.generating {
        ProgressView(draft.generating ? "Generating on this Mac…" : "Checking model…")
          .controlSize(.small)
      }
      if let error = draft.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Spacer()
        Button("Cancel") { store.cancelGenerativeFill() }.keyboardShortcut(.cancelAction)
        Button("Generate") { store.generateFill(draft) }
          .keyboardShortcut(.defaultAction)
          .disabled(draft.selectedModel == nil || draft.selectingModel || draft.generating || (draft.targetLayerID != nil && !draft.hasPrompt))
      }
    }
    .padding(20)
    .frame(width: 410)
    .interactiveDismissDisabled(draft.generating)
  }

  private func chooseModel() {
    let prompted = draft.prompted
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = !prompted
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Model"
    panel.message = prompted ? "Select the extracted Runway_SD1.5_Inpaint folder." : "Select the compiled LaMa512.mlmodelc package."
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        guard store.generativeFillDraft === draft, !draft.generating, !draft.selectingModel else { return }
        guard prompted || url.pathExtension.lowercased() == "mlmodelc" else {
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
            if prompted {
              try LocalGenerativeFill.validatePromptModel(url)
            } else {
              try LocalGenerativeFill.validateModel(url)
            }
          }.value
          guard store.generativeFillDraft === draft else { return }
          let key = prompted ? GenerativeFillModelPreference.promptKey : GenerativeFillModelPreference.key
          UserDefaults.standard.set(bookmark, forKey: key)
          if prompted {
            draft.promptModel = GenerativeFillModelPreference.url(prompted: true)
            draft.promptModelBookmark = bookmark
          } else {
            draft.model = GenerativeFillModelPreference.url()
          }
        } catch { draft.error = error.localizedDescription }
      }
    }
  }
}
