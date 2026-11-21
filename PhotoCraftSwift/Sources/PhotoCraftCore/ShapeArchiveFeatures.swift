import Foundation

extension CraftDocument {
  /// Retained animation/video content needs the same reader admission as visible layers.
  var requiresExtendedShapeArchive:Bool {
    hasShapeArchiveFeature { shape in
      shape.importedAppearance != nil || shape.definition?.requiresExtendedShapeArchive == true
    }
  }

  var requiresShapeExteriorArchive: Bool {
    hasShapeArchiveFeature { shape in
      shape.definition?.exteriorFrame != nil || shape.importedAppearance?.definition.exteriorFrame != nil
    }
  }

  private func hasShapeArchiveFeature(_ matches: (ShapeContent) -> Bool) -> Bool {
    func content(_ value: LayerContent) -> Bool {
      guard case .shape(let shape) = value else { return false }
      return matches(shape)
    }
    func layer(_ value:Layer)->Bool {
      content(value.content) || value.videoKeyframes?.contains(where:{$0.content.map{content($0.content)} ?? false}) == true
    }
    if layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains(where:{$0.payload.map{content($0.content)} ?? false})}) == true{return true}
    var retained=videoTimeline?.retainedFrameSources ?? []
    if let original=animation?.retainedVideoSource{retained.append(original)}
    while let original=retained.popLast(){
      if original.layers.contains(where:layer){return true}
      retained.append(contentsOf:original.timeline.retainedFrameSources ?? [])
    }
    return false
  }
}
