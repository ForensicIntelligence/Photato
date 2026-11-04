import Foundation

/// Multiple independently retained styles and optional shared light commit as
/// one history transaction. Null values clear styles; absent targets stay intact.
public struct LayerStyleEdit:Sendable {
  public var styles:[UUID:LayerStyle?]
  public var globalLight:GlobalLight?
  public init(styles:[UUID:LayerStyle?],globalLight:GlobalLight?=nil){self.styles=styles;self.globalLight=globalLight}
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
    for (id, style) in styles.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
      try Task.checkCancellation()
      guard let index = indices[id] else { throw CraftError.invalid("Layer no longer exists.") }
      guard !hierarchy.effectiveProtection(id).fullyLocks else {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      try style?.validate(in: document)
      if style != nil, document.width > 8_388_608 / document.height {
        throw CraftError.unsupported("Layer styles support canvases up to8,388,608 pixels.")
      }
      if case .adjustment = document.layers[index].content {
        throw CraftError.unsupported("Layer styles on adjustment layers are not available yet.")
      }
      candidate.layers[index].style = style
      for tag in ["lfx2", "lmfx", "lrFX", "iOpa"] { candidate.layers[index].sourceTags?.removeValue(forKey: tag) }
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
  public init(_ edit:LayerStyleEdit,in document:CraftDocument) {
    let rows=edit.styles.sorted{$0.key.uuidString<$1.key.uuidString}
    targets=rows.map{ActionLayerTarget($0.key,in:document)};styles=rows.map(\.value);globalLight=edit.globalLight
  }
  public func validate()throws {
    guard (1...LayerLimits.maximumLayers).contains(targets.count),targets.count==styles.count else {throw CraftError.invalid("Invalid recorded style targets.")}
    try globalLight?.validate();for style in styles {try style?.validate()}
  }
  public func resolved(in document:CraftDocument)throws->LayerStyleEdit {
    try validate();let ids=try targets.map{try $0.resolve(in:document)}
    guard Set(ids).count==ids.count else {throw CraftError.invalid("Recorded style targets resolve to duplicate layers.")}
    return LayerStyleEdit(styles:Dictionary(uniqueKeysWithValues:zip(ids,styles)),globalLight:globalLight)
  }
}
