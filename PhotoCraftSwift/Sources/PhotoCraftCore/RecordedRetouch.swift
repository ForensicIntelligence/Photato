import Foundation

/// Sampling provenance travels with an immutable preview image, but Actions save only this recipe.
public struct RetouchSampleOrigin: Equatable, Sendable {
  public let documentID: UUID
  public let documentName: String
  public let layerID: UUID
  public let layer: ActionLayerTarget
  public let sampling: CloneSampling
  public let ignoreAdjustments: Bool
  public let mask: Bool
  public var convertToTarget: Bool
  public init(document: CraftDocument, layerID: UUID, sampling: CloneSampling,
    ignoreAdjustments: Bool, mask: Bool, convertToTarget: Bool = false) {
    documentID = document.id; documentName = document.name; self.layerID = layerID
    layer = .init(layerID, in: document, preferActive: false)
    self.sampling = sampling; self.ignoreAdjustments = ignoreAdjustments; self.mask = mask
    self.convertToTarget = convertToTarget
  }
}

public struct RecordedRetouchSource: Codable, Sendable {
  public var layer: ActionLayerTarget
  /// Nil means the playback document. External IDs use a unique name fallback after reopening.
  public var documentID: UUID?
  public var documentName: String?
  public var sampling: CloneSampling
  public var ignoreAdjustments: Bool
  public var mask: Bool
  public var convertToTarget: Bool
  public init(layer: ActionLayerTarget, sampling: CloneSampling = .current,
    ignoreAdjustments: Bool = false, mask: Bool = false, convertToTarget: Bool = false,
    documentID: UUID? = nil, documentName: String? = nil) {
    self.layer = layer; self.sampling = sampling; self.ignoreAdjustments = ignoreAdjustments
    self.mask = mask; self.convertToTarget = convertToTarget
    self.documentID = documentID; self.documentName = documentName
  }
  public init?(sample: CloneSample, in document: CraftDocument) {
    guard let origin = sample.origin else { return nil }
    self.init(layer: origin.documentID == document.id ? .init(origin.layerID, in: document) : origin.layer,
      sampling: origin.sampling, ignoreAdjustments: origin.ignoreAdjustments, mask: origin.mask,
      convertToTarget: origin.convertToTarget,
      documentID: origin.documentID == document.id ? nil : origin.documentID,
      documentName: origin.documentID == document.id ? nil : origin.documentName)
  }
  public func validate() throws {
    guard (documentID == nil) == (documentName == nil),
      documentName.map({ !$0.isEmpty && $0.utf8.count <= 1024 }) ?? true else {
      throw CraftError.invalid("Invalid recorded retouch source document.")
    }
    if case .named(let name, let occurrence) = layer {
      guard !name.isEmpty, name.utf8.count <= 1024, (0..<100_000).contains(occurrence) else {
        throw CraftError.invalid("Invalid recorded retouch source layer.")
      }
    }
  }
}

public enum RecordedRetouchTool: String, Codable, CaseIterable, Sendable {
  case cloneStamp, healingBrush, spotHealing, dodge, burn, sponge, blur, sharpen, smudge
  public var toning: ToningTool? {
    switch self { case .dodge: .dodge; case .burn: .burn; case .sponge: .sponge; default: nil }
  }
  public var focus: FocusTool? {
    switch self { case .blur: .blur; case .sharpen: .sharpen; case .smudge: .smudge; default: nil }
  }
}

