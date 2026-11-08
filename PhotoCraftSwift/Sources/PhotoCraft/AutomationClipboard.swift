import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum ClipboardAPI {
  static let commands = ["clipboard.copy", "clipboard.cut", "clipboard.paste", "clipboard.newDocument"]
  static let maximumBytes = 2 * 1024 * 1024
  static let maximumBase64 = ((maximumBytes + 2) / 3) * 4
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "target":return ClipboardPlaneAPI.targetSchema
    case "backgroundValue":return BrushAPI.number()
    case "colorDecision": return BrushAPI.enumeration(["convertAppearance", "preserveNumbers"])
    case "payloadBase64": return ["type": "string", "contentEncoding": "base64", "maxLength": maximumBase64]
    case "layerIDs": return ["type": "array", "minItems": 1, "maxItems": LayerLimits.maximumLayers, "uniqueItems": true, "items": ["type": "string", "format": "uuid"]]
    case "merged": return ["type": "boolean", "default": false]
    case "placement": return ["type": "string", "enum": ["centered", "inPlace", "into", "outside"], "default": "centered"]
    case "backgroundColor": return ["type": "array", "minItems": 3, "maxItems": 3, "items": ["type": "number", "minimum": 0, "maximum": 1]]
    case "center": return ["type": "array", "minItems": 2, "maxItems": 2, "items": ["type": "number", "minimum": -1000000, "maximum": 1000000]]
    case "name": return ["type": "string", "minLength": 1, "maxLength": 256]
    default: return [:]
    }
  }
  static func decode(_ bytes: Data) throws -> ClipboardContent {
    let content = try ClipboardContent.decode(bytes)
    try validate(content); return content
  }
  static func validate(_ content: ClipboardContent) throws {
    try AutomationService.checkLimits(content.document)
    guard content.bounds.width <= 4_194_304 / content.bounds.height,
      content.document.estimatedBytes + (content.restrictedSamples?.estimatedBytes ?? 0) <= 128 * 1024 * 1024 else {
      throw AutomationFailure(status: 413, message: "Clipboard extent or decoded data exceeds API limits.")
    }
  }
  static var capabilities: [String: Any] { [
    "nativeImageFallbackPixelBudget":Surface.maximumDensePixels,
    "largeNativeClipboard":"Native payloads retain full extent/precision. Full TIFF/PNG fallbacks are omitted above the existing dense-image budget, never replaced by a reduced-size image. External applications need a standard representation; native512MiB and API2MiB/decoded4MP limits remain.",
    "targetedPlanes":ClipboardPlaneAPI.capabilities,
    "commands": commands, "envelopeVersions": [1, 2], "maximumPayloadBytes": maximumBytes,
    "transport": "Explicit native clipboard payloads only; these commands never read or write the Mac system clipboard. Copy returns payloadBase64, sourceMode, kind, width, height and revision. Cut also returns updated document state; Undo restores the document, not the returned payload. New Document requires document transfers and returns a new shared state with201.",
    "resultSchema": BrushAPI.object(["payloadBase64": schema("payloadBase64"), "sourceMode": ["type": "string"], "kind": ["type": "string", "enum": ["pixels", "layers"]], "width": ["type": "integer"], "height": ["type": "integer"], "revision": ["type": "string"], "document": ["type": "object"]], required: ["payloadBase64", "sourceMode", "kind", "width", "height", "revision"]),
    "placement": "centered defaults to selection center, otherwise canvas center; optional center is document pixels. inPlace uses copied coordinates. Into/Outside require a selection. Desktop ordinary paste uses its visible viewport center.",
    "restricted": "Envelope2 retains original palette indices/bits separately from selection coverage. Matching opaque full-coverage paste preserves duplicate entry identity. Other pixels remap to the destination palette or black/white; paste changes the existing flat layer. Exact New from Clipboard retains mode; fractional/irregular coverage needing extra alpha produces RGB. Cut clears to transparency when available, otherwise the supplied backgroundColor (default current desktop background) mapped to the mode.",
    "limits": "Payloads above2MiB reject before Cut commits; document/API limits also apply and decoded extents are checked before flattening or creating output. Existing Adobe action clipboard descriptors remain unsupported. Live cross-application clipboard behavior and Photoshop pixel parity are unqualified."] }
}

