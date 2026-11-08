import Foundation
import PhotoCraftCore

/// Restores editable source layers. This is deliberately distinct from Rasterize.
public enum SmartObjectUnpack {
  public static func available(in document: CraftDocument, selected: Set<UUID>) -> Bool {
    guard !selected.isEmpty, document.colorMode == .rgb,
      document.animation == nil, document.videoTimeline == nil,
      selected.isSubset(of: Set(document.layers.map(\.id))) else { return false }
    return document.layers.filter { selected.contains($0.id) }.allSatisfy {
      guard let object = $0.smartObject else { return false }
      return !document.isImageLocked($0.id) && !object.data.isEmpty
        && object.pdfSource == nil && object.rawDevelopment == nil
        && $0.video == nil && $0.videoTiming == nil && $0.videoKeyframes == nil
    }
  }

  public static func command(in document: CraftDocument, selected: Set<UUID>) throws -> Command {
    try Task.checkCancellation()
    try document.validate()
    guard available(in: document, selected: selected) else {
      throw CraftError.unsupported("Select unlocked RGB Smart Objects with available original contents. PDF, RAW and temporal conversion to layers is not yet supported.")
    }
    var result = document
    // Nested instances retain sharing within each original source, without joining
    // an unrelated class already present in the destination document.
    var sourceClasses: [UUID: [UUID: UUID]] = [:]
    for container in document.layers where selected.contains(container.id) {
      try Task.checkCancellation()
      let object = container.smartObject!
      let decoded = try SmartObjectIO.sourceDocument(object)
      let source = try SmartObjectLayerCompIO.presentation(decoded, compID: object.layerComps?.selectedID)
      guard source.colorMode == .rgb, source.colorSpace == document.colorSpace,
        source.workingICC == document.workingICC,
        source.animation == nil, source.videoTimeline == nil, source.variables == nil,
        source.artboardOrigin == nil,
        source.layers.allSatisfy({ $0.nativeMode == nil && $0.video == nil && $0.videoTiming == nil && $0.videoKeyframes == nil && $0.group?.artboard == nil })
      else {
        throw CraftError.unsupported("Convert to Layers currently requires static RGB source layers with a matching working profile. Mode/profile, artboard, variable and temporal transfers remain unavailable.")
      }
      guard !source.layers.isEmpty, result.layers.count - 1 + source.layers.count <= LayerLimits.maximumLayers else {
        throw CraftError.invalid("The restored layers exceed the document layer limit.")
      }
      let direct = source.layers.count == 1 && !source.layers[0].isGroup
        && container.opacity == 1 && container.blendMode == .normal
        && container.mask == nil && container.vectorMask == nil && container.style == nil
      guard result.layers.count - 1 + source.layers.count + (direct ? 0 : 1) <= LayerLimits.maximumLayers else {
        throw CraftError.invalid("The restored group exceeds the document layer limit.")
      }
      var patterns: [String: String] = [:]
      for id in patternIDs(source).sorted() {
        try Task.checkCancellation()
        guard let pattern = source.pattern(id) else { throw CraftError.invalid("A source layer pattern is missing.") }
        patterns[id] = try result.installPattern(pattern)
      }
      let ids = Dictionary(uniqueKeysWithValues: source.layers.map { ($0.id, direct ? container.id : UUID()) })
      var classes = sourceClasses[object.sourceID] ?? [:]
      var copies: [Layer] = []
      for original in source.layers {
        try Task.checkCancellation()
        var copy = try transferred(original, from: source, to: document, patterns: patterns, classes: &classes)
        copy.id = ids[original.id]!
        copy.parentID = original.parentID.flatMap { ids[$0] } ?? (direct ? container.parentID : container.id)
        if direct {
          copy.name = container.name
          copy.visible = copy.visible && container.visible
          copy.clipped = container.clipped
          copy.linkID = container.linkID
          copy.linkDisabled = container.linkDisabled
          copy.blendClippedAsGroup = container.blendClippedAsGroup ?? copy.blendClippedAsGroup
        }
        copies.append(copy)
      }
      sourceClasses[object.sourceID] = classes
      guard let index = result.layers.firstIndex(where: { $0.id == container.id }) else {
        throw CraftError.invalid("The Smart Object disappeared during preparation.")
      }
      if !direct {
        var folder = container
        folder.content = .group(.init(passThrough: false))
        folder.smartObject = nil; folder.importedSmartAppearance = nil; folder.smartFilters = nil
        folder.sourceProjection = nil; folder.warp = nil; folder.affine = nil
        folder.x = 0; folder.y = 0; folder.sourceTags = nil
        // Masks are document-space attachments; removing the source transform
        // must not reinterpret their placement in the restored folder.
        if folder.mask != nil {
          var properties = container.effectiveMaskProperties
          properties.transform = container.maskCoordinateTransform
          folder.maskProperties = properties
        }
        copies.append(folder)
      }
      result.layers.replaceSubrange(index...index, with: copies)
      if !direct {
        LayerLinks.independentCopies(in: &result, layerIDs: Set(copies.dropLast().map(\.id)))
      }
    }
    // Wrapper IDs are retained, including the active layer and parent comp targets.
    // Selection, channels, paths, source metadata and other parent state stay intact.
    try result.validate()
    try Task.checkCancellation()
    return .preparedAction(.init(source: document, result: result, title: "Convert to Layers"))
  }

