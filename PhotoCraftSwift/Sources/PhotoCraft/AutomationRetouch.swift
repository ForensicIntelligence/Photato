import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RetouchStrokeAPI {
  static let name = "retouch.stroke"
  static var brush: [String: Any] { BrushAPI.object([
    "size": BrushAPI.number(1, 2048), "hardness": BrushAPI.number(), "opacity": BrushAPI.number(),
    "flow": BrushAPI.number(), "spacing": BrushAPI.number(0.01, 10), "pressureSize": BrushAPI.flag,
    "pressureOpacity": BrushAPI.flag, "mode": BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue))]) }
  static var mapping: [String: Any] {
    let point = BrushAPI.object(["x": BrushAPI.number(-1_000_000, 1_000_000),
      "y": BrushAPI.number(-1_000_000, 1_000_000)], required: ["x", "y"])
    return BrushAPI.object(["source": point, "anchor": point, "width": BrushAPI.number(1, 1000),
      "height": BrushAPI.number(1, 1000), "rotation": BrushAPI.number(-360_000, 360_000),
      "flipHorizontal": BrushAPI.flag, "flipVertical": BrushAPI.flag], required: ["source"])
  }
  static var toning: [String: Any] { BrushAPI.object([
    "range": BrushAPI.enumeration(RetouchToneRange.allCases.map(\.rawValue)), "exposure": BrushAPI.number(),
    "protectTones": BrushAPI.flag, "spongeMode": BrushAPI.enumeration(SpongeMode.allCases.map(\.rawValue)),
    "vibrance": BrushAPI.flag]) }
  static var focus: [String: Any] { BrushAPI.object(["strength": BrushAPI.number(),
    "protectDetail": BrushAPI.flag, "sampleAllLayers": BrushAPI.flag, "fingerPainting": BrushAPI.flag]) }
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "tool": return BrushAPI.enumeration(RecordedRetouchTool.allCases.map(\.rawValue))
    case "target": return BrushAPI.enumeration(["pixels", "layerMask"])
    case "layerID", "sourceLayerID": return ["type": "string", "format": "uuid"]
    case "points": return BrushAPI.schema("points")
    case "brush": return brush
    case "mapping": return mapping
    case "toning": return toning
    case "focus": return focus
    case "foreground": return BrushAPI.color
    case "spotType": return BrushAPI.enumeration(SpotHealingType.allCases.map(\.rawValue))
    case "sampling": return BrushAPI.enumeration(CloneSampling.allCases.map(\.rawValue))
    case "ignoreAdjustments": return BrushAPI.flag
    case "source": return BrushAPI.object(["id": ["type": "string", "format": "uuid"],
      "revision": ["type": "string", "minLength": 1, "maxLength": 256]], required: ["id", "revision"])
    default: return [:]
    }
  }
  static var capabilities: [String: Any] {
    ["commands": [name], "tools": RecordedRetouchTool.allCases.map(\.rawValue), "actionVersion": 21,
     "targets": ["pixels", "layerMask"], "maximumSamples": 4096,
     "settings": "Partial settings override the selected retouch tool's native defaults. Values use native units: opacity/flow/exposure/strength0–1, size in document pixels, source scaling in percent.",
     "sources": "Clone/Healing accept an explicit shared source id/revision and sourceLayerID. Other tools sample the target document. No source file paths or unshared documents are admitted. Sources are rechecked before atomic commit.",
     "actions": "Semantic settings, samples and portable layer/source references; playback resamples each current document. External source UUID is preferred, otherwise its unique document name must match an explicitly supplied/open source. No captured image buffers or ATN support.",
     "history": "One shared native transaction, with Undo/Redo and source/target busy, stale, cancellation and sharing checks.",
     "limits": "Existing native solve/storage budgets and API document/body limits apply. Native retouch kernels, full Photoshop preference parity and physical60fps remain unqualified.",
     "adobe": "No dedicated retouch stroke route in the pinned Photoshop v2 contract. Unqualified execute-actions descriptors remain unsupported."]
  }
  static func decode<T: Codable>(_ raw: AutomationValue?, schema: [String: Any], base: T) throws -> T {
    guard let raw else { return base }
    let merged = try BrushAPI.merge(raw, schema: schema, base: BrushAPI.json(base), path: "retouch")
    do { return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: merged)) }
    catch { throw AutomationFailure(status: 400, message: "Invalid retouch settings: \(error.localizedDescription)") }
  }
  @MainActor static func settings(_ tool: RecordedRetouchTool, store: EditorStore) -> RetouchSettings {
    switch tool {
    case .cloneStamp: store.cloneState.clone; case .healingBrush: store.cloneState.healing
    case .spotHealing: store.cloneState.spot; case .dodge: store.cloneState.dodge
    case .burn: store.cloneState.burn; case .sponge: store.cloneState.sponge
    case .blur: store.cloneState.blur; case .sharpen: store.cloneState.sharpen; case .smudge: store.cloneState.smudge
    }
  }
}

