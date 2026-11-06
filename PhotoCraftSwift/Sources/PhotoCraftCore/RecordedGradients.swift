import Foundation

private func validateGradientActionTarget(_ target: ActionLayerTarget) throws {
  if case .named(let name,let occurrence)=target {
    guard !name.isEmpty,name.utf16.count<=65_535,(0..<LayerLimits.maximumLayers).contains(occurrence)
    else{throw CraftError.invalid("Invalid recorded gradient layer reference.")}
  }
}
/// A fresh fill recipe, not a serialized document UUID or raster snapshot.
public struct RecordedGradientFill: Codable, Sendable {
  public var name: String
  public var fill: GradientFill
  public var parent: ActionLayerTarget?
  public var opacity: Float
  public var blend: BlendMode
  public var maskFromSelection: Bool
  public init?(layer: Layer, maskFromSelection: Bool, in document: CraftDocument) {
    guard case .gradientFill(let fill)=layer.content else{return nil}
    var supported=Layer(name:layer.name,content:.gradientFill(fill))
    supported.id=layer.id;supported.parentID=layer.parentID;supported.opacity=layer.opacity;supported.blendMode=layer.blendMode
    // Never silently discard masks, transforms, styles, locks or other metadata
    // supplied by a direct command. Those templates remain explicitly unsupported.
    guard supported==layer else{return nil}
    name=layer.name;self.fill=fill;parent=layer.parentID.map{.init($0,in:document)}
    opacity=layer.opacity;blend=layer.blendMode;self.maskFromSelection=maskFromSelection
  }
  public func validate() throws {
    try fill.validate()
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=65_535,
      opacity.isFinite,(0...1).contains(opacity)else{throw CraftError.invalid("Invalid recorded Gradient Fill.")}
    if let parent{try validateGradientActionTarget(parent)}
  }
  public func command(in document:CraftDocument)throws->Command {
    try validate()
    let parentID=try parent?.resolve(in:document)
    if let parentID {
      guard let layer=document.layers.first(where:{$0.id==parentID}),layer.isGroup,!document.isLocked(parentID)
      else{throw CraftError.invalid("Recorded Gradient Fill requires an unlocked parent group.")}
    }
    var layer=Layer(name:name,content:.gradientFill(fill));layer.parentID=parentID
    layer.opacity=opacity;layer.blendMode=blend
    return .addGradientFill(layer,maskFromSelection)
  }
}
public struct RecordedGradientStroke: Codable, Sendable {
  public var target: ActionLayerTarget
  public var gradient: GradientDefinition
  public var start,end: PathPoint
  public var style: GradientStyle
  public var reverse,dither,transparency,mask: Bool
  public var opacity: Float
  public var mode: BlendMode
  public init(layerID:UUID,stroke:GradientStroke,in document:CraftDocument) {
    target = .init(layerID,in:document);gradient=stroke.gradient;start=stroke.start;end=stroke.end
    style=stroke.style;reverse=stroke.reverse;dither=stroke.dither;transparency=stroke.transparency
    mask=stroke.mask;opacity=stroke.opacity;mode=stroke.mode
  }
  public func validate()throws {
    try validateGradientActionTarget(target);try GradientFill(gradient:gradient).validate()
    _=try GradientToolField(style:style,start:start,end:end)
    guard opacity.isFinite,(0...1).contains(opacity)else{throw CraftError.invalid("Invalid recorded Classic Gradient opacity.")}
  }
  public func command(in document:CraftDocument)throws->Command {
    try validate()
    var stroke=GradientStroke(gradient:gradient,start:start,end:end)
    stroke.style=style;stroke.reverse=reverse;stroke.dither=dither;stroke.transparency=transparency
    stroke.mask=mask;stroke.opacity=opacity;stroke.mode=mode
    return .paintGradient(try target.resolve(in:document),stroke)
  }
}
