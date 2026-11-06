import Foundation

/// Editable style stack. Names, light direction and PSD mappings follow PhotoCraft's
/// doc/effects.rs and io/effects_map.rs (MIT OR Apache-2.0). Rendering is native Swift.
public struct LayerEffect: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case bevelEmboss, stroke, innerShadow, innerGlow, satin, colorOverlay, gradientOverlay
    case patternOverlay, outerGlow, dropShadow
    public var title: String {
      switch self {
      case .bevelEmboss: "Bevel & Emboss"
      case .stroke: "Stroke"
      case .innerShadow: "Inner Shadow"
      case .innerGlow: "Inner Glow"
      case .satin: "Satin"
      case .colorOverlay: "Color Overlay"
      case .gradientOverlay: "Gradient Overlay"
      case .patternOverlay: "Pattern Overlay"
      case .outerGlow: "Outer Glow"
      case .dropShadow: "Drop Shadow"
      }
    }
  }
  public enum StrokePosition: String, Codable, CaseIterable, Sendable { case outside, inside, center }
  public var advanced:LayerEffectAdvanced?
  public var kind: Kind
  public var enabled = true
  public var opacity: Float = 1
  public var blendMode: BlendMode = .normal
  public var color = Pixel.black
  public var size: Double = 5
  public var distance: Double = 5
  public var angle: Double = 120
  public var spread: Double = 0
  public var useGlobalLight = true
  public var position: StrokePosition = .outside
  public var depth: Double = 100
  public var soften: Double = 0
  public var highlightColor = Pixel.white
  public var highlightOpacity: Float = 0.5
  public var shadowColor = Pixel.black
  public var shadowOpacity: Float = 0.5
  public var gradient: GradientFill?
  public var pattern: PatternFill?
  public init(_ kind: Kind) {
    self.kind = kind
    switch kind {
    case .dropShadow, .innerShadow, .satin: blendMode = .multiply; opacity = 0.5
    case .innerGlow, .outerGlow: color = .white; blendMode = .screen; opacity = 0.5
    case .colorOverlay: color = Pixel(1, 0, 0)
    case .stroke: size = 3
    default: break
    }
  }
  public func validate(in document: CraftDocument? = nil) throws {
    func validColor(_ p: Pixel) -> Bool { [p.r,p.g,p.b,p.a].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    guard opacity.isFinite, (0...1).contains(opacity), validColor(color),
      size.isFinite, (0...250).contains(size), distance.isFinite, ((advanced == nil ? 0.0:-30000.0)...30000).contains(distance),
      angle.isFinite, (-360...360).contains(angle), spread.isFinite, (0...100).contains(spread),
      depth.isFinite, ((advanced == nil ? 1.0:0.0)...1000).contains(depth), soften.isFinite, (0...16).contains(soften),
      validColor(highlightColor), validColor(shadowColor),
      highlightOpacity.isFinite, (0...1).contains(highlightOpacity),
      shadowOpacity.isFinite, (0...1).contains(shadowOpacity)
    else { throw CraftError.invalid("Invalid layer effect parameters.") }
    try advanced?.validate(kind:kind,in:document)
    try gradient?.validate()
    try pattern?.validate()
    if kind == .gradientOverlay,advanced?.paint?.kind != .gradient {
      guard let gradient else { throw CraftError.invalid("Gradient Overlay requires a gradient.") }
      try gradient.validate()
    }
    if kind == .patternOverlay,advanced?.paint?.kind != .pattern {
      guard let pattern else { throw CraftError.invalid("Pattern Overlay requires a pattern.") }
      try pattern.validate()
      if let document, document.pattern(pattern.patternID) == nil {
        throw CraftError.invalid("Missing embedded style pattern.")
      }
    }
  }
}

