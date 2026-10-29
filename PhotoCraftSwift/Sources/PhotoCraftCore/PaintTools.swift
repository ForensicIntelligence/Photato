import Foundation

public enum PaintTool: String, Codable, CaseIterable, Sendable {
  case brush, pencil, colorReplacement, mixerBrush, patternStamp, backgroundEraser, magicEraser
  public var title: String {
    switch self {
    case .brush: "Brush"; case .pencil: "Pencil"; case .colorReplacement: "Color Replacement"
    case .mixerBrush: "Mixer Brush"; case .patternStamp: "Pattern Stamp"
    case .backgroundEraser: "Background Eraser"; case .magicEraser: "Magic Eraser"
    }
  }
}
public enum PaintSampling: String, Codable, CaseIterable, Sendable { case continuous, once, backgroundSwatch }
public enum PaintLimits: String, Codable, CaseIterable, Sendable { case discontiguous, contiguous, findEdges }
public struct PaintToolOptions: Codable, Equatable, Sendable {
  public var autoErase = false
  public var sampling = PaintSampling.continuous
  public var limits = PaintLimits.contiguous
  public var tolerance = 0.3
  public var replacementMode = BlendMode.color
  public var antiAlias = true
  public var protectForeground = false
  public var sampleAllLayers = false
  public var contiguous = true
  public var wet = 0.5
  public var load = 0.5
  public var mix = 0.5
  public var flow = 1.0
  public var loadAfterStroke = true
  public var cleanAfterStroke = true
  public var loadSolidColorOnly = false
  public var aligned = true
  public var impressionist = false
  public var placement = PatternPlacement()
  public init() {}
  public static func defaults(for tool: PaintTool) -> Self {
    var v = Self(); if tool == .backgroundEraser { v.tolerance = 0.5 }
    if tool == .magicEraser { v.tolerance = 32.0 / 255 }; return v
  }
  public func validate() throws {
    guard [tolerance,wet,load,mix,flow].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
      [.hue,.saturation,.color,.luminosity].contains(replacementMode)
    else { throw CraftError.invalid("Invalid painting tool settings.") }
    try placement.validate()
  }
}
/// Session paint, never document content. Commit only after a successful edit.
public struct MixerPaint: Codable, Equatable, Sendable {
  public var reservoir: Pixel?
  public var amount: Double = 0
  public var pickup: Pixel?
  public var tip: Surface?
  public init() {}
  public mutating func load(_ color: Pixel, tip: Surface? = nil) {
    reservoir = color; amount = 1; self.tip = tip
  }
  public mutating func clean() { reservoir = nil; pickup = nil; tip = nil; amount = 0 }
  public func validate() throws {
    guard amount.isFinite,(0...1).contains(amount),reservoir?.isFinite != false,pickup?.isFinite != false,
      reservoir.map({(0...1).contains($0.a)}) != false,pickup.map({(0...1).contains($0.a)}) != false
    else { throw CraftError.invalid("Invalid Mixer Brush paint.") }
    if let tip { guard tip.width <= 256,tip.height <= 256 else { throw CraftError.invalid("Mixer load is limited to 256 pixels per edge.") };try tip.validated() }
  }
}
public enum PaintTarget: Equatable, Sendable {
  case pixels(UUID), layerMask(UUID), smartFilterMask(UUID), channel(ChannelPlaneTarget)
  public var layerID: UUID? {
    switch self { case .pixels(let id),.layerMask(let id),.smartFilterMask(let id): id; case .channel: nil }
  }
  public var isPixels: Bool { if case .pixels = self { return true };return false }
}
public struct PaintToolRequest: Sendable {
  public var tool: PaintTool
  public var target: PaintTarget
  public var points: [StrokePoint]
  public var brush: Brush
  public var options: PaintToolOptions
  public var pattern: RasterPattern?
  public var mixer = MixerPaint()
  public var newLayerID = UUID()
  public init(tool: PaintTool,target: PaintTarget,points: [StrokePoint],brush: Brush,options: PaintToolOptions? = nil) {
    self.tool=tool;self.target=target;self.points=points;self.brush=brush;self.options=options ?? .defaults(for:tool)
  }
  public func validate() throws {
    try BrushPainter.validate(brush,points:points);try options.validate();try mixer.validate()
    if tool == .patternStamp { guard let pattern else { throw CraftError.invalid("Choose a pattern before painting.") };try pattern.validate() }
    if tool == .magicEraser && points.count != 1 { throw CraftError.invalid("Magic Eraser requires one click.") }
    if !target.isPixels && [.colorReplacement,.backgroundEraser,.magicEraser].contains(tool) {
      throw CraftError.unsupported("This color-aware tool requires an ordinary pixel layer.")
    }
    if !target.isPixels && options.sampleAllLayers { throw CraftError.unsupported("Sample All Layers requires a pixel-layer target.") }
  }
}
public struct PaintingSessionResult: Sendable {
  public var tool: PaintTool
  public var mixer: MixerPaint
  public var patternOrigin: PathPoint?
  public var patternID: String? = nil
}
/// Frozen preview and final edit share exactly the same native preparation.
public struct PaintingEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let request: PaintToolRequest
  public let session: PaintingSessionResult
  public var label: String { request.tool.title }
  public func applied(to document: CraftDocument) throws -> CraftDocument {
    guard document == source else { throw CraftError.invalid("Document changed during painting.") }
    try Task.checkCancellation();try result.validate();return result
  }
  public static func prepare(_ request: PaintToolRequest,in document: CraftDocument,sample: Surface? = nil) throws -> Self {
    try request.validate();try Task.checkCancellation()
    var d=document,brush=request.brush,mixer=request.mixer,origin:PathPoint?
    if request.points.isEmpty || (request.tool == .magicEraser && request.points.first.map({$0.x<0 || $0.y<0 || $0.x>=Double(d.width) || $0.y>=Double(d.height)}) == true) {
      return .init(source:document,result:document,request:request,session:.init(tool:request.tool,mixer:mixer,patternOrigin:nil))
    }
    brush.settings=brush.settings ?? .init();brush.erase=false
    if request.tool == .pencil { brush.settings!.aliased=true;brush.hardness=1;brush.settings!.flow=1;brush.settings!.buildUp=false }
    let target=request.target
    // Sampled Mixer loads and pattern resources remain immutable during preview.
    func paint(_ surface:inout Surface,_ transform:Transform2D,_ gray:Bool,_ preserve:Bool) throws {
      if gray {brush.color=PaintToolPainter.gray(brush.color);brush.backgroundColor=PaintToolPainter.gray(brush.backgroundColor ?? .white)}
      if request.tool == .brush || request.tool == .pencil {
        if request.options.autoErase,request.tool == .pencil,let first=request.points.first {
          let p=try transform.inverted().point(first.x,first.y),c=surface.pixel(x:Int(floor(p.x)),y:Int(floor(p.y)))
          let fg=brush.color
          if c.a>0,max(abs(c.r-fg.r),max(abs(c.g-fg.g),abs(c.b-fg.b))) < 1.5/255 { brush.color=brush.backgroundColor ?? .white }
        }
        try Painter.stroke(surface:&surface,points:request.points,brush:brush,selection:d.selection,selectionMask:d.selectionMask,transform:transform,grayscaleMask:gray,preserveTransparency:preserve)
      } else {
        try PaintToolPainter.stroke(surface:&surface,request:request,brush:brush,transform:transform,canvasWidth:d.width,canvasHeight:d.height,selection:d.selection,selectionMask:d.selectionMask,grayscale:gray,preserveTransparency:preserve,sample:sample,mixer:&mixer)
      }
    }
    switch target {
    case .channel(let target):
      var channel=try d.channel(target)
      let inverted=channel.options.display(0) != 0
      func invert(_ surface:inout Surface) {surface.mapPixels{_,_,p in Pixel(1-unit(p.r),1-unit(p.r),1-unit(p.r))}}
      if inverted {invert(&channel.pixels)}
      try paint(&channel.pixels,.identity,true,false)
      if inverted {invert(&channel.pixels)}
      try d.setChannel(channel,at:target)
    case .pixels(let id),.layerMask(let id),.smartFilterMask(let id):
      guard var i=d.layers.firstIndex(where:{$0.id==id}) else { throw CraftError.invalid("Painting target no longer exists.") }
      let raster:Bool;if case .raster=d.layers[i].content { raster=d.layers[i].smartObject == nil } else { raster=false }
      if target.isPixels && !raster && [.brush,.pencil].contains(request.tool) {
        var layer=try NewPixelLayerOptions(name:d.suggestedPixelLayerName).layer(in:d);layer.id=request.newLayerID
        d.activeLayerID=id;try d.insertNewLayer(layer);i=d.layers.firstIndex(where:{$0.id==layer.id})!
      }
      var layer=d.layers[i]
      if target.isPixels {
        guard !d.isImageLocked(layer.id),layer.smartObject == nil,case .raster(var surface)=layer.content else { throw CraftError.invalid("Choose an unlocked ordinary pixel layer for this tool.") }
        // The upstream Background representation is name + position/transparency locks.
        // Require the bottom root layer and canvas bounds to avoid renaming arbitrary layers.
        let background=i==0 && layer.parentID==nil && layer.name=="Background" && layer.protection.contains([.position,.transparency]) && layer.coordinateTransform == .identity && surface.width==d.width && surface.height==d.height
        if background && [.backgroundEraser,.magicEraser].contains(request.tool) { layer.name="Layer 0";layer.protection.subtract([.position,.transparency]) }
        let inherited=d.ancestors(of:layer.id).reduce(LayerProtection()){ $0.union($1.protection) }
        let preserve=layer.protection.union(inherited).locksTransparency
        guard request.tool != .backgroundEraser || !preserve else { throw CraftError.invalid("Unlock transparency before using Background Eraser.") }
        try paint(&surface,layer.coordinateTransform,false,preserve);layer.content = .raster(surface)
      } else {
        guard !d.isLocked(id) else { throw CraftError.invalid("Unlock the layer and its groups before painting its mask.") }
        let smart:Bool;if case .smartFilterMask=target { smart=true;layer=try layer.filterMaskProjection() } else { smart=false }
        try layer.expandMask(for:request.points,brush:brush,clipping:d.selection)
        guard var surface=layer.mask else { throw CraftError.invalid("Create a mask before painting it.") }
        try paint(&surface,layer.maskCoordinateTransform,true,false);layer.mask=surface
        if smart { d.layers[i].smartFilters!.mask=surface;var properties=layer.effectiveMaskProperties;properties.transform=layer.maskCoordinateTransform;d.layers[i].smartFilters!.maskProperties=properties;layer=d.layers[i] }
      }
      d.layers[i]=layer
    }
    if request.tool == .mixerBrush {
      if request.options.cleanAfterStroke { mixer.clean() }
      if request.options.loadAfterStroke { mixer.load(request.mixer.reservoir ?? brush.color,tip:request.mixer.tip) }
    }
    if request.tool == .patternStamp { origin=PathPoint(Double(request.options.placement.phaseX),Double(request.options.placement.phaseY)) }
    // Preview and commit must use the same palette, bit or component samples.
    // Native saves rebuild the display cache from these authoritative samples.
    try d.reconcileModeStorage(from: document)
    try d.validate();try Task.checkCancellation()
    return .init(source:document,result:d,request:request,session:.init(tool:request.tool,mixer:mixer,patternOrigin:origin,patternID:request.pattern?.id))
  }
}
