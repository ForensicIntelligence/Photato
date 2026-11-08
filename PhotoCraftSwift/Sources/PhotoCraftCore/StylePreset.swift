import Foundation

/// General layer blending saved separately from editable effect parameters.
public struct StylePresetBlending: Codable, Equatable, Sendable {
  public var mode: BlendMode
  public var opacity: Float
  public var passThrough:Bool?
  public var blendClippedAsGroup:Bool?
  public init(mode: BlendMode, opacity: Float,passThrough:Bool?=nil,blendClippedAsGroup:Bool?=nil) { self.mode=mode; self.opacity=opacity;self.passThrough=passThrough;self.blendClippedAsGroup=blendClippedAsGroup }
  public func validate() throws {
    guard opacity.isFinite, (0...1).contains(opacity) else { throw CraftError.invalid("Invalid preset opacity.") }
  }
}

public struct StylePreset: Codable, Equatable, Sendable {
  public var style: LayerStyle
  public var includesEffects: Bool
  public var blending: StylePresetBlending?
  public var patterns: [RasterPattern]
  public init(style: LayerStyle, includesEffects: Bool = true, blending: StylePresetBlending? = nil, patterns: [RasterPattern] = []) {
    self.style=style; self.includesEffects=includesEffects; self.blending=blending; self.patterns=patterns
  }
  public static func capture(layerID: UUID, in document: CraftDocument, includesEffects: Bool = true, includesBlending: Bool = false, styleOverride: LayerStyle? = nil) throws -> Self {
    guard includesEffects || includesBlending, let layer=document.layers.first(where:{$0.id==layerID}) else { throw CraftError.invalid("Choose a layer and at least one style category.") }
    let style=styleOverride ?? layer.style ?? LayerStyle()
    try style.validate(in:document)
    let resources=includesEffects ? try style.presetPatternIDs.sorted().map { id -> RasterPattern in
      guard let pattern=document.pattern(id) else { throw CraftError.invalid("A style pattern is missing.") }; return pattern
    } : []
    let result=Self(style:style, includesEffects:includesEffects, blending:includesBlending ? .init(mode:layer.blendMode,opacity:layer.opacity,passThrough:layer.group?.passThrough,blendClippedAsGroup:layer.blendClippedAsGroup):nil, patterns:resources)
    try result.validate(); return result
  }
  public func validate() throws {
    guard includesEffects || blending != nil else { throw CraftError.invalid("A style preset must include effects or blending options.") }
    try style.validate(); try blending?.validate(); try PatternArchive.validate(patterns)
    guard Set(patterns.map(\.id)) == (includesEffects ? style.presetPatternIDs:[]) else { throw CraftError.invalid("Style preset pattern resources are incomplete or unrelated.") }
  }
  public func edit(layerIDs: Set<UUID>, in document: CraftDocument) throws -> LayerStyleEdit {
    try validate()
    guard !layerIDs.isEmpty,layerIDs.isSubset(of:Set(document.layers.map(\.id))) else { throw CraftError.invalid("Choose existing style targets.") }
    let captured=style
    var values=[UUID:LayerStyle?](),options=[UUID:StylePresetBlending]()
    for layer in document.layers where layerIDs.contains(layer.id) {
      let old=layer.style ?? LayerStyle()
      var next=includesEffects ? captured:old
      if blending == nil {
        next.fillOpacity=old.fillOpacity; next.restrictedChannels=old.restrictedChannels
      } else {
        next.fillOpacity=captured.fillOpacity; next.restrictedChannels=captured.restrictedChannels
        options[layer.id]=blending!
      }
      values.updateValue(next==LayerStyle() ? nil:next,forKey:layer.id)
    }
    return try LayerStyleEdit(styles:values,patterns:patterns.isEmpty ? nil:patterns,blending:options.isEmpty ? nil:options).remappingPatternResources(in:document)
  }
}
extension LayerStyle {
  public var presetPatternIDs: Set<String> {
    var ids=Set<String>()
    for effect in effects {
      if let id=effect.pattern?.patternID {ids.insert(id)}
      if let id=effect.advanced?.paint?.pattern?.patternID {ids.insert(id)}
      if let id=effect.advanced?.texture?.pattern.patternID {ids.insert(id)}
    }
    return ids
  }
  public mutating func remapPresetPatterns(_ mapping:[String:String]) {
    for i in effects.indices {
      if let id=effects[i].pattern?.patternID,let mapped=mapping[id] {effects[i].pattern?.patternID=mapped}
      if let id=effects[i].advanced?.paint?.pattern?.patternID,let mapped=mapping[id] {effects[i].advanced?.paint?.pattern?.patternID=mapped}
      if let id=effects[i].advanced?.texture?.pattern.patternID,let mapped=mapping[id] {effects[i].advanced?.texture?.pattern.patternID=mapped}
    }
  }
}

extension LayerStyleEdit {
  /// Embed every dependency for portable replay, remapping conflicting identities.
  public func remappingPatternResources(in document:CraftDocument)throws->Self {
    guard let patterns else{return self};try PatternArchive.validate(patterns)
    var result=self,mapping=[String:String](),resources=[RasterPattern]()
    var used=Set((document.patterns ?? []).map(\.id)).union(patterns.map(\.id))
    for original in patterns {
      var pattern=original
      if let old=document.pattern(original.id),old != original {
        var id=UUID().uuidString;while !used.insert(id).inserted {id=UUID().uuidString}
        mapping[original.id]=id;pattern=try RasterPattern(name:original.name,surface:original.surface,id:id)
      }
      resources.append(pattern)
    }
    result.patterns=resources
    for (id,value) in styles {if var style=value {style.remapPresetPatterns(mapping);result.styles.updateValue(style,forKey:id)}}
    return result
  }
}
