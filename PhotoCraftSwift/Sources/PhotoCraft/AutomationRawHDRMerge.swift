import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RawHDRMergeAPI {
  static let name = "raw.mergeHDR"
  static let definition = AutomationCommand.Definition(name: name, parameters: [
    "layerIDs": "RAW Smart Object layer UUIDs in bracket order",
    "align": "Align bracketed exposures",
    "autoSettings": "Embed editable automatic tone and color settings without changing the merged RAW samples",
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
      ids = try RawPhotoMergeInput.layerIDs(command)
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
      let brackets = try RawPhotoMergeInput.sources(ids, in: document)
      let sourcesForMerge = try RawHDRMerge.prepareSources(brackets)
      let name = ImageProcessor.safeBase((brackets[0].fileName as NSString).deletingPathExtension) + "-HDR"
      let result = try RawHDRMerge.prepare(sourcesForMerge, options: settings, name: name, makePreview: false)
      return try FileBackedSource.writing(maximumBytes: SmartObject.maximumCameraRawSourceBytes) { url in
        try result.write(to: url)
      }.data
    }
  }
}

enum RawPhotoMergeInput {
  static func layerIDs(_ command: AutomationCommand, count: ClosedRange<Int> = RawHDRMerge.sourceCount) throws -> [UUID] {
    guard case .array(let values) = command.parameters["layerIDs"], count.contains(values.count) else {
      throw AutomationFailure(status: 400, message: "Provide \(count.lowerBound) to \(count.upperBound) RAW layer IDs.")
    }
    let ids = try values.map { value in
      guard case .string(let uuid) = value, let id = UUID(uuidString: uuid) else {
        throw AutomationFailure(status: 400, message: "Each RAW photo needs a valid layer UUID.")
      }
      return id
    }
    guard Set(ids).count == ids.count else { throw AutomationFailure(status: 400, message: "Choose distinct RAW photos.") }
    return ids
  }

  static func sources(_ ids: [UUID], in document: CraftDocument) throws -> [RawHDRMerge.Source] {
    var sourceIDs = Set<UUID>()
    return try ids.map { id in
      guard let object = document.layers.first(where: { $0.id == id })?.smartObject,
        let settings = object.rawDevelopment else {
        throw AutomationFailure(status: 422, message: "Select embedded Camera Raw layers.")
      }
      guard sourceIDs.insert(object.sourceID).inserted else {
        throw AutomationFailure(status: 422, message: "Choose different original photos instead of instances of the same source.")
      }
      return .init(bytes: object.sourceBytes, fileName: object.fileName, settings: settings)
    }
  }
}

enum RawPanoramaAPI {
  static let name = "raw.mergePanorama"
  static let definition = AutomationCommand.Definition(name: name, parameters: [
    "layerIDs": "Overlapping RAW Smart Object layer UUIDs in panorama order",
    "projection": "Spherical, cylindrical or perspective projection",
    "boundaryWarp": "Amount from 0 to 100 used to fit the boundary towards the canvas",
    "fillEdges": "Synthesize missing boundary pixels",
    "autoCrop": "Crop to the largest rectangle covered by the merged photos",
    "autoSettings": "Embed editable automatic tone and color settings",
  ], description: "Stitch overlapping RAW photos into a linear panorama DNG and download it.",
    optionalParameters: ["projection", "boundaryWarp", "fillEdges", "autoCrop", "autoSettings"])

  static let hdrName = "raw.mergeHDRPanorama"
  static let hdrDefinition = AutomationCommand.Definition(name: hdrName, parameters: [
    "layerIDs": "RAW Smart Object layer UUIDs in capture order, with each exposure bracket kept together",
    "bracketSize": "Optional number of exposures per position. Omit to detect the repeating capture pattern",
    "projection": "Spherical, cylindrical or perspective projection",
    "boundaryWarp": "Amount from 0 to 100 used to fit the boundary towards the canvas",
    "fillEdges": "Synthesize missing boundary pixels",
    "autoCrop": "Crop to the largest rectangle covered by the merged photos",
    "autoSettings": "Embed editable automatic tone and color settings",
  ], description: "Fuse each contiguous HDR exposure bracket, stitch the scene-linear results, and download an editable panorama DNG.",
    optionalParameters: ["bracketSize", "projection", "boundaryWarp", "fillEdges", "autoCrop", "autoSettings"])

