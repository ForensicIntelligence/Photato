import AppKit
import CoreText
import PhotoCraftCore

/// The same bounded polyline is used for path drawing and insertion hit tests.
public struct PathTextBaseline:Sendable {
  public let points:[PathPoint]
  public let distances:[Double]
  public var length:Double{distances.last ?? 0}
  public init(_ component:PathComponent,reverse:Bool=false)throws {
    try VectorPath(components:[component]).validate()
    var points=try PathConstruction.flattened(component,tolerance:0.05)
    guard points.count>=2 else{throw CraftError.invalid("Text baseline path requires two points.")}
    if reverse{points.reverse()}
    var distances=[Double](repeating:0,count:points.count)
    for i in 1..<points.count{distances[i]=distances[i-1]+hypot(points[i].x-points[i-1].x,points[i].y-points[i-1].y)}
    guard let total=distances.last,total>0.001 else{throw CraftError.invalid("Text baseline path has no length.")}
    self.points=points;self.distances=distances
  }
  public func locate(_ distance:Double)->(point:PathPoint,angle:Double) {
    var lo=0,hi=distances.count-1
    while hi-lo>1{let m=(hi+lo)/2;if distances[m]<=distance{lo=m}else{hi=m}}
    let a=points[lo],b=points[hi],length=max(1e-12,distances[hi]-distances[lo]),t=max(0,min(1,(distance-distances[lo])/length))
    return(.init(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t),atan2(b.y-a.y,b.x-a.x))
  }
  public func nearestFraction(to point:PathPoint,tolerance:Double)->Double? {
    guard point.x.isFinite,point.y.isFinite,tolerance.isFinite,tolerance>=0 else{return nil}
    var best=tolerance*tolerance,result:Double?
    for i in 1..<points.count {
      let a=points[i-1],b=points[i],dx=b.x-a.x,dy=b.y-a.y,l=dx*dx+dy*dy
      guard l>0 else{continue}
      let t=max(0,min(1,((point.x-a.x)*dx+(point.y-a.y)*dy)/l)),x=a.x+t*dx,y=a.y+t*dy
      let d=(point.x-x)*(point.x-x)+(point.y-y)*(point.y-y)
      if d<=best{best=d;result=(distances[i-1]+t*(distances[i]-distances[i-1]))/length}
    }
    return result
  }
}

/// Shared preparation, retaining the renderer's original CoreText/fitting arithmetic.
struct PathTextLine {
  let baseline:PathTextBaseline,attributed:NSAttributedString,line:CTLine
  let scale:Double,align:Double,available:Double,overset:Bool
  init(_ text:TextContent,dpi:Double)throws {
    try text.validate()
    guard let type=text.typography,let geometry=type.geometry,[.path,.circle,.arch,.bow].contains(geometry.mode),
      type.writingOrientation == .horizontal else{throw CraftError.unsupported("Native path editing requires horizontal text on a baseline path.")}
    guard text.text.utf16.count<=ShapedTextLayout.maximumGlyphs else{throw CraftError.invalid("Shaped type supports at most16,384 UTF-16 units.")}
    baseline=try PathTextBaseline(geometry.baselinePath(),reverse:geometry.reverse)
    let lineText=NSMutableAttributedString(attributedString:ShapedTextLayout.adjusted(try NativeTextLayout.attributed(text,dpi:dpi),scale:1,geometry:geometry))
    for i in 0..<lineText.length where (lineText.string as NSString).character(at:i)==10{lineText.replaceCharacters(in:NSRange(location:i,length:1),with:" ")}
    attributed=lineText;line=CTLineCreateWithAttributedString(lineText)
    let width=CTLineGetTypographicBounds(line,nil,nil,nil)
    available=baseline.length*(geometry.end-geometry.start)
    scale=geometry.fit && width>0 ? min(64,available/width):1
    let alignment=type.defaultParagraph.alignment
    align=alignment == .center ? max(0,(available-width*scale)/2):alignment == .right ? max(0,available-width*scale):0
    overset=width*scale>available+0.01
  }
}

public struct PathTextCaret:Equatable,Sendable {
  public var utf16Index:Int
  public var baseline:PathPoint
  public var top:PathPoint
  public var bottom:PathPoint
  public var visible:Bool
}
public struct PathTextEditingGeometry:Sendable {
  public var carets:[PathTextCaret]
  public var baseline:PathTextBaseline
  public var overset:Bool
  public var utf16Count:Int
  public func caret(at index:Int)->PathTextCaret? {
    carets.first{$0.utf16Index==index} ?? carets.last{$0.utf16Index<=index}
  }
  public func insertionIndex(at point:PathPoint)->Int {
    carets.filter(\.visible).min{a,b in
      hypot(a.baseline.x-point.x,a.baseline.y-point.y)<hypot(b.baseline.x-point.x,b.baseline.y-point.y)
    }?.utf16Index ?? 0
  }
  /// Each strip follows grapheme boundaries, avoiding a straight selection box across a curve.
  public func selectionStrips(_ range:NSRange)->[[PathPoint]] {
    guard range.location != NSNotFound,range.location>=0,range.length>0,range.location<=utf16Count,range.length<=utf16Count-range.location else{return []}
    return zip(carets,carets.dropFirst()).compactMap{a,b in
      guard a.visible,b.visible,b.utf16Index>range.location,a.utf16Index<NSMaxRange(range) else{return nil}
      return [a.top,b.top,b.bottom,a.bottom]
    }
  }
}
extension ShapedTextLayout {
  public static func pathEditingGeometry(_ text:TextContent,dpi:Double)throws->PathTextEditingGeometry {
    let prepared=try PathTextLine(text,dpi:dpi),geometry=text.typography!.geometry!
    var ascent:CGFloat=0,descent:CGFloat=0
    _=CTLineGetTypographicBounds(prepared.line,&ascent,&descent,nil)
    if ascent+descent==0 {
      let font=try NativeFonts.font(text.typography!.defaultStyle,dpi:dpi)
      ascent=CTFontGetAscent(font as CTFont);descent=CTFontGetDescent(font as CTFont)
    }
    let string=text.text as NSString
    var indices=[0],index=0
    while index<string.length{index=NSMaxRange(string.rangeOfComposedCharacterSequence(at:index));indices.append(index)}
    let carets=indices.map{index->PathTextCaret in
      let inline=prepared.align+CTLineGetOffsetForStringIndex(prepared.line,index,nil)*prepared.scale
      let location=prepared.baseline.locate(geometry.start*prepared.baseline.length+inline),normal=PathPoint(-sin(location.angle),cos(location.angle))
      let p=PathPoint(location.point.x+normal.x*geometry.offset,location.point.y+normal.y*geometry.offset)
      return .init(utf16Index:index,baseline:p,
        top:.init(p.x-normal.x*Double(ascent)*prepared.scale,p.y-normal.y*Double(ascent)*prepared.scale),
        bottom:.init(p.x+normal.x*Double(descent)*prepared.scale,p.y+normal.y*Double(descent)*prepared.scale),
        visible:inline>=0 && inline<=prepared.available+0.01)
    }
    return .init(carets:carets,baseline:prepared.baseline,overset:prepared.overset,utf16Count:string.length)
  }
}
