import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension AutomationCommand {
  static func batchSchema(_ key: String) -> [String: Any] {
    switch key {
    case "clipboardPayloadBase64": return ClipboardAPI.schema("payloadBase64")
    case "sources":
      var value = PhotomergeSettings.sourcesSchema; value["minItems"] = 1; value["maxItems"] = 8; return value
    case "format": return ["type": "string", "enum": DocumentIO.Format.allCases.map(\.rawValue)]
    case "options": return DocumentEncodingOptions.schema
    case "naming": return BatchNamingAPI.schema
    case "suffix": return ["type": "string", "maxLength": 64]
    case "stopOnError": return ["type": "boolean", "default": false]
    default: return ["type": "string", "format": "uuid"]
    }
  }
}
extension AutomationService {
  var actionBatchState: [String: Any] {
    ["active": actionBatchTask != nil, "operationID": actionBatchOperationID?.uuidString as Any? ?? NSNull(), "results": actionBatchResults.map(\.json), "naming":actionBatchNaming.map(BatchNamingAPI.object) as Any? ?? NSNull(),"namingCapabilities":BatchNamingAPI.capabilities]
  }
  func executeActionBatch(_ command: AutomationCommand, anchorID: UUID) async throws -> AutomationResponse {
    guard documentSavesEnabled, let destination = saveDirectoryURL else { throw AutomationFailure(status: 403, message: "Enable local saving and choose an API output folder first.") }
    guard actionBatchTask == nil else { throw AutomationFailure(status: 409, message: "A batch is already running.") }
    guard case .array(let values) = command.parameters["sources"], (1...8).contains(values.count) else { throw AutomationFailure(status: 400, message: "Choose one to eight shared source documents.") }
    let inputs = try values.map { value -> (UUID, String, CraftNSDocument) in
      guard case .object(let fields) = value, Set(fields.keys) == ["id", "revision"], case .string(let raw) = fields["id"], let id = UUID(uuidString: raw), case .string(let revision) = fields["revision"], let document = shares.first(where: { $0.id == id })?.document else { throw AutomationFailure(status: 400, message: "Each source requires a shared id and current revision.") }
      try preflight(document)
      guard self.revision(document.store) == revision else { throw AutomationFailure(status: 409, message: "A batch source revision is stale.") }
      return (id, revision, document)
    }
    let ids = Set(inputs.map { $0.0 })
    guard ids.count == inputs.count, ids.contains(anchorID) else { throw AutomationFailure(status: 400, message: "Include the command target exactly once; no duplicate sources.") }
    let anchor = inputs.first { $0.0 == anchorID }!.2
    guard anchor.store.session.actionRecording == nil else { throw AutomationFailure(status: 409, message: "Stop recording before running Batch.") }
    let action = try anchor.store.actions.action(command.actionUUID("actionID"))
    guard let format = DocumentIO.Format(rawValue: try command.string("format")) else { throw AutomationFailure(status: 400, message: "Unknown batch format.") }
    let options = try DocumentEncodingOptions.parse(command.parameters["options"], format: format) ?? .init()
    let suffix: String
    if let value = command.parameters["suffix"] { guard case .string(let text) = value else { throw AutomationFailure(status: 400, message: "suffix must be text.") }; suffix = text } else { suffix = "-processed" }
    let naming:BatchFileNaming?
    if let raw=command.parameters["naming"] {
      guard command.parameters["suffix"]==nil else{throw AutomationFailure(status:400,message:"Choose naming fields or the legacy suffix, not both.")}
      naming=try BatchNamingAPI.parse(raw)
      do{_ = try naming!.plan(sources:inputs.map{$0.2.store.document.name},format:format)}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    }else{naming=nil;_ = try ActionBatch.outputName("test",index:0,suffix:suffix,format:format)}
    var stop = false
    if let value = command.parameters["stopOnError"] { guard case .bool(let flag) = value else { throw AutomationFailure(status: 400, message: "stopOnError must be boolean.") }; stop = flag }
    let snapshots = inputs.map { $0.2.store.document }
    let clipboardBytes = try command.actionClipboardBytes()
    let token = token, saveGeneration = documentSaveGeneration
    let operationID = UUID(); actionBatchNaming=naming; actionBatchOperationID = operationID; actionBatchSourceIDs = ids; actionBatchResults = []
    let task = Task { @MainActor in
      let decoder = Task.detached(priority: .userInitiated) { try clipboardBytes.map(ClipboardAPI.decode) }
      let clipboard = try await withTaskCancellationHandler { try await decoder.value } onCancel: { decoder.cancel() }
      return try await ActionBatch.run(sources: snapshots.map { ActionBatchSource(document: $0) }, action: action, destination: destination, format: format, options: options, suffix: suffix, naming:naming, stopOnError: stop, clipboard: clipboard, validateClipboard: ClipboardAPI.validate, validateOutput: Self.checkLimits, validatePublication: {
        guard self.isRunning, self.token == token, self.documentSavesEnabled, self.documentSaveGeneration == saveGeneration else { throw AutomationFailure(status: 409, message: "Batch saving was revoked or its output folder changed.") }
        for (i, input) in inputs.enumerated() {
          guard self.shares.contains(where: { $0.id == input.0 && $0.document === input.2 }), self.revision(input.2.store) == input.1, input.2.store.document == snapshots[i] else { throw AutomationFailure(status: 409, message: "Batch source changed or sharing ended.") }
        }
      }, progress: { self.actionBatchResults = $0 })
    }
    actionBatchTask = task
    defer { actionBatchTask = nil; actionBatchOperationID = nil; actionBatchSourceIDs = []; actionBatchNaming=nil }
    let results = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    return .json(["operationID": operationID.uuidString, "results": results.map(\.json), "completed": results.filter { $0.output != nil }.count, "cancelled": results.contains(where: \.cancelled)])
  }
}
