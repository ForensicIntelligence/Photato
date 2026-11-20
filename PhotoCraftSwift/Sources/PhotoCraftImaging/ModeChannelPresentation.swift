import PhotoCraftCore

/// Component previews use retained planes, never a CMYK-to-RGB-to-CMYK round trip.
/// The existing renderer still defines multi-layer blending; ink-space blend
/// fidelity and arbitrary rich-content separations are separate parity gates.
public enum ModeChannelPresentation {
  public static func surface(_ document: CraftDocument, visible: Set<Int>?) throws -> Surface {
    try surface(document, visible: visible, region: nil)
  }
  private static func surface(_ document: CraftDocument, visible: Set<Int>?, region: IntRect?) throws -> Surface {
    func composite(_ source: CraftDocument) throws -> Surface {
      if let region { return try Renderer.composite(source, region: region) }
      return try Renderer.composite(source)
    }
    let all = Set(0..<document.colorMode.componentCount)
    guard let visible, visible != all || all.count == 1 else { return try composite(document) }
    guard !visible.isEmpty, visible.isSubset(of: all) else { throw CraftError.invalid("Invalid visible components.") }
    let needsComposite = document.layers.contains { layer in
      if layer.style != nil || layer.smartObject != nil || layer.smartFilters != nil || layer.warp != nil { return true }
      switch layer.content { case .raster, .group: return false; default: return true }
    }
    if needsComposite {
      // Rich effects must be rendered before extracting a preview. This fallback
      // is explicitly a separation of the existing RGB composite, not retained
      // ink-space compositing or an editable source-plane substitute.
      let pixels = try composite(document)
      let native = try NativeModeRaster.converting(pixels, to: document.colorMode,
        profile: document.modeDescriptor?.profile, sourceProfile: document.workingICC)
      var flattened = try CraftDocument(width: document.width, height: document.height, depth: document.depth)
      flattened.modeDescriptor = try .init(mode: native.mode, depth: native.depth, profile: native.profile)
      flattened.layers[0].nativeMode = native
      flattened.layers[0].content = .raster(try native.surface())
      return try surface(flattened, visible: visible, region: region)
    }
    var proxy = document
    proxy.modeDescriptor = nil; proxy.workingICC = nil
    for i in document.layers.indices {
      try Task.checkCancellation()
      let layer = document.layers[i]
      if case .group = layer.content { continue }
      let native = try ModeComponentEdit.raster(layer, in: document)
      let pixels: Surface
      if let region, visible.count == 1, let component = visible.first {
        let local = IntRect(x: region.x - layer.x, y: region.y - layer.y, width: region.width, height: region.height)
        pixels = try native.presentingComponent(component, region: local)
      } else {
        pixels = try native.presentingComponents(visible)
      }
      proxy.layers[i].nativeMode = nil; proxy.layers[i].content = .raster(pixels)
    }
    return try composite(proxy)
  }
  public static func thumbnails(_ document: CraftDocument, maximumSize: Int) throws -> [Surface] {
    var result = [try Renderer.channelThumbnails(Renderer.composite(document), maximumSize: maximumSize)[0]]
    for c in 0..<document.colorMode.componentCount {
      // Gray has only one plane; request its numerical projection rather than
      // treating the singleton as the complete color composite.
      let plane = try singleComponent(document, component: c)
      result.append(try Renderer.channelThumbnails(plane, maximumSize: maximumSize)[0])
    }
    return result
  }
  public static func singleComponent(_ document: CraftDocument, component: Int) throws -> Surface {
    try singleComponent(document, component: component, region: nil)
  }
  static func singleComponent(_ document: CraftDocument, component: Int, region: IntRect?) throws -> Surface {
    guard (0..<document.colorMode.componentCount).contains(component) else { throw CraftError.invalid("Invalid component.") }
    return try surface(document, visible: [component], region: region)
  }
}
