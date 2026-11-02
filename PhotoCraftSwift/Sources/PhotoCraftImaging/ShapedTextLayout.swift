import AppKit
import CoreText
import PhotoCraftCore

/// Core Text supplies visual glyph order and actual fallback fonts. Layout instructions
/// remain editable; outlines are temporary render data, never a replacement for the text.
public enum ShapedTextLayout {
  struct Mark {var path:CGPath;var color:NSColor}
  struct Layout {var marks:[Mark];var bounds:CGRect;var overset:Bool;var baseline:Double}
  struct Glyph {var path:CGPath;var position:CGPoint;var advance:Double;var color:NSColor;var cluster:Int}
  static let maximumGlyphs=16_384,maximumPoints=2_000_000

  static func adjusted(_ source:NSAttributedString,scale:Double,geometry:TextGeometry)->NSAttributedString {
    let result=NSMutableAttributedString(attributedString:source)
    source.enumerateAttributes(in:NSRange(location:0,length:source.length)){attrs,range,_ in
      var next=attrs
      if let font=attrs[.font] as? NSFont{next[.font]=CTFontCreateCopyWithAttributes(font as CTFont,font.pointSize*scale,nil,nil) as NSFont}
      for key:NSAttributedString.Key in [.kern,.baselineOffset]{if let n=attrs[key] as? NSNumber{next[key]=n.doubleValue*scale}}
      if let p=(attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
        p.minimumLineHeight *= scale;p.maximumLineHeight *= scale;p.lineSpacing=(p.lineSpacing+geometry.lineSpacing)*scale
        p.paragraphSpacing *= scale;p.paragraphSpacingBefore *= scale;p.headIndent *= scale;p.firstLineHeadIndent *= scale;p.tailIndent *= scale
        next[.paragraphStyle]=p
      }
      result.setAttributes(next,range:range)
    }
    if geometry.wordSpacing != 0 {
      let string=source.string as NSString
      for i in 0..<string.length where string.character(at:i)==32 {
        let current=(result.attribute(.kern,at:i,effectiveRange:nil) as? NSNumber)?.doubleValue ?? 0
        result.addAttribute(.kern,value:current+geometry.wordSpacing*scale,range:NSRange(location:i,length:1))
      }
    }
    return result
  }
  static func glyphs(_ line:CTLine,origin:CGPoint,string:NSString)throws->[Glyph] {
    var result:[Glyph]=[]
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
      let count=CTRunGetGlyphCount(run);guard count<=maximumGlyphs else{throw CraftError.invalid("Shaped type exceeds 16,384 glyphs.")}
      let raw=CTRunGetAttributes(run) as NSDictionary
      guard let font=raw[kCTFontAttributeName as String] as? NSFont else{throw CraftError.invalid("A shaped glyph has no native font.")}
      let color=raw[NSAttributedString.Key.foregroundColor.rawValue] as? NSColor ?? .black
      var ids=[CGGlyph](repeating:0,count:count),positions=[CGPoint](repeating:.zero,count:count),advances=[CGSize](repeating:.zero,count:count),indices=[CFIndex](repeating:0,count:count)
      CTRunGetGlyphs(run,CFRange(location:0,length:0),&ids);CTRunGetPositions(run,CFRange(location:0,length:0),&positions);CTRunGetAdvances(run,CFRange(location:0,length:0),&advances);CTRunGetStringIndices(run,CFRange(location:0,length:0),&indices)
      for i in 0..<count {
        try Task.checkCancellation()
        let index=max(0,min(max(0,string.length-1),indices[i])),cluster=string.length>0 ? string.rangeOfComposedCharacterSequence(at:index).location:0
        let outline=CTFontCreatePathForGlyph(font as CTFont,ids[i],nil)
        if outline==nil {
          let unit=string.length>0 ? string.substring(with:string.rangeOfComposedCharacterSequence(at:index)):" "
          guard unit.unicodeScalars.allSatisfy({CharacterSet.whitespacesAndNewlines.contains($0)}) else{throw CraftError.unsupported("This shaped text contains a color or bitmap glyph without a vector outline.")}
        }
        let path=CGMutablePath();if let outline{path.addPath(outline)}
        let underline=(raw[NSAttributedString.Key.underlineStyle.rawValue] as? NSNumber)?.intValue ?? 0,strike=(raw[NSAttributedString.Key.strikethroughStyle.rawValue] as? NSNumber)?.intValue ?? 0
        if underline != 0{path.addRect(CGRect(x:0,y:CTFontGetUnderlinePosition(font as CTFont),width:advances[i].width,height:max(0.5,CTFontGetUnderlineThickness(font as CTFont))))}
        if strike != 0{path.addRect(CGRect(x:0,y:CTFontGetXHeight(font as CTFont)/2,width:advances[i].width,height:max(0.5,CTFontGetUnderlineThickness(font as CTFont))))}
        result.append(.init(path:path,position:CGPoint(x:origin.x+positions[i].x,y:origin.y+positions[i].y),advance:advances[i].width,color:color,cluster:cluster))
      }
    }
    return result
  }
  static func mapped(_ path:CGPath,visits:inout Int,map:(CGPoint)->CGPoint)throws->CGPath {
    let output=CGMutablePath();var current=CGPoint.zero,first=CGPoint.zero
    var count=0
    func line(_ p:CGPoint){output.addLine(to:map(p));count += 1}
    path.applyWithBlock{pointer in
      let e=pointer.pointee,p=e.points
      switch e.type {
      case .moveToPoint:current=p[0];first=current;output.move(to:map(current));count += 1
      case .addLineToPoint:
        let start=current,end=p[0],n=min(256,max(1,Int(ceil(hypot(end.x-start.x,end.y-start.y)/2))))
        for i in 1...n{let t=Double(i)/Double(n);line(CGPoint(x:start.x+(end.x-start.x)*t,y:start.y+(end.y-start.y)*t))};current=end
      case .addQuadCurveToPoint,.addCurveToPoint:
        let start=current,quad=e.type == .addQuadCurveToPoint,b=p[0],c=quad ? p[1]:p[1],d=quad ? p[1]:p[2]
        let length=hypot(b.x-start.x,b.y-start.y)+hypot(c.x-b.x,c.y-b.y)+(quad ? 0:hypot(d.x-c.x,d.y-c.y)),n=min(256,max(4,Int(ceil(length/2))))
        for i in 1...n{let t=Double(i)/Double(n),u=1-t
          line(quad ? CGPoint(x:u*u*start.x+2*u*t*b.x+t*t*d.x,y:u*u*start.y+2*u*t*b.y+t*t*d.y):CGPoint(x:u*u*u*start.x+3*u*u*t*b.x+3*u*t*t*c.x+t*t*t*d.x,y:u*u*u*start.y+3*u*u*t*b.y+3*u*t*t*c.y+t*t*t*d.y))
        };current=d
      case .closeSubpath:
        let start=current,n=min(256,max(1,Int(ceil(hypot(first.x-start.x,first.y-start.y)/2))))
        for i in 1...n{let t=Double(i)/Double(n);line(CGPoint(x:start.x+(first.x-start.x)*t,y:start.y+(first.y-start.y)*t))};output.closeSubpath();current=first
      @unknown default:break
      }
    }
    visits += count;guard visits<=maximumPoints else{throw CraftError.invalid("Shaped text exceeds its outline work limit.")};return output
  }
  static func layout(_ text:TextContent,dpi:Double)throws->Layout {
    try text.validate();guard let type=text.typography,let geometry=type.geometry else{throw CraftError.invalid("Missing shaped-text settings.")}
    guard type.writingOrientation == .horizontal else{throw CraftError.unsupported("Vertical shaped text is not qualified yet; use horizontal type for path and warp layouts.")}
    guard text.text.utf16.count<=maximumGlyphs else{throw CraftError.invalid("Shaped type supports at most16,384 UTF-16 units.")}
    let attributed=try NativeTextLayout.attributed(text,dpi:dpi)
    var marks:[Mark]=[],overset=false,baseline=0.0,visits=0,frameBounds:CGRect?
    if [.path,.circle,.arch,.bow].contains(geometry.mode) {
      var points=try PathConstruction.flattened(geometry.baselinePath(),tolerance:0.05);if geometry.reverse{points.reverse()}
      var distances=[Double](repeating:0,count:points.count)
      for i in 1..<points.count{distances[i]=distances[i-1]+hypot(points[i].x-points[i-1].x,points[i].y-points[i-1].y)}
      guard let total=distances.last,total>0.001 else{throw CraftError.invalid("Text baseline path has no length.")}
      let lineText=NSMutableAttributedString(attributedString:adjusted(attributed,scale:1,geometry:geometry))
      for i in 0..<lineText.length where (lineText.string as NSString).character(at:i)==10{lineText.replaceCharacters(in:NSRange(location:i,length:1),with:" ")}
      let line=CTLineCreateWithAttributedString(lineText),width=CTLineGetTypographicBounds(line,nil,nil,nil),available=total*(geometry.end-geometry.start)
      let scale=geometry.fit && width>0 ? min(64,available/width):1
      let alignment=type.defaultParagraph.alignment,align=alignment == .center ? max(0,(available-width*scale)/2):alignment == .right ? max(0,available-width*scale):0
      overset=width*scale>available+0.01
      let glyphs=try glyphs(line,origin:.zero,string:lineText.string as NSString)
      var clusters:[Int:(Double,Double)]=[:]
      for g in glyphs{let old=clusters[g.cluster] ?? (g.position.x,g.position.x+g.advance);clusters[g.cluster]=(min(old.0,g.position.x),max(old.1,g.position.x+g.advance))}
      func locate(_ distance:Double)->(CGPoint,Double){var lo=0,hi=distances.count-1;while hi-lo>1{let m=(hi+lo)/2;if distances[m]<=distance{lo=m}else{hi=m}};let a=points[lo],b=points[hi],length=max(1e-12,distances[hi]-distances[lo]),t=max(0,min(1,(distance-distances[lo])/length));return (CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t),atan2(b.y-a.y,b.x-a.x))}
      for glyph in glyphs {
        let cluster=clusters[glyph.cluster]!,middle=(cluster.0+cluster.1)/2,s=geometry.start*total+align+middle*scale
        guard align+cluster.0*scale>=0,align+cluster.1*scale<=available+0.01 else{continue}
        let (p,angle)=locate(s),c=cos(angle),v=sin(angle),dx=(glyph.position.x-middle)*scale,dy=geometry.offset-glyph.position.y*scale
        var transform=CGAffineTransform(a:c*scale,b:v*scale,c:v*scale,d:-c*scale,tx:p.x+c*dx-v*dy,ty:p.y+v*dx+c*dy)
        if let path=glyph.path.copy(using:&transform){marks.append(.init(path:path,color:glyph.color))}
      }
    }else {
      var plain=text;plain.typography?.geometry=nil
      let base=try NativeTextLayout.metrics(plain,dpi:dpi)
      let width=geometry.mode == .warp ? Double(base.width):geometry.width,height=geometry.mode == .warp ? Double(base.height):geometry.height
      let logical:CGPath
      if geometry.mode == .inside{logical=try VectorRasterizer.filledPath(geometry.path!)}else{logical=CGPath(rect:CGRect(x:0,y:0,width:width,height:height),transform:nil)}
      var flip=CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:height);let path=logical.copy(using:&flip)!
      func frame(_ scale:Double)->CTFrame{CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(adjusted(attributed,scale:scale,geometry:geometry)),CFRange(location:0,length:0),path,nil)}
      var factor=1.0
      if geometry.fit && !text.text.isEmpty && geometry.mode != .warp {
        var lo=0.001,hi=64.0
        for _ in 0..<18 {try Task.checkCancellation();let m=(lo+hi)/2,f=frame(m);if CTFrameGetVisibleStringRange(f).length==attributed.length{lo=m}else{hi=m}}
        factor=lo
      }
      let f=frame(factor),lines=CTFrameGetLines(f) as! [CTLine];overset=CTFrameGetVisibleStringRange(f).length<attributed.length
      var origins=[CGPoint](repeating:.zero,count:lines.count);CTFrameGetLineOrigins(f,CFRange(location:0,length:0),&origins)
      for (i,line) in lines.enumerated(){if i==0{baseline=height-origins[i].y}
        for glyph in try glyphs(line,origin:origins[i],string:text.text as NSString) {
          var transform=CGAffineTransform(a:1,b:0,c:0,d:-1,tx:glyph.position.x,ty:height-glyph.position.y)
          guard let outline=glyph.path.copy(using:&transform) else{continue}
          let drawn:CGPath
          if geometry.mode == .warp {drawn=try mapped(outline,visits:&visits){p in let q=geometry.warp.point(p.x,p.y,width:width,height:height);return CGPoint(x:q.x,y:q.y)}}else{drawn=outline}
          marks.append(.init(path:drawn,color:glyph.color))
        }
      }
      if geometry.mode != .warp{frameBounds=logical.boundingBoxOfPath}
    }
    var bounds=frameBounds ?? CGRect.null
    for mark in marks where !mark.path.isEmpty{bounds=bounds.union(mark.path.boundingBoxOfPath)}
    if bounds.isNull || bounds.isEmpty{bounds=CGRect(x:0,y:0,width:1,height:1)}
    let x=floor(bounds.minX)-1,y=floor(bounds.minY)-1,w=ceil(bounds.maxX)-x+1,h=ceil(bounds.maxY)-y+1
    guard [x,y,w,h].allSatisfy({$0.isFinite && abs($0)<=1_000_000}),w>=1,h>=1,w<=32768,h<=32768,w*h<=16_777_216 else{throw CraftError.invalid("Shaped text exceeds the 16 megapixel render limit.")}
    return .init(marks:marks,bounds:CGRect(x:x,y:y,width:w,height:h),overset:overset,baseline:baseline)
  }
  public static func metrics(_ text:TextContent,dpi:Double)throws->NativeTextLayout.Metrics {
    let layout=try layout(text,dpi:dpi);return .init(width:Int(layout.bounds.width),height:Int(layout.bounds.height),firstBaseline:layout.baseline,overset:layout.overset,origin:.init(layout.bounds.minX,layout.bounds.minY))
  }
  public static func outline(_ text:TextContent,dpi:Double)throws->CGPath {
    let layout=try layout(text,dpi:dpi),path=CGMutablePath(),shift=CGAffineTransform(translationX:-layout.bounds.minX,y:-layout.bounds.minY)
    for mark in layout.marks{path.addPath(mark.path,transform:shift)};return path
  }
  public static func render(_ text:TextContent,document:CraftDocument)throws->Surface {
    let layout=try layout(text,dpi:document.pixelsPerInch),width=Int(layout.bounds.width),height=Int(layout.bounds.height),floating=document.depth != .u8
    let info=CGImageAlphaInfo.premultipliedLast.rawValue | (floating ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue:0)
    guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:floating ? 32:8,bytesPerRow:width*(floating ? 16:4),space:try ColorManagement.space(for:document),bitmapInfo:info) else{throw CraftError.invalid("Could not allocate shaped type renderer.")}
    context.setShouldAntialias(text.typography?.antialiasMode.map{$0 != .none} ?? text.typography?.antialias ?? true);context.translateBy(x:0,y:Double(height));context.scaleBy(x:1,y:-1);context.translateBy(x:-layout.bounds.minX,y:-layout.bounds.minY)
    for mark in layout.marks{try Task.checkCancellation();context.setFillColor(mark.color.cgColor);context.addPath(mark.path);context.fillPath()}
    guard let image=context.makeImage() else{throw CraftError.invalid("Could not render shaped type.")}
    return try RasterIO.surface(image,depth:document.depth,space:ColorManagement.space(for:document),colorEncoding:document.depth == .f32 ? .linearRGB:.sRGB)
  }
  public static func replacement(_ layer:Layer,content:TextContent,document:CraftDocument)throws->Command {
    guard case .text(let old)=layer.content else{throw CraftError.invalid("Select editable type.")}
    if let appearance=old.pristineSourceAppearance,appearance.isPristine(content){var same=content;same.importedAppearance=old.importedAppearance;return .editType(layer.id,same,originDelta:.init(0,0))}
    var edited=content;edited.importedAppearance=nil
    let b=try NativeTextLayout.metrics(edited,dpi:document.pixelsPerInch).origin
    if try layer.sourceTypeTransform() != nil{return .importedType(.init(layerID:layer.id,content:edited,origin:b))}
    let a=try NativeTextLayout.metrics(old,dpi:document.pixelsPerInch).origin
    return .editType(layer.id,edited,originDelta:.init(b.x-a.x,b.y-a.y))
  }
}
