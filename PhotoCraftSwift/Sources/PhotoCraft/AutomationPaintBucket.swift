import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PaintBucketAPI {
  static let name = "paint.bucket"
  private static let settings = ["mode", "opacity", "tolerance", "contiguous", "antiAlias", "sampleAllLayers", "source", "placement"]
  private static let fillArguments = ["x", "y", "layerID", "target", "color", "patternID"]
  private static let sources = ["foreground", "pattern"]
  private static let targets = ["content", "layerMask"]

  static var definition: AutomationCommand.Definition {
    .init(name: name, parameters: [
      "operation": "configure or fill", "mode": "Paint Bucket mode including Clear",
      "opacity": "0 through 1", "tolerance": "Integer 0 through 255",
      "contiguous": "Connected color region only", "antiAlias": "Soften region edges",
      "sampleAllLayers": "Sample the visible composite",
      "source": "foreground or pattern", "placement": "Optional pattern placement",
      "x": "Fill seed x", "y": "Fill seed y", "layerID": "Optional target layer UUID",
      "target": "content or layerMask", "color": "Optional foreground RGBA",
      "patternID": "Optional document or library pattern ID",
    ], description: "Configure Paint Bucket or fill a sampled region through the native prepared transaction.",
    optionalParameters: Set(settings + fillArguments))
  }

  private static var placementSchema: [String: Any] {
    BrushAPI.object(["scale": BrushAPI.number(1, 1000), "angle": BrushAPI.number(-360_000, 360_000),
      "phaseX": BrushAPI.number(-1_000_000, 1_000_000), "phaseY": BrushAPI.number(-1_000_000, 1_000_000)])
  }

  private static var toolFields: [String: [String: Any]] {
    ["mode": BrushAPI.enumeration(BucketOptions.modeNames), "opacity": BrushAPI.number(),
      "tolerance": BrushAPI.number(0, 255, integer: true), "contiguous": BrushAPI.flag,
      "antiAlias": BrushAPI.flag, "sampleAllLayers": BrushAPI.flag, "source": BrushAPI.enumeration(sources),
      "placement": placementSchema]
  }

  static var parameterSchema: [String: Any] {
    let commandSettings = toolFields
    var configure = commandSettings
    configure["operation"] = ["const": "configure"]
    var configSchema = BrushAPI.object(configure, required: ["operation"])
    configSchema["minProperties"] = 2
    var fill = commandSettings
    fill["operation"] = ["const": "fill"]
    let coordinate: [String: Any] = ["type": "number", "minimum": 0, "exclusiveMaximum": Surface.maxDimension]
    fill["x"] = coordinate; fill["y"] = coordinate
    fill["layerID"] = VariablesAPI.uuid
    fill["target"] = BrushAPI.enumeration(targets)
    fill["color"] = BrushAPI.color
    fill["patternID"] = ["type": "string", "minLength": 1, "maxLength": 255]
    return ["oneOf": [configSchema, BrushAPI.object(fill, required: ["operation", "x", "y"])]]
  }

  static var stateSchema: [String: Any] {
    BrushAPI.object([
      "available": BrushAPI.flag, "clearAvailable": BrushAPI.flag,
      "target": BrushAPI.enumeration(targets), "settings": BrushAPI.object(toolFields, required: settings),
      "selectedPatternID": ["type": ["string", "null"]],
    ], required: ["available", "clearAvailable", "target", "settings", "selectedPatternID"])
  }

  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    let value = store.bucketOptions
    return ["available": store.canUseBucket(clearsAlpha: value.clearsAlpha)
        && (!store.bucketUsesPattern || (!store.patterns.busy && store.patterns.selected != nil)),
      "clearAvailable": store.canUseBucket(clearsAlpha: true),
      "target": store.editingMask ? "layerMask" : "content",
      "selectedPatternID": store.patterns.selected?.id as Any? ?? NSNull(),
      "settings": ["mode": value.modeName, "opacity": value.opacity, "tolerance": value.match.tolerance,
        "contiguous": value.match.contiguous, "antiAlias": value.match.antiAlias,
        "sampleAllLayers": value.sampleAllLayers, "source": store.bucketUsesPattern ? "pattern" : "foreground",
        "placement": BrushAPI.json(store.bucketPatternPlacement)]]
  }

  static var capabilities: [String: Any] {
    ["command": name, "parameterSchema": parameterSchema, "stateSchema": stateSchema,
      "resultSchema": BrushAPI.object(["revision": ["type": "string"], "paintBucket": stateSchema],
        required: ["revision", "paintBucket"]),
      "clear": "Reduces destination alpha using fill opacity, region and selection coverage. Pattern fill also weights that removal by pattern alpha. Requires unlocked 8- or 16-bit pixel transparency.",
      "history": "Configure has no document history. A successful fill is one native undoable document edit. Fill overrides are request-local.",
      "adobe": "The pinned Photoshop v2 contract has no dedicated Paint Bucket endpoint."]
  }

  static func validate(_ parameters: [String: AutomationValue]) throws {
    _ = try BrushAPI.merge(.object(parameters), schema: parameterSchema, path: "paint.bucket")
    if case .string("configure")? = parameters["operation"], parameters.count == 1 {
      throw AutomationFailure(status: 400, message: "Configure requires a nonempty Paint Bucket settings patch.")
    }
  }
}