  private static func patternIDs(_ source: CraftDocument) -> Set<String> {
    var ids = Set<String>()
    func shape(_ value: ShapeDefinition?) {
      if let id = value?.fill.pattern?.patternID { ids.insert(id) }
      if let id = value?.stroke.paint.pattern?.patternID { ids.insert(id) }
    }
    for layer in source.layers {
      ids.formUnion(layer.style?.presetPatternIDs ?? [])
      if case .patternFill(let fill) = layer.content { ids.insert(fill.patternID) }
      shape(layer.shape?.definition); shape(layer.shape?.importedAppearance?.definition)
    }
    return ids
  }

  private static func transferred(_ original: Layer, from source: CraftDocument,
    to target: CraftDocument, patterns: [String: String], classes: inout [UUID: UUID]) throws -> Layer {
    func pixels(_ value: Surface) throws -> Surface {
      try ColorManagement.converted(value, from: source, to: target)
    }
    func remap(_ value: SmartObject) -> SmartObject {
      var result = value
      if classes[value.sourceID] == nil { classes[value.sourceID] = UUID() }
      result.sourceID = classes[value.sourceID]!
      return result
    }
    func shape(_ value: ShapeDefinition) -> ShapeDefinition {
      var value = value
      if let id = value.fill.pattern?.patternID { value.fill.pattern?.patternID = patterns[id] ?? id }
      if let id = value.stroke.paint.pattern?.patternID { value.stroke.paint.pattern?.patternID = patterns[id] ?? id }
      return value
    }
    var copy = original
    if copy.isBackground { copy.background = nil; copy.protection = []; copy.sourceTags?.removeValue(forKey: "lyid") }
    copy.style?.remapPresetPatterns(patterns)
    switch original.content {
    case .raster(let value): copy.content = .raster(try pixels(value))
    case .text(var text):
      let pristine = text.pristineSourceAppearance != nil
      text.layoutWidth = text.layoutWidth ?? source.width
      text.layoutHeight = text.layoutHeight ?? source.height
      if var appearance = text.importedAppearance {
        appearance.pixels = try appearance.pixels.map(pixels)
        if pristine { appearance.reference = .init(text) }
        text.importedAppearance = appearance
      }
      copy.content = .text(text)
    case .shape(var value):
      value.definition = value.definition.map(shape)
      if var appearance = value.importedAppearance {
        appearance.definition = shape(appearance.definition)
        appearance.pixels = try appearance.pixels.map(pixels)
        value.importedAppearance = appearance
      }
      copy.content = .shape(value)
    case .patternFill(var value):
      value.patternID = patterns[value.patternID] ?? value.patternID
      copy.content = .patternFill(value)
    default: break
    }
    copy.mask = try copy.mask.map { try $0.converted(to: target.depth) }
    copy.smartFilters?.mask = try original.smartFilters?.mask.map { try $0.converted(to: target.depth) }
    if let object = original.smartObject { copy.smartObject = remap(object) }
    if let appearance = original.importedSmartAppearance {
      // Rebind the captured reference, rather than the current layer. A stale
      // imported appearance must remain stale after identity/depth conversion.
      let reference = appearance.reference
      var captured = Layer(name: original.name, content: .raster(try pixels(reference.sourcePixels)))
      captured.smartObject = remap(reference.source); captured.affine = reference.transform
      captured.sourceProjection = reference.projection; captured.warp = reference.warp
      captured.smartFilters = reference.filters
      captured.smartFilters?.mask = try reference.filters?.mask.map { try $0.converted(to: target.depth) }
      copy.importedSmartAppearance = try .init(layer: captured, pixels: appearance.pixels.map(pixels),
        x: appearance.x, y: appearance.y, placedRecord: appearance.placedRecord)
    }
    return copy
  }
}
