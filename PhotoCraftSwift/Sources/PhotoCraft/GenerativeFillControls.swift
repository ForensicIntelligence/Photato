import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PhotoCraftCore
import PhotoCraftImaging

enum GenerativeFillModelPreference {
  static let key = "localGenerativeFillModel"
  static let promptKey = "localPromptGenerativeFillModel"
  static let instructionKey = "localPromptEditModel"
  static let referenceFillKey = "localReferenceFillModel"

  static func referenceFillURL(defaults: UserDefaults = .standard) -> URL? {
    defaults.data(forKey: referenceFillKey).flatMap(resolve)
  }

  static func guideKey(_ kind: LocalGenerationGuide.Kind) -> String { "localGenerationGuide.\(kind.rawValue)" }

  static func guideBookmark(_ kind: LocalGenerationGuide.Kind) -> Data? {
    guard let bookmark = UserDefaults.standard.data(forKey: guideKey(kind)), resolve(bookmark) != nil else { return nil }
    return bookmark
  }

  static func url(prompted: Bool = false, instructions: Bool = false, defaults: UserDefaults = .standard) -> URL? {
    let key = instructions ? instructionKey : prompted ? promptKey : Self.key
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
  var instructionModel = GenerativeFillModelPreference.url(instructions: true)
  var instructionBookmark = UserDefaults.standard.data(forKey: GenerativeFillModelPreference.instructionKey)
  var prompt = ""
  var seed = UInt32.random(in: .min ... .max)
  var variationCount = LocalGenerativeFill.maximumVariations
  var maximumVariations = LocalGenerativeFill.maximumVariations
  var targetLayerID: UUID?
  var backgroundSubjectID: UUID?
  var expandRequest: CropRequest?
  var referenceVariationID: UUID?
  var referenceVariationNumber: Int?
  var generateImage = false
  var promptEdit = false
  var instructionSourceID: UUID?
  var imageReference: ImageGenerationReference?
  var referenceFillModel = GenerativeFillModelPreference.referenceFillURL()
  var referenceFillBookmark = UserDefaults.standard.data(forKey: GenerativeFillModelPreference.referenceFillKey)
  var fillReferenceScope: ReferenceInpainting.Options.Scope = .object
  var fillReferenceIntent: ReferenceInpainting.Options.Intent = .swap
  var savedFillReference: ReferenceInpainting.Options?
  var canChooseFillReference: Bool {
    !generateImage && !promptEdit && targetLayerID == nil && expandRequest == nil && backgroundSubjectID == nil
  }
  var referenceFill: Bool { savedFillReference != nil || (canChooseFillReference && imageReference != nil) }
  var referenceUse: LocalGenerationGuide.Kind = .style
  var savedReferenceUse: LocalGenerationGuide.Kind?
  var guideBookmarks = Dictionary(uniqueKeysWithValues: LocalGenerationGuide.Kind.allCases.compactMap {
    kind in GenerativeFillModelPreference.guideBookmark(kind).map { (kind, $0) }
  })
  var importingReference = false
  var guideUse: LocalGenerationGuide.Kind? { savedReferenceUse ?? (generateImage && imageReference != nil ? referenceUse : nil) }
  var guideBookmark: Data? { guideUse.flatMap { guideBookmarks[$0] } }
  var missingGuideModel: Bool { guideUse != nil && guideBookmark == nil }
  var selectingModel = false
  var generating = false
  var error: String?

  var hasPrompt: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  var prompted: Bool { generateImage || promptEdit || referenceFill || targetLayerID != nil || backgroundSubjectID != nil || hasPrompt }
  var selectedModel: URL? {
    if referenceFill { return referenceFillModel }
    return promptEdit ? instructionModel : prompted ? promptModel : model
  }
}

extension EditorStore {
  private func canStartLocalFill(allowingMask: Bool = false) -> Bool {
    LocalGenerativeFill.supported && generativeFillDraft == nil && cropDraft == nil && !geometryBusy && !aiBusy
      && !hasToneDraft && !coalescingChanges && transformDraft == nil && !editingComponent
      && (!editingMask || (allowingMask && !smartFilterMaskEditing))
  }

