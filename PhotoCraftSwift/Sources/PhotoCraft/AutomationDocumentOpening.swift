import Foundation
import PhotoCraftCore

extension AutomationService {
  var documentOpeningState: [String: Any] {
    let opening = controller.documentOpening
    let state = opening.state
    return [
      "active": opening.isActive, "operationID": state?.id.uuidString as Any? ?? NSNull(),
      "cancellationRequested": state?.cancellationRequested ?? false,
      "total": state?.total ?? 0, "opened": state?.opened ?? 0,
      "alreadyOpen": state?.alreadyOpen ?? 0, "failed": state?.failed ?? 0,
      "canCancel": opening.isActive && (documentTransfersEnabled
        || (recentFilesEnabled && ownedRecentOpening == state?.id)),
      "queuedFiles": opening.queuedCount, "lastError": state?.lastError as Any? ?? NSNull(),
    ]
  }
  func handleDocumentOpening(_ request: AutomationRequest) throws -> AutomationResponse? {
    if request.path == "/v1/document-opening", request.method == "GET" {
      return .json(documentOpeningState)
    }
    guard request.path == "/v1/document-opening/cancel", request.method == "POST" else { return nil }
    guard documentTransfersEnabled || (recentFilesEnabled && ownedRecentOpening != nil
      && ownedRecentOpening == controller.documentOpening.state?.id) else {
      throw AutomationFailure(status: 403, message: "Allow document transfers and cancellation in the native API window first.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    guard let body = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      Set(body.keys) == ["operationID"], case .string(let value) = body["operationID"],
      let id = UUID(uuidString: value) else {
      throw AutomationFailure(status: 400, message: "Required: operationID UUID.")
    }
    guard controller.documentOpening.isActive, controller.documentOpening.state?.id == id else {
      throw AutomationFailure(status: 409, message: "That document opening operation is no longer active.")
    }
    controller.documentOpening.cancel(id)
    return .json(documentOpeningState)
  }
  static var documentOpeningCapabilities: [String: Any] {
    let count: [String: Any] = ["type": "integer", "minimum": 0]
    return [
      "desktop": "File > Open: Show All Readable Documents/All Documents, Format selector and cancellable background file/model/fingerprint reads. Earlier opened files stay open if a later read fails or is cancelled.",
      "formats": DocumentOpenFormat.allCases.map { ["id": $0.rawValue, "title": $0.title] },
      "uploadPath": "/v1/documents/import", "uploadHeader": "X-Photato-Open-Format",
      "uploadHeaderSchema": ["type": "string", "enum": DocumentOpenFormat.allCases.filter{$0 != .pdf}.map(\.rawValue)],
      "pdfImportPath": PDFImportAPI.importPath,
      "contentType": "Existing upload types remain supported. application/octet-stream requires X-Photato-Open-Format. Without that header, legacy Content-Type native/raster routing is unchanged.",
      "selection": "Verifies actual container before the shared decoder; mismatches fail422 and unknown selections400. Automatic detects native chunked/plist containers independently of filenames. Full decoder validation is still required; a signature is not proof of a valid file.",
      "pcraft": ["mode": "editable-import-subset", "mediaType": "application/vnd.photocraft.project",
        "input": "Original PhotoCraft v1 ZIP projects through upload/action jobs; ZIP and directory projects through native Open. Select PhotoCraft Project in Open to select a directory.",
        "supported": "RGB8/16/32 raster layers, nested groups, visibility/opacity/blending/clipping, protection, grayscale masks, vector masks, saved/work paths, canvas GRAY8 selection and RGB working profiles. Solid/gradient/pattern fill layers, fill opacity document-owned RGB/grayscale patterns full-control Exposure adjustments and editable shape/live-path/stroke data and rich text (Unicode runs, character/paragraph formatting, fractional frames, orientation/AA/warp and pristine source appearance) are retained as editable native data. Embedded Smart Object originals, nested supported projects, source placement/Warp, stack modes, mapped filter stages/masks and pristine appearance are retained with native70. All16 executable source adjustment kinds plus opaque records, all ten source effect kinds, contours, glow/bevel/texture/paint controls, inert pattern/PSD references and shared document light are retained within their admitted bounds; advanced styles require native75. Original auxiliary alpha/spot channels and Quick Mask import at document depth; spots require native76.",
        "documentGuides":"Original horizontal/vertical Float32 positions retain editable native guide records, desktop/API controls, native78 persistence and PSD/PSB fixed-point interchange.",
        "artboards":["supported":true,"behavior":"Top-level source artboard groups retain editable bounds, white/black/transparent/custom RGB or grayscale backgrounds, preset names, hierarchy, blending, protection and children in document coordinates. Negative extents are rebased into the native canvas while logical artboard coordinates, original manifest and source pixels are retained. Existing native artboard editing/history/extraction/export uses the same engine.","limits":"Existing native canvas, layer, color, source and metadata admission applies. Nested or clipped artboards and unknown fields reject atomically. Editable artboard PSD/PSB interchange remains unsupported; PhotoCraft input is a Photato extension, not an added Adobe input type."],
        "linkedEmbeddedOriginals":["supported":true,"blocks":["lnk2","lnk3","lnkD","lnkE"],"behavior":"SmartSource.Linked identifiers can resolve currently decodable liFD originals already inside retained8BIM/8B64 project metadata. Original bytes, shared source identity, placement/filters and pristine caches remain editable. No filesystem lookup; external liFE, aliases, missing originals and ambiguous IDs reject. Unreferenced globals stay opaque.","limits":"Existing64MiB source, nesting, decoder/import/owned budgets and supported original kinds remain. PDF source context, authorized external resolution and full migration/fidelity remain open."],
        "unsupported": "Nonzero unbounded raster defaults, non-RGB documents, nondefault document text-style libraries, external/alias/unresolved linked Smart sources without authorized original extents, unmapped/unknown Smart Filter and adjustment programs, other rich layer types/comps/timeline, nested or clipped artboards, dual-alpha gradients, linked pattern masks, out-of-frame nondefault pattern samples and unsupported color/parameter budgets reject the whole import. No preview flattening.",
        "sourceAdjustmentExecutableKinds":SourceAdjustment.Kind.allCases.filter{$0 != .unsupported}.map(\.rawValue),
        "sourceLayerEffectKinds":LayerEffect.Kind.allCases.map(\.rawValue),"sourceStyleArchiveVersion":75,"sourceChannelArchiveVersion":76,
        "sourceStyleLimitations":"Source inactive switches remain retained/inactive. Direct and full-project exact words, vector/text/off-canvas/geometry/ICC contexts and full Photoshop fidelity remain unqualified. Bound pattern references use only document-owned artwork; source hints never open files.",
        "save": "Imports have no writable source association. Save As creates a native Photato document; original project files remain unchanged.",
        "adobe": "Photato-only input format; Adobe v2 input contract is unchanged."],
      "statePath": "/v1/document-opening", "readMethod": "GET",
      "cancelPath": "/v1/document-opening/cancel", "cancelMethod": "POST",
      "cancelSchema": ["type": "object", "additionalProperties": false,
        "required": ["operationID"], "properties": ["operationID": ["type": "string", "format": "uuid"]]],
      "stateSchema": ["type": "object", "additionalProperties": false,
        "required": ["active", "operationID", "cancellationRequested", "total", "opened", "alreadyOpen", "failed", "canCancel", "queuedFiles", "lastError"],
        "properties": ["active": ["type": "boolean"], "operationID": ["type": ["string", "null"], "format": "uuid"],
          "cancellationRequested": ["type": "boolean"], "total": count, "opened": count,
          "alreadyOpen": count, "failed": count, "canCancel": ["type": "boolean"],
          "queuedFiles": count, "lastError": ["type": ["string", "null"]]]],
      "cancellation": "Separate native opening operation ID. Requires document-transfer permission, or an active operation owned by this session's enabled recent-file access. Permissions start off each session. No file paths/names are exposed. Cancellation keeps completed documents, never publishes a cancelled read, and may wait for a non-interruptible decoder to finish.",
      "errors": ["400": "Invalid selection/fields", "401": "Authentication", "403": "Transfers disabled",
        "409": "Busy/stale operation ID", "415": "Unsupported media type", "422": "Format mismatch or decode failure"],
      "sdkQueue": "Public Open requests queue behind active reads and startup recovery; each receives one callback, including unstarted files in a cancelled batch. Later arriving batches have their own operation IDs. queuedFiles reports pending requests. Queue capacity is1000 requests.",
      "limits": "Same supported decoders, colour policy and input/raster limits; PDF pages use a native selection dialog; embedded images, PDF-backed Smart Objects and editable Photoshop PDF data remain open. Not full Camera Raw/EPS/video/import-options parity. Complete sandbox/platform/live UI qualification remains open.",
      "adobe": "No corresponding desktop file-dialog/cancel endpoint. Adobe resource jobs retain their published contracts and shared codecs; no new Adobe route.",
    ]
  }
}