public struct LayerStyle: Codable, Equatable, Sendable {
  /// Layer-local linked pattern anchor; a nil value follows the shape bounds.
  public var referenceOffset:PathPoint?
  /// Inert original PSD descriptor bytes; editable export must qualify their mapping.
  public var sourcePSDData:Data?
  public var enabled = true
  public var fillOpacity: Float = 1
  public var scale: Double = 100
  public var lightAngle: Double = 120
  public var lightAltitude: Double = 30
  public var effects: [LayerEffect] = []
  public init(effects: [LayerEffect] = []) { self.effects = effects }
  public var estimatedBytes: Int { (sourcePSDData?.count ?? 0) + effects.reduce(256) { $0 + 1024 + ($1.advanced?.estimatedBytes ?? 0) + ($1.gradient?.gradient.colors.count ?? 0) * 96 + ($1.gradient?.gradient.opacity.count ?? 0) * 32 } }
  public var hasEffects: Bool { enabled && effects.contains { $0.enabled && $0.opacity > 0 } }
  public func validate(in document: CraftDocument? = nil) throws {
    guard fillOpacity.isFinite, (0...1).contains(fillOpacity),
      scale.isFinite, (1...1000).contains(scale), lightAngle.isFinite,
      (-360...360).contains(lightAngle), lightAltitude.isFinite, (0...90).contains(lightAltitude),
      effects.count <= 32
    else { throw CraftError.invalid("Invalid layer style or more than 32 effects.") }
    guard (sourcePSDData?.count ?? 0)<=1024*1024,referenceOffset.map({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1e9 && abs($0.y)<=1e9}) != false else {throw CraftError.invalid("Invalid retained effect reference data.")}
    for effect in effects { try effect.validate(in: document) }
  }
  /// Optional fields inherit the same defaults as the native editor; unknown keys reject.
  public static func decodeJSON(_ data: Data) throws -> Self {
    guard data.count<=16*1024*1024 else {throw CraftError.invalid("Style JSON exceeds16MiB.")}
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CraftError.invalid("Expected a layer style object.")
    }
    let encoder = JSONEncoder()
    func defaults<T: Encodable>(_ value: T) throws -> [String: Any] {
      try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
    }
    var merged = try defaults(Self())
    guard Set(object.keys).isSubset(of: Set(merged.keys).union(["referenceOffset","sourcePSDData"])) else { throw CraftError.invalid("Unknown layer style parameter.") }
    if let point=object["referenceOffset"],!(point is NSNull){try AdvancedEffectJSON.point(point)}
    for (key, value) in object where key != "effects" { merged[key] = value }
    if let effects = object["effects"] {
      guard let effects = effects as? [[String: Any]], effects.count <= 32 else { throw CraftError.invalid("Invalid effect array.") }
      merged["effects"] = try effects.map { fields in
        guard let text = fields["kind"] as? String, let kind = LayerEffect.Kind(rawValue: text) else {
          throw CraftError.invalid("Unknown layer effect.")
        }
        var value = try defaults(LayerEffect(kind))
        guard Set(fields.keys).isSubset(of: Set(value.keys).union(["gradient", "pattern","advanced"])) else {
          throw CraftError.invalid("Unknown effect parameter.")
        }
        if let advanced=fields["advanced"] {try AdvancedEffectJSON.validate(advanced)}
        for (key, field) in fields { value[key] = field }
        return value
      }
    }
    let result = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: merged))
    try result.validate()
    return result
  }
}