/// Original samples/settings and portable references; never a captured pixel buffer.
public struct RecordedRetouchStroke: Codable, Sendable {
  public var target: ActionLayerTarget
  public var tool: RecordedRetouchTool
  public var brush = CloneBrush()
  public var points: [StrokePoint]
  public var mask = false
  public var mapping = CloneMapping(source: .init(0, 0), anchor: .init(0, 0))
  public var source: RecordedRetouchSource?
  public var destination: RecordedRetouchSource?
  public var toning = ToningOptions()
  public var focus = FocusOptions()
  public var foreground = Pixel.black
  public var spotType = SpotHealingType.contentAware
  public init(tool: RecordedRetouchTool, target: ActionLayerTarget, points: [StrokePoint]) {
    self.tool = tool; self.target = target; self.points = points
  }
  public var needsExternalSources: Bool { source?.documentID != nil || destination?.documentID != nil }
  public func validate() throws {
    try brush.validate(); _ = try mapping.transform()
    let dummy = CloneSample(surface: try Surface(width: 1, height: 1))
    _ = try ClonePainter.prepare(.init(source: dummy, mapping: mapping, brush: brush, points: points, mask: mask))
    try source?.validate(); try destination?.validate()
    if case .named(let name, let occurrence) = target {
      guard !name.isEmpty, name.utf8.count <= 1024, (0..<100_000).contains(occurrence) else {
        throw CraftError.invalid("Invalid recorded retouch target.")
      }
    }
    guard foreground.isFinite, (0...1).contains(foreground.a),
      toning.exposure.isFinite, (0...1).contains(toning.exposure),
      focus.strength.isFinite, (0...1).contains(focus.strength) else {
      throw CraftError.invalid("Invalid recorded retouch settings.")
    }
    if tool.toning != nil {
      guard brush.mode == .normal else { throw CraftError.invalid("This retouch tool requires Normal brush mode.") }
    }
    if tool.focus != nil && !FocusBlendModes.supported.contains(brush.mode) {
      throw CraftError.invalid("Choose Normal, Darken, Lighten, Hue, Saturation, Color or Luminosity for this focus tool.")
    }
    if tool.toning == nil {
      guard let source, source.mask == mask else { throw CraftError.invalid("Retouch sampling must match the target kind.") }
    } else if source != nil || destination != nil { throw CraftError.invalid("Toning does not accept source images.") }
    if tool != .healingBrush && destination != nil { throw CraftError.invalid("Only Healing Brush accepts a destination context.") }
    if let destination, destination.mask != mask { throw CraftError.invalid("Healing destination kind does not match.") }
  }
  public init?(recording command: Command, in document: CraftDocument) {
    let id: UUID
    switch command {
    case .cloneStamp(let value, let stroke):
      guard let source = RecordedRetouchSource(sample: stroke.source, in: document) else { return nil }
      self.init(tool: .cloneStamp, target: .init(value, in: document), points: stroke.points)
      self.source = source; brush = stroke.brush; mapping = stroke.mapping; mask = stroke.mask; id = value
    case .healingBrush(let value, let healing):
      let stroke = healing.stroke
      guard let source = RecordedRetouchSource(sample: stroke.source, in: document) else { return nil }
      self.init(tool: .healingBrush, target: .init(value, in: document), points: stroke.points)
      self.source = source; brush = stroke.brush; mapping = stroke.mapping; mask = stroke.mask; id = value
      if let sample = healing.destination {
        guard let reference = RecordedRetouchSource(sample: sample, in: document) else { return nil }
        destination = reference
      }
    case .spotHealing(let value, let stroke):
      guard let source = RecordedRetouchSource(sample: stroke.sample, in: document) else { return nil }
      self.init(tool: .spotHealing, target: .init(value, in: document), points: stroke.points)
      self.source = source; brush = stroke.brush; mask = stroke.mask; spotType = stroke.kind; id = value
    case .toning(let value, let stroke):
      let tool: RecordedRetouchTool = stroke.tool == .dodge ? .dodge : stroke.tool == .burn ? .burn : .sponge
      self.init(tool: tool, target: .init(value, in: document), points: stroke.points)
      brush = stroke.brush; mask = stroke.mask; toning = stroke.options; id = value
    case .focus(let value, let stroke):
      let tool: RecordedRetouchTool = stroke.tool == .blur ? .blur : stroke.tool == .sharpen ? .sharpen : .smudge
      self.init(tool: tool, target: .init(value, in: document), points: stroke.points)
      brush = stroke.brush; mask = stroke.mask; focus = stroke.options; foreground = stroke.foreground; id = value
      if stroke.options.sampleAllLayers && !stroke.mask {
        guard let sample = stroke.sample, let reference = RecordedRetouchSource(sample: sample, in: document) else { return nil }
        source = reference
      } else { source = .init(layer: target, mask: mask) }
    default: return nil
    }
    guard document.layers.contains(where: { $0.id == id }) else { return nil }
  }
}
