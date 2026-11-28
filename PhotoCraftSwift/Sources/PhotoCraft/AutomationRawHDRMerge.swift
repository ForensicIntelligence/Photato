import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RawHDRMergeAPI {
  static let name = "raw.mergeHDR"
  static let definition = AutomationCommand.Definition(name: name, parameters: [
    "layerIDs": "RAW Smart Object layer UUIDs in bracket order",
    "align": "Align bracketed exposures",
    "autoSettings": "Embed an automatic exposure adjustment",
    "deghost": "Deghost amount",
  ], description: "Merge selected RAW exposure brackets and directly download an editable linear HDR DNG.",
    optionalParameters: ["align", "autoSettings", "deghost"])

  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "align", "autoSettings": ["type": "boolean", "default": true]
    case "deghost": ["type": "string", "enum": RawHDRMergeSettings.Deghost.allCases.map(\.rawValue), "default": "off"]
    default:
      ["type": "array", "minItems": RawHDRMerge.sourceCount.lowerBound, "maxItems": RawHDRMerge.sourceCount.upperBound,
        "uniqueItems": true, "items": VariablesAPI.uuid]
    }
  }

  struct Request: Sendable {
    let ids: [UUID]
    var settings = RawHDRMergeSettings()

    init(_ command: AutomationCommand) throws {
      guard case .array(let values) = command.parameters["layerIDs"], RawHDRMerge.sourceCount.contains(values.count) else {
        throw AutomationFailure(status: 400, message: "Provide two to sixteen RAW exposure layer IDs.")
      }
      ids = try values.map { value in
        guard case .string(let uuid) = value, let id = UUID(uuidString: uuid) else {
          throw AutomationFailure(status: 400, message: "Each RAW exposure needs a valid layer UUID.")
        }
        return id
      }
      guard Set(ids).count == ids.count else {
        throw AutomationFailure(status: 400, message: "Choose distinct RAW exposures.")
      }
      if let value = command.parameters["align"] {
        guard case .bool(let align) = value else { throw AutomationFailure(status: 400, message: "Align must be a boolean.") }
        settings.align = align
      }
      if let value = command.parameters["autoSettings"] {
        guard case .bool(let auto) = value else { throw AutomationFailure(status: 400, message: "Auto Settings must be a boolean.") }
        settings.autoSettings = auto
      }
      if let value = command.parameters["deghost"] {
        guard case .string(let name) = value, let deghost = RawHDRMergeSettings.Deghost(rawValue: name) else {
          throw AutomationFailure(status: 400, message: "Deghost must be off, low, medium or high.")
        }
        settings.deghost = deghost
      }
    }

    func dng(_ document: CraftDocument) throws -> Data {
      var sources = Set<UUID>()
      let brackets = try ids.map { id -> RawHDRMerge.Source in
        guard let object = document.layers.first(where: { $0.id == id })?.smartObject,
          let settings = object.rawDevelopment else {
          throw AutomationFailure(status: 422, message: "Select embedded Camera Raw exposure layers.")
        }
        guard sources.insert(object.sourceID).inserted else {
          throw AutomationFailure(status: 422, message: "Choose different original exposures instead of instances of the same source.")
        }
        return .init(bytes: object.sourceBytes, fileName: object.fileName, settings: settings)
      }
      let sourcesForMerge = try RawHDRMerge.prepareSources(brackets)
      let name = ImageProcessor.safeBase((brackets[0].fileName as NSString).deletingPathExtension) + "-HDR"
      let result = try RawHDRMerge.prepare(sourcesForMerge, options: settings, name: name, makePreview: false)
      return try FileBackedSource.writing(maximumBytes: ImageAssetExport.maximumBytes) { url in
        try result.write(to: url)
      }.data
    }
  }
}

@MainActor extension AutomationService {
  func mergeRawHDR(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else {
      throw AutomationFailure(status: 403, message: "Enable document transfers before downloading an HDR DNG.")
    }
    guard !documentTransferBusy else {
      throw AutomationFailure(status: 429, message: "A document transfer is already in progress.")
    }
    let request = try RawHDRMergeAPI.Request(command)
    let source = document.store.document
    let expectedToken = token, transfer = documentTransferGeneration, service = generation
    documentTransferBusy = true
    let worker = Task.detached(priority: .utility) { try request.dng(source) }
    rawHDRMergeTask = worker
    defer {
      rawHDRMergeTask = nil
      documentTransferBusy = false
    }
    let dng = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transfer,
      generation == service, shares.contains(where: { $0.id == shareID && $0.document === document }),
      document.closeWorkflowID == nil, document.store.document == source, revision(document.store) == command.revision else {
      throw AutomationFailure(status: 409, message: "The HDR download was revoked or the source changed.")
    }
    return AutomationResponse(status: 200, contentType: "image/x-adobe-dng", body: dng,
      headers: ["Content-Disposition": "attachment; filename=\"Camera-Raw-HDR.dng\""])
  }
}
