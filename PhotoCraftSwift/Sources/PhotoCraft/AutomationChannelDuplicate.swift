import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ChannelDuplicateAPI {
  static let name = "channel.duplicate"
  static let sourceKinds = ["alpha", "component", "plate", "duotone"]
  private static let uuid = ["type": "string", "format": "uuid"]
  private static var nameSchema: [String: Any] { ["type": "string", "minLength": 1, "maxLength": 256] }

  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "source": SelectionChannelSourceAPI.schema(for: sourceKinds)
    case "name": nameSchema
    case "invert": ["type": "boolean", "default": false]
    default: ["oneOf": [
      BrushAPI.object(["kind": ["const": "current"]], required: ["kind"]),
      BrushAPI.object(["kind": ["const": "open"], "shareID": uuid, "revision": ["type": "string", "minLength": 1, "maxLength": 256]],
        required: ["kind", "shareID", "revision"]),
      BrushAPI.object(["kind": ["const": "new"], "name": nameSchema], required: ["kind"])
    ]]
    }
  }

  static var capabilities: [String: Any] {
    ["command": name, "sourcesState": "selectionChannels.duplicateSources",
     "source": schema("source"), "destination": schema("destination"),
     "resultSchema": BrushAPI.object(["channelID": uuid, "document": ["type": "object"]], required: ["channelID", "document"]),
     "result": "200 current or existing destination state, or 201 new document state, with the new channel UUID.",
     "samples": "Duplicate one numeric component, saved alpha, spot or Duotone channel at full canvas size. Invert complements numeric samples. Existing destinations must match dimensions. Cross-depth output quantizes to destination depth without an ICC round trip. Spot copies retain ink settings within supported spot destinations.",
     "transaction": "Existing-document copies create one destination Undo step. Cross-document operations require both current share revisions. New creates an unsaved single-channel Multichannel document and requires document transfers. The original remains open.",
     "limits": "Indexed and Bitmap destinations cannot accept a copy. Creating a new printing-ink document requires 8 or 16 bits. Existing document, scratch, and API sharing limits apply.",
     "adobe": "The pinned Photoshop v2 HTTP contract has no Duplicate Channel route. This is a typed Photato desktop-automation command."]
  }
}

private enum ChannelDuplicateDestination {
  case current, open(UUID, String), new(String?)

  init(_ value: AutomationValue?) throws {
    guard case .object(let fields) = value, case .string(let kind) = fields["kind"] else {
      throw AutomationFailure(status: 400, message: "Choose a current, open or new destination.")
    }
    switch kind {
    case "current" where fields.count == 1:
      self = .current
    case "open" where fields.count == 3:
      guard case .string(let share) = fields["shareID"], let id = UUID(uuidString: share),
        case .string(let revision) = fields["revision"], !revision.isEmpty, revision.count <= 256 else {
        throw AutomationFailure(status: 400, message: "An open destination needs its shareID and current revision.")
      }
      self = .open(id, revision)
    case "new" where fields.count == 1:
      self = .new(nil)
    case "new" where fields.count == 2:
      guard case .string(let name) = fields["name"] else {
        throw AutomationFailure(status: 400, message: "Specify a name for the new document.")
      }
      self = .new(name)
    default:
      throw AutomationFailure(status: 400, message: "Destination fields do not match the destination kind.")
    }
  }
}

extension AutomationService {
  func duplicateChannel(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    guard let raw = command.parameters["source"] else { throw AutomationFailure(status: 400, message: "Specify one source channel.") }
    let source = try SelectionChannelSourceAPI.decode(raw)
    let original = document.store.document
    guard ChannelDuplication.sources(in: original).contains(source), document.store.canEditChannels else {
      throw AutomationFailure(status: 422, message: "Choose an available individual source channel.")
    }
    let name = try command.parameters["name"].map { _ in try command.string("name") } ?? source.title(in: original) + " copy"
    let invert = try command.pathFlag("invert", false)
    let destination = try ChannelDuplicateDestination(command.parameters["destination"])
    let target: CraftNSDocument, targetShare: Share, expectedRevision: String
    switch destination {
    case .current:
      (target, targetShare, expectedRevision) = (document, share, command.revision)
    case .open(let targetID, let revision):
      guard let lease = shares.first(where: { $0.id == targetID }), let file = lease.document else {
        throw AutomationFailure(status: 404, message: "The shared destination document was not found.")
      }
      try preflight(file)
      guard self.revision(file.store) == revision else {
        throw AutomationFailure(status: 409, message: "The destination revision is stale.")
      }
      (target, targetShare, expectedRevision) = (file, lease, revision)
    case .new(let documentName):
      let newName = documentName ?? controller.nextUntitledName
      return try await publishDerivedChannelDocument(document: document, share: share, revision: command.revision) {
        guard case .document(let created, let id) = try ChannelDuplication.prepare(source, in: $0, to: nil,
          name: name, documentName: newName, invert: invert) else { throw CraftError.invalid("Expected a new channel document.") }
        return (created, id)
      }
    }
    guard ChannelDuplication.accepts(target.store.document, source: source, in: original) else {
      throw AutomationFailure(status: 422, message: "The destination needs matching dimensions and space for the copied channel.")
    }
    let sourceSession = document.store.sessionGeneration
    let copiedID = try await executePreparedResult(document: target, shareID: targetShare.id, revision: expectedRevision,
      allowAuxiliary: true, validateCommit: {
        if target !== document {
          try self.preflight(document)
          guard self.shares.contains(where: { $0.id == share.id && $0.document === document }),
            self.revision(document.store) == command.revision, document.store.sessionGeneration == sourceSession,
            document.store.document == original else {
            throw AutomationFailure(status: 409, message: "The source changed, closed or sharing was revoked.")
          }
        }
      }) { snapshot in
        guard case .edit(let edit, let id) = try ChannelDuplication.prepare(source, in: original, to: snapshot,
          name: name, invert: invert) else { throw CraftError.invalid("Expected an existing channel destination.") }
        return (edit, id)
      }
    return .json(["channelID": copiedID.uuidString, "document": state(targetShare, document: target)])
  }
}
