import Foundation

/// Multiple independently retained styles and optional shared light commit as
/// one history transaction. Null values clear styles; absent targets stay intact.
public struct LayerStyleEdit:Sendable {
  public var styles:[UUID:LayerStyle?]
  public var globalLight:GlobalLight?
  public var patterns:[RasterPattern]?
  public var blending:[UUID:StylePresetBlending]?
  public init(styles:[UUID:LayerStyle?],globalLight:GlobalLight?=nil,patterns:[RasterPattern]?=nil,blending:[UUID:StylePresetBlending]?=nil){self.styles=styles;self.globalLight=globalLight;self.patterns=patterns;self.blending=blending}
  public init(layerIDs:Set<UUID>,style:LayerStyle?,globalLight:GlobalLight?=nil){self.styles=Dictionary(uniqueKeysWithValues:layerIDs.map{($0,style)});self.globalLight=globalLight}
  public func apply(to document:inout CraftDocument)throws {
    guard (1...LayerLimits.maximumLayers).contains(styles.count) else {throw CraftError.invalid("Choose one to8,000 layer style targets.")}
    try globalLight?.validate()
    // Capture assumes a valid source composition; do not heal stale keys or
    // index a malformed selected frame while preparing an otherwise valid edit.
    if let animation = document.animation { try animation.validate(in: document) }
    if document.videoTimeline != nil { try document.validateVideoKeyframes() }
    let hierarchy = LayerHierarchyIndex(document)
    let indices = Dictionary(uniqueKeysWithValues: document.layers.enumerated().map { ($0.element.id, $0.offset) })
    var candidate = document
    if let patterns {
      try PatternArchive.validate(patterns)
      var assets=candidate.patterns ?? []
      for pattern in patterns {
        if let old=assets.first(where:{$0.id==pattern.id}) {guard old==pattern else {throw CraftError.invalid("Style pattern identity conflicts with the document.")}}
        else {assets.append(pattern)}
      }
      try PatternArchive.validate(assets);candidate.patterns=assets
    }
    if let blending {guard Set(blending.keys).isSubset(of:Set(styles.keys)) else {throw CraftError.invalid("Blending targets must also be style targets.")};for value in blending.values {try value.validate()}}
    for (id, style) in styles.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
      try Task.checkCancellation()
      guard let index = indices[id] else { throw CraftError.invalid("Layer no longer exists.") }
      guard !hierarchy.effectiveProtection(id).fullyLocks else {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      try style?.validate(in: candidate)
      if let style,!style.isChannelBlendingOnly, document.width > 8_388_608 / document.height {
        throw CraftError.unsupported("Layer styles support canvases up to8,388,608 pixels.")
      }
      if case .adjustment = document.layers[index].content,style != nil,style?.isChannelBlendingOnly != true {
        throw CraftError.unsupported("Layer styles on adjustment layers are not available yet.")
      }
      if let option=blending?[id] {
        guard option.passThrough != true || candidate.layers[index].isGroup else {throw CraftError.invalid("Pass Through requires a layer group.")}
        candidate.layers[index].blendClippedAsGroup=option.blendClippedAsGroup
        if var group=candidate.layers[index].group {group.passThrough=option.passThrough ?? false;candidate.layers[index].content = .group(group)}
        candidate.layers[index].opacity=option.opacity;candidate.layers[index].blendMode=option.mode
      }
      candidate.layers[index].style = style
      for tag in ["lfx2", "lmfx", "lrFX", "iOpa", "brst"] { candidate.layers[index].sourceTags?.removeValue(forKey: tag) }
    }
    if let globalLight {candidate.globalLight=globalLight}
    // Styles belong to the current temporal composition. Capture that change
    // before validating its agreement with the enabled keys/selected frame.
    try candidate.captureVideoKeyframeChanges()
    try candidate.captureAnimationChanges()
    try candidate.validate();document=candidate
  }
}
public struct RecordedStyleEdit:Codable,Sendable {
  public var targets:[ActionLayerTarget]
  public var styles:[LayerStyle?]
  public var globalLight:GlobalLight?
  public var patterns:[RasterPattern]?
  public var blending:[StylePresetBlending?]?
  public init(_ edit:LayerStyleEdit,in document:CraftDocument) {
    let rows=edit.styles.sorted{$0.key.uuidString<$1.key.uuidString}
    targets=rows.map{ActionLayerTarget($0.key,in:document)};styles=rows.map(\.value);globalLight=edit.globalLight;patterns=edit.patterns;blending=edit.blending.map{values in rows.map{values[$0.key]}}
  }
  public func validate()throws {
    guard (1...LayerLimits.maximumLayers).contains(targets.count),targets.count==styles.count else {throw CraftError.invalid("Invalid recorded style targets.")}
    if let patterns{try PatternArchive.validate(patterns)};if let blending{guard blending.count==targets.count else{throw CraftError.invalid("Invalid recorded style blending targets.")};for value in blending{try value?.validate()}}
    try globalLight?.validate();for style in styles {try style?.validate()}
  }
  public func resolved(in document:CraftDocument)throws->LayerStyleEdit {
    try validate();let ids=try targets.map{try $0.resolve(in:document)}
    guard Set(ids).count==ids.count else {throw CraftError.invalid("Recorded style targets resolve to duplicate layers.")}
    return try LayerStyleEdit(styles:Dictionary(uniqueKeysWithValues:zip(ids,styles)),globalLight:globalLight,patterns:patterns,blending:blending.map{values in Dictionary(uniqueKeysWithValues:zip(ids,values).compactMap{id,value in value.map{(id,$0)}})}).remappingPatternResources(in:document)
  }
}
