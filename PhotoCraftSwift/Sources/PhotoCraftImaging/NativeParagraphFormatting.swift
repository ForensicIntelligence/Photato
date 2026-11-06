import AppKit
import PhotoCraftCore

/// Keep native paragraph controls on TextKit's line/glyph positions. This applies
/// only to the extended formatting fields, leaving the legacy layout untouched.
enum NativeParagraphFormatting {
  static let key=NSAttributedString.Key("PhotatoRichParagraph")
  static func apply(storage:NSTextStorage,manager:NSLayoutManager,container:NSTextContainer,dpi:Double) {
    struct Line {var rect:CGRect,used:CGRect,range:NSRange}
    var lines:[Line]=[]
    manager.enumerateLineFragments(forGlyphRange:manager.glyphRange(for:container)){rect,used,_,range,_ in lines.append(.init(rect:rect,used:used,range:range))}
    let string=storage.string as NSString
    for line in lines where line.range.length>0 {
      let character=manager.characterIndexForGlyph(at:line.range.location)
      guard character<string.length,let data=storage.attribute(key,at:character,effectiveRange:nil)as?Data,let paragraph=try? JSONDecoder().decode(TypeParagraph.self,from:data),paragraph.alignment == .justified,let formatting=paragraph.formatting else{continue}
      let paragraphRange=string.paragraphRange(for:.init(location:character,length:0))
      let next=NSMaxRange(line.range)<manager.numberOfGlyphs ? manager.characterIndexForGlyph(at:NSMaxRange(line.range)):string.length
      guard next>=NSMaxRange(paragraphRange),formatting.lastLine != .left else{continue}
      let start=max(line.rect.minX,paragraph.startIndent*dpi/72),right=line.rect.maxX-paragraph.endIndent*dpi/72
      let free=max(0,right-start-line.used.width)
      if formatting.lastLine != .justified {
        let delta=start-line.used.minX+free*(formatting.lastLine == .center ? 0.5:1)
        let locations=(line.range.location..<NSMaxRange(line.range)).map{manager.location(forGlyphAt:$0)}
        if (container as? NativeTypeTextContainer)?.pointAnchored == true {
          // NSTextView also uses these bounds for caret visibility/hit testing.
          // Keep them with the shifted glyphs, inside the same line fragment.
          manager.setLineFragmentRect(line.rect,forGlyphRange:line.range,usedRect:line.used.offsetBy(dx:delta,dy:0))
        }
        for (offset,old) in locations.enumerated(){manager.setLocation(.init(x:old.x+delta,y:old.y),forStartOfGlyphRange:.init(location:line.range.location+offset,length:1))}
        continue
      }
      var gaps:[Int]=[]
      for glyph in line.range.location..<NSMaxRange(line.range)-1 {
        let index=manager.characterIndexForGlyph(at:glyph)
        if index<string.length,let scalar=UnicodeScalar(Int(string.character(at:index))),CharacterSet.whitespaces.contains(scalar){gaps.append(glyph)}
      }
      if gaps.isEmpty{gaps=Array(line.range.location..<NSMaxRange(line.range)-1)}
      guard !gaps.isEmpty else{continue}
      var displacement:Double=0,at=0
      for glyph in line.range.location..<NSMaxRange(line.range){let old=manager.location(forGlyphAt:glyph);manager.setLocation(.init(x:old.x+displacement,y:old.y),forStartOfGlyphRange:.init(location:glyph,length:1));if at<gaps.count,gaps[at]==glyph{displacement+=free/Double(gaps.count);at+=1}}
    }
  }
}

extension NativeTextLayout {
  /// Call once after a fresh TextKit layout; repeated application to already
  /// adjusted glyphs would accumulate last-line displacement.
  public static func applyParagraphFormatting(storage:NSTextStorage,manager:NSLayoutManager,container:NSTextContainer,dpi:Double) {
    NativeParagraphFormatting.apply(storage:storage,manager:manager,container:container,dpi:dpi)
  }
}