  var canBeginGenerativeFill: Bool {
    canStartLocalFill() && LocalGenerativeFill.selection(in: document) != nil
  }

  var canBeginLocalImage: Bool {
    canStartLocalFill() && !showAI && !showImagePlayground && historyOperation == nil && geometrySheet == nil
      && brushGesture == nil && pathGesture == nil && error == nil && LocalGeneratedImage.supports(document)
  }

  func beginGenerateImage() {
    finishLayerName()
    guard canBeginLocalImage else { return }
    let draft = GenerativeFillDraft()
    draft.generateImage = true
    generativeFillDraft = draft
  }

  var contextualGenerateImage: Bool {
    guard canBeginLocalImage else { return false }
    guard let activeLayer else { return true }
    if case .raster(let raster) = activeLayer.content { return raster.tileCount == 0 && raster.defaultPixel.a == 0 }
    return false
  }

  var promptEditTarget: Layer? {
    guard canBeginLocalImage else { return nil }
    return LocalPromptEdit.target(in: document)
  }

  func beginPromptToEdit() {
    finishLayerName()
    guard let target = promptEditTarget else { return }
    let draft = GenerativeFillDraft()
    draft.promptEdit = true
    draft.instructionSourceID = target.id
    generativeFillDraft = draft
  }

  func canBeginGenerativeFillBatch(_ id: UUID) -> Bool {
    guard canStartLocalFill(), let layer = activeLayer, layer.id == id else { return false }
    return GenerativeFillVariations.canAppend(layer, in: document)
  }

