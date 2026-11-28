import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RawBatchExport {
  static let formats: [DocumentIO.Format] = [.tiff, .jpeg, .png, .psd]

  static func name(_ name: String, format: DocumentIO.Format) -> String {
    ImageProcessor.safeBase(name) + "." + (format == .jpeg ? "jpg" : format.rawValue)
  }

  static func prepare(_ document: CraftDocument, format: DocumentIO.Format,
    workflow: RawWorkflowOutput, options: RasterEncodingOptions) throws -> PreparedDocumentOutput {
    let developed = try RawOpenMode.copy.output(from: document, workflow: workflow)
    return try DocumentIO.prepareOutput(developed, format: format, persistence: false, options: options)
  }
}

enum RawBatchExportAPI {
  static let name = "raw.exportBatch"
  static let maximumLayers = RawSynchronizationAPI.maximumTargets
  static let maximumBytes = ImageAssetExport.maximumBytes
  static let definition = AutomationCommand.Definition(name: name, parameters: [
    "layerIDs": "RAW Smart Object layer UUIDs",
    "format": "TIFF, JPEG, PNG or PSD",
    "workflow": "Camera Raw output settings",
    "options": "File encoding options",
  ], description: "Develop selected RAW originals and download separate files as ZIP without editing the document.",
    optionalParameters: ["workflow", "options"])

  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "format": BrushAPI.enumeration(RawBatchExport.formats.map(\.rawValue))
    case "workflow": RawWorkflowOutput.apiSchema
    case "options": DocumentEncodingOptions.schema
    default: ["type": "array", "minItems": 1, "maxItems": maximumLayers, "uniqueItems": true,
      "items": VariablesAPI.uuid]
    }
  }

  struct Request: Sendable {
    let ids: [UUID]
    let format: DocumentIO.Format
    let workflow: RawWorkflowOutput
    let options: RasterEncodingOptions

    init(_ command: AutomationCommand) throws {
      guard let format = DocumentIO.Format(rawValue: try command.string("format")),
        RawBatchExport.formats.contains(format),
        case .array(let array) = command.parameters["layerIDs"], (1...maximumLayers).contains(array.count) else {
        throw AutomationFailure(status: 400, message: "Provide RAW layers and a supported export format.")
      }
      self.format = format
      ids = try array.map { value in
        guard case .string(let string) = value, let id = UUID(uuidString: string) else {
          throw AutomationFailure(status: 400, message: "Each RAW layer identifier must be a UUID.")
        }
        return id
      }
      guard Set(ids).count == ids.count else {
        throw AutomationFailure(status: 400, message: "RAW layer identifiers must be unique.")
      }
      workflow = try command.parameters["workflow"].map { try RawWorkflowOutput.apiValue($0.jsonValue) } ?? .init()
      options = try DocumentEncodingOptions.parse(command.parameters["options"], format: format) ?? .init()
    }

    func archive(_ document: CraftDocument) throws -> Data {
      let objects = try ids.map { id in
        guard let object = document.layers.first(where: { $0.id == id })?.smartObject,
          let settings = object.rawDevelopment else {
          throw AutomationFailure(status: 422, message: "Choose embedded Camera Raw layers.")
        }
        return (object, settings)
      }
      var files: [StoredZIP.File] = []
      var names = Set<String>()
      var bytes = 0
      for (object, settings) in objects {
        try Task.checkCancellation()
        let input = try RawSourceIO.open(object.sourceBytes, fileName: object.fileName, settings: settings, depth: document.depth)
        let output = try RawBatchExport.prepare(input, format: format, workflow: workflow, options: options)
        guard output.count <= maximumBytes - bytes else {
          throw AutomationFailure(status: 413, message: "The RAW batch exceeds the download limit.")
        }
        let data: Data
        switch output {
        case .data(let encoded): data = encoded
        case .file(let file): data = try Data(contentsOf: file.url, options: .alwaysMapped)
        }
        bytes += data.count
        let original = RawBatchExport.name(object.fileName, format: format)
        let path = URL(fileURLWithPath: original), base = path.deletingPathExtension().lastPathComponent
        var name = original, index = 0
        while !names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted {
          index += 1
          name = "\(base)_\(index).\(path.pathExtension)"
        }
        files.append(.init(name: name, data: data))
      }
      return try StoredZIP.encode(files, maximumBytes: maximumBytes)
    }
  }
}

@MainActor extension AutomationService {
  func exportRawBatch(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else {
      throw AutomationFailure(status: 403, message: "Enable document transfers before exporting RAW images.")
    }
    guard !documentTransferBusy else {
      throw AutomationFailure(status: 429, message: "A document transfer is already in progress.")
    }
    let request = try RawBatchExportAPI.Request(command)
    let source = document.store.document
    let authorization = token, generation = documentTransferGeneration
    documentTransferBusy = true
    defer { documentTransferBusy = false }
    let worker = Task.detached(priority: .utility) { try request.archive(source) }
    let archive = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard isRunning, token == authorization, documentTransfersEnabled, documentTransferGeneration == generation,
      shares.contains(where: { $0.id == shareID && $0.document === document }), document.closeWorkflowID == nil,
      document.store.document == source, revision(document.store) == command.revision else {
      throw AutomationFailure(status: 409, message: "The RAW export was revoked or its source changed.")
    }
    return .init(status: 200, contentType: "application/zip", body: archive)
  }
}
