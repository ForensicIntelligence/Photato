import AppKit
import Observation
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging

enum EditPlanOrigin: String, Sendable {
  case supplied, onDevice, privateCloudCompute
  var title: String {
    switch self {
    case .supplied: "Supplied plan — no model was used"
    case .onDevice: "Apple on-device language model"
    case .privateCloudCompute: "Apple Private Cloud Compute language model"
    }
  }
}

extension NativeEditPlan {
  func recordedAction() throws -> RecordedAction {
    try validate()
    return RecordedAction(name: "Reviewed Edit Plan", steps: operations.map { operation in
      let edit: ActionOperation
      switch operation {
      case .autoTone: edit = .autoCorrection(.active, .tone)
      case .autoContrast: edit = .autoCorrection(.active, .contrast)
      case .autoColor: edit = .autoCorrection(.active, .color)
      case .desaturate: edit = .desaturate(.active)
      case .invert: edit = .adjustment(.active, .invert)
      case .adjustment(let value):
        let p = value.parameters
        switch value.operation {
        case .exposure:
          edit = .adjustment(.active, .classic(.exposure(.init(exposure: Float(p["exposure"]!),
            offset: Float(p["offset"]!), gammaCorrection: Float(p["gammaCorrection"]!)))))
        case .brightnessContrast:
          edit = .adjustment(.active, .source(.init(.brightnessContrast,
            parameters: ["brightness": Float(p["brightness"]!), "contrast": Float(p["contrast"]!)], options: ["legacy": false])))
        case .hueSaturation:
          var settings = HueSaturationAdjustment()
          settings.master = .init(hue: Int(p["hue"]!), saturation: Int(p["saturation"]!), lightness: Int(p["lightness"]!))
          edit = .adjustment(.active, .hueSaturation(settings))
        case .vibrance:
          var settings = ClassicAdjustment(.vibrance)
          settings.vibrance = Int(p["vibrance"]!); settings.saturation = Int(p["saturation"]!)
          edit = .adjustment(.active, .classic(settings))
        }
      }
      return RecordedActionStep(name: operation.title, operation: edit)
    })
  }
}

final class PreparedEditPlan: Sendable {
  let edit: PreparedEdit
  let before: CGImage
  let after: CGImage
  init(edit: PreparedEdit, before: CGImage, after: CGImage) {
    self.edit = edit; self.before = before; self.after = after
  }
  // Keep the large value-based command/transaction frames out of the preview
  // compositor's frame. Cooperative executor threads have bounded stacks.
  private static func transaction(_ plan: NativeEditPlan, source: CraftDocument) throws -> PreparedEdit {
    try PreparedEdit(command: RecordedActionRenderer.prepare(plan.recordedAction(), in: source).command, document: source)
  }
  private static func result(_ edit: PreparedEdit, source: CraftDocument) throws -> CraftDocument {
    var candidate = EditorSession(document: source)
    try candidate.executePrepared(edit)
    return candidate.document
  }
  private static func preview(_ source: CraftDocument) throws -> CGImage {
    let request = try RasterPreviewRequest.overview(width: source.width, height: source.height)
    return try ColorManagement.displayImage(request.reducing(Renderer.composite(source)), in: source)
  }
  static func prepare(_ plan: NativeEditPlan, source: CraftDocument) throws -> Self {
    let prepared = try transaction(plan, source: source)
    try Task.checkCancellation()
    let before = try preview(source)
    try Task.checkCancellation()
    let after = try preview(result(prepared, source: source))
    return Self(edit: prepared, before: before, after: after)
  }
}

@MainActor @Observable final class EditPlanReview {
  let id = UUID()
  var source: CraftDocument?
  let session: UUID
  let lifecycle: UUID
  var phase = "planning"
  var origin: EditPlanOrigin
  var plan: NativeEditPlan?
  var prepared: PreparedEditPlan?
  var error: String?
  @ObservationIgnored var worker: Task<PreparedEditPlan, Error>?
  @ObservationIgnored var planning: Task<NativeEditPlan, Error>?
  init(store: EditorStore, origin: EditPlanOrigin) {
    source = store.document; session = store.sessionGeneration
    lifecycle = store.layerPanelGeneration; self.origin = origin
  }
  var busy: Bool { phase == "planning" || phase == "preparing" }
  func matches(_ store: EditorStore) -> Bool {
    guard let source else { return false }
    return store.editPlanReview === self && store.sessionGeneration == session
      && store.layerPanelGeneration == lifecycle && store.document == source
      && store.editPlanTargetAvailable
  }
}

