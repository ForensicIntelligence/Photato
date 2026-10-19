import AppKit
import Foundation
import PhotoCraftCore

extension AutomationService {
  static var documentSavingCapabilities: [String: Any] {
    [
      "enablement":
        "Separate native Allow local document saving switch; off on every API session. Save As additionally requires a folder chosen in the native API window.",
      "save":
        "document.save writes only the shared document's associated local file. No path parameters. Rejects unsaved documents and externally modified files.",
      "saveAs":
        "document.saveAs accepts name, format and replace. The name is a filename inside the native-selected folder, never a path. replace must be true to overwrite an existing file; symbolic-link targets are refused.",
      "formats": DocumentIO.Format.allCases.map {
        ["format": $0.rawValue, "notice": $0.saveNotice]
      },
      "stateEffect":
        "Successful Save/Save As clears the modified flag, retains undo/redo, and returns the current file format/name. Save As changes the document's file association. Recovery autosaves remain native archives.",
      "availability":
        "The document's saveFormats reports formats that can retain the currently supported editable structure. The encoder can still reject unsupported content. Save a Copy/download remains available for explicit flattening.",
      "errors": [
        "400": "Invalid filename/format/replace", "403": "Saving disabled or no Save As folder",
        "409": "Busy/stale/revoked, destination exists/is open, source externally changed",
        "413": "API size limit", "422": "Unsupported document representation or I/O error",
      ],
      "adobe":
        "Adobe v2 has no open-desktop-document Save/Save As operation. Its existing resource outputs continue to use the shared codecs; no Adobe route is invented.",
    ]
  }
  func chooseSaveDirectory() {
    guard isRunning else { return }
    let panel = NSOpenPanel()
    panel.title = "Choose API Save As Folder"
    panel.prompt = "Allow Saving Here"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    setSaveDirectory(url)
  }
  func handleDocumentSave(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID)
    async throws -> Bool
  {
    guard command.name == "document.save" || command.name == "document.saveAs" else { return false }
    guard documentSavesEnabled else {
      throw AutomationFailure(
        status: 403, message: "Allow local document saving in the native API window first.")
    }
    let url: URL
    let format: DocumentIO.Format
    let operation: NSDocument.SaveOperationType
    var replace = true
    if command.name == "document.save" {
      guard let associated = document.fileURL else {
        throw AutomationFailure(
          status: 409,
          message: "Save this document first, or use Save As with a native-approved folder.")
      }
      url = associated
      format = document.persistenceFormat
      operation = .saveOperation
      let current = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      guard let current, document.fileModificationDate == current else {
        throw AutomationFailure(
          status: 409,
          message:
            "The saved file changed outside Photato. Resolve it in the desktop before saving.")
      }
    } else {
      guard let directory = saveDirectoryURL else {
        throw AutomationFailure(
          status: 403, message: "Choose an API Save As folder in the native API window.")
      }
      let name = try command.string("name")
      guard name.utf8.count <= 200, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"),
        !name.contains("\\"),
        let requested = DocumentIO.Format(rawValue: try command.string("format")),
        case .bool(let replacement) = command.parameters["replace"]
      else {
        throw AutomationFailure(
          status: 400,
          message:
            "Choose a filename without path components, a supported format and boolean replace.")
      }
      format = requested
      let filename =
        name.lowercased().hasSuffix("." + format.rawValue) ? name : name + "." + format.rawValue
      url = directory.appendingPathComponent(filename)
      operation = .saveAsOperation
      replace = replacement
    }
    let expectedToken = token
    let expectedGeneration = documentSaveGeneration
    let initial = try? url.resourceValues(forKeys: [
      .contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey,
    ])
    func validateDestination() throws {
      self.prune()
      guard self.isRunning, self.token == expectedToken, self.documentSavesEnabled,
        self.documentSaveGeneration == expectedGeneration,
        self.shares.contains(where: { $0.id == shareID }),
        command.revision == self.revision(document.store)
      else {
        throw AutomationFailure(
          status: 409, message: "Save was cancelled or local saving/sharing changed.")
      }
      let current = try? url.resourceValues(forKeys: [
        .contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey,
      ])
      guard current?.isSymbolicLink != true else {
        throw AutomationFailure(
          status: 409, message: "Symbolic-link save destinations are not allowed through the API.")
      }
      if operation == .saveAsOperation, !replace, FileManager.default.fileExists(atPath: url.path) {
        throw AutomationFailure(
          status: 409, message: "The destination exists. Set replace to true to replace it.")
      }
      guard current?.contentModificationDate == initial?.contentModificationDate,
        current?.fileSize == initial?.fileSize
      else {
        throw AutomationFailure(
          status: 409, message: "The destination changed while preparing the save.")
      }
      if let other = self.controller.document(for: url), other !== document {
        throw AutomationFailure(
          status: 409, message: "This destination is open in another document.")
      }
    }
    try validateDestination()
    let encoder = document.saveEncoder
    try await document.persistDocument(
      to: url, format: format, operation: operation, validate: validateDestination,
      encoder: { model, format in
        let data = try encoder(model, format)
        guard data.count <= DocumentIO.maximumDownloadBytes else {
          throw AutomationFailure(
            status: 413, message: "Saved output exceeds the 128 MiB API limit.")
        }
        return data
      })
    return true
  }
}
