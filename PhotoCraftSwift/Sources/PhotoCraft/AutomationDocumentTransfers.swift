import AppKit
import Foundation
import ImageIO
import PhotoCraftCore

extension DocumentIO {
  static func decodeUpload(_ data: Data, native: Bool, name: String) throws -> CraftDocument {
    guard !data.isEmpty, data.count <= maximumUploadBytes else {
      throw AutomationFailure(status: 413, message: "Upload must contain 1 byte to 64 MiB.")
    }
    let width: Int
    let height: Int
    if native {
      struct Header: Decodable {
        struct Document: Decodable {
          let width: Int
          let height: Int
        }
        let document: Document
      }
      let header = try PropertyListDecoder().decode(Header.self, from: data)
      (width, height) = (header.document.width, header.document.height)
    } else if data.starts(with: Data("8BPS".utf8)) {
      guard data.count >= 26 else {
        throw AutomationFailure(status: 422, message: "Truncated PSD header.")
      }
      func number(_ offset: Int) -> Int {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
      }
      (width, height) = (number(18), number(14))
    } else {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let w = properties[kCGImagePropertyPixelWidth] as? Int,
        let h = properties[kCGImagePropertyPixelHeight] as? Int
      else { throw AutomationFailure(status: 422, message: "Unsupported image data.") }
      (width, height) = (w, h)
    }
    guard width > 0, height > 0, width <= 4_194_304 / height else {
      throw AutomationFailure(status: 413, message: "Upload exceeds the 4,194,304 pixel API limit.")
    }
    return try decode(data, native: native, name: name, rasterByteLimit: 128 * 1_024 * 1_024)
  }
}

extension AutomationService {
  static var documentTransferCapabilities: [String: Any] {
    [
      "import": [
        "method": "POST", "path": "/v1/documents/import", "successStatus": 201,
        "contentTypes": DocumentIO.uploadTypes,
        "bodySchema": [
          "type": "string", "format": "binary", "minLength": 1,
          "maxLength": DocumentIO.maximumUploadBytes,
        ],
        "nameHeader": [
          "name": "X-Photato-Name", "required": false,
          "schema": ["type": "string", "minLength": 1, "maxLength": 256, "pattern": "^[ -~]+$"],
        ],
        "result":
          "New shared document state, including id, revision and isModified. Native archives retain their stored name.",
      ],
      "download": [
        "method": "GET", "path": "/v1/documents/{id}/file.{format}",
        "formats": DocumentIO.Format.allCases.map(\.rawValue),
        "formatAliases": ["pcswift": DocumentIO.Format.native.rawValue],
        "responseTypes": DocumentIO.Format.allCases.map(\.mediaType),
        "maxBytes": DocumentIO.maximumDownloadBytes,
        "revisionHeader": "Optional X-Photato-Revision must equal the current document revision.",
        "result":
          "Binary snapshot; native archives retain editable structure, PSD retains supported structures, raster outputs flatten.",
      ],
      "metadata": [
        "raster":
          "Retains imported ImageIO camera, copyright, descriptive and XMP metadata where the output format supports it; updates orientation, dimensions, resolution and sRGB color-space fields.",
        "psd":
          "Retains opaque image-resource blocks except regenerated profile/resolution/paths and stale thumbnail, layer-index, selection, version and recovery records. Retention does not implement unsupported Photoshop workflows.",
        "profiles":
          "Working/output samples remain sRGB (linear sRGB for RGB32 PSD). Original non-sRGB profile preservation is not yet supported.",
        "metadataLimitBytes": 16 * 1024 * 1024,
      ],
      "float32Storage": [
        "nativeArchiveVersion": 9,
        "encoding": "linearRGB",
        "preservation":
          "Supported linear-sRGB RGB32 PSD raster samples retain their IEEE754 bits through native archives, metadata-only edits and PSD layer output. Opaque untransformed Normal raster composition and ordinary groups retain exact samples in merged output.",
        "limits":
          "Original non-sRGB profiles, transforms, adjustments, fractional blending and all HDR editing operations are not fully qualified for exact Photoshop output. Source RGB32 replacement still requires Save As review.",
        "interfaces": [
          "document downloads", "document.save", "document.saveAs", "/v1/action-jobs",
          "/v2/execute-actions",
        ],
      ],
      "saveCopy": [
        "desktopCommand": "File > Save a Copy…", "shortcut": "Option-Command-S",
        "apiOperation": "GET /v1/documents/{id}/file.{format}",
        "formats": DocumentIO.Format.allCases.map {
          ["format": $0.rawValue, "effect": $0.copyDescription]
        },
        "stateEffect":
          "Does not change the open document, its filename, modified flag or undo/redo history.",
      ],
      "revert": [
        "command": "document.revert", "method": "POST", "path": "/v1/documents/{id}/commands",
        "parameters": "Empty object; current revision is required. No filesystem paths accepted.",
        "stateEffect":
          "Reads only the associated local file; restores it as one undoable edit and clears the modified flag. Upload-only documents have no source until saved in the desktop.",
        "limits": "Same 64 MiB input, pixel, layer and decoded-memory limits as uploads.",
      ],
      "availability":
        "Requires native document-transfer enablement and session authentication. Downloads additionally require an existing document share. One transfer at a time; eight shared documents maximum.",
      "errors": [
        "400": "Invalid name", "401": "Authentication", "403": "Disabled",
        "404": "Missing share/route", "409": "Busy, stale, changed or revoked",
        "413": "Resource limit", "415": "Content type",
        "422": "Decode/encode or unsupported format semantics", "429": "Transfer or share capacity",
      ],
      "persistence":
        "No filesystem paths accepted. Uploads create unsaved native documents. Downloads never save or clear desktop dirty/history state. Explicit document.revert reloads only the already-associated file and is undoable.",
      "adobe":
        "Desktop open/download has no dedicated Adobe v2 endpoint. Existing execute-actions resource input/output remains a separately qualified subset using the shared native codecs.",
    ]
  }