extension EditorStore {
  var editPlanTargetAvailable: Bool {
    guard document.colorMode == .rgb, !editingComponent, !editingMask, !smartFilterMaskEditing,
      !hasToneDraft, !coalescingChanges, transformDraft == nil,
      let layer = activeLayer, case .raster = layer.content, layer.smartObject == nil,
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id] else { return false }
    return !document.isImageLocked(layer.id)
  }
  var canReviewEditPlan: Bool { editPlanTargetAvailable && !geometryBusy && !aiBusy && !editPlanBusy }
  var editPlanBusy: Bool { editPlanReview?.busy == true }
  var canApplyEditPlan: Bool {
    guard let review = editPlanReview else { return false }
    return review.phase == "ready" && review.prepared != nil && review.matches(self) && !geometryBusy && !aiBusy
  }
  func cancelReviewedEditPlan() {
    guard let review = editPlanReview, review.phase != "applied", review.phase != "cancelled" else { return }
    review.worker?.cancel(); review.planning?.cancel()
    if review.busy { geometryBusy = false; geometryTask?.cancel(); geometryTask = nil }
    review.prepared = nil; review.source = nil; review.phase = "cancelled"
  }
  func prepareReviewedEditPlan(_ plan: NativeEditPlan, validate: @escaping @MainActor () throws -> Void = {}) async throws {
    guard canReviewEditPlan else { throw CraftError.invalid("Finish the current interaction and select one unlocked RGB pixel layer.") }
    try plan.validate(); cancelReviewedEditPlan()
    let review = EditPlanReview(store: self, origin: .supplied)
    editPlanReview = review
    try await prepareReviewedEditPlan(plan, review: review, validate: validate)
  }
  private func prepareReviewedEditPlan(_ plan: NativeEditPlan, review: EditPlanReview,
    validate: @escaping @MainActor () throws -> Void = {}) async throws {
    guard let source = review.source else { throw CancellationError() }
    review.plan = plan; review.phase = "preparing"; geometryBusy = true
    let prepare = editPlanPreparation
    let worker = Task.detached(priority: .userInitiated) { try await prepare(plan, source) }
    review.worker = worker
    geometryTask = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    defer {
      review.worker = nil
      if editPlanReview === review, layerPanelGeneration == review.lifecycle {
        geometryBusy = false; geometryTask = nil
      }
    }
    do {
      let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      guard !worker.isCancelled, review.phase == "preparing", review.matches(self) else {
        throw CraftError.invalid("The edit plan was cancelled or its source changed. Prepare a new preview.")
      }
      try validate()
      review.prepared = prepared; review.phase = "ready"
    } catch {
      if editPlanReview === review, review.phase != "cancelled" { review.phase = "failed"; review.source = nil; review.error = error.localizedDescription }
      throw error
    }
  }
  func proposeReviewedEditPlan() async {
    guard canReviewEditPlan else { return }
    cancelReviewedEditPlan()
    let provider = editPlanProvider, prompt = editPlanPrompt
    let review = EditPlanReview(store: self, origin: provider == .onDevice ? .onDevice : .privateCloudCompute)
    editPlanReview = review; geometryBusy = true
    let propose = editPlanProposal
    let planning = Task { try await propose(prompt, provider) }
    review.planning = planning
    do {
      let plan = try await withTaskCancellationHandler { try await planning.value } onCancel: { planning.cancel() }
      try Task.checkCancellation()
      guard !planning.isCancelled, review.phase == "planning", review.matches(self) else {
        throw CraftError.invalid("The edit instruction was cancelled or its source changed.")
      }
      try await prepareReviewedEditPlan(plan, review: review)
    } catch {
      if editPlanReview === review, review.phase != "cancelled" { review.phase = "failed"; review.source = nil; review.error = error.localizedDescription }
    }
    review.planning = nil
    if editPlanReview === review, layerPanelGeneration == review.lifecycle { geometryBusy = false }
  }
  func applyReviewedEditPlan(_ id: UUID) throws {
    guard let review = editPlanReview, review.id == id, canApplyEditPlan, let prepared = review.prepared, let source = review.source else {
      throw CraftError.invalid("This edit preview is stale or unavailable. Prepare a new preview.")
    }
    try executeCompositePreparedEdit(prepared.edit)
    review.phase = "applied"; review.prepared = nil; review.source = nil
    if document != source { onChange?(.changeDone) }
    status = "Reviewed Edit Plan"; render()
  }
}