extension AutomationCommand {
  func clipboardBackground(default color: Pixel) throws -> Pixel {
    guard let raw = parameters["backgroundColor"] else { return Pixel(color.r, color.g, color.b, 1) }
    guard case .array(let values) = raw, values.count == 3 else { throw AutomationFailure(status: 400, message: "Background color requires three RGB values.") }
    let rgb = try values.map { value -> Float in
      guard case .number(let n) = value, n.isFinite, (0...1).contains(n) else { throw AutomationFailure(status: 400, message: "Invalid background color.") }; return Float(n)
    }
    return Pixel(rgb[0], rgb[1], rgb[2], 1)
  }
  func clipboardBytes() throws -> Data {
    guard case .string(let value) = parameters["payloadBase64"], value.utf8.count <= ClipboardAPI.maximumBase64,
      let bytes = Data(base64Encoded: value), bytes.count <= ClipboardAPI.maximumBytes else {
      throw AutomationFailure(status: 400, message: "A valid native clipboard payload up to2MiB is required.")
    }
    return bytes
  }
  func clipboardIDs(default ids: Set<UUID>) throws -> Set<UUID> {
    guard let raw = parameters["layerIDs"] else { return ids }
    guard case .array(let values) = raw, !values.isEmpty, values.count <= LayerLimits.maximumLayers else { throw AutomationFailure(status: 400, message: "Provide1–8,000 layer IDs.") }
    let parsed = try values.map { value -> UUID in
      guard case .string(let text) = value, let id = UUID(uuidString: text) else { throw AutomationFailure(status: 400, message: "Invalid clipboard layer ID.") }
      return id
    }
    guard Set(parsed).count == parsed.count else { throw AutomationFailure(status: 400, message: "Clipboard layer IDs must be unique.") }
    return Set(parsed)
  }
  func clipboardPasteOptions() throws -> (PastePlacement, PathPoint?) {
    let placement: PastePlacement
    if parameters["placement"] != nil {
      guard let parsed = PastePlacement(rawValue: try string("placement")) else { throw AutomationFailure(status: 400, message: "Invalid paste placement.") }
      placement = parsed
    } else { placement = .centered }
    var center: PathPoint?
    if let raw = parameters["center"] {
      guard case .array(let values) = raw, values.count == 2 else { throw AutomationFailure(status: 400, message: "Paste center needs x and y.") }
      let points = try values.map { value -> Double in
        guard case .number(let n) = value, n.isFinite, abs(n) <= 1000000 else { throw AutomationFailure(status: 400, message: "Invalid paste center.") }; return n
      }
      center = .init(points[0], points[1])
    }
    return (placement, center)
  }
}