extension CraftDocument {
  public var requiresLayerStylesArchive: Bool { layers.contains { $0.style != nil } }
  public var minimumArchiveVersion: Int { if requiresShapeBlurKernelArchive {return 87}; if layers.contains(where: { $0.nativeMode?.requiresPagedArchive == true }) { return 86 }; if isChannelOnly {return 85}; if requiresLayerLinkArchive {return 84}; if layers.contains(where:{$0.isBackground}) {return 83}; if requiresLayerComp82Archive {return 82}; if layerComps?.requiresSmartObjectSelectionArchive == true {return 81}; if requiresSmartObjectLayerCompArchive {return 80}; if layerComps != nil {return 79}; if guides != nil {return 78}; if hasPSDChannelRetention {return 77}; if hasSpotChannels {return 76}; if requiresAdvancedStyleArchive {return 75}; if requiresSourceAdjustmentArchive {return 74}; if requiresSourceDisplacementArchive{return 73}; if requiresLightingArchive{return 72};if requiresRelightArchive{return 71}; if requiresSourceSmartArchive {return 70}; if requiresRichTypeArchive {return 69}; if requiresExtendedShapeArchive {return 68}; if layers.contains(where:{if case .adjustment(.classic(let value))=$0.content{return value.kind == .exposure};return false}) {return 67}; if layers.contains(where:{$0.smartObject?.linkedSource != nil}) {return 66}; if layers.contains(where:{if case .adjustment(.modern)=$0.content{return true};return false}) {return 65}; if selectionMask?.isPaged == true {return 64}; if layers.contains(where: { $0.smartObject?.pdfSource != nil }) { return 62 }; if variables != nil { return 61 }; if videoTimeline?.retainedFrameSources != nil || videoTimeline?.frameTransitionKeys != nil || (videoTimeline?.audioTracks?.flatMap(\.clips).contains(where:{$0.playbackRate != nil}) == true) || layers.contains(where:{$0.videoKeyframes?.contains(where:{$0.property == .content}) == true}) {return 60};if let animation,animation.sampledTimeline != nil || animation.retainedVideoSource != nil || animation.frames.contains(where:{$0.sourceVideoFrame != nil || $0.transitions != nil || $0.layers.contains(where:{$0.payload != nil})}) {return 60};if videoTimeline?.finiteLoopCount != nil || layers.contains(where:{$0.videoKeyframes?.contains(where:{$0.property == .visibility || $0.frameComposition == true}) == true}) {return 59};if videoTimeline?.trimmedToWorkArea == true {return 58};if videoTimeline?.workArea != nil || videoTimeline?.onionSkin != nil {return 57};if videoTimeline?.audioTracks != nil || layers.contains(where:{$0.video?.audio != nil}) {return 56};if videoTimeline?.transitions != nil {return 55};if layers.contains(where:{$0.videoTiming != nil || $0.group?.videoStartTime != nil || $0.video?.sourceIn != nil || $0.video?.sourceOut != nil}) {return 54};return layers.contains(where:{$0.videoKeyframes != nil}) ? 53 : layers.contains(where:{$0.video?.movie != nil}) ? 52 : videoTimeline != nil ? 51 : animation != nil ? 50 : profileIsUntagged == true ? 49 : inkMode != nil ? 48 : restrictedMode != nil ? 47 : hasNativeModeStorage ? 46 : layers.contains(where:{$0.smartFilters?.filters.contains(where:{$0.filter.kind == .shadowsHighlights}) == true}) ? 45 :layers.contains(where:{$0.smartFilters?.filters.contains(where:{$0.filter.kind.isClassicDetail}) == true}) ? 44 :layers.contains(where:{$0.smartFilters?.filters.contains(where:{$0.filter.kind.isOtherVideo}) == true}) ? 43 :layers.contains(where:{$0.smartFilters?.filters.contains(where:{$0.filter.kind.isRender}) == true}) ? 42 :layers.contains(where:{$0.smartFilters?.filters.contains(where:{$0.filter.kind.isStylize}) == true}) ? 41 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind.isPixelate }) == true }) ? 40 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind.isDistortion }) == true }) ? 39 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .lensBlur }) == true }) ? 38 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .smartSharpen || $0.filter.kind == .reduceNoise }) == true }) ? 37 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .filterGallery }) == true }) ? 36 : hasShapedText ? 35 : hasAdvancedTypography ? 34 : layers.contains(where: { $0.shape?.definition != nil }) ? 33 : vanishingPoint != nil ? 32 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .adaptiveWideAngle }) == true }) ? 31 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .lensCorrection }) == true }) ? 30 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .blurGallery }) == true }) ? 29 : hasFrames ? 28 : hasArtboards || artboardOrigin != nil ? 27 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .perspectiveWarp }) == true }) ? 26 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .puppetWarp }) == true }) ? 25 : layers.contains(where: { $0.warp != nil }) ? 24 : layers.contains(where: { $0.smartObject?.stackMode != nil }) ? 23 : layers.contains(where: { $0.smartObject?.rawDevelopment != nil }) ? 22 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .cameraRaw }) == true }) ? 21 : hasAuxiliaryChannels ? 20 : layers.contains(where: { $0.smartFilters?.filters.contains(where: { $0.filter.kind == .liquify }) == true }) ? 19 : layers.contains(where: { if case .adjustment(.colorLookup) = $0.content { return true }; return false }) ? 18 : layers.contains(where: { if case .adjustment(.classic) = $0.content { return true }; return false }) ? 17 : layers.contains(where: { if case .text(let t) = $0.content { return t.typography != nil }; return false }) ? 16 : layers.contains(where: { $0.smartFilters != nil }) ? 15 : requiresSmartObjectArchive ? 14 : requiresLayerStylesArchive ? 13 : requiresPartialProtectionArchive ? 12 : 10 }
}
