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
      if layer.style != nil, d.width > LayerStyleRenderer.maximumPixels/d.height {
        throw CraftError.unsupported("Large layer styles still require bounded effect maps.")
      }
      if d.width > Surface.maximumDensePixels/d.height {
        guard layer.vectorMask?.enabled != true || layer.vectorMask?.feather==0 else {
          throw CraftError.unsupported("Large feathered vector masks still require bounded kernel preparation.")
        }
        guard layer.warp == nil else {throw CraftError.unsupported("Large Warp preparation retains its separate raster limit.")}
        if layer.smartFilters != nil {_ = try SmartFilterEngine.renderBounds(layer,in:d)}
      }
      if let mask=layer.mask,layer.effectiveMaskProperties.enabled,layer.effectiveMaskProperties.feather>0 {
        let pad=2*Int(ceil(3*max(0.05,layer.effectiveMaskProperties.feather)))
        guard mask.width+pad<=Surface.maxDimension,mask.height+pad<=Surface.maxDimension,
          mask.width+pad<=Surface.maximumDensePixels/(mask.height+pad) else {
          throw CraftError.unsupported("This feathered pixel mask still needs bounded kernel preparation.")
        }
      }
    }
  }

  static func composite(_ d: CraftDocument, region: IntRect, inputTarget: UUID? = nil,
    video: VideoTransitionRenderContext? = nil, onPatch: ((Int) -> Void)? = nil
  ) throws -> Surface {
    try Task.checkCancellation();try validateResources(d)
    let facts=CompositionFacts(d)
    var reachedInput=false
    func render(_ rect:IntRect) throws -> Surface {
      do {return try Renderer.compositePrepared(d,region:rect,inputTarget:inputTarget,video:video,facts:facts)}
      catch let captured as AdjustmentInputReached {reachedInput=true;return captured.surface}
    }
    let complete=IntRect(x:0,y:0,width:d.width,height:d.height)
    let sources=try region==complete && video==nil ? pointwiseSources(d,facts:facts):nil
    let columns=(d.width+63)/64,total=columns*((d.height+63)/64)
    var template=try Renderer.emptyCanvas(d)
    if let sources {
      var firstMissing=0
      for key in TileKeys(sources) {
        try Task.checkCancellation()
        if key>firstMissing {break};firstMissing=key+1
      }
      if firstMissing<total {
        let x=(firstMissing%columns)*64,y=(firstMissing/columns)*64
        let sampled=try render(.init(x:x,y:y,width:1,height:1))
        let implicit=d.depth == .f32 ? sampled.linearPixel(x:x,y:y):sampled.pixel(x:x,y:y)
        template=try template.mappedStoredSamples {_ in implicit}
      }
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

  /// Exhaustive pointwise eligibility: every missing tile has the same samples.
  /// Spatial/dithered/affine/rich sources keep complete patch evaluation.
  private static func pointwiseSources(_ d: CraftDocument,facts:CompositionFacts) throws -> [Surface]? {
    guard d.videoTimeline == nil else {return nil}
    var sources:[Surface]=[]
    for layer in d.layers {
      guard layer.style==nil,layer.smartObject?.pdfSource==nil,layer.smartFilters==nil,layer.warp==nil,
        layer.blendMode != .dissolve,layer.coordinateTransform == .identity else {return nil}
      if let vector=layer.vectorMask,vector.enabled {
        guard vector.feather==0,d.width>Surface.maximumDensePixels/d.height else {return nil}
        if let source=try facts.mask(layer)?.vectorTileSource {sources.append(source)}
      }
      if let mask=layer.mask,layer.effectiveMaskProperties.enabled {
        guard mask.width==d.width,mask.height==d.height,
          layer.maskCoordinateTransform == .identity,layer.effectiveMaskProperties.feather==0 else {return nil}
        sources.append(mask)
      }
      switch layer.content {
      case .raster(let surface):
        guard surface.width==d.width,surface.height==d.height else {return nil}
        sources.append(surface)
      case .fill:break
      case .group(let group):
        guard group.frame==nil,group.artboard==nil else {return nil}
      case .adjustment(let adjustment):
        switch adjustment {
        case .modern(let value):if value.needsNeighborhood || value.variesWithPosition {return nil}
        case .colorLookup,.gradientMap:return nil
        case .levels,.curves,.hueSaturation,.colorBalance,.classic,.tonalSteps,
          .exposure,.brightnessContrast,.saturation,.invert,.grayscale:break
        }
      case .text,.shape,.gradientFill,.patternFill:return nil
      }
    }
    return sources
  }

  private struct TileKeys:Sequence {
    let sources:[Surface]
    init(_ sources:[Surface]) {self.sources=sources}
    func makeIterator()->AnyIterator<Int> {
      var iterators=sources.map {$0.storedTileKeys.makeIterator()}
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
