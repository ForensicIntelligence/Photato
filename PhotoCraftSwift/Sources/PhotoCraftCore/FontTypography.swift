import Foundation

public struct TypeFontFeature:Codable,Equatable,Sendable {
  public var tag:String
  public var value:Int
  public init(_ tag:String,_ value:Int=1){self.tag=tag;self.value=value}
}
public struct TypeFontVariation:Codable,Equatable,Sendable {
  public var axis:UInt32
  public var value:Double
  public init(_ axis:UInt32,_ value:Double){self.axis=axis;self.value=value}
}
public struct TypeFontOptions:Codable,Equatable,Sendable {
  public var features:[TypeFontFeature]=[]
  public var variations:[TypeFontVariation]=[]
  public var language:String?
  public init(){}
  public var isEmpty:Bool{features.isEmpty && variations.isEmpty && language==nil}
  public func validate()throws {
    guard features.count<=64,Set(features.map(\.tag)).count==features.count,
      features.allSatisfy({$0.tag.utf8.count==4 && $0.tag.utf8.allSatisfy{(32...126).contains($0)} && (0...65535).contains($0.value)}),
      variations.count<=32,Set(variations.map(\.axis)).count==variations.count,
      variations.allSatisfy({$0.value.isFinite && abs($0.value)<=1_000_000}),
      language.map({!$0.isEmpty && $0.utf8.count<=64 && $0.utf8.allSatisfy{(65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0==45}}) ?? true
    else{throw CraftError.invalid("Invalid OpenType features, variation axes or language tag.")}
  }
}
public struct TypeGlyphOverride:Codable,Equatable,Sendable {
  public var glyph:UInt16
  public var baseString:String
  public init(glyph:UInt16,baseString:String){self.glyph=glyph;self.baseString=baseString}
  public func validate()throws{guard glyph>0,!baseString.isEmpty,baseString.utf16.count<=16,!baseString.contains("\n"),!baseString.contains("\r") else{throw CraftError.invalid("A glyph override requires one bounded base string and a valid glyph.")}}
}
extension TypeStyle {
  public var requiresAdvancedTypography:Bool{fontOptions?.isEmpty==false || glyphOverride != nil}
}
extension TextTypography {
  public enum Orientation:String,Codable,CaseIterable,Sendable{case horizontal,vertical}
  public var writingOrientation:Orientation{orientation ?? .horizontal}
  public var requiresAdvancedTypography:Bool{writingOrientation == .vertical || defaultStyle.requiresAdvancedTypography || runs.contains{$0.style.requiresAdvancedTypography}}
}
extension CraftDocument {
  public var hasAdvancedTypography:Bool{layers.contains{if case .text(let text)=$0.content{return text.typography?.requiresAdvancedTypography==true};return false}}
}