  func beginGenerativeFillBatch(_ id: UUID, referenceVariationID: UUID? = nil) {
    finishLayerName()
    guard canBeginGenerativeFillBatch(id), let layer = activeLayer,
      let record = GenerativeFillVariations.read(layer) else { return }
    let draft = GenerativeFillDraft()
    draft.targetLayerID = id
    draft.generateImage = record.isGeneratedImage
    draft.savedReferenceUse = record.guideUse
    draft.savedFillReference = record.referenceOptions
    draft.promptEdit = record.isPromptEdit
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

  var canBeginLocalBackground: Bool {
    canStartLocalFill(allowingMask: true) && GeneratedBackground.foreground(in: document) != nil
  }

  func beginLocalBackground() {
    finishLayerName()
    guard canBeginLocalBackground, let subject = document.activeLayerID else { return }
    let draft = GenerativeFillDraft()
    draft.backgroundSubjectID = subject
    generativeFillDraft = draft
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
      !draft.importingReference, !draft.missingGuideModel,
      !editingComponent, !smartFilterMaskEditing, !editingMask || draft.backgroundSubjectID != nil,
      (draft.targetLayerID == nil && !draft.generateImage && !draft.promptEdit) || draft.referenceFill || draft.hasPrompt,
      let url = draft.selectedModel else { return }
    let background = draft.backgroundSubjectID
    if let background {
      guard GeneratedBackground.foreground(in: document)?.id == background else {
        draft.error = "Select the masked subject layer again to generate a background."
        return
      }
      if editingMask { select(background) }
    }
    let prompt = draft.prompt, seed = draft.seed
    let bookmark = draft.referenceFill ? draft.referenceFillBookmark
      : draft.promptEdit ? draft.instructionBookmark : draft.prompted ? draft.promptModelBookmark : nil
    let count = draft.prompted ? draft.variationCount : 1
    let target = draft.targetLayerID, prompted = draft.prompted, reference = draft.referenceVariationID
    let generateImage = draft.generateImage, isReferenceFill = draft.referenceFill
    let fillOptions = ReferenceInpainting.Options(scope: draft.fillReferenceScope, intent: draft.fillReferenceIntent)
    let imageReference = draft.imageReference, imageReferenceUse = draft.referenceUse, guideBookmark = draft.guideBookmark
    let instructionSource = draft.instructionSourceID
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
        } else if background != nil {
          command = try LocalGeneratedBackground.prepare(original, model: url, bookmark: bookmark,
            prompt: prompt, seed: seed, count: count)
        } else if isReferenceFill, let target {
          command = try await GenerativeFillVariations.appendReference(to: target, in: original, model: url,
            bookmark: bookmark, seed: nil, count: count, referenceVariationID: reference)
        } else if isReferenceFill, let imageReference {
          command = try await LocalReferenceFill.prepare(original, image: imageReference, options: fillOptions, model: url,
            bookmark: bookmark, seed: seed, count: count)
        } else if let target {
          command = try GenerativeFillVariations.append(to: target, in: original, model: url, bookmark: bookmark,
            prompt: prompt, seed: nil, count: count, referenceVariationID: reference, guideBookmark: guideBookmark)
        } else if let instructionSource {
          command = try LocalPromptEdit.prepare(original, targetID: instructionSource, model: url, bookmark: bookmark,
            prompt: prompt, seed: seed, count: count)
        } else if generateImage {
          let guide = try imageReference.map { try LocalGeneratedImage.makeGuide($0, use: imageReferenceUse, in: original) }
          command = try LocalGeneratedImage.prepare(original, model: url, bookmark: bookmark, prompt: prompt, seed: seed,
            count: count, guide: guide, guideBookmark: guideBookmark)
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
  @objc func generateImage() { store?.beginGenerateImage() }
  @objc func promptToEdit() { store?.beginPromptToEdit() }
}

struct GenerativeFillSheet: View {
  let store: EditorStore
  @Bindable var draft: GenerativeFillDraft
  @FocusState private var promptFocused: Bool

  private var title: String {
    if draft.backgroundSubjectID != nil { return "Generate Background" }
    if draft.expandRequest != nil { return "Generative Expand" }
    if draft.referenceVariationID != nil { return draft.promptEdit ? "Edit This Variation" : "Generate Similar" }
    if draft.targetLayerID != nil { return "Generate More Variations" }
    if draft.promptEdit { return "Prompt to Edit" }
    return draft.generateImage ? "Generate Image" : "Generative Fill"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title).font(.headline)
      if !draft.referenceFill {
        LabeledContent("Prompt") {
          TextField("Prompt", text: $draft.prompt, prompt: Text(draft.promptEdit ? "Describe what to change" : draft.generateImage ? "Describe the image"
            : draft.backgroundSubjectID == nil ? "Describe what to add" : "Describe the background"))
            .labelsHidden()
            .focused($promptFocused)
            .disabled(draft.selectingModel || draft.generating)
            .onChange(of: draft.prompt) { _, _ in draft.error = nil }
        }
      }
      Group {
        if draft.backgroundSubjectID != nil {
          Text("The result goes on an editable layer below the subject. A blank prompt lets the subject guide the background.")
        } else if draft.expandRequest != nil {
          Text("Leave the prompt blank to extend the image from its edges. Generated pixels appear on a masked layer outside the original canvas.")
        } else if let number = draft.referenceVariationNumber {
          Text("New results use variation \(number) as a reference and stay in this layer.")
        } else if draft.promptEdit {
          Text(draft.targetLayerID == nil ? "Edit the selected image on this Mac. The original layer stays in the document and is hidden after generation."
            : "New variations start from the saved original image and stay in this layer.")
        } else if draft.generateImage {
          Text(draft.targetLayerID == nil ? "Create an image from text on this Mac. Variations appear on one editable layer."
            : "Generate new results from the prompt and keep the earlier variations in this layer.")
        } else if draft.referenceFill {
          Text(draft.targetLayerID == nil ? "The reference image guides the selected area. Results appear on an editable masked layer."
            : "New variations reuse the saved reference and selection.")
        } else if draft.targetLayerID == nil {
          Text("Leave the prompt blank to fill from surrounding pixels. Results appear on an editable masked layer.")
        } else {
          Text("New results use the original image area and appear in this layer alongside earlier variations.")
        }
      }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LabeledContent(draft.referenceFill ? "Local reference model"
        : draft.promptEdit ? "Local editing model" : draft.prompted ? "Local prompt model" : "Local context model") {
        HStack(spacing: 8) {
          if let model = draft.selectedModel {
            Text(draft.referenceFill ? "Paint by Example" : draft.promptEdit ? "InstructPix2Pix" : draft.prompted ? "Stable Diffusion 1.5" : "LaMa512")
              .lineLimit(1)
              .help(model.lastPathComponent)
          }
          Button(draft.selectedModel == nil ? "Choose Model…" : "Change…", action: chooseModel)
            .disabled(draft.selectingModel || draft.generating)
        }
      }
      if draft.selectedModel == nil {
        let guide = draft.referenceFill ? "GENERATIVE_FILL_REFERENCE.md"
          : draft.promptEdit ? "PROMPT_TO_EDIT.md" : "LOCAL_GENERATIVE_FILL.md"
        Link("Model setup", destination: URL(string: "https://github.com/ForensicIntelligence/Photato/blob/main/PhotoCraftSwift/docs/\(guide)")!)
      }
      if draft.generateImage || draft.canChooseFillReference || draft.savedFillReference != nil { referenceControls }
      if draft.prompted {
        Picker("Variations", selection: $draft.variationCount) {
          ForEach(1...draft.maximumVariations, id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(draft.selectingModel || draft.generating)
      }
      if draft.selectingModel || draft.generating || draft.importingReference {
        ProgressView(draft.generating ? "Generating on this Mac…" : draft.importingReference ? "Reading reference…" : "Checking model…")
          .controlSize(.small)
      }
      if let error = draft.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Spacer()
        Button("Cancel") { store.cancelGenerativeFill() }.keyboardShortcut(.cancelAction)
        Button("Generate") { store.generateFill(draft) }
          .keyboardShortcut(.defaultAction)
          .disabled(draft.selectedModel == nil || draft.selectingModel || draft.generating || draft.importingReference || draft.missingGuideModel
            || ((draft.generateImage || draft.promptEdit || draft.targetLayerID != nil) && !draft.referenceFill && !draft.hasPrompt))
      }
    }
    .padding(20)
    .frame(width: 410)
    .interactiveDismissDisabled(draft.generating)
    .onAppear { if draft.generateImage || draft.promptEdit { promptFocused = true } }
  }

  @ViewBuilder private var referenceControls: some View {
    if draft.targetLayerID == nil {
      LabeledContent("Reference image") {
        HStack {
          if let reference = draft.imageReference {
            Image(decorative: reference.image, scale: 1)
              .resizable().scaledToFit().frame(width: 40, height: 32).accessibilityHidden(true)
          }
          Button(draft.imageReference == nil ? "Choose Image…" : "Change Image…", action: chooseReference)
          if draft.imageReference != nil {
            Button("Remove") { draft.imageReference = nil; draft.error = nil }
          }
        }
        .disabled(draft.importingReference || draft.selectingModel || draft.generating)
      }
      if draft.canChooseFillReference, draft.imageReference != nil {
        Picker("Reference to", selection: $draft.fillReferenceScope) {
          ForEach(ReferenceInpainting.Options.Scope.allCases, id: \.self) { scope in Text(scope.title).tag(scope) }
        }
        .pickerStyle(.segmented)
        .disabled(draft.importingReference || draft.selectingModel || draft.generating)
        Picker("Intent", selection: $draft.fillReferenceIntent) {
          ForEach(ReferenceInpainting.Options.Intent.allCases, id: \.self) { intent in Text(intent.title).tag(intent) }
        }
        .pickerStyle(.segmented)
        .disabled(draft.importingReference || draft.selectingModel || draft.generating)
        Text(draft.fillReferenceIntent == .swap ? "Replace content in the selected area."
          : "Add the generated subject while keeping the background.")
          .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else if draft.imageReference != nil {
        Picker("Use reference for", selection: $draft.referenceUse) {
          ForEach(LocalGenerationGuide.Kind.allCases, id: \.self) { use in Text(use.title).tag(use) }
        }
        .pickerStyle(.segmented)
        .disabled(draft.importingReference || draft.selectingModel || draft.generating)
        .onChange(of: draft.referenceUse) { _, _ in draft.error = nil }
      }
    } else if let settings = draft.savedFillReference {
      LabeledContent("Reference image", value: "\(settings.scope.title) · \(settings.intent.title)")
    } else if let use = draft.savedReferenceUse {
      LabeledContent("Reference image", value: "\(use.title) · Saved in layer")
    }
    if draft.generateImage, let use = draft.guideUse {
      if draft.targetLayerID == nil {
        Text(use == .style ? "Apply the reference’s colours and textures to the generated image."
          : "Use edges in the reference to guide the placement and scale of objects.")
          .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      LabeledContent("\(use.title) model") {
        HStack(spacing: 8) {
          if draft.guideBookmark != nil { Text(use.modelName) }
          Button(draft.guideBookmark == nil ? "Choose Model…" : "Change…") { chooseGuideModel(use) }
          if draft.guideBookmark == nil {
            Link("Setup", destination: URL(string: "https://github.com/ForensicIntelligence/Photato/blob/main/PhotoCraftSwift/docs/GENERATE_IMAGE_REFERENCE.md")!)
              .accessibilityLabel("\(use.title) model setup")
          }
        }
        .disabled(draft.importingReference || draft.selectingModel || draft.generating)
      }
    }
  }

  private func chooseReference() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Image"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        guard store.generativeFillDraft === draft, !draft.generating, !draft.importingReference else { return }
        draft.importingReference = true
        draft.error = nil
        defer { draft.importingReference = false }
        do {
          let reference = try await Task.detached(priority: .userInitiated) {
            try ImageGenerationReference.prepare(ImageGenerationReference.read(url))
          }.value
          if store.generativeFillDraft === draft { draft.imageReference = reference }
        } catch {
          if store.generativeFillDraft === draft { draft.error = error.localizedDescription }
        }
      }
    }
  }

