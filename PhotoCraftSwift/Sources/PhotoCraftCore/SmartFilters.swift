import Foundation

/// Application order is bottom to top, matching Photoshop's filter stack.
public struct SmartFilter: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var filter: RasterFilter
  public var enabled: Bool
  public var opacity: Float
  public var blendMode: BlendMode
  public init(id: UUID = UUID(), filter: RasterFilter, enabled: Bool = true,
    opacity: Float = 1, blendMode: BlendMode = .normal) {
    self.id = id; self.filter = filter; self.enabled = enabled
    self.opacity = opacity; self.blendMode = blendMode
  }
}

public struct SmartFilterStack: Codable, Equatable, Sendable {
  public static let maximumFilters = 32
  public var filters: [SmartFilter] = []
  public var programBytes: Int { filters.reduce(0) { $0 + ($1.filter.distortion?.estimatedBytes ?? 0) + ($1.filter.wideAngle?.constraints.reduce(0) { $0 + $1.points.count*32 + $1.segmentCount*24 } ?? 0) + ($1.filter.perspective?.estimatedBytes ?? 0) + ($1.filter.puppet?.estimatedBytes ?? 0) + ($1.filter.liquify?.estimatedBytes ?? 0) + ($1.filter.cameraRaw == nil ? 0 : 4096) } }
  public var enabled = true
  public var mask: Surface?
  /// Unlike layer masks, this transform maps directly into document coordinates.
  public var maskProperties = MaskProperties()
  public init() { maskProperties.linked = false; maskProperties.outside = 1 }
  public func validate() throws {
    guard filters.count <= Self.maximumFilters, Set(filters.map(\.id)).count == filters.count else {
      throw CraftError.invalid("Smart Filters require at most32 uniquely identified filters.")
    }
    for item in filters {
      try item.filter.validate()
      guard item.opacity.isFinite, (0...1).contains(item.opacity) else {
        throw CraftError.invalid("Smart Filter opacity must be between0 and1.")
      }
    }
    try mask?.validated(); try maskProperties.validate()
  }
  public mutating func createMask(in document: CraftDocument, selection: Bool = false, value: Float = 1) throws {
    guard value.isFinite, (0...1).contains(value) else { throw CraftError.invalid("Invalid filter mask value.") }
    var pixels = try Surface(width: document.width, height: document.height, depth: .u8,
      fill: Pixel(value, value, value, 1))
    maskProperties = MaskProperties(); maskProperties.outside = selection ? 0 : value
    maskProperties.linked = selection
    if selection {
      guard document.selection != nil else { throw CraftError.invalid("Create a selection first.") }
      if let coverage=document.selectionMask {pixels=try coverage.coverageSurface()}
      else if let rectangle=document.selection {
        pixels=try Surface.rectangularCoverage(width:document.width,height:document.height,rectangle:rectangle)
      }else{for y in 0..<document.height {
        try Task.checkCancellation()
        for x in 0..<document.width {
          let k = document.selectionCoverage(x: x, y: y)
          pixels.setPixel(x: x, y: y, Pixel(k, k, k, 1))
        }
      }}
    }
    mask = pixels
  }
}

extension Layer {
  /// Projection used exclusively by mask editing and preview, never committed as a layer.
  public func filterMaskProjection() throws -> Layer {
    guard let stack = smartFilters, let mask = stack.mask else { throw CraftError.invalid("This Smart Object has no filter mask.") }
    var layer = self
    layer.mask = mask; layer.maskProperties = stack.maskProperties
    layer.maskProperties?.transform = try coordinateTransform.inverted() * stack.maskProperties.transform
    return layer
  }
}