@MainActor extension AutomationService {
  func executePaintBucket(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    let store = document.store, operation = try command.string("operation")
    var options = store.bucketOptions
    if command.parameters["mode"] != nil {
      guard options.chooseMode(try command.string("mode")) else {
        throw AutomationFailure(status: 400, message: "Invalid Paint Bucket mode.")
      }
    }
    if command.parameters["opacity"] != nil { options.opacity = Float(try command.number("opacity", range: 0...1)) }
    if command.parameters["tolerance"] != nil { options.match.tolerance = try command.integer("tolerance", range: 0...255) }
    options.match.contiguous = try command.adjustmentBrushFlag("contiguous", options.match.contiguous)
    options.match.antiAlias = try command.adjustmentBrushFlag("antiAlias", options.match.antiAlias)
    options.sampleAllLayers = try command.adjustmentBrushFlag("sampleAllLayers", options.sampleAllLayers)
    try options.validate()

    var placement = store.bucketPatternPlacement
    if case .object(let fields)? = command.parameters["placement"] {
      if case .number(let v)? = fields["scale"] { placement.scale = Float(v) }
      if case .number(let v)? = fields["angle"] { placement.angle = Float(v) }
      if case .number(let v)? = fields["phaseX"] { placement.phaseX = Float(v) }
      if case .number(let v)? = fields["phaseY"] { placement.phaseY = Float(v) }
      try placement.validate()
    }
    let source = try command.parameters["source"].map { _ in try command.string("source") }

    if operation == "configure" {
      try Task.checkCancellation()
      store.bucketOptions = options
      if let source { store.bucketUsesPattern = source == "pattern" }
      store.bucketPatternPlacement = placement
    } else {
      guard store.canUseBucketContext else {
        throw AutomationFailure(status: 422, message: "Paint Bucket requires an idle pixel layer or its pixel mask.")
      }
      let rawID = try command.parameters["layerID"].map { _ in try command.actionUUID("layerID") }
      guard let id = rawID ?? store.document.activeLayerID else {
        throw AutomationFailure(status: 422, message: "Choose a Paint Bucket target.")
      }
      let target = try command.parameters["target"].map { _ in try command.string("target") }
      let mask = target.map { $0 == "layerMask" } ?? store.editingMask
      guard !store.editingMask || mask else {
        throw AutomationFailure(status: 422, message: "Close mask editing before filling layer pixels.")
      }
      try store.document.validateBucketTarget(layerID: id, mask: mask, clearsAlpha: options.clearsAlpha)
      let point = PathPoint(try command.number("x", range: 0...Double(Surface.maxDimension)),
        try command.number("y", range: 0...Double(Surface.maxDimension)))
      guard point.x < Double(store.document.width), point.y < Double(store.document.height) else {
        throw AutomationFailure(status: 400, message: "Sample inside the document.")
      }

      let patternID = try command.parameters["patternID"].map { _ in try command.string("patternID") }
      let explicitColor = command.parameters["color"]
      let usesPattern = source.map { $0 == "pattern" } ?? (patternID != nil || (explicitColor == nil && store.bucketUsesPattern))
      let pattern: RasterPattern?
      var color = store.brush.color
      if usesPattern {
        guard explicitColor == nil else { throw AutomationFailure(status: 400, message: "Choose foreground color or pattern.") }
        guard !store.patterns.busy else { throw AutomationFailure(status: 409, message: "Wait for patterns to finish loading.") }
        let resource = patternID.map { id in store.pixelFillPatterns.first(where: { $0.id == id }) }
          ?? store.patterns.selected
        guard let captured = resource else {
          throw AutomationFailure(status: 404, message: "Paint Bucket pattern not found.")
        }
        pattern = captured
      } else {
        guard patternID == nil, command.parameters["placement"] == nil else {
          throw AutomationFailure(status: 400, message: "Pattern options require the pattern source.")
        }
        pattern = nil
        if case .object(let rgba)? = explicitColor,
          case .number(let r)? = rgba["r"], case .number(let g)? = rgba["g"],
          case .number(let b)? = rgba["b"], case .number(let a)? = rgba["a"] {
          color = Pixel(Float(r), Float(g), Float(b), Float(a))
        }
      }
      let request = PaintBucketRequest(layerID: id, point: point, color: color, options: options,
        mask: mask, pattern: pattern, placement: placement)
      try await executePreparedOperation(document: document, shareID: shareID, revision: command.revision,
        allowAuxiliary: mask) { try request.command(in: $0) }
    }
    return .json(["revision": revision(store), "paintBucket": PaintBucketAPI.state(store)])
  }
}
