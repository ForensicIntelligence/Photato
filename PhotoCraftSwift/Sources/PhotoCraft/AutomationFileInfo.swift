import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum FileInfoAPI {
  static func schema(_ key: String) -> [String: Any] {
    if key == "copyrightStatus" { return ["type": "string", "enum": FileInformation.CopyrightStatus.allCases.map(\.rawValue)] }
    if key == "keywords" { return ["type": "array", "maxItems": FileInformation.maximumKeywords, "items": ["type": "string", "maxLength": FileInformation.maximumTextBytes]] }
    return ["type": "string", "maxLength": FileInformation.maximumTextBytes]
  }
  static var stateSchema: [String: Any] {
    ["type": "object", "properties": ["available": ["type": "boolean"], "workspaceOpen": ["type": "boolean"],
      "fields": ["type": "object", "additionalProperties": false, "properties": Dictionary(uniqueKeysWithValues: FileInformation.fields.map { ($0, schema($0)) }), "required": FileInformation.fields], "error": ["type": "string"]], "required": ["available", "workspaceOpen"], "additionalProperties": false]
  }
  static var capabilities: [String: Any] {
    ["command": "file.info", "fields": FileInformation.fields, "read": "No parameters reads without history; fields patch only named values.",
      "history": "Desktop and API share File Info history; no-op values preserve the raw packet and history.",
      "maximumTextUTF8Bytes": FileInformation.maximumTextBytes, "maximumKeywords": FileInformation.maximumKeywords,
      "maximumPacketBytes": FileInfoMetadata.maximumPacketBytes, "authors": "Semicolon-separated ordered author names; commas remain part of a name.",
      "sourceImport": "Original PhotoCraft XMP, EXIF blobs, image resources and opaque global-block payloads persist in native documents. Opaque source globals are provenance, not executable rendering data. Supported output metadata follows existing format regeneration/stale-resource rules.",
      "interchange": "XMP plus descriptive TIFF/IPTC properties where supported; preserves unrelated XMP namespaces/locales and camera properties. Native archive version unchanged.",
      "remaining": ["Full Photoshop File Info panels, templates and metadata schemas", "Exact Adobe/Rust packet serialization", "Opaque source globals/EXIF interpretation and full export fidelity", "Live Photoshop and supported-platform qualification", "Semantic File Info Actions"],
      "adobe": "No dedicated File Info endpoint in the pinned published contract; metadata actionJSON descriptors remain unsupported. No Adobe route is invented."]
  }
  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    do { return ["available": true, "workspaceOpen": store.fileInfoDraft != nil, "fields": BrushAPI.json(try FileInfoMetadata.read(store.document))] }
    catch { return ["available": false, "workspaceOpen": store.fileInfoDraft != nil, "error": error.localizedDescription] }
  }
}

extension AutomationCommand {
  func fileInfo(_ original: CraftDocument) throws -> (FileInformation, Set<String>) {
    var info = try FileInfoMetadata.read(original)
    for (key, value) in parameters {
      if key == "keywords" {
        guard case .array(let items) = value, items.count <= FileInformation.maximumKeywords else { throw AutomationFailure(status: 400, message: "Keywords must be a string array.") }
        info.keywords = try items.map { value in guard case .string(let text) = value else { throw AutomationFailure(status: 400, message: "Keywords must be strings.") }; return text }
        continue
      }
      guard case .string(let text) = value else { throw AutomationFailure(status: 400, message: "File Info values must be strings.") }
      switch key {
      case "title": info.title = text
      case "author": info.author = text
      case "authorTitle": info.authorTitle = text
      case "description": info.description = text
      case "copyright": info.copyright = text
      case "copyrightUrl": info.copyrightUrl = text
      case "copyrightStatus": guard let status = FileInformation.CopyrightStatus(rawValue: text) else { throw AutomationFailure(status: 400, message: "Invalid copyright status.") }; info.copyrightStatus = status
      default: throw AutomationFailure(status: 400, message: "Unknown File Info field.")
      }
    }
    do { try info.validate() } catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    return (info, Set(parameters.keys))
  }
}