  private func chooseGuideModel(_ kind: LocalGenerationGuide.Kind) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Model"
    panel.message = "Select the compiled \(kind.modelName).mlmodelc package."
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        guard store.generativeFillDraft === draft, !draft.generating, !draft.selectingModel else { return }
        draft.selectingModel = true
        draft.error = nil
        defer { draft.selectingModel = false }
        do {
          let bookmark = try GenerativeFillModelPreference.bookmark(for: url)
          try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try LocalGenerationGuide.validateModel(url, kind: kind)
          }.value
          guard store.generativeFillDraft === draft else { return }
          UserDefaults.standard.set(bookmark, forKey: GenerativeFillModelPreference.guideKey(kind))
          draft.guideBookmarks[kind] = bookmark
        } catch {
          if store.generativeFillDraft === draft { draft.error = error.localizedDescription }
        }
      }
    }
  }

  private func chooseModel() {
    let prompted = draft.prompted
    let instructions = draft.promptEdit
    let reference = draft.referenceFill
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = !prompted
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Model"
    panel.message = reference ? "Select the PaintByExampleCoreML folder."
      : instructions ? "Select the extracted TimBrooks_InstructPix2Pix folder."
      : prompted ? "Select the extracted Runway_SD1.5_Inpaint folder." : "Select the compiled LaMa512.mlmodelc package."
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
            if reference {
              try LocalGenerativeFill.validateReferenceModel(url)
            } else if instructions {
              try LocalGenerativeFill.validateInstructionModel(url)
            } else if prompted {
              try LocalGenerativeFill.validatePromptModel(url)
            } else {
              try LocalGenerativeFill.validateModel(url)
            }
          }.value
          guard store.generativeFillDraft === draft else { return }
          let key = reference ? GenerativeFillModelPreference.referenceFillKey
            : instructions ? GenerativeFillModelPreference.instructionKey
            : prompted ? GenerativeFillModelPreference.promptKey : GenerativeFillModelPreference.key
          UserDefaults.standard.set(bookmark, forKey: key)
          if reference {
            draft.referenceFillModel = GenerativeFillModelPreference.referenceFillURL()
            draft.referenceFillBookmark = bookmark
          } else if instructions {
            draft.instructionModel = GenerativeFillModelPreference.url(instructions: true)
            draft.instructionBookmark = bookmark
          } else if prompted {
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
