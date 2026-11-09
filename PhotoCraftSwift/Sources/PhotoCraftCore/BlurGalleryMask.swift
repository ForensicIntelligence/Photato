import Foundation

/// Numeric blur coverage, independent of the image's colors, profile or alpha.
public enum BlurGalleryMask {
  public static func sourceLayer(in document:CraftDocument,layerID:UUID,beforeFilterID:UUID?=nil)throws->Layer {
    guard var layer=document.layers.first(where:{$0.id==layerID}) else {throw CraftError.invalid("Missing Blur Gallery layer.")}
    if let beforeFilterID {
      guard var stack=layer.smartFilters,let index=stack.filters.firstIndex(where:{$0.id==beforeFilterID}),stack.filters[index].filter.kind == .blurGallery else {throw CraftError.invalid("The Blur Gallery Smart Filter is no longer available.")}
      stack.filters=Array(stack.filters.prefix(index));layer.smartFilters=stack
    }
    if layer.smartObject != nil {layer=try SmartFilterEngine.renderedLayer(layer,in:document)}
    guard case .raster=layer.content else {throw CraftError.invalid("Choose a pixel layer or Smart Object for Blur Gallery.")}
    return layer
  }
  public static func value(_ settings:BlurGallerySettings,x:Double,y:Double,width:Int,height:Int)->Double {
    value(settings,x:x,y:y,width:width,height:height,segments:BlurGalleryEngine.segments(settings,width,height))
  }
  private static func value(_ settings:BlurGallerySettings,x:Double,y:Double,width:Int,height:Int,segments:[BlurGalleryEngine.Segment])->Double {
    var coverage=0.0
    for mode in settings.enabled {
      let maximum:Double
      switch mode {
      case .field,.iris,.tiltShift:maximum=settings.pins(mode).map(\.blur).max() ?? 0
      case .spin:maximum=settings.spin.map(\.blurAngle).max() ?? 0
      case .path:maximum=settings.paths.map(\.speed).max() ?? 0
      }
      guard maximum>0 else {continue}
      // A uniform positive field has full normalized coverage exactly. Avoid
      // introducing division roundoff into the mask's constant white proof.
      if mode == .field,let first=settings.field.first,settings.field.allSatisfy({$0.blur==first.blur}) {return 1}
      var amount=BlurGalleryEngine.amount(settings,mode:mode,x:x,y:y,width:width,height:height)
      if mode == .path {
        var sum=0.0,total=0.0
        for segment in segments {
          let dx=segment.b.x-segment.a.x,dy=segment.b.y-segment.a.y,l2=dx*dx+dy*dy
          let t=max(0,min(1,((x-segment.a.x)*dx+(y-segment.a.y)*dy)/l2))
          let ox=x-segment.a.x-dx*t,oy=y-segment.a.y-dy*t,weight=1/(ox*ox+oy*oy+1)
          sum+=weight*segment.speed*(1-segment.taper*(segment.t0+(segment.t1-segment.t0)*t));total+=weight
        }
        amount=total>0 ? sum/total:0
      }
      coverage=max(coverage,max(0,min(1,amount/maximum)))
    }
    return coverage
  }
  /// Sparse document-space mask. Source sampling is bounded like Blur Gallery;
  /// a huge empty canvas does not require a full-canvas dense allocation or scan.
  public static func surface(in document:CraftDocument,layer:Layer,settings:BlurGallerySettings)throws->Surface {
    try Task.checkCancellation();try settings.validate()
    guard !document.colorMode.isRestricted,document.inkMode==nil,document.quickMask==nil,case .raster(let pixels)=layer.content else {throw CraftError.unsupported("Save Blur Mask requires an RGB pixel layer or Smart Object outside Quick Mask.")}
    guard pixels.width<=RasterFilterEngine.maximumPixels/pixels.height else {throw CraftError.unsupported("Blur Gallery currently supports at most 8,388,608 source pixels.")}
    var output=try Surface(width:document.width,height:document.height,depth:document.depth,fill:.black)
    if settings.isIdentity {return try output.retaggedCoverageStorage(depth:document.depth)}
    let transform=layer.coordinateTransform,inverse=try transform.inverted()
    let corners=[PathPoint(0,0),PathPoint(Double(pixels.width),0),PathPoint(0,Double(pixels.height)),PathPoint(Double(pixels.width),Double(pixels.height))].map{$0.transformed(transform)}
    guard corners.allSatisfy({$0.x.isFinite && $0.y.isFinite}) else {throw CraftError.invalid("Invalid Blur Mask transform.")}
    func edge(_ value:Double,_ maximum:Int)->Int {Int(max(0,min(Double(maximum),value)))}
    let x0=edge(floor(corners.map(\.x).min() ?? 0),document.width),x1=edge(ceil(corners.map(\.x).max() ?? 0),document.width)
    let y0=edge(floor(corners.map(\.y).min() ?? 0),document.height),y1=edge(ceil(corners.map(\.y).max() ?? 0),document.height)
    let segments=settings.enabled.contains(.path) ? BlurGalleryEngine.segments(settings,pixels.width,pixels.height):[]
    if x1>x0,y1>y0 {
      guard x1-x0<=RasterFilterEngine.maximumPixels/(y1-y0) else {throw CraftError.unsupported("The transformed Blur Mask footprint exceeds the current 8,388,608-pixel processing limit.")}
      for y in y0..<y1 {try Task.checkCancellation();for x in x0..<x1 {
        let q=PathPoint(Double(x)+0.5,Double(y)+0.5).transformed(inverse)
        guard q.x>=0,q.y>=0,q.x<Double(pixels.width),q.y<Double(pixels.height) else {continue}
        let v=Float(value(settings,x:q.x,y:q.y,width:pixels.width,height:pixels.height,segments:segments))
        if v>0 {output.setPixel(x:x,y:y,Pixel(v,v,v))}
      }}
    }
    return try output.retaggedCoverageStorage(depth:document.depth)
  }
}

