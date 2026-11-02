import Foundation

public struct TrimOptions: Codable, Equatable, Sendable {
  public enum Basis: String, Codable, CaseIterable, Sendable { case transparent, topLeft, bottomRight }
  public var basis: Basis = .topLeft
  public var top = true, left = true, bottom = true, right = true
  public init(basis: Basis = .topLeft) { self.basis = basis }
  public var hasEdges: Bool { top || left || bottom || right }
  public func bounds(in pixels: Surface) throws -> IntRect {
    guard hasEdges else { return .init(x:0,y:0,width:pixels.width,height:pixels.height) }
    let raw = try pixels.interpretingSamples(as:.sRGB)
    let reference = basis == .bottomRight ? raw.pixel(x:pixels.width-1,y:pixels.height-1) : raw.pixel(x:0,y:0)
    let content:IntRect?
    if basis == .transparent {content=try pixels.contentBounds()}else{content=try raw.matchingBounds{$0 != reference}}
    guard let content else { throw CraftError.invalid("No image content would remain after trimming.") }
    return bounds(content:content,width:pixels.width,height:pixels.height)
  }
  public func bounds(content: IntRect,width:Int,height:Int) -> IntRect {
    let x = left ? content.x:0, y = top ? content.y:0
    let x1 = right ? content.x+content.width:width, y1 = bottom ? content.y+content.height:height
    return .init(x:x,y:y,width:x1-x,height:y1-y)
  }
}
public enum CanvasEdgeOperation: Codable, Equatable, Sendable {
  case trim(TrimOptions), revealAll
  public var label: String { switch self {case .trim:"Trim";case .revealAll:"Reveal All"} }
}
public struct CanvasEdgesEdit: Sendable {
  public let source: CraftDocument, result: CraftDocument
  public let operation: CanvasEdgeOperation
  public let background: Pixel
  public init(source:CraftDocument,result:CraftDocument,operation:CanvasEdgeOperation,background:Pixel = .white){self.source=source;self.result=result;self.operation=operation;self.background=background}
  public func applied(to document:CraftDocument)throws->CraftDocument {
    try Task.checkCancellation()
    guard document == source, result.id == source.id else {throw CraftError.invalid("The document changed before the canvas edit could commit.")}
    try result.validate();return result
  }
}
public enum CanvasFrameGeometry {
  public static func reframed(_ source:CraftDocument,bounds:IntRect,background:Pixel = .white)throws->CraftDocument {
    guard (-1_000_000...1_000_000).contains(bounds.x),(-1_000_000...1_000_000).contains(bounds.y) else{throw CraftError.invalid("Canvas origin exceeds supported coordinates.")}
    _ = try Surface(width:bounds.width,height:bounds.height,depth:source.depth)
    guard background.isFinite,background.a == 1 else {throw CraftError.invalid("Canvas background must be an opaque finite color.")}
    if bounds == IntRect(x:0,y:0,width:source.width,height:source.height){return source}
    guard source.animation == nil, source.videoTimeline == nil else {throw CraftError.unsupported("Canvas edges need frame and Timeline source rebasing for temporal documents.")}
    let dx = -bounds.x,dy = -bounds.y,delta=Transform2D.translation(Double(dx),Double(dy))
    var result=source
    result.width=bounds.width;result.height=bounds.height
    for i in result.layers.indices {
      try Task.checkCancellation();let old=source.layers[i]
      DocumentGeometry.freezeTextLayout(&result.layers[i],document:source)
      result.layers[i].x += dx;result.layers[i].y += dy
      result.layers[i].smartFilters?.transformPuppetPins(delta);result.layers[i].smartFilters?.transformPerspectivePlanes(delta)
      if let stack=old.smartFilters {result.layers[i].smartFilters?.maskProperties.transform=delta*stack.maskProperties.transform}
      if case .patternFill(var fill)=old.content {try fill.transform(by:delta);result.layers[i].content = .patternFill(fill)}
      if case .gradientFill(var fill)=old.content {try fill.transform(by:delta);result.layers[i].content = .gradientFill(fill)}
      if let mask=old.vectorMask {result.layers[i].vectorMask?.path=mask.path.transformed(delta)}
      if old.isBackground,let native=old.nativeMode {
        let plane=try native.reframedExactly(bounds:bounds,background:background)
        result.layers[i].nativeMode=plane;result.layers[i].content = .raster(try plane.surface())
        result.layers[i].x=0;result.layers[i].y=0;result.layers[i].affine=nil
      } else if old.isBackground,case .raster(let pixels)=old.content {
        result.layers[i].content = .raster(try pixels.reframedExactly(bounds:bounds,fill:background))
        result.layers[i].x=0;result.layers[i].y=0;result.layers[i].affine=nil
      }
    }
    if let origin=source.artboardOrigin {result.artboardOrigin = .init(x:origin.x-dx,y:origin.y-dy)}
    result.transformSavedPaths(by:delta);try result.mapGuides(delta)
    try result.mapSelection(from:source,by:delta);try result.transformChannels(from:source,by:delta)
    rebaseComps(from:source,in:&result)
    try result.validate();try Task.checkCancellation();return result
  }
  public static func rebaseComps(from source:CraftDocument,in result:inout CraftDocument) {
    guard var comps=result.layerComps else{return}
    let old=Dictionary(uniqueKeysWithValues:source.layers.map{($0.id,$0)})
    let shifts=Dictionary(uniqueKeysWithValues:result.layers.compactMap{layer -> (UUID,(Int,Int))? in
      guard let before=old[layer.id] else{return nil};return(layer.id,(layer.x-before.x,layer.y-before.y))})
    func moved(_ values:[LayerCompLayerState])->[LayerCompLayerState] {values.map{value in
      var value=value;if let d=shifts[value.layerID] {if let x=value.x{value.x=x+d.0};if let y=value.y{value.y=y+d.1}};return value}}
    for i in comps.comps.indices {comps.comps[i].layers=moved(comps.comps[i].layers)}
    if let last=comps.lastDocumentState {comps.lastDocumentState=moved(last)}
    result.layerComps=comps
  }
}