public enum SmartFilterEngine {
  public static func append(_ filter: RasterFilter, to id: UUID, in document: inout CraftDocument) throws {
    guard let i = document.layers.firstIndex(where: { $0.id == id }) else { throw CraftError.invalid("Missing Smart Object.") }
    if filter.kind == .perspectiveWarp { try PerspectiveEngine.validateTarget(document,layerID:id);if filter.perspective!.planes.isEmpty { return } }
    if filter.kind == .puppetWarp { try PuppetEngine.validateTarget(document,layerID:id); if filter.puppet!.pins.isEmpty { return } }
    var stack = document.layers[i].smartFilters ?? SmartFilterStack()
    if stack.filters.isEmpty, stack.mask == nil { try stack.createMask(in: document, selection: document.selection != nil) }
    stack.filters.append(SmartFilter(filter: filter))
    try set(stack, on: id, in: &document)
  }
  public static func set(_ stack: SmartFilterStack?, on id: UUID, in document: inout CraftDocument) throws {
    guard let i = document.layers.firstIndex(where: { $0.id == id }), document.layers[i].smartObject != nil,
      !document.isImageLocked(id) else { throw CraftError.invalid("Select an unlocked Smart Object for Smart Filters.") }
    guard try document.layers[i].linkedSmartObjectPreview()==nil else{throw CraftError.unsupported("Resolve the linked source before changing Smart Filters.")}
    try stack?.validate()
    var layer = document.layers[i]; layer.smartFilters = stack
    for item in stack?.filters ?? [] {
      try item.filter.lighting?.validateReferences(in:document)
      if let source=item.filter.distortion?.source,source.map==nil,stack != document.layers[i].smartFilters,stack?.enabled==true,item.enabled,item.opacity>0,layer.pristineSmartAppearance?.pixels==nil{throw CraftError.invalid("Bind the original displacement map before changing this active Smart Filter.")}

      if let settings=item.filter.lensBlur {
        if stack?.enabled==true && item.enabled && item.opacity>0 && layer.pristineSmartAppearance?.pixels==nil {
          try settings.validateSources(layer:layer,document:document)
        }else{try settings.validateStoredSources(layer:layer,document:document)}
      }
    }
    if stack?.filters.contains(where: { $0.filter.kind == .puppetWarp || $0.filter.kind == .perspectiveWarp }) == true {
      guard !document.isPositionLocked(id),!document.isTransparencyLocked(id),document.layers[i].vectorMask == nil else { throw CraftError.unsupported("Deformation filters require unlocked position/transparency and no vector mask.") }
    }

    // Admit the render before committing, including transformed size and numeric limits.
    if stack != nil { _ = try renderedLayer(layer, in: document) }
    document.layers[i] = layer
  }
  public static func editMask(_ command: Command, on id: UUID, in document: inout CraftDocument) throws {
    let target: UUID
    switch command {
    case .maskStroke(let id, _, _), .maskFill(let id, _), .invertMask(let id),
      .maskProperties(let id, _), .deleteMask(let id): target = id
    default: throw CraftError.unsupported("This tool is not available on Smart Filter masks yet.")
    }
    guard target == id, let i = document.layers.firstIndex(where: { $0.id == id }),
      document.layers[i].smartObject != nil else { throw CraftError.invalid("Select a Smart Filter mask.") }
    let original = document.layers[i]
    guard try original.linkedSmartObjectPreview()==nil else{throw CraftError.unsupported("Resolve the linked source before changing its Smart Filter mask.")}
    var projected = document
    projected.layers[i] = try original.filterMaskProjection()
    // The projected mask is a filter mask, not the layer-mask depth source.
    projected.layers[i].smartFilters = nil
    try command.apply(to: &projected)
    var result = original
    result.smartFilters?.mask = projected.layers[i].mask
    var properties = projected.layers[i].effectiveMaskProperties
    properties.transform = projected.layers[i].maskCoordinateTransform
    result.smartFilters?.maskProperties = properties
    document.layers[i] = result
  }
  /// Source pixels -> affine placement -> filters -> filter mask. Layer masks and
  /// styles remain outside this pipeline. Derived pixels never replace the source.
  public static func renderedLayer(_ layer: Layer, in document: CraftDocument) throws -> Layer {
    try renderedLayer(layer,in:document,paged:false)
  }
  static func renderedLayer(_ layer:Layer,in document:CraftDocument,paged forcePaged:Bool)throws->Layer {
    guard layer.smartObject != nil else { return layer }
    if let original=try layer.originalSmartAppearanceLayer(){return original}
    if try layer.linkedSmartObjectPreview() != nil {var cached=layer;cached.smartObject=nil;cached.smartFilters=nil;return cached}
    var layer = try WarpRaster.baked(layer, in: document)
    guard let stack = layer.smartFilters else { layer.smartObject = nil; layer.importedSmartAppearance=nil; return layer }
    try stack.validate()
    guard case .raster(let source) = layer.content else { throw CraftError.invalid("Missing Smart Object pixels.") }
    var bounds = try renderBounds(layer, in: document)
    let paged=forcePaged || bounds.width>RasterFilterEngine.maximumPixels/bounds.height
    var x = bounds.x, y = bounds.y
    var base = paged ? try PagedSmartFilterStorage.placed(source,transform:layer.coordinateTransform,bounds:bounds)
      : try RasterGeometry.render(source, transform: layer.coordinateTransform, bounds: bounds, method: .bicubic, clampEdges: true)
    var current = base
    if stack.enabled {
      for item in stack.filters where item.enabled && item.opacity > 0 {
        try Task.checkCancellation()
        let filtered:Surface
        if item.filter.puppet != nil || item.filter.perspective != nil {
          let pixels:Surface,extent:IntRect
          if let perspective=item.filter.perspective { (pixels,extent)=try PerspectiveEngine.render(current,origin:PathPoint(Double(x),Double(y)),settings:perspective) }
          else { (pixels,extent)=try PuppetEngine.render(current,origin:PathPoint(Double(x),Double(y)),settings:item.filter.puppet!) }
          let expanded=try PuppetEngine.union(bounds,extent)
          base=try PuppetEngine.reframe(base,from:bounds,to:expanded)
          current=try PuppetEngine.reframe(current,from:bounds,to:expanded)
          filtered=try PuppetEngine.reframe(pixels,from:extent,to:expanded)
          bounds=expanded;x=bounds.x;y=bounds.y
        } else if let settings=item.filter.distortion,settings.source != nil {
          // Original Smart filters retain references, not a resolved map; their
          // missing-map stage is identity. No external hint is read here.
          if settings.source?.map==nil{filtered=current}
          else{filtered=try DistortionEngine.render(current,kind:item.filter.kind,settings:settings,referenceBounds:IntRect(x:0,y:0,width:document.width,height:document.height),pixelToDocument:.translation(Double(x),Double(y)))}
        } else if let settings=item.filter.lighting {
          guard document.colorMode == .rgb,document.inkMode==nil,document.restrictedMode==nil else{throw CraftError.unsupported("Lighting Effects requires an RGB image target.")}
          try settings.validateReferences(in:document)
          let texture=settings.textureChannelID.flatMap{id in document.alphaChannels?.first{$0.id==id}?.pixels}
          filtered=try LightingEngine.render(current,settings:settings,referenceBounds:IntRect(x:0,y:0,width:document.width,height:document.height),pixelToDocument:.translation(Double(x),Double(y)),texture:texture)
        } else if let settings=item.filter.relight {
          guard document.colorMode == .rgb,document.inkMode==nil,document.restrictedMode==nil else{throw CraftError.unsupported("Relight currently supports RGB editing.")}
          filtered=try RelightEngine.render(current,settings:settings,canvasWidth:document.width,canvasHeight:document.height)
        } else if let settings=item.filter.tone {
          filtered=try ClassicToneEngine.render(current,settings:settings)
        } else if let settings=item.filter.classicDetail {
          filtered=try ClassicDetailEngine.render(current,kind:item.filter.kind,settings:settings,area:IntRect(x:-x,y:-y,width:document.width,height:document.height))
        } else if let settings=item.filter.otherVideo {
          if item.filter.kind == .offset {guard (-2*document.width...2*document.width).contains(settings.horizontal),(-2*document.height...2*document.height).contains(settings.vertical) else {throw CraftError.invalid("Offset exceeds twice the document size.")}}
          filtered=try OtherVideoEngine.render(current,kind:item.filter.kind,settings:settings,area:IntRect(x:-x,y:-y,width:document.width,height:document.height))
        } else if let settings=item.filter.renderSettings {
          filtered=try RenderFilterEngine.render(current,kind:item.filter.kind,settings:settings,canvasWidth:document.width,canvasHeight:document.height,pixelToDocument:.translation(Double(x),Double(y)))
        } else if let settings=item.filter.lensBlur {
          let depth=try LensBlurEngine.depthValues(settings,source:current,layer:layer,document:document,pixelToDocument:.translation(Double(x),Double(y)))
          filtered=try LensBlurEngine.render(current,settings:settings,depth:depth)
        } else {
          var working = try CraftDocument(width: bounds.width, height: bounds.height, depth: document.depth)
          let input = Layer(name: "Filter input", content: .raster(current))
          working.layers = [input]; working.activeLayerID = input.id
          try RasterFilterEngine.apply(item.filter, to: input.id, in: &working)
          guard case .raster(let pixels) = working.layers[0].content else { throw CraftError.invalid("Missing filter result.") };filtered=pixels
        }
        if item.blendMode == .normal && item.opacity == 1 { current = filtered; continue }
        current = try combine(current, filtered,paged:paged,pointwise:item.blendMode != .dissolve) { a, b, px, py in
          item.blendMode.composite(backdrop: a, source: b, opacity: item.opacity, x: px + x, y: py + y)
        }
      }
      if stack.mask != nil {
        let sampler = try MaskSampler(layer: layer.filterMaskProjection(), canvasSize: (document.width, document.height))
        if paged && (current.depth != .f32 || current.colorEncoding == .linearRGB) && sampler.isIdentity(over:bounds) { /* Preserve current. */ }
        else {
        func masked(_ a:Pixel,_ b:Pixel,_ k:Float)->Pixel {
          if k == 0 { return a }; if k == 1 { return b }
          let alpha = a.a * (1 - k) + b.a * k
          guard alpha > 0 else { return .clear }
          let rgb = (a.rgb * a.a * (1 - k) + b.rgb * b.a * k) / alpha
          return Pixel(rgb.x, rgb.y, rgb.z, alpha)
        }
        let projection=try layer.filterMaskProjection(),mask=stack.mask!
        let pointwise=stack.maskProperties.feather==0 && mask.width==bounds.width && mask.height==bounds.height
          && projection.maskCoordinateTransform == .translation(Double(x),Double(y))
        var implicit:((Pixel,Pixel)->Pixel)?
        if pointwise {
          var raw=projection;raw.mask=try mask.reframedImplicitValue(width:mask.width,height:mask.height)
          let prepared=try MaskSampler(layer:raw,canvasSize:(document.width,document.height))
          let k=prepared.coverage(x:Double(x)+0.5,y:Double(y)+0.5)
          implicit={a,b in masked(a,b,k)}
        }
        current = try combine(base,current,paged:paged,pointwise:pointwise,extraSources:pointwise ? [mask]:[],implicitOperation:implicit) {a,b,px,py in
          masked(a,b,sampler.coverage(x:Double(px+x)+0.5,y:Double(py+y)+0.5))
        }
        }
      }
    }
    var result = layer
    result.content = .raster(current); result.x = x; result.y = y; result.affine = nil
    result.smartObject = nil; result.smartFilters = nil
    result.importedSmartAppearance = nil
    if layer.mask != nil {
      result.maskProperties = layer.effectiveMaskProperties
      let mapping = try result.coordinateTransform.inverted() * layer.maskCoordinateTransform
      result.maskProperties?.transform = mapping
    }
    return result
  }
  public static func renderBounds(_ layer: Layer, in document: CraftDocument) throws -> IntRect {
    if let cached=try layer.originalSmartAppearanceLayer(),case .raster(let pixels)=cached.content{return try cached.coordinateTransform.bounds(width:pixels.width,height:pixels.height)}
    guard case .raster(let source) = layer.content else { throw CraftError.invalid("Missing Smart Object source pixels.") }
    let placed = try layer.sourceProjection.map{try $0.followed(by:layer.coordinateTransform).bounds(width:source.width,height:source.height)} ?? layer.coordinateTransform.bounds(width: source.width, height: source.height)
    let x = min(0, placed.x), y = min(0, placed.y)
    let bounds = IntRect(x: x, y: y, width: max(document.width, placed.x + placed.width) - x,
      height: max(document.height, placed.y + placed.height) - y)
    _ = try Surface(width:bounds.width,height:bounds.height)
    if bounds.width > RasterFilterEngine.maximumPixels / bounds.height {
      guard layer.smartObject != nil,document.colorMode == .rgb,document.inkMode==nil,document.restrictedMode==nil,layer.warp==nil,
        layer.smartFilters?.enabled != true || layer.smartFilters!.filters.allSatisfy({!$0.enabled || $0.opacity==0 || RasterFilterEngine.pagedFilterKinds.contains($0.filter.kind)}) else {
        throw CraftError.unsupported("Large Smart Filters currently support the eight basic RGB filters without Warp; other families retain separate preparation limits.")
      }
      if let stack=layer.smartFilters,let mask=stack.mask,stack.maskProperties.enabled,stack.maskProperties.feather>0 {
        let pad=2*Int(ceil(3*max(0.05,stack.maskProperties.feather)))
        guard mask.width+pad<=Surface.maxDimension,mask.height+pad<=Surface.maxDimension,
          mask.width+pad<=Surface.maximumDensePixels/(mask.height+pad) else {
          throw CraftError.unsupported("This Smart Filter mask still requires bounded feather preparation.")
        }
      }
    }
    return bounds
  }
  private static func combine(_ a: Surface, _ b: Surface,paged:Bool,pointwise:Bool,extraSources:[Surface]=[],
    implicitOperation:((Pixel,Pixel)->Pixel)?=nil,operation: (Pixel, Pixel, Int, Int) -> Pixel) throws -> Surface {
    if paged {return try PagedSmartFilterStorage.combine(a,b,pointwise:pointwise,extraSources:extraSources,implicitOperation:implicitOperation,operation:operation)}
    var result = a
    for y in 0..<a.height {
      try Task.checkCancellation()
      for x in 0..<a.width {
        let p = operation(a.depth == .f32 ? a.linearPixel(x: x, y: y) : a.pixel(x: x, y: y),
          b.depth == .f32 ? b.linearPixel(x: x, y: y) : b.pixel(x: x, y: y), x, y)
        if a.depth == .f32 { result.setLinearPixel(x: x, y: y, p) } else { result.setPixel(x: x, y: y, p) }
      }
    }
    return result
  }
}