/// A filter and its reusable mask publish together, or neither publishes.
/// Saving a channel is an output option, not part of the Smart Filter's pixels.
public struct BlurGalleryMaskEdit:Sendable {
  public var layerID:UUID
  public var settings:BlurGallerySettings
  public var filterID:UUID?
  public var opacity:Float
  public var blendMode:BlendMode
  public var channelID:UUID
  public init(layerID:UUID,settings:BlurGallerySettings,filterID:UUID?=nil,opacity:Float=1,blendMode:BlendMode = .normal,channelID:UUID=UUID()) {
    self.layerID=layerID;self.settings=settings;self.filterID=filterID;self.opacity=opacity;self.blendMode=blendMode;self.channelID=channelID
  }
  public var filter:RasterFilter {var filter=RasterFilter(.blurGallery);filter.gallery=settings;return filter}
  private func updatedStack(in document:CraftDocument)throws->SmartFilterStack {
    guard let filterID,var stack=document.layers.first(where:{$0.id==layerID})?.smartFilters,let index=stack.filters.firstIndex(where:{$0.id==filterID}),stack.filters[index].filter.kind == .blurGallery else {throw CraftError.invalid("The Blur Gallery Smart Filter is no longer available.")}
    stack.filters[index].filter=filter;stack.filters[index].opacity=opacity;stack.filters[index].blendMode=blendMode
    return stack
  }
  public func filterCommand(in document:CraftDocument)throws->Command {
    try settings.validate()
    if filterID != nil {return .smartFilters(layerID,try updatedStack(in:document))}
    return .applyFilter(layerID,filter)
  }
  @inline(never) private func validateTarget(in document:CraftDocument)throws {
    try filterCommand(in:document).validateProtection(in:document)
  }
  @inline(never) private func applyPixels(to document:inout CraftDocument)throws {
    // The outer Command transaction owns document bookkeeping. Calling a second
    // full Command.apply here also nests its large Debug stack frame beneath
    // Smart Filter rendering; use the identical modular pixel engines directly.
    if filterID != nil {try PixelCommandEngine.stack(layerID,updatedStack(in:document),in:&document)}
    else {try PixelCommandEngine.filter(layerID,filter,in:&document)}
  }
  func applied(to document:CraftDocument)throws->CraftDocument {
    try Task.checkCancellation()
    guard (document.alphaChannels?.count ?? 0)<document.auxiliaryChannelLimit else {throw CraftError.invalid("Channel limit reached. Remove a channel before saving a Blur Mask.")}
    try validateTarget(in:document)
    let layer=try BlurGalleryMask.sourceLayer(in:document,layerID:layerID,beforeFilterID:filterID)
    let pixels=try BlurGalleryMask.surface(in:document,layer:layer,settings:settings)
    var candidate=document
    try applyPixels(to:&candidate)
    let names=Set((candidate.alphaChannels ?? []).map(\.name));var name="Blur Mask",suffix=2
    while names.contains(name) {name="Blur Mask \(suffix)";suffix+=1}
    try ChannelCommand.create(AlphaChannel(id:channelID,name:name,pixels:pixels)).apply(to:&candidate)
    try Task.checkCancellation();return candidate
  }
}
