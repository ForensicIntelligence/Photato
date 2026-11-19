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
    let complete=IntRect(x:0,y:0,width:d.width,height:d.height)
    let facts=CompositionFacts(d, vectorViewport: region)
    if region == complete, inputTarget == nil, video == nil, !forLayerOutput,
      let plan = RectangleFeatherPlan(d) {
      return try plan.composite(d, facts: facts, onPatch: onPatch)
    }
    var reachedInput=false
    func render(_ rect:IntRect) throws -> Surface {
      do {return try Renderer.compositePrepared(d,region:rect,inputTarget:inputTarget,video:video,facts:facts,forLayerOutput:forLayerOutput)}
      catch let captured as AdjustmentInputReached {reachedInput=true;return captured.surface}
    }
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

  /// If a tile's entire Feather cache footprint stays on one side of an edge,
  /// it can reuse a result from the same zone and cache phase on that axis.
  /// Aligned raster tiles are exceptions and always render at their own addresses.
  private struct RectangleFeatherPlan {
    private enum Zone: Hashable {
      case before, inside(Int), after, boundary(Int)
    }

    private struct Axis {
      let classes: [Int]
      let counts: [Int]
      let representative: Int

      init(length: Int, bounds: [(start: Int, length: Int, margin: Int, phaseCount: Int)]) {
        let side = Surface.tileSide
        let count = (length + side - 1) / side
        let edge = bounds.map(\.phaseCount).max()! * side
        var identifiers: [[Zone]: Int] = [:]
        var ids: [Int] = [], frequencies: [Int] = [], first: [Int] = []
        for index in 0..<count {
          let start = index * side, end = min(start + side, length)
          let signature: [Zone]
          if start < edge || end > length - edge {
            // The partial cache tiles at a canvas edge can have a different footprint.
            signature = [.boundary(index)]
          } else {
            signature = bounds.map { bound in
              let left = start - bound.margin, right = end + bound.margin
              let last = bound.start + bound.length
              if right <= bound.start { return .before }
              if left >= last { return .after }
              if left >= bound.start && right <= last { return .inside(index % bound.phaseCount) }
              return .boundary(index)
            }
          }
          let id = identifiers[signature] ?? frequencies.count
          if id == frequencies.count {
            identifiers[signature] = id
            frequencies.append(0)
            first.append(index)
          }
          ids.append(id)
          frequencies[id] += 1
        }
        classes = ids
        counts = frequencies
        representative = first[frequencies.indices.max(by: { frequencies[$0] < frequencies[$1] })!]
      }
    }

    private let x: Axis
    private let y: Axis
    private let exceptions: [AnySequence<Int>]

    init?(_ document: CraftDocument) {
      guard document.videoTimeline == nil,
        document.layers.allSatisfy({ !$0.isGroup && !$0.isClipped && $0.parentID == nil })
      else { return nil }
      let visible = document.layers.filter { $0.visible && $0.opacity > 0 }
      var shapes: [(rect: IntRect, margin: Int, phaseCount: Int)] = []
      var sources: [AnySequence<Int>] = []
      var hasFill = false
      for layer in visible {
        guard layer.style == nil, layer.smartObject == nil, layer.smartFilters == nil,
          layer.sourceProjection == nil, layer.coordinateTransform == .identity, layer.blendMode != .dissolve
        else { return nil }
        if let vector = layer.vectorMask, vector.enabled, vector.density > 0 {
          guard vector.feather > 0, let rect = VectorRasterizer.integerRectangle(vector.path) else { return nil }
          let cacheSide = FeatheredMask.vectorTileSide(radius: vector.feather)
          let margin = Int(MaskSampler.featherDamageRadius(vector.feather)) + cacheSide + 1
          shapes.append((rect, margin, cacheSide / Surface.tileSide))
        }
        if let mask = layer.mask, layer.effectiveMaskProperties.enabled {
          guard mask.width == document.width, mask.height == document.height,
            layer.effectiveMaskProperties.feather == 0, layer.maskCoordinateTransform == .identity
          else { return nil }
          if mask.tileCount > 0 { sources.append(mask.storedTileKeys) }
        }
        switch layer.content {
        case .fill: hasFill = true
        case .raster(let surface):
          guard surface.width == document.width, surface.height == document.height else { return nil }
          if surface.tileCount > 0 { sources.append(surface.storedTileKeys) }
        default: return nil
        }
      }
      guard !shapes.isEmpty, shapes.count <= 32 else { return nil }
      // Small, narrowly feathered masks can still take the dense rasterizer.
      // Large canvases and wide Feather both prepare a bounded vector plane.
      if !hasFill, document.depth == .f32, let bottom = visible.first?.vectorMask,
        bottom.enabled, bottom.density > 0, bottom.feather > 0, bottom.feather <= 100,
        document.width <= Surface.maximumDensePixels / document.height
      { return nil }
      x = Axis(length: document.width, bounds: shapes.map { ($0.rect.x, $0.rect.width, $0.margin, $0.phaseCount) })
      y = Axis(length: document.height, bounds: shapes.map { ($0.rect.y, $0.rect.height, $0.margin, $0.phaseCount) })
      exceptions = sources
    }

    func composite(_ document: CraftDocument, facts: CompositionFacts,
      onPatch: ((Int) -> Void)?
    ) throws -> Surface {
      let side = Surface.tileSide, columns = x.classes.count
      let seedX = x.representative * side, seedY = y.representative * side
      let seed = try Renderer.compositePrepared(document,
        region: IntRect(x: seedX, y: seedY, width: 1, height: 1), facts: facts)
      let implicit = document.depth == .f32 ? seed.linearPixel(x: seedX, y: seedY) : seed.pixel(x: seedX, y: seedY)
      let template = try Renderer.emptyCanvas(document).mappedStoredSamples { _ in implicit }
      let builder = try Surface.PagedBuilder(template: template)
      var patches = 0
      func render(column: Int, row: Int) throws -> Surface.PagedBuilder.PreparedTile {
        let px = column * side, py = row * side
        let rect = IntRect(x: px, y: py, width: min(side, document.width - px), height: min(side, document.height - py))
        let surface = try Renderer.compositePrepared(document, region: rect, facts: facts)
        let tile = try builder.prepareTile(surface.cropped(to: rect))
        patches += 1
        onPatch?(patches)
        return tile
      }
      var runs: [Range<Int>] = []
      var begin = 0
      for column in 1..<columns where x.classes[column] != x.classes[begin] {
        runs.append(begin..<column)
        begin = column
      }
      runs.append(begin..<columns)
      var cache: [Int: Surface.PagedBuilder.PreparedTile] = [:]
      let keys = TileKeys(exceptions).makeIterator()
      var next = keys.next()
      for (row, yClass) in y.classes.enumerated() {
        try Task.checkCancellation()
        let rowStart = row * columns
        var rowCache: [Int: Surface.PagedBuilder.PreparedTile] = [:]
        for run in runs {
          let xClass = x.classes[run.lowerBound]
          let key = yClass * x.counts.count + xClass
          var ordinary = cache[key] ?? rowCache[xClass]
          var column = run.lowerBound
          while column < run.upperBound {
            if next == rowStart + column {
              try builder.append(render(column: column, row: row), row: row, columns: column..<(column + 1))
              next = keys.next()
              column += 1
              continue
            }
            let end = min(run.upperBound, next.map { $0 - rowStart } ?? run.upperBound)
            if ordinary == nil {
              let tile = try render(column: column, row: row)
              ordinary = tile
              if cache.count < 4_096 && y.counts[yClass] > 1 {
                cache[key] = tile
              } else if x.counts[xClass] > run.count {
                rowCache[xClass] = tile
              }
            }
            try builder.append(ordinary!, row: row, columns: column..<end)
            column = end
          }
        }
      }
      return try builder.finish()
    }
  }
}