  static func schema(_ key: String, hdr: Bool = false) -> [String: Any] {
    switch key {
    case "bracketSize": ["type": "integer", "minimum": RawHDRMerge.sourceCount.lowerBound, "maximum": RawHDRMerge.sourceCount.upperBound]
    case "layerIDs" where hdr:
      ["type": "array", "minItems": RawPanorama.hdrSourceCount.lowerBound, "maxItems": RawPanorama.hdrSourceCount.upperBound,
        "uniqueItems": true, "items": VariablesAPI.uuid]
    case "projection": ["type": "string", "enum": RawPanoramaSettings.Projection.allCases.map(\.rawValue), "default": "spherical"]
    case "boundaryWarp": ["type": "number", "minimum": 0, "maximum": 100, "default": 0]
    case "autoCrop", "autoSettings": ["type": "boolean", "default": true]
    case "fillEdges": ["type": "boolean", "default": false]
    default: RawHDRMergeAPI.schema("layerIDs")
    }
  }

  struct Request: Sendable {
    let ids: [UUID]
    let hdr: Bool
    var bracketSize: Int?
    var settings = RawPanoramaSettings()

    init(_ command: AutomationCommand) throws {
      hdr = command.name == RawPanoramaAPI.hdrName
      ids = try RawPhotoMergeInput.layerIDs(command, count: hdr ? RawPanorama.hdrSourceCount : RawPanorama.sourceCount)
      if hdr, let value = command.parameters["bracketSize"] {
        guard case .number(let number) = value, let size = Int(exactly: number), RawHDRMerge.sourceCount.contains(size) else {
          throw AutomationFailure(status: 400, message: "Bracket size must be an integer from 2 to 16.")
        }
        bracketSize = size
      }
      if let value = command.parameters["projection"] {
        guard case .string(let text) = value, let projection = RawPanoramaSettings.Projection(rawValue: text) else {
          throw AutomationFailure(status: 400, message: "Choose spherical, cylindrical or perspective projection.")
        }
        settings.projection = projection
      }
      if let value = command.parameters["boundaryWarp"] {
        guard case .number(let amount) = value, (0...100).contains(amount) else {
          throw AutomationFailure(status: 400, message: "Boundary Warp must be a number from 0 to 100.")
        }
        settings.boundaryWarp = amount
      }
      func flag(_ key: String, default fallback: Bool) throws -> Bool {
        guard let value = command.parameters[key] else { return fallback }
        guard case .bool(let setting) = value else { throw AutomationFailure(status: 400, message: "\(key) must be a boolean.") }
        return setting
      }
      settings.autoCrop = try flag("autoCrop", default: settings.autoCrop)
      settings.fillEdges = try flag("fillEdges", default: settings.fillEdges)
      settings.autoSettings = try flag("autoSettings", default: settings.autoSettings)
    }

    func dng(_ document: CraftDocument) throws -> Data {
      let inputs = try RawPhotoMergeInput.sources(ids, in: document)
      let name = ImageProcessor.safeBase((inputs[0].fileName as NSString).deletingPathExtension) + (hdr ? "-HDR-Pano" : "-Pano")
      let sources = try hdr ? RawPanorama.prepareHDRSources(inputs, bracketSize: bracketSize).photos
        : RawPanorama.prepareSources(inputs)
      let result = try RawPanorama.prepare(sources, options: settings, name: name, makePreview: false)
      return try FileBackedSource.writing(maximumBytes: ImageAssetExport.maximumBytes) { url in
        try result.write(to: url)
      }.data
    }
  }
}

@MainActor extension AutomationService {
  func mergeRawPhotos(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else {
      throw AutomationFailure(status: 403, message: "Enable document transfers before downloading a Camera Raw DNG.")
    }
    guard !documentTransferBusy else {
      throw AutomationFailure(status: 429, message: "A document transfer is already in progress.")
    }
    let hdrPanorama = command.name == RawPanoramaAPI.hdrName
    let panorama = hdrPanorama || command.name == RawPanoramaAPI.name
    let render: @Sendable (CraftDocument) throws -> Data
    if panorama {
      let request = try RawPanoramaAPI.Request(command)
      render = { try request.dng($0) }
    } else {
      let request = try RawHDRMergeAPI.Request(command)
      render = { try request.dng($0) }
    }
    let source = document.store.document
    let expectedToken = token, transfer = documentTransferGeneration, service = generation
    documentTransferBusy = true
    let worker = Task.detached(priority: .utility) { try render(source) }
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
      throw AutomationFailure(status: 409, message: "The Camera Raw download was revoked or the source changed.")
    }
    let filename = hdrPanorama ? "Camera-Raw-HDR-Panorama.dng"
      : (panorama ? "Camera-Raw-Panorama.dng" : "Camera-Raw-HDR.dng")
    return AutomationResponse(status: 200, contentType: "image/x-adobe-dng", body: dng,
      headers: ["Content-Disposition": "attachment; filename=\"\(filename)\""])
  }
}
