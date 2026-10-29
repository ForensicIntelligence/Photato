import PhotoCraftCore

/// Component previews use retained planes, never a CMYK-to-RGB-to-CMYK round trip.
/// The existing renderer still defines multi-layer blending; ink-space blend
/// fidelity and arbitrary rich-content separations are separate parity gates.
public enum ModeChannelPresentation {
  public static func surface(_ document: CraftDocument, visible: Set<Int>?) throws -> Surface {
    let all = Set(0..<document.colorMode.componentCount)
    guard let visible, visible != all || all.count == 1 else { return try Renderer.composite(document) }
    guard !visible.isEmpty, visible.isSubset(of: all) else { throw CraftError.invalid("Invalid visible components.") }
    let needsComposite = document.layers.contains { layer in
      if layer.style != nil || layer.smartObject != nil || layer.smartFilters != nil || layer.warp != nil { return true }
      switch layer.content { case .raster, .group: return false; default: return true }
    }
    if needsComposite {
      // Rich effects must be rendered before extracting a preview. This fallback
      // is explicitly a separation of the existing RGB composite, not retained
      // ink-space compositing or an editable source-plane substitute.
      let pixels = try Renderer.composite(document)
      let native = try NativeModeRaster.converting(pixels, to: document.colorMode,
        profile: document.modeDescriptor?.profile, sourceProfile: document.workingICC)
      var flattened = try CraftDocument(width: document.width, height: document.height, depth: document.depth)
      flattened.modeDescriptor = try .init(mode: native.mode, depth: native.depth, profile: native.profile)
      flattened.layers[0].nativeMode = native
      flattened.layers[0].content = .raster(try native.surface())
      return try surface(flattened, visible: visible)
    }
    var proxy = document
    proxy.modeDescriptor = nil; proxy.workingICC = nil
    let single = visible.count == 1 ? visible.first : nil
    for i in document.layers.indices {
      try Task.checkCancellation()
      let layer = document.layers[i]
      if case .group = layer.content { continue }
      var native = try ModeComponentEdit.raster(layer, in: document)
      let pixels: Surface
      if let single {
        var plane = try Surface(width: native.width, height: native.height, depth: native.depth)
        for y in 0..<native.height { try Task.checkCancellation(); for x in 0..<native.width {
          let index = y * native.width + x, sample = native.value(component: single, index: index)
          let gray = native.mode == .cmyk ? 1 - sample : sample
          plane.setPixel(x: x, y: y, Pixel(gray, gray, gray, native.value(component: native.mode.componentCount, index: index)))
        } }
        pixels = plane
      } else {
        for c in all.subtracting(visible) {
          let neutral: Float = native.mode == .lab && c != 0 ? 128 / 255 : 0
          for index in 0..<native.width * native.height {
            if index % 4096 == 0 { try Task.checkCancellation() }
            try native.set(neutral, component: c, index: index)
          }
        }
        pixels = try native.surface()
      }
      proxy.layers[i].nativeMode = nil; proxy.layers[i].content = .raster(pixels)
    }
    return try Renderer.composite(proxy)
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
    guard (0..<document.colorMode.componentCount).contains(component) else { throw CraftError.invalid("Invalid component.") }
    return try surface(document, visible: [component])
  }
}
