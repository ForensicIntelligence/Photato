import AppKit
import ImageIO
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import Security
import UniformTypeIdentifiers

@MainActor @Observable final class AutomationService {
  struct Share: Identifiable {
    let id = UUID()
    weak var document: CraftNSDocument?
    let generation: UUID
  }
  let controller: CraftDocumentController
  private let server = AutomationHTTPServer()
  @ObservationIgnored let actionJobs: AdobeActionJobs
  private(set) var resourceJobsEnabled = false
  private(set) var documentTransfersEnabled = false
  private(set) var documentSavesEnabled = false
  private(set) var saveDirectoryURL: URL?
  @ObservationIgnored var documentSaveGeneration = UUID()
  @ObservationIgnored private var saveDirectoryScoped = false
  @ObservationIgnored var documentTransferGeneration = UUID()
  @ObservationIgnored var documentTransferBusy = false
  @ObservationIgnored let documentDecoder: @Sendable (Data, Bool, String) throws -> CraftDocument
  @ObservationIgnored private let pressedMouseButtons: @MainActor () -> Int
  @ObservationIgnored private(set) var token: String?
  private var generation = UUID()
  private var previewBusy = false
  private(set) var shares: [Share] = []
  private(set) var endpoint: String?
  private(set) var starting = false
  var message = "Stopped. Start the API and explicitly share a document to connect a client."
  var isRunning: Bool { endpoint != nil }
  init(
    controller: CraftDocumentController,
    pressedMouseButtons: @escaping @MainActor () -> Int = { NSEvent.pressedMouseButtons },
    resourceTransport: any AdobeResourceTransport = NativeAdobeResourceTransport(),
    documentDecoder: @escaping @Sendable (Data, Bool, String) throws -> CraftDocument = {
      try DocumentIO.decodeUpload($0, native: $1, name: $2)
    }
  ) {
    self.actionJobs = AdobeActionJobs(transport: resourceTransport)
    self.controller = controller
    self.pressedMouseButtons = pressedMouseButtons
    self.documentDecoder = documentDecoder
  }