extension AutomationService {
  func executeClipboard(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    let store = document.store
    if command.parameters["target"] != nil{return try await executeClipboardPlane(command,document:document,share:share)}
    guard command.parameters["backgroundValue"]==nil else{throw AutomationFailure(status:400,message:"backgroundValue requires an explicit scalar target.")}
    if command.name == "clipboard.newDocument" { return try await clipboardNewDocument(command, document: document, share: share) }
    guard store.clipboardTargetAvailable else { throw AutomationFailure(status: 422, message: "Choose an available composite image target.") }
    if command.name == "clipboard.paste" {
      let bytes = try command.clipboardBytes(), (placement, center) = try command.clipboardPasteOptions()
      let settings = controller.colorSettings.value
      let choice = try ColorPolicyAPI.choice(command.parameters["colorDecision"].map { _ in try command.string("colorDecision") }, opening: false)
      try await executePreparedOperation(document: document, shareID: share.id, revision: command.revision) { source in
        try ColorPolicyInput.pasteCommand(ClipboardAPI.decode(bytes), into: source, settings: settings,
          choice: choice, placement: placement, center: center)
      }
      if store.document.restrictedMode != nil { store.selectedLayerIDs = Set(store.document.activeLayerID.map { [$0] } ?? []) }
      return .json(state(share, document: document))
    }
    if command.name == "clipboard.newDocument" { return try await clipboardNewDocument(command, document: document, share: share) }
    let cut = command.name == "clipboard.cut", ids = try command.clipboardIDs(default: store.clipboardLayerIDs)
    let merged = try command.pathFlag("merged", false), original = store.document
    let background = try command.clipboardBackground(default: store.backgroundColor)
    var response = try await clipboardPayload(original, ids: ids, merged: merged, command: command, document: document, share: share)
    if cut {
      try await executePreparedOperation(document: document, shareID: share.id, revision: command.revision) { snapshot in
        guard snapshot == original else { throw AutomationFailure(status: 409, message: "The Cut source changed.") }
        return .cut(Array(ids), background: background)
      }
      store.selectedLayerIDs = Set(store.document.activeLayerID.map { [$0] } ?? [])
      if store.document == original, store.session.actionRecording != nil { store.session.recordActionOperation(ActionOperation(recording: .cut(Array(ids), background: background), in: original), name: "Cut"); store.actionRevision += 1 }
      response["revision"] = revision(store); response["document"] = state(share, document: document)
    } else {
      store.recordClipboardCopy(ids: ids, merged: merged); response["revision"] = revision(store)
    }
    return .json(response)
  }
  private func clipboardPayload(_ original: CraftDocument, ids: Set<UUID>, merged: Bool,
    command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> [String: Any] {
    let store = document.store, expectedToken = token, panelGeneration = store.layerPanelGeneration
    store.geometryBusy = true
    defer { if store.layerPanelGeneration == panelGeneration { store.geometryBusy = false; store.geometryTask = nil } }
    let worker = Task.detached(priority: .userInitiated) {
      let content = try ClipboardRenderer.copy(original, layerIDs: ids, merged: merged), bytes = try content.encoded()
      guard bytes.count <= ClipboardAPI.maximumBytes else { throw AutomationFailure(status: 413, message: "Clipboard payload exceeds the2MiB API limit. Nothing was cut.") }
      return (content, bytes)
    }
    store.geometryTask = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    let (content, bytes) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard store.geometryTask?.isCancelled != true, isRunning, token == expectedToken,
      shares.contains(where: { $0.id == share.id && $0.document === document }), revision(store) == command.revision,
      store.document == original, store.layerPanelGeneration == panelGeneration else {
      throw AutomationFailure(status: 409, message: "Clipboard source changed or sharing ended.")
    }
    return ["payloadBase64": bytes.base64EncodedString(), "kind": content.kind.rawValue,
      "sourceMode": (content.restrictedSamples?.mode ?? content.document.colorMode).rawValue,
      "width": content.bounds.width, "height": content.bounds.height, "revision": revision(store)]
  }
  private func clipboardNewDocument(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers to create a clipboard document.") }
    guard !documentTransferBusy, shares.count < 8 else { throw AutomationFailure(status: 429, message: "Document transfer busy or sharing limit reached.") }
    let bytes = try command.clipboardBytes(), name = try parametersName(command)
    let store = document.store, original = store.document, expectedToken = token, transferGeneration = documentTransferGeneration
    let panelGeneration = store.layerPanelGeneration, closing = controller.documentClosing.state?.id
    let opening = controller.documentOpening.generation, maintenance = controller.recoveryMaintenance.generation, discovery = controller.recoveryDiscovery.generation
    guard !controller.documentClosing.isActive, !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, !controller.recoveryIndex.isBusy else { throw AutomationFailure(status: 409, message: "Finish the document lifecycle operation first.") }
    documentTransferBusy = true; store.geometryBusy = true
    defer { documentTransferBusy = false; if store.layerPanelGeneration == panelGeneration { store.geometryBusy = false; store.geometryTask = nil } }
    let worker = Task.detached(priority: .userInitiated) { try ClipboardAPI.decode(bytes).newDocument(name: name) }
    store.geometryTask = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    let model = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard store.geometryTask?.isCancelled != true, isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transferGeneration,
      shares.contains(where: { $0.id == share.id && $0.document === document }), store.document == original, revision(store) == command.revision, store.layerPanelGeneration == panelGeneration,
      shares.count < 8, NSApp?.modalWindow == nil, !controller.documentClosing.isActive, controller.documentClosing.state?.id == closing,
      !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, controller.documentOpening.generation == opening,
      !controller.recoveryIndex.isBusy, controller.recoveryMaintenance.generation == maintenance, controller.recoveryDiscovery.generation == discovery else {
      throw AutomationFailure(status: 409, message: "Clipboard creation cancelled or sharing/lifecycle changed.")
    }
    try Self.checkLimits(model)
    let created = CraftNSDocument(model: model); controller.addDocument(created)
    do { try self.share(created) } catch { controller.removeDocument(created); throw error }
    created.updateChangeCount(.changeDone); created.makeWindowControllers(); created.showWindows()
    guard let added = shares.first(where: { $0.document === created }) else { throw AutomationFailure(status: 409, message: "Document sharing ended.") }
    return .json(state(added, document: created), status: 201)
  }
  private func parametersName(_ command: AutomationCommand) throws -> String {
    try command.parameters["name"].map { _ in try command.string("name") } ?? controller.nextUntitledName
  }
}

extension EditorStore {
  var clipboardAPIState: [String: Any] {
    ["copyAvailable": canCopy(), "copyMergedAvailable": canCopy(merged: true), "cutAvailable": canCopy(cut: true),
     "pasteTargetAvailable": (clipboardPlaneTarget.map{canUseClipboardPlane($0,writing:true)} ?? false) || (clipboardTargetAvailable && (document.restrictedMode == nil || document.activeLayerID.map { !document.isImageLocked($0) } == true)),
     "targetedPlane":ClipboardPlaneAPI.state(self),
     "backgroundColor": [backgroundColor.r, backgroundColor.g, backgroundColor.b], "systemClipboardAccess": false]
  }
}
