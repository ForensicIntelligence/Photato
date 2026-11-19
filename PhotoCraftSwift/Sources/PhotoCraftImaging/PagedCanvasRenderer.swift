import Foundation
import PhotoCraftCore

/// The existing compositor evaluated on bounded, document-coordinate patches.
/// No proxy document, changed layer geometry or reduced working pixels are used.
enum PagedCanvasRenderer {
  static let patchWidth=2048, patchHeight=64

  static func validateResources(_ d: CraftDocument) throws {
    guard d.colorMode == .rgb,d.inkMode == nil,d.restrictedMode == nil else {
      throw CraftError.unsupported("Large non-RGB composition retains its separate mode limits.")
    }
    for layer in d.layers {
      if layer.style != nil,layer.style?.isChannelBlendingOnly != true, d.width > LayerStyleRenderer.maximumPixels/d.height {
        throw CraftError.unsupported("Large layer styles still require bounded effect maps.")
      }
      if d.width > Surface.maximumDensePixels/d.height {
        // Renderer prepares Warp through its checked dense/paged raster backend
        // before composition. Canvas area alone is not a Warp source limit.
        if layer.smartFilters != nil {_ = try SmartFilterEngine.renderBounds(layer,in:d)}
      }
    }
  }

  static func composite(_ d: CraftDocument, region: IntRect, inputTarget: UUID? = nil,
    video: VideoTransitionRenderContext? = nil, forLayerOutput: Bool = false, onPatch: ((Int) -> Void)? = nil
  ) throws -> Surface {
    guard d.layers.allSatisfy({$0.warp==nil}) else{throw CraftError.invalid("Prepare warped sources before paged composition.")}
    try Task.checkCancellation();try validateResources(d)
    let facts=CompositionFacts(d)
    var reachedInput=false
    func render(_ rect:IntRect) throws -> Surface {
      do {return try Renderer.compositePrepared(d,region:rect,inputTarget:inputTarget,video:video,facts:facts,forLayerOutput:forLayerOutput)}
      catch let captured as AdjustmentInputReached {reachedInput=true;return captured.surface}
    }
    let complete=IntRect(x:0,y:0,width:d.width,height:d.height)
    let sources=try region==complete && video==nil ? pointwiseSources(d,facts:facts):nil
    let layerSupport = forLayerOutput && sources == nil && region == complete && video == nil
      ? try layerOutputSupport(d) : nil
    let columns=(d.width+63)/64,total=columns*((d.height+63)/64)
    var template=try Renderer.emptyCanvas(d, fill: forLayerOutput ? Pixel(1, 1, 1, 0) : .clear)
    var firstMissing = total
    if let sources {
      firstMissing = 0
      for key in TileKeys(sources) {
        try Task.checkCancellation()
        if key > firstMissing { break }
        firstMissing = key + 1
      }
    } else if let layerSupport {
      firstMissing = 0
      for patch in layerSupport {
        try Task.checkCancellation()
        let first = (patch.y / 64) * columns + patch.x / 64
        if first > firstMissing { break }
        firstMissing = first + (patch.width + 63) / 64
      }
    }
    if firstMissing < total {
      let x = (firstMissing % columns) * 64, y = (firstMissing / columns) * 64
      let sampled = try render(.init(x: x, y: y, width: 1, height: 1))
      let implicit = d.depth == .f32 ? sampled.linearPixel(x: x, y: y) : sampled.pixel(x: x, y: y)
      template = try template.mappedStoredSamples { _ in implicit }
    }
    let builder=try Surface.PagedBuilder(template:template)
    var completedPatches=0
    func append(_ patch:IntRect) throws {
      let x=max(patch.x,region.x),y=max(patch.y,region.y)
      let work=IntRect(x:x,y:y,width:min(patch.x+patch.width,region.x+region.width)-x,
        height:min(patch.y+patch.height,region.y+region.height)-y)
      let rendered=try render(work)
      try builder.append(rendered.cropped(to:patch),atX:patch.x,atY:patch.y)
      completedPatches += 1;onPatch?(completedPatches)
    }
    if let sources {
      var keys=TileKeys(sources).makeIterator(),next=keys.next()
      while let first=next {
        try Task.checkCancellation()
        let row=first/columns;var end=first+1;next=keys.next()
        while let key=next,key==end,key/columns==row,end-first<32 {end+=1;next=keys.next()}
        let x=first%columns*64,y=row*64
        try append(.init(x:x,y:y,width:min(d.width-x,(end-first)*64),height:min(64,d.height-y)))
      }
    } else if let layerSupport {
      for patch in layerSupport {
        try Task.checkCancellation()
        try append(patch)
      }
    } else {
      let left=region.x/64*64,top=region.y/64*64
      let right=min(d.width,((region.x+region.width+63)/64)*64)
      let bottom=min(d.height,((region.y+region.height+63)/64)*64)
      for y in stride(from:top,to:bottom,by:patchHeight) {
        for x in stride(from:left,to:right,by:patchWidth) {
          try Task.checkCancellation()
          try append(.init(x:x,y:y,width:min(patchWidth,right-x),height:min(patchHeight,bottom-y)))
        }
      }
    }
    let result=try builder.finish()
    if reachedInput {throw AdjustmentInputReached(surface:result)}
    return result
  }