  func start() {
    stop()
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      message = "Could not create an authentication token."
      return
    }
    token = Data(bytes).base64EncodedString()
    let expected = generation
    starting = true
    do {
      try server.start(
        onState: { [weak self] port, error in
          guard let self, self.generation == expected else { return }
          self.starting = false
          if let port {
            self.endpoint = "http://127.0.0.1:\(port)"
            self.message = "Running on this Mac. Only shared documents are accessible."
          } else {
            self.stop()
            self.message = error ?? "Stopped."
          }
        },
        handler: { [weak self] request in
          guard let self, self.generation == expected, !Task.isCancelled else {
            return .failure(.init(status: 503, message: "Session ended."))
          }
          return await self.handle(request)
        })
    } catch {
      stop()
      message = "Could not start the local API."
    }
  }
  func stop() {
    setDocumentTransfersEnabled(false)
    setDocumentSavesEnabled(false)
    setSaveDirectory(nil)
    resourceJobsEnabled = false
    actionJobs.revoke()
    generation = UUID()
    token = nil
    endpoint = nil
    starting = false
    shares.removeAll()
    server.stop()
    message = "Stopped. All tokens and document shares have been revoked."
  }
  func setResourceJobsEnabled(_ enabled: Bool) {
    resourceJobsEnabled = enabled && isRunning
    if !resourceJobsEnabled { actionJobs.revoke() }
  }
  func setDocumentTransfersEnabled(_ enabled: Bool) {
    documentTransferGeneration = UUID()
    documentTransfersEnabled = enabled && isRunning
  }
  func setDocumentSavesEnabled(_ enabled: Bool) {
    documentSaveGeneration = UUID()
    documentSavesEnabled = enabled && isRunning
  }
  func setSaveDirectory(_ url: URL?) {
    documentSaveGeneration = UUID()
    if saveDirectoryScoped { saveDirectoryURL?.stopAccessingSecurityScopedResource() }
    saveDirectoryURL = isRunning ? url?.standardizedFileURL.resolvingSymlinksInPath() : nil
    saveDirectoryScoped = saveDirectoryURL?.startAccessingSecurityScopedResource() ?? false
  }
  func copyToken() {
    guard let token, isRunning else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(token, forType: .string)
    message = "Token copied. Treat it as a password; stopping the API invalidates it."
  }
  func share(_ document: CraftNSDocument) throws {
    guard isRunning, controller.documents.contains(where: { $0 === document }) else {
      throw AutomationFailure(
        status: 409, message: "Start the API and select an open document first.")
    }
    try Self.checkLimits(document.store.document)
    prune()
    guard !shares.contains(where: { $0.document === document }) else { return }
    guard shares.count < 8 else {
      throw AutomationFailure(status: 429, message: "Share up to eight documents at once.")
    }
    shares.append(Share(document: document, generation: document.store.layerPanelGeneration))
    message =
      "Shared \(document.displayName ?? "Untitled"). Clients may read and edit this document."
  }
  func revoke(_ id: UUID) { shares.removeAll { $0.id == id } }
  func prune() {
    shares.removeAll { share in
      guard let document = share.document else { return true }
      return !controller.documents.contains(where: { $0 === document })
        || document.store.layerPanelGeneration != share.generation
    }
  }
  static func checkLimits(_ document: CraftDocument) throws {
    guard document.width * document.height <= 4_194_304, document.layers.count <= 64,
      document.estimatedBytes <= 128 * 1024 * 1024
    else {
      throw AutomationFailure(
        status: 413,
        message:
          "API v1 supports canvases up to 4,194,304 pixels, 64 layers and 128 MiB of document data."
      )
    }
  }
  func revision(_ store: EditorStore) -> String {
    "\(store.layerPanelGeneration.uuidString):\(store.revision):\(store.document.activeLayerID?.uuidString ?? "none")"
  }
  func state(_ share: Share, document: CraftNSDocument) -> [String: Any] {
    let store = document.store
    let saveFormats = document.saveFormats
    return [
      "id": share.id.uuidString, "name": document.displayName ?? "Untitled",
      "revision": revision(store),
      "width": store.document.width, "height": store.document.height,
      "depth": store.document.depth.rawValue,
      "activeLayerID": store.document.activeLayerID?.uuidString as Any? ?? NSNull(),
      "canUndo": !store.session.undoStack.isEmpty, "canRedo": !store.session.redoStack.isEmpty,
      "isModified": document.isDocumentEdited,
      "persistenceFormat": document.persistenceFormat.rawValue,
      "saveFormats": saveFormats.map(\.rawValue),
      "sourceSaveNeedsReview": document.sourceSaveNeedsReview,
      "canSave": documentSavesEnabled && document.fileURL != nil && !document.sourceSaveNeedsReview
        && saveFormats.contains(document.persistenceFormat) && document.canRunFileCommand,
      "canSaveAs": documentSavesEnabled && saveDirectoryURL != nil && document.canRunFileCommand,
      "hasRevertSource": document.revertSourceURL != nil,
      "fileOperationBusy": document.fileOperationBusy,
      "canRevert": documentTransfersEnabled && document.canRevertDocument,
      "channelTarget": store.componentTarget.title,
      "channelView": [
        "preview": store.channelView.preview.title,
        "visible": RGBChannelPreview.allCases.filter {
          $0 != .composite && store.channelView.isVisible($0)
        }.map(\.title),
        "componentEditing": store.editingComponent,
      ],
      "layers": store.document.layers.map { layer in
        [
          "id": layer.id.uuidString, "name": layer.name, "opacity": layer.opacity,
          "visible": layer.visible, "x": layer.x, "y": layer.y,
        ] as [String: Any]
      },
    ]
  }
  func preflight(_ document: CraftNSDocument) throws {
    let store = document.store
    // NSEvent reports buttons across the whole Mac. A click in another app or document
    // cannot be an in-progress pointer edit of this shared document. Gesture/draft guards
    // below continue to protect edits even after its window loses focus.
    let documentPointerActive =
      pressedMouseButtons() != 0 && NSApp?.isActive == true
      && document.windowForSheet?.isKeyWindow == true
    guard !document.fileOperationBusy, document.copyPanel == nil,
      !store.geometryBusy, !store.aiBusy, !store.hasToneDraft, store.transformDraft == nil,
      store.numericEditor == nil, store.layerNameDraft == nil, !store.coalescingChanges,
      store.pathGesture == nil, store.geometrySheet == nil, !store.showFeatherSelection,
      store.patternNameDraft == nil, store.gradientNameDraft == nil, !store.showAI,
      !store.showImagePlayground, store.error == nil, document.windowForSheet?.attachedSheet == nil,
      NSApp?.modalWindow == nil, !documentPointerActive
    else {
      throw AutomationFailure(
        status: 409,
        message: "Finish or cancel the current desktop interaction before editing through the API.")
    }
    try Self.checkLimits(store.document)
  }
  func handle(_ request: AutomationRequest) async -> AutomationResponse {
    if request.method == "GET", let asset = AutomationBrowser.asset(request.path) { return asset }
    guard let token, isRunning, request.headers["authorization"] == "Bearer \(token)" else {
      if request.path.hasPrefix("/v2/") {
        return AdobeAPIError(
          status: 401, code: "401013", message: "A current local bearer token is required."
        ).response
      }
      return .failure(.init(status: 401, message: "A current bearer token is required."))
    }
    do {
      guard !Task.isCancelled else {
        throw AutomationFailure(status: 503, message: "Request cancelled.")
      }
      prune()
      if let response = try handleActionJobRequest(request) { return response }
      if let response = try await handleDocumentTransfer(request) { return response }
      if request.method == "GET", request.path == "/v1/capabilities" {
        var result = Self.capabilities
        result["resourceJobsEnabled"] = resourceJobsEnabled
        result["documentTransfersEnabled"] = documentTransfersEnabled
        result["documentSavesEnabled"] = documentSavesEnabled
        result["saveAsFolderSelected"] = saveDirectoryURL != nil
        return .json(result)
      }
      if request.method == "GET", request.path == "/v1/documents" {
        return .json([
          "documents": shares.compactMap { share in
            share.document.map { state(share, document: $0) }
          }
        ])
      }
      let parts = request.path.split(separator: "/", omittingEmptySubsequences: false)
      guard parts.count == 4 || parts.count == 5, parts[0] == "", parts[1] == "v1",
        parts[2] == "documents",
        let id = UUID(uuidString: String(parts[3])),
        let share = shares.first(where: { $0.id == id }),
        let document = share.document
      else { throw AutomationFailure(status: 404, message: "Shared document or route not found.") }
      let store = document.store
      if request.method == "GET", parts.count == 4 {
        return .json(state(share, document: document))
      }
      if request.method == "GET", parts.count == 5,
        parts[4] == "preview.png" || parts[4] == "channel-preview.png"
      {
        try Self.checkLimits(store.document)
        guard !previewBusy else {
          throw AutomationFailure(
            status: 429, message: "A preview is already rendering. Retry shortly.")
        }
        previewBusy = true
        defer { previewBusy = false }
        let snapshot = store.document
        let channelView = parts[4] == "channel-preview.png" ? store.channelView : RGBChannelView()
        let expectedRevision = revision(store)
        let expectedGeneration = generation
        let worker = Task.detached(priority: .utility) {
          try Self.png(snapshot, channelView: channelView)
        }
        let bytes = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        prune()
        guard !Task.isCancelled, generation == expectedGeneration,
          revision(store) == expectedRevision,
          shares.contains(where: { $0.id == id })
        else {
          throw AutomationFailure(
            status: 409, message: "Document changed or sharing ended during rendering.")
        }
        return .init(status: 200, contentType: "image/png", body: bytes)
      }
      guard request.method == "POST", parts.count == 5, parts[4] == "commands" else {
        throw AutomationFailure(status: 404, message: "Route not found.")
      }
      guard
        request.headers["content-type"]?.lowercased().split(separator: ";").first
          == "application/json"
      else {
        throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
      }
      let command = try AutomationCommand(data: request.body)
      guard command.revision == revision(store) else {
        throw AutomationFailure(
          status: 409, message: "Stale revision. Refresh the document before retrying.")
      }
      try preflight(document)
      if try await handleDocumentSave(command, document: document, shareID: id) {
        return .json(state(share, document: document))
      }
      if command.name == "document.revert" {
        guard documentTransfersEnabled else {
          throw AutomationFailure(
            status: 403, message: "Enable document transfers and Revert in the native API window.")
        }
        guard document.revertSourceURL != nil else {
          throw AutomationFailure(
            status: 409, message: "This document has no saved file to revert to.")
        }
        let expectedToken = token
        let expectedGeneration = documentTransferGeneration
        let decoder = documentDecoder
        try await document.revertDocument(
          reader: { url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= DocumentIO.maximumUploadBytes else {
              throw AutomationFailure(
                status: 413, message: "Saved file exceeds the API input limit.")
            }
            return try decoder(
              Data(contentsOf: url), DocumentIO.isNativeFile(url),
              url.deletingPathExtension().lastPathComponent)
          },
          validate: { model in
            self.prune()
            guard self.isRunning, self.token == expectedToken, self.documentTransfersEnabled,
              self.documentTransferGeneration == expectedGeneration,
              self.shares.contains(where: { $0.id == id }), command.revision == self.revision(store)
            else {
              throw AutomationFailure(
                status: 409, message: "Revert was cancelled or sharing changed.")
            }
            try Self.checkLimits(model)
          })
        return .json(state(share, document: document))
      }
      if try command.applyViewCommand(to: store) {
        return .json(state(share, document: document))
      }
      if command.name == "layer.new" {
        guard store.document.layers.count < 64,
          store.document.estimatedBytes + store.document.width * store.document.height * 16 <= 128
            * 1024 * 1024
        else {
          throw AutomationFailure(status: 413, message: "Adding a layer would exceed API limits.")
        }
      }
      if let native = try command.nativeCommand(document: store.document) {
        try store.executeEditorCommand(native)
      } else if command.name == "history.undo" {
        if let candidate = store.session.undoStack.last?.document {
          try Self.checkLimits(candidate)
        }
        store.undo()
      } else {
        if let candidate = store.session.redoStack.last?.document {
          try Self.checkLimits(candidate)
        }
        store.redo()
      }
      return .json(state(share, document: document))
    } catch let failure as DocumentSaveConflict {
      return .failure(.init(status: 409, message: failure.localizedDescription))
    } catch let failure as DocumentPersistenceConflict {
      return .failure(.init(status: 409, message: failure.localizedDescription))
    } catch let failure as AdobeAPIError {
      return request.path.hasPrefix("/v2/")
        ? failure.response
        : .failure(.init(status: failure.status, message: failure.message))
    } catch let failure as AutomationFailure { return .failure(failure) } catch {
      return .failure(.init(status: 422, message: error.localizedDescription))
    }
  }
  nonisolated static func png(
    _ document: CraftDocument, channelView: RGBChannelView = RGBChannelView()
  ) throws -> Data {
    try Task.checkCancellation()
    let composite = try Renderer.composite(document)
    try Task.checkCancellation()
    let image = try RasterIO.displayImage(channelView.applying(to: composite))
    let bytes = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        bytes, UTType.png.identifier as CFString, 1, nil)
    else {
      throw AutomationFailure(status: 500, message: "Could not encode preview.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AutomationFailure(status: 500, message: "Could not encode preview.")
    }
    return bytes as Data
  }
  static var capabilities: [String: Any] {
    func inventory(_ nodes: [EditorMenuNode], parents: [String] = []) -> [[String: Any]] {
      nodes.filter { $0.title != "-" }.flatMap { node -> [[String: Any]] in
        let path = parents + [node.title]
        return [
          ["path": path, "kind": node.children == nil ? "command" : "menu", "shortcut": node.key]
        ]
          + (node.children.map { inventory($0, parents: path) } ?? [])
      }
    }
    return [
      "apiVersion": 1, "transport": "loopback HTTP; bearer token; same origin",
      "commands": AutomationCommand.definitions.map {
        [
          "command": $0.name, "parameters": $0.parameters, "description": $0.description,
          "schema": $0.schema,
        ] as [String: Any]
      }, "menuInventory": inventory(PhotoshopMenuCatalog.menus),
      "menuInventoryNotice":
        "Reference inventory only. Only entries in commands are executable through this API.",
      "previews": [
        "preview.png": "Committed document composite, independent of channel visibility.",
        "channel-preview.png":
          "Committed composite with native channel visibility. Excludes drafts and mask overlays.",
      ],
      "channelView": [
        "preview": "RGB, Red, Green or Blue", "visible": "Nonempty array of Red, Green, Blue",
        "componentEditing":
          "True when an individual editing target is selected; independent of preview",
        "persistence": "Per-document view state; no document history entry",
      ],
      "componentEditing": [
        "targets": RGBChannelPreview.allCases.map(\.title),
        "depth": "RGB8", "operations": ["Normal neutral Fill"],
        "unimplemented": [
          "Other component tools", "RGB16/32 component writes", "Alpha/spot channels",
        ],
      ],
      "actionJobs": [
        "photatoSubmit": "/v1/action-jobs", "photatoStatus": "/v1/action-jobs/{jobId}",
        "adobeSubmit": "/v2/execute-actions", "adobeStatus": "/v2/status/{jobId}",
        "notice":
          "Optional isolated resource jobs. Requires native enablement each session. Inline actionJSON RGB8 select/neutral Fill; RGB16/32 PSD supports composite RGB selection and PSD preservation only. Other Adobe operations are unsupported.",
      ],
      "documentTransfers": documentTransferCapabilities,
      "documentSaving": documentSavingCapabilities,
      "stateSchemas": [
        "isModified": ["type": "boolean"],
        "persistenceFormat": [
          "type": "string", "enum": DocumentIO.Format.allCases.map(\.rawValue),
        ],
        "saveFormats": [
          "type": "array", "uniqueItems": true,
          "items": ["type": "string", "enum": DocumentIO.Format.allCases.map(\.rawValue)],
        ],
        "canSave": ["type": "boolean"], "canSaveAs": ["type": "boolean"],
        "sourceSaveNeedsReview": ["type": "boolean"],
        "channelTarget": ["type": "string", "enum": RGBChannelPreview.allCases.map(\.title)],
        "channelView": [
          "type": "object", "additionalProperties": false,
          "required": ["preview", "visible", "componentEditing"],
          "properties": [
            "preview": ["type": "string", "enum": RGBChannelPreview.allCases.map(\.title)],
            "visible": [
              "type": "array", "minItems": 1, "maxItems": 3, "uniqueItems": true,
              "items": ["type": "string", "enum": ["Red", "Green", "Blue"]],
            ],
            "componentEditing": ["type": "boolean"],
          ],
        ],
      ],
      "limits": [
        "maxCanvasPixels": 4_194_304, "maxLayers": 64, "maxDocumentBytes": 134_217_728,
        "maxSharedDocuments": 8, "maxRequestBytes": 65_536,
      ],
      "commandEnvelope": [
        "command": "stable command name", "revision": "latest document revision",
        "parameters": "object; all listed fields required",
      ],
      "history":
        "Shared with desktop edits. A successful no-op may leave revision and history unchanged.",
    ]
  }
}