extension EditorStore {
  var retouchToolState: [String: Any] {
    Dictionary(uniqueKeysWithValues: RecordedRetouchTool.allCases.map { tool in
      let value = RetouchStrokeAPI.settings(tool, store: self)
      return (tool.rawValue, ["brush": BrushAPI.json(value.brush), "toning": BrushAPI.json(value.toning),
        "focus": BrushAPI.json(value.focus), "sampling": value.sampling.rawValue,
        "ignoreAdjustments": value.ignoreAdjustments, "aligned": value.aligned,
        "spotType": value.spotType.rawValue] as [String: Any])
    })
  }
}

extension AutomationCommand {
  @MainActor func retouchRequest(store: EditorStore, sourceDocument: CraftDocument?) throws -> RecordedRetouchStroke {
    // Validate required nested coordinates before applying tool-setting defaults.
    for (key, value) in parameters {
      _ = try BrushAPI.merge(value, schema: RetouchStrokeAPI.schema(key), path: key)
    }
    guard let tool = RecordedRetouchTool(rawValue: try string("tool")), let rawPoints = parameters["points"] else {
      throw AutomationFailure(status: 400, message: "Choose a retouch tool and stroke points.")
    }
    let original = store.document
    let id = try parameters["layerID"].map { _ in try actionUUID("layerID") } ?? original.activeLayerID
    guard let id, original.layers.contains(where: { $0.id == id }) else {
      throw AutomationFailure(status: 400, message: "Choose an existing retouch target layer.")
    }
    let target = try parameters["target"].map { _ in try string("target") } ?? "pixels"
    guard ["pixels", "layerMask"].contains(target) else { throw AutomationFailure(status: 400, message: "Unknown retouch target.") }
    let array = try BrushAPI.merge(rawPoints, schema: RetouchStrokeAPI.schema("points"), path: "points") as! [[String: Any]]
    let points = try array.map { input -> StrokePoint in
      var input = input; input["pressure"] = input["pressure"] ?? 1
      return try JSONDecoder().decode(StrokePoint.self, from: JSONSerialization.data(withJSONObject: input))
    }
    let settings = RetouchStrokeAPI.settings(tool, store: store)
    var r = RecordedRetouchStroke(tool: tool, target: .init(id, in: original), points: points)
    r.mask = target == "layerMask"
    r.brush = try RetouchStrokeAPI.decode(parameters["brush"], schema: RetouchStrokeAPI.brush, base: settings.brush)
    let sampled = tool == .cloneStamp || tool == .healingBrush
    var allowed: Set<String> = ["tool", "layerID", "target", "points", "brush"]
    if sampled { allowed.formUnion(["source", "sourceLayerID", "mapping", "sampling", "ignoreAdjustments"]) }
    if tool == .spotHealing { allowed.formUnion(["spotType", "sampling"]) }
    if tool.toning != nil { allowed.insert("toning") }
    if tool.focus != nil { allowed.formUnion(["focus", "foreground"]) }
    guard Set(parameters.keys).isSubset(of: allowed) else { throw AutomationFailure(status: 400, message: "Irrelevant retouch parameter for this tool.") }
    r.toning = try RetouchStrokeAPI.decode(parameters["toning"], schema: RetouchStrokeAPI.toning, base: settings.toning)
    r.focus = try RetouchStrokeAPI.decode(parameters["focus"], schema: RetouchStrokeAPI.focus, base: settings.focus)
    r.foreground = try RetouchStrokeAPI.decode(parameters["foreground"], schema: BrushAPI.color, base: store.brush.color)
    r.spotType = settings.spotType
    if let raw = parameters["spotType"] {
      _ = try BrushAPI.merge(raw, schema: RetouchStrokeAPI.schema("spotType"))
      r.spotType = SpotHealingType(rawValue: try string("spotType"))!
    }
    let sampling: CloneSampling
    if tool.focus != nil { sampling = r.focus.sampleAllLayers ? .all : .current }
    else if let raw = parameters["sampling"] {
      _ = try BrushAPI.merge(raw, schema: RetouchStrokeAPI.schema("sampling"))
      sampling = CloneSampling(rawValue: try string("sampling"))!
    } else { sampling = settings.sampling }
    var ignore = settings.ignoreAdjustments
    if let raw = parameters["ignoreAdjustments"] { guard case .bool(let value) = raw else { throw AutomationFailure(status: 400, message: "ignoreAdjustments must be boolean.") }; ignore = value }
    if tool.toning == nil {
      let source = sourceDocument ?? original
      let sourceID = try parameters["sourceLayerID"].map { _ in try actionUUID("sourceLayerID") } ?? (sampled && sourceDocument != nil ? source.activeLayerID : id)
      guard let sourceID, source.layers.contains(where: { $0.id == sourceID }) else { throw AutomationFailure(status: 400, message: "Choose an existing source layer.") }
      r.source = .init(layer: .init(sourceID, in: source, preferActive: sourceDocument == nil), sampling: sampling,
        ignoreAdjustments: sampled && ignore, mask: r.mask, convertToTarget: sampled,
        documentID: sourceDocument?.id, documentName: sourceDocument?.name)
      if tool == .healingBrush && sampling != .current && !r.mask {
        r.destination = .init(layer: r.target, sampling: sampling, ignoreAdjustments: ignore)
      }
    }
    if sampled {
      guard case .object(let fields) = parameters["mapping"], fields["source"] != nil else { throw AutomationFailure(status: 400, message: "Clone/Healing require mapping.source coordinates.") }
      let base = CloneMapping(source: .init(0, 0), anchor: .init(points[0].x, points[0].y))
      r.mapping = try RetouchStrokeAPI.decode(parameters["mapping"], schema: RetouchStrokeAPI.mapping, base: base)
    }
    do { try r.validate() } catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    return r
  }
}

