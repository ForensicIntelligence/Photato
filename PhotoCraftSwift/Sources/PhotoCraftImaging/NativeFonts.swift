import AppKit
import CoreText
import PhotoCraftCore

public enum NativeFonts {
  public struct Axis:Codable,Equatable,Sendable,Identifiable {
    public var id:UInt32;public var name:String;public var minimum:Double;public var maximum:Double;public var defaultValue:Double
  }
  public struct Glyph:Codable,Equatable,Sendable,Identifiable {
    public var id:UInt16;public var name:String;public var unicode:String?
  }
  public static let features:[(tag:String,name:String)]=[("liga","Standard Ligatures"),("calt","Contextual Alternates"),("dlig","Discretionary Ligatures"),("swsh","Swash"),("onum","Oldstyle"),("salt","Stylistic Alternates"),("titl","Titling Alternates"),("ornm","Ornaments"),("ordn","Ordinals"),("frac","Fractions"),("smcp","Small Capitals")]+(1...20).map{(String(format:"ss%02d",$0),"Stylistic Set \($0)")}
  public static func axes(_ name:String)throws->[Axis]{
    guard let font=NSFont(name:name,size:12) else{throw CraftError.unsupported("The font ‘\(name)’ is not installed.")}
    return ((CTFontCopyVariationAxes(font as CTFont) as? [[String:Any]]) ?? []).compactMap{raw in
      guard let id=raw[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,let minimum=raw[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber,let maximum=raw[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber,let value=raw[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber else{return nil}
      return Axis(id:id.uint32Value,name:raw[kCTFontVariationAxisNameKey as String] as? String ?? "Axis \(id)",minimum:minimum.doubleValue,maximum:maximum.doubleValue,defaultValue:value.doubleValue)
    }
  }
  /// OpenType Layout feature tags plus common AAT equivalents reported by Core Text.
  public static func availableFeatures(_ name:String)throws->[String] {
    guard let font=NSFont(name:name,size:12) else{throw CraftError.unsupported("The font ‘\(name)’ is not installed.")}
    var tags=Set<String>()
    for table:UInt32 in [0x47535542,0x47504F53] {
      guard let data=CTFontCopyTable(font as CTFont,table,[]) as Data?,data.count<=16_777_216,data.count>=10 else{continue}
      let bytes=[UInt8](data);func u16(_ i:Int)->Int{Int(bytes[i])<<8|Int(bytes[i+1])}
      let offset=u16(6);guard offset+2<=bytes.count else{continue};let count=u16(offset);guard count<=4096,offset+2+count*6<=bytes.count else{continue}
      for i in 0..<count{let a=offset+2+i*6;tags.insert(String(decoding:bytes[a..<(a+4)],as:UTF8.self))}
    }
    for raw in (CTFontCopyFeatures(font as CTFont) as? [[String:Any]]) ?? [] {
      let id=(raw[kCTFontFeatureTypeIdentifierKey as String] as? NSNumber)?.intValue
      let selectors=(raw[kCTFontFeatureTypeSelectorsKey as String] as? [[String:Any]]) ?? []
      let ids=Set(selectors.compactMap{($0[kCTFontFeatureSelectorIdentifierKey as String] as? NSNumber)?.intValue})
      if id==1{if ids.contains(2){tags.insert("liga")};if ids.contains(4){tags.insert("dlig")}}
      if id==21,ids.contains(0){tags.insert("onum")};if id==11{tags.insert("frac")};if id==36{tags.insert("calt")}
    }
    return tags.sorted()
  }
  public static func font(_ style:TypeStyle,dpi:Double)throws->NSFont {
    try style.validate()
    guard let base=NSFont(name:style.font,size:style.size*dpi/72) else{throw CraftError.unsupported("The font ‘\(style.font)’ is not installed on this Mac.")}
    var attributes:[CFString:Any]=[:]
    if let options=style.fontOptions {
      let available=try axes(style.font)
      for choice in options.variations{guard let axis=available.first(where:{$0.id==choice.axis}), (axis.minimum...axis.maximum).contains(choice.value) else{throw CraftError.invalid("Variation axis is absent or outside this font’s range.")}}
      if !options.features.isEmpty{attributes[kCTFontFeatureSettingsAttribute]=options.features.map{[kCTFontOpenTypeFeatureTag:$0.tag,kCTFontOpenTypeFeatureValue:$0.value] as [CFString:Any]}}
      if !options.variations.isEmpty{attributes[kCTFontVariationAttribute]=Dictionary(uniqueKeysWithValues:options.variations.map{(NSNumber(value:$0.axis),NSNumber(value:$0.value))})}
    }
    var matrix=CGAffineTransform(scaleX:style.horizontalScale,y:style.verticalScale)
    let font=CTFontCreateCopyWithAttributes(base as CTFont,base.pointSize,&matrix,CTFontDescriptorCreateWithAttributes(attributes as CFDictionary))
    if let glyph=style.glyphOverride,Int(glyph.glyph)>=CTFontGetGlyphCount(font){throw CraftError.invalid("Glyph is outside this font’s glyph table.")}
    return font as NSFont
  }
  public static func glyphs(_ name:String,start:Int=1,count:Int=256)throws->[Glyph] {
    guard let font=NSFont(name:name,size:24),start>=1,(1...512).contains(count) else{throw CraftError.invalid("Choose an installed font and a bounded glyph page.")}
    let total=CTFontGetGlyphCount(font as CTFont),end=min(total,start+count);guard start<end else{return []}
    var unicode:[UInt16:String]=[:]
    // Unicode's BMP is bounded; supplementary characters can still be typed normally.
    let characters=Array(UInt16(0)...UInt16.max);var glyphs=[CGGlyph](repeating:0,count:characters.count)
    CTFontGetGlyphsForCharacters(font as CTFont,characters,&glyphs,characters.count)
    for i in characters.indices where Int(glyphs[i])>=start && Int(glyphs[i])<end && unicode[glyphs[i]]==nil {
      if let scalar=UnicodeScalar(Int(characters[i])),!CharacterSet.controlCharacters.contains(scalar){unicode[glyphs[i]]=String(scalar)}
    }
    return (start..<end).map{let id=UInt16($0);return Glyph(id:id,name:CTFontCopyNameForGlyph(font as CTFont,id) as String? ?? "glyph\(id)",unicode:unicode[id])}
  }
}
