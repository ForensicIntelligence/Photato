import Foundation
import PhotoCraftCore

/// Shared native/API request construction. Pixel math stays in the existing core.
enum GradientToolCommands {
  static func layer(fill: GradientFill, in document: CraftDocument, name: String = "Gradient Fill",
    parentID: UUID?, opacity: Float = 1, blend: BlendMode = .normal) throws -> Layer {
    try fill.validate()
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 65_535,
      opacity.isFinite, (0...1).contains(opacity) else { throw CraftError.invalid("Invalid Gradient Fill name or opacity.") }
    if let parentID {
      guard let parent = document.layers.first(where: { $0.id == parentID }), parent.isGroup,
        !document.isLocked(parentID) else { throw CraftError.invalid("Choose an unlocked parent group for the gradient.") }
    }
    var layer = Layer(name: name, content: .gradientFill(fill))
    layer.parentID = parentID; layer.opacity = opacity; layer.blendMode = blend
    return layer
  }
  static func stroke(gradient: GradientDefinition, start: PathPoint, end: PathPoint,
    style: GradientStyle, reverse: Bool, dither: Bool, transparency: Bool,
    opacity: Float, blend: BlendMode, mask: Bool) throws -> GradientStroke {
    try GradientFill(gradient: gradient).validate()
    guard opacity.isFinite, (0...1).contains(opacity),
      [start.x,start.y,end.x,end.y].allSatisfy({$0.isFinite && abs($0)<=1_000_000})
    else { throw CraftError.invalid("Invalid Classic Gradient endpoints or opacity.") }
    var stroke = GradientStroke(gradient: gradient, start: start, end: end)
    stroke.style=style;stroke.reverse=reverse;stroke.dither=dither;stroke.transparency=transparency
    stroke.opacity=opacity;stroke.mode=blend;stroke.mask=mask
    return stroke
  }
}
struct GradientInteractionSource {
  let document: CraftDocument
  let session: UUID
  let generation: UUID
  let tool: EditorTool
  @MainActor init(_ store: EditorStore) {
    document=store.document;session=store.sessionGeneration;generation=store.layerPanelGeneration;tool=store.tool
  }
  @MainActor func matches(_ store: EditorStore) -> Bool {
    session==store.sessionGeneration && generation==store.layerPanelGeneration && tool==store.tool && document==store.document
  }
}
extension EditorStore {
  var gradientCreationParent: UUID? {activeLayer.flatMap {$0.isGroup ? $0.id:$0.parentID}}
  var canConfigureGradientCreation: Bool {
    !geometryBusy && !hasToneDraft && transformDraft==nil && gradientGesture==nil
      && gradientStopColorDraft==nil && brushGesture==nil && cloneDraft==nil
  }
  func setGradientCreationOptions(_ options: GradientToolOptions) throws {
    guard canConfigureGradientCreation else {throw CraftError.invalid("Finish the current interaction before changing Gradient tool options.")}
    try options.gradient.validate()
    guard options.opacity.isFinite,(0...1).contains(options.opacity)else{throw CraftError.invalid("Gradient opacity must be between0and1.")}
    gradientOptions=options
  }
  var creationToolGradient: GradientDefinition {
    (try? gradientOptions.gradient.resolved(foreground:brush.color,background:backgroundColor)) ?? .blackToWhite
  }
}