extension AutomationService {
  func executeRetouchStroke(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws {
    var source: CraftNSDocument?, sourceID: UUID?, expected: String?
    if let raw = command.parameters["source"] {
      _ = try BrushAPI.merge(raw, schema: RetouchStrokeAPI.schema("source"), path: "source")
      guard case .object(let fields) = raw, case .string(let text) = fields["id"], let id = UUID(uuidString: text),
        id != shareID, case .string(let rev) = fields["revision"],
        let input = shares.first(where: { $0.id == id })?.document else { throw AutomationFailure(status: 400, message: "Choose a distinct shared source document.") }
      try preflight(input)
      guard revision(input.store) == rev else { throw AutomationFailure(status: 409, message: "Retouch source revision is stale.") }
      source = input; sourceID = id; expected = rev
    }
    let snapshot = source?.store.document
    let request = try command.retouchRequest(store: document.store, sourceDocument: snapshot)
    let capturedSource = source, capturedID = sourceID, capturedRevision = expected
    try await executePreparedOperation(document: document, shareID: shareID, revision: command.revision,
      validateCommit: { [self] in
        if let source = capturedSource {
          guard shares.contains(where: { $0.id == capturedID && $0.document === source }),
            revision(source.store) == capturedRevision, source.store.document == snapshot else {
            throw AutomationFailure(status: 409, message: "Retouch source changed or sharing ended.")
          }
          try preflight(source)
        }
      }) { original in try RetouchPreparation.command(request, in: original, sources: snapshot.map { [$0] } ?? []) }
  }
}