  func handleDocumentTransfer(_ request: AutomationRequest) async throws -> AutomationResponse? {
    let importing = request.method == "POST" && request.path == "/v1/documents/import"
    let parts = request.path.split(separator: "/")
    let format =
      parts.count == 4 && parts[0] == "v1" && parts[1] == "documents"
        && parts[3].hasPrefix("file.")
      ? DocumentIO.Format(fileExtension: String(parts[3].dropFirst(5))) : nil
    let downloading = request.method == "GET" && format != nil
    guard importing || downloading, request.path == "/" + parts.joined(separator: "/") else {
      return nil
    }
    guard documentTransfersEnabled else {
      throw AutomationFailure(
        status: 403, message: "Enable document uploads and downloads in the native API window.")
    }
    guard !documentTransferBusy else {
      throw AutomationFailure(status: 429, message: "A document transfer is already in progress.")
    }
    let expectedGeneration = documentTransferGeneration
    let expectedToken = token
    documentTransferBusy = true
    defer { documentTransferBusy = false }
    func validateSession() throws {
      guard !Task.isCancelled, isRunning, token == expectedToken, documentTransfersEnabled,
        documentTransferGeneration == expectedGeneration
      else {
        throw AutomationFailure(status: 409, message: "Document transfer was cancelled or revoked.")
      }
    }

    if importing {
      guard
        let contentType = request.headers["content-type"]?.lowercased().split(separator: ";").first
          .map(String.init),
        DocumentIO.uploadTypes.contains(contentType)
      else {
        throw AutomationFailure(
          status: 415, message: "Choose a supported image or Photato document Content-Type.")
      }
      let name = request.headers["x-photato-name"] ?? "Imported Image"
      guard !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 256,
        name.utf8.allSatisfy({ (32...126).contains($0) })
      else {
        throw AutomationFailure(
          status: 400, message: "X-Photato-Name must contain 1–256 printable ASCII characters.")
      }
      guard shares.count < 8 else {
        throw AutomationFailure(status: 429, message: "Share up to eight documents at once.")
      }
      guard NSApp?.modalWindow == nil else {
        throw AutomationFailure(
          status: 409, message: "Finish the modal dialog before opening a document.")
      }
      let native = contentType == DocumentIO.Format.native.mediaType
      let decoder = documentDecoder
      let worker = Task.detached(priority: .utility) { try decoder(request.body, native, name) }
      let model = try await withTaskCancellationHandler(
        operation: { try await worker.value }, onCancel: { worker.cancel() })
      try validateSession()
      try Self.checkLimits(model)
      guard NSApp?.modalWindow == nil else {
        throw AutomationFailure(status: 409, message: "A modal dialog opened during the transfer.")
      }
      guard shares.count < 8 else {
        throw AutomationFailure(
          status: 429, message: "Document sharing capacity changed during upload.")
      }
      let document = CraftNSDocument(model: model)
      controller.addDocument(document)
      do { try share(document) } catch {
        controller.removeDocument(document)
        throw error
      }
      document.updateChangeCount(.changeDone)
      document.makeWindowControllers()
      document.showWindows()
      guard let share = shares.first(where: { $0.document === document }) else {
        throw AutomationFailure(status: 409, message: "Document sharing ended.")
      }
      return .json(state(share, document: document), status: 201)
    }

    guard let format, let id = UUID(uuidString: String(parts[2])),
      let share = shares.first(where: { $0.id == id }), let document = share.document
    else {
      throw AutomationFailure(status: 404, message: "Shared document not found.")
    }
    try preflight(document)
    try Self.checkLimits(document.store.document)
    let expectedRevision = revision(document.store)
    guard
      request.headers["x-photato-revision"] == nil
        || request.headers["x-photato-revision"] == expectedRevision
    else {
      throw AutomationFailure(status: 409, message: "Stale document revision.")
    }
    let snapshot = document.store.document
    let worker = Task.detached(priority: .utility) {
      try DocumentIO.encode(snapshot, format: format)
    }
    let data = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try validateSession()
    prune()
    guard shares.contains(where: { $0.id == id }), revision(document.store) == expectedRevision
    else {
      throw AutomationFailure(
        status: 409, message: "Document changed or sharing ended during encoding.")
    }
    guard data.count <= DocumentIO.maximumDownloadBytes else {
      throw AutomationFailure(
        status: 413, message: "Encoded document exceeds the 128 MiB download limit.")
    }
    return .init(status: 200, contentType: format.mediaType, body: data)
  }
}
