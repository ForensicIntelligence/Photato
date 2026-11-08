import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum IllustratorPathExportAPI {
  static var selectionSchema: [String: Any] {
    BrushAPI.object(["target": BrushAPI.enumeration(IllustratorPathExport.Target.allCases.map(\.rawValue)),
      "id": ["anyOf": [["type": "null"], ["type": "string", "format": "uuid"]]]], required: ["target", "id"])
  }
  static var stateSchema: [String: Any] {
    let choice = BrushAPI.object(["name": ["type": "string"], "selection": selectionSchema], required: ["name", "selection"])
    return BrushAPI.object(["available": BrushAPI.flag, "busy": BrushAPI.flag,
      "operationID": ["anyOf": [["type": "null"], ["type": "string", "format": "uuid"]]],
      "choices": ShapeAPI.array(choice, 132), "defaultSelection": selectionSchema],
      required: ["available", "busy", "operationID", "choices", "defaultSelection"])
  }
  static var capabilities: [String: Any] { [
    "method": "GET", "path": "/v1/documents/{id}/paths.ai", "contentType": IllustratorPathExport.mediaType,
    "maximumBytes": IllustratorPathExport.maximumBytes, "permission": "documentTransfersEnabled",
    "targetHeader": ["name": "X-Photato-Path-Target", "required": false,
      "schema": BrushAPI.enumeration(IllustratorPathExport.Target.allCases.map(\.rawValue))],
    "identifierHeader": "X-Photato-Path-ID: UUID required only for saved, shape or vectorMask. Shape/vectorMask must belong to the active layer.",
    "filenameHeader": "X-Photato-Path-Filename: optional percent-encoded basename, 1–1024 UTF-8 bytes without controls; default Paths.ai.",
    "revisionHeader": "Optional X-Photato-Revision must match the shared document.",
    "cancelCommand": "image.export.cancel with operationID from paths.illustratorExport",
    "defaults": "All Paths when there are multiple eligible paths; the sole eligible path otherwise; Document Bounds when there are none.",
    "stateSchema": stateSchema, "resultSchema": ["type": "string", "format": "binary", "maxLength": IllustratorPathExport.maximumBytes],
    "behavior": "Shared native geometry-only Illustrator path export. Document pixels convert to PostScript points using document resolution, y upward. Retains cubic handles, open/closed contours, smooth/corner anchors, joined contours, boolean operation annotations and inversion. Bounds-only contains crop marks without a rectangle. No document/history/dirty changes.",
    "errors": [400, 401, 403, 404, 409, 413, 422, 429],
    "qualification": "Owned Photoshop 2026 path files qualify selected geometry and options only. No pixel artwork, fills, strokes, type, layer effects, modern AI document or PDF preview is included. Broader Illustrator consumer, physical macOS14/Intel and full I04 qualification remain open. No dedicated route in the pinned Adobe v2 contract; no Adobe route or action descriptor is invented."
  ] }
  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    func selection(_ value: IllustratorPathExport.Selection) -> [String: Any] {
      ["target": value.target.rawValue, "id": value.id?.uuidString as Any? ?? NSNull()]
    }
    let choices = (try? IllustratorPathExport.choices(store.document)) ?? []
    return ["available": store.canExportIllustratorPaths, "busy": store.illustratorExportID != nil,
      "operationID": store.illustratorExportID?.uuidString as Any? ?? NSNull(),
      "choices": choices.map { ["name": $0.name, "selection": selection($0.selection)] },
      "defaultSelection": selection((try? IllustratorPathExport.defaultSelection(store.document)) ?? .init(.documentBounds))]
  }
  static func selection(_ request: AutomationRequest) throws -> IllustratorPathExport.Selection? {
    let raw = request.headers["x-photato-path-target"], identifier = request.headers["x-photato-path-id"]
    guard let raw else {
      guard identifier == nil else { throw AutomationFailure(status: 400, message: "Path ID requires an explicit target.") }
      return nil
    }
    guard let target = IllustratorPathExport.Target(rawValue: raw), identifier == nil || UUID(uuidString: identifier!) != nil else {
      throw AutomationFailure(status: 400, message: "Invalid Illustrator path target or UUID.")
    }
    let selection = IllustratorPathExport.Selection(target, id: identifier.flatMap(UUID.init(uuidString:)))
    do { try selection.validate() } catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    return selection
  }
}

extension AutomationService {
  func cancelSharedIllustratorPaths(_ share: Share) {
    if illustratorExportShares.contains(share.id) { share.document?.store.illustratorExportWorker?.cancel() }
  }
  func exportIllustratorPaths(_ request: AutomationRequest, share: Share, document: CraftNSDocument) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers before exporting paths.") }
    guard request.body.isEmpty else { throw AutomationFailure(status: 400, message: "Path export expects an empty body.") }
    guard !documentTransferBusy else { throw AutomationFailure(status: 429, message: "A document transfer is already in progress.") }
    try preflight(document)
    let store = document.store, source = store.document, expectedRevision = revision(store)
    if let requested = request.headers["x-photato-revision"], requested != expectedRevision { throw AutomationFailure(status: 409, message: "The document revision changed.") }
    let selection = try IllustratorPathExportAPI.selection(request)
    if let selection, selection.id != nil, !(try IllustratorPathExport.sources(source)).contains(where: { $0.selection == selection }) {
      throw AutomationFailure(status: 404, message: "The selected saved or active-layer path is unavailable.")
    }
    let title: String
    if let raw = request.headers["x-photato-path-filename"] {
      guard let name = raw.removingPercentEncoding, !name.isEmpty, name.utf8.count <= 1024,
        name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
        !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
        throw AutomationFailure(status: 400, message: "Supply a percent-encoded Illustrator basename without controls or directory separators.")
      }
      title = name
    } else { title = "Paths.ai" }
    let expectedToken = token, transfer = documentTransferGeneration
    documentTransferBusy = true; illustratorExportShares.insert(share.id)
    defer { documentTransferBusy = false; illustratorExportShares.remove(share.id) }
    let bytes = try await store.encodedIllustratorPaths(selection, title: title)
    prune()
    guard !Task.isCancelled, isRunning, token == expectedToken, documentTransfersEnabled,
      documentTransferGeneration == transfer, document.closeWorkflowID == nil,
      shares.contains(where: { $0.id == share.id && $0.document === document }),
      store.document == source, revision(store) == expectedRevision else {
      throw AutomationFailure(status: 409, message: "Path export was cancelled, revoked or its source changed.")
    }
    return .init(status: 200, contentType: IllustratorPathExport.mediaType, body: bytes)
  }
}
