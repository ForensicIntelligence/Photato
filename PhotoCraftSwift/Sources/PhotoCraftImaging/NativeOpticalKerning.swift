import AppKit
import CoreText
import PhotoCraftCore

/// Native outline profiles and fitted pair spacing ported from PhotoCraft's
/// crates/text/src/optical.rs (MIT OR Apache-2.0). Full Photoshop equality is unqualified.
public enum NativeOpticalKerning {
  public struct Profile:Equatable,Sendable {
    public var left:[Float?],right:[Float?]
    public var advance:Float
    public init(left:[Float?],right:[Float?],advance:Float){self.left=left;self.right=right;self.advance=advance}
  }
  public static let samples=48
  public static func sampleY(_ i:Int)->Float{-0.25+1.25*(Float(i)+0.5)/Float(samples)}
  public static func features(_ left:Profile,_ right:Profile)->(Float,Float)? {
    guard left.left.count==samples,left.right.count==samples,right.left.count==samples,right.right.count==samples else{return nil}
    var gaps:[Float]=[]
    for i in 0..<samples where sampleY(i)>=(-0.1) && sampleY(i)<=1 {
      if let a=left.right[i],let b=right.left[i],a.isFinite,b.isFinite {gaps.append(a+b)}
    }
    guard let minimum=gaps.min() else{return nil}
    let excess=gaps.reduce(Float(0)){$0+min($1-minimum,0.04)}/Float(gaps.count)
    return (minimum,excess)
  }
  public static func sizeAdjustment(_ size:Float)->Float {
    guard size.isFinite,size>0 else{return 0};return 11*log(95/min(95,max(15,size)))
  }
  public static func kern(features f:(Float,Float),reference r:(Float,Float))->Float {
    let first:Float = -0.0033+0.5384*(r.0-f.0)
    let second:Float = first+0.5526*(r.1-f.1)
    let value:Float = (second + (-0.1612)*(min(r.0,0.1)-min(f.0,0.1)))*1000
    return value.isFinite ? min(400,max(-400,value)):0
  }
  public static func profile(font original:CTFont,glyph:CGGlyph)->Profile? {
    var matrix=CGAffineTransform.identity
    let font=CTFontCreateCopyWithAttributes(original,1,&matrix,nil)
    guard let path=CTFontCreatePathForGlyph(font,glyph,nil) else{return nil}
    var advance=CGSize.zero,g=glyph;CTFontGetAdvancesForGlyphs(font,.horizontal,&g,&advance,1)
    struct Point {var x:Float,y:Float}
    var segments:[(Point,Point)]=[],at=Point(x:0,y:0),start=at
    func line(_ point:Point){segments.append((at,point));at=point}
    path.applyWithBlock{element in
      let e=element.pointee
      func p(_ i:Int)->Point{.init(x:Float(e.points[i].x),y:Float(e.points[i].y))}
      switch e.type {
      case .moveToPoint:at=p(0);start=at
      case .addLineToPoint:line(p(0))
      case .addQuadCurveToPoint:
        let first=at,c=p(0),end=p(1)
        for i in 1...8{let t=Float(i)/8,u:Float=1-t;line(.init(x:u*u*first.x+2*u*t*c.x+t*t*end.x,y:u*u*first.y+2*u*t*c.y+t*t*end.y))}
      case .addCurveToPoint:
        let first=at,c0=p(0),c1=p(1),end=p(2)
        for i in 1...12 {let t=Float(i)/12,u:Float=1-t,a=u*u*u,b:Float=3*u*u*t,c:Float=3*u*t*t,d=t*t*t;line(.init(x:a*first.x+b*c0.x+c*c1.x+d*end.x,y:a*first.y+b*c0.y+c*c1.y+d*end.y))}
      case .closeSubpath:if at.x != start.x || at.y != start.y{line(start)}
      @unknown default:break
      }
    }
    var left=[Float?](repeating:nil,count:samples),right=left
    for i in 0..<samples {
      let y=sampleY(i);var low=Float.infinity,high = -Float.infinity
      for (a,b) in segments where (a.y<=y && y<b.y) || (b.y<=y && y<a.y) {
        let x=a.x+(b.x-a.x)*(y-a.y)/(b.y-a.y);low=min(low,x);high=max(high,x)
      }
      if low.isFinite,high.isFinite{left[i]=low;right[i]=Float(advance.width)-high}
    }
    return .init(left:left,right:right,advance:Float(advance.width))
  }
  /// Install spacing on cluster boundaries before TextKit performs line layout.
  static func apply(to string:NSMutableAttributedString,stylesKey:NSAttributedString.Key,dpi:Double)throws {
    guard string.length>1 else{return}
    let line=CTLineCreateWithAttributedString(string),runs=CTLineGetGlyphRuns(line)as! [CTRun]
    for run in runs {
      let attrs=CTRunGetAttributes(run)as! [String:Any]
      guard let data=attrs[stylesKey.rawValue]as?Data,let style=try? JSONDecoder().decode(TypeStyle.self,from:data),style.characterFormatting?.kerning == .optical,let rawFont=attrs[kCTFontAttributeName as String] else{continue}
      let font=rawFont as! CTFont
      let count=CTRunGetGlyphCount(run);guard count>1 else{continue}
      var glyphs=[CGGlyph](repeating:0,count:count),indices=[CFIndex](repeating:0,count:count)
      CTRunGetGlyphs(run,.init(location:0,length:0),&glyphs);CTRunGetStringIndices(run,.init(location:0,length:0),&indices)
      var reference:(Float,Float)?
      for character:UniChar in [111,79,110,72] {
        var code=character,glyph:CGGlyph=0
        if CTFontGetGlyphsForCharacters(font,&code,&glyph,1),let round=profile(font:font,glyph:glyph),let pair=features(round,round){reference=pair;break}
      }
      guard let reference else{continue}
      var cache:[CGGlyph:Profile]=[:]
      for i in 0..<(count-1) where indices[i]>=0 && indices[i]<string.length && indices[i+1] != indices[i] {
        let a=glyphs[i],b=glyphs[i+1];let left=cache[a] ?? profile(font:font,glyph:a),right=cache[b] ?? profile(font:font,glyph:b)
        if let left{cache[a]=left};if let right{cache[b]=right}
        guard let left,let right,let f=features(left,right) else{continue}
        let old=(string.attribute(.kern,at:indices[i],effectiveRange:nil)as?NSNumber)?.doubleValue ?? 0
        let amount=Double(kern(features:f,reference:reference)+sizeAdjustment(Float(style.size)))*style.size*dpi/72/1000*style.horizontalScale
        string.addAttribute(.kern,value:old+amount,range:NSRange(location:indices[i],length:1))
      }
    }
  }
}