  /// Support of translated Normal layer output. Outside these rectangles every
  /// full-canvas source contributes its implicit value and partial rasters are absent.
  /// The original document still supplies the global opacity and copy proofs.
  private static func layerOutputSupport(_ document: CraftDocument) throws -> GeometryPatchRegions? {
    var rectangles: [IntRect] = []
    let side = Surface.tileSide
    let permitsPixelMasks = RGB32NormalRenderer.supportsLayerOutput(document)
    func appendTiles(_ surface: Surface, x: Int, y: Int) throws {
      let columns = (surface.width + side - 1) / side
      for key in surface.storedTileKeys {
        try Task.checkCancellation()
        let left = key % columns * side, top = key / columns * side
        let changes = IntRect(x: x + left, y: y + top,
          width: min(side, surface.width - left), height: min(side, surface.height - top))
        rectangles.append(changes.clipped(toWidth: document.width, height: document.height))
      }
    }
    for layer in document.layers {
      try Task.checkCancellation()
      guard layer.affine == nil, layer.style == nil, layer.blendMode == .normal,
        layer.mask == nil || permitsPixelMasks, layer.vectorMask == nil, layer.smartObject == nil,
        layer.smartFilters == nil, layer.warp == nil, layer.sourceProjection == nil
      else { return nil }
      if case .group(let group) = layer.content {
        guard group.frame == nil, group.artboard == nil, layer.x == 0, layer.y == 0 else { return nil }
        continue
      }
      guard case .raster(let source) = layer.content else { return nil }
      guard layer.visible && layer.opacity > 0 else { continue }
      let aligned = layer.x == 0 && layer.y == 0
        && source.width == document.width && source.height == document.height
      // A translated transparent raster can affect straight HDR color in its
      // rectangle, even when its implicit alpha is zero.
      if aligned {
        try appendTiles(source, x: layer.x, y: layer.y)
        if let mask = layer.mask, layer.effectiveMaskProperties.enabled {
          let transform = layer.maskCoordinateTransform
          guard let x = Int(exactly: transform.tx), let y = Int(exactly: transform.ty) else { return nil }
          let coversDocument = x == 0 && y == 0 && mask.width == document.width && mask.height == document.height
          if coversDocument || layer.effectiveMaskProperties.outside == mask.defaultPixel.r {
            try appendTiles(mask, x: x, y: y)
          } else {
            let bounds = IntRect(x: x, y: y, width: mask.width, height: mask.height)
            rectangles.append(bounds.clipped(toWidth: document.width, height: document.height))
          }
        }
      } else {
        let bounds = IntRect(x: layer.x, y: layer.y, width: source.width, height: source.height)
        rectangles.append(bounds.clipped(toWidth: document.width, height: document.height))
      }
    }
    return GeometryPatchRegions(width: document.width, height: document.height, rectangles: rectangles)
  }

  /// Exhaustive pointwise eligibility: every missing tile has the same samples.
  /// Spatial/dithered/affine/rich sources keep complete patch evaluation.
  private static func pointwiseSources(_ d: CraftDocument,facts:CompositionFacts) throws -> [AnySequence<Int>]? {
    guard d.videoTimeline == nil else {return nil}
    var sources: [AnySequence<Int>] = []
    for layer in d.layers {
      guard layer.style==nil,layer.smartObject?.pdfSource==nil,layer.smartFilters==nil,layer.warp==nil,
        layer.blendMode != .dissolve,layer.coordinateTransform == .identity else {return nil}
      if let vector = layer.vectorMask, vector.enabled {
        let sampler = try facts.mask(layer)
        if let rectangles = sampler?.vectorFeatherSupport {
          let columns = (d.width + Surface.tileSide - 1) / Surface.tileSide
          let patches = GeometryPatchRegions(width: d.width, height: d.height, rectangles: rectangles)
          sources.append(AnySequence(patches.lazy.flatMap { rect -> Range<Int> in
            let first = rect.y / Surface.tileSide * columns + rect.x / Surface.tileSide
            return first..<(first + (rect.width + Surface.tileSide - 1) / Surface.tileSide)
          }))
        } else if let raw = sampler?.vectorTileSource {
          sources.append(raw.storedTileKeys)
        } else if sampler != nil {
          return nil
        }
      }
      if let mask=layer.mask,layer.effectiveMaskProperties.enabled {
        guard mask.width==d.width,mask.height==d.height,
          layer.maskCoordinateTransform == .identity,layer.effectiveMaskProperties.feather==0 else {return nil}
        sources.append(mask.storedTileKeys)
      }
      switch layer.content {
      case .raster(let surface):
        guard surface.width==d.width,surface.height==d.height else {return nil}
        sources.append(surface.storedTileKeys)
      case .fill:break
      case .group(let group):
        guard group.frame==nil,group.artboard==nil else {return nil}
      case .adjustment(let adjustment):
        switch adjustment {
        case .modern(let value):if value.needsNeighborhood || value.variesWithPosition {return nil}
        case .colorLookup,.gradientMap:return nil
        case .source,.levels,.curves,.hueSaturation,.colorBalance,.classic,.tonalSteps,
          .exposure,.brightnessContrast,.saturation,.invert,.grayscale:break
        }
      case .text,.shape,.gradientFill,.patternFill:return nil
      }
    }
    return sources
  }

  private struct TileKeys:Sequence {
    let sources: [AnySequence<Int>]
    init(_ sources: [AnySequence<Int>]) { self.sources = sources }
    func makeIterator()->AnyIterator<Int> {
      var iterators = sources.map { $0.makeIterator() }
      var heads=iterators.indices.map {iterators[$0].next()}
      return AnyIterator {
        var first:Int?
        for head in heads {if let head {first=first.map {Swift.min($0,head)} ?? head}}
        guard let key=first else {return nil}
        for i in heads.indices where heads[i]==key {heads[i]=iterators[i].next()}
        return key
      }
    }
  }
}
