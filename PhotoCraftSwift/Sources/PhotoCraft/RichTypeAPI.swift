import Foundation
import AppKit
import PhotoCraftCore

enum RichTypeAPI {
  static var character:[String:Any] {
    func number(_ low:Double,_ high:Double,_ integer:Bool)->[String:Any]{BrushAPI.number(low,high,integer:integer)}
    return BrushAPI.object(["weight":number(100,900,true),"italic":BrushAPI.flag,"fauxBold":BrushAPI.flag,"fauxItalic":BrushAPI.flag,"kerning":BrushAPI.enumeration(TypeCharacterFormatting.Kerning.allCases.map(\.rawValue)),"manualKerning":number(-10000,10000,false),"caps":BrushAPI.enumeration(TypeCharacterFormatting.Caps.allCases.map(\.rawValue)),"ligatures":BrushAPI.flag,"discretionaryLigatures":BrushAPI.flag,"sourceFace":["type":"string","maxLength":256],"sourcePostScriptName":["type":"string","maxLength":256],"sourceFontReference":["type":"string","maxLength":256],"sourceWeight":number(100,900,true),"sourceItalic":BrushAPI.flag,"linearColor":BrushAPI.flag,"styleSheet":number(1,Double(UInt32.max),true)],required:[])
  }
  static var paragraph:[String:Any] {BrushAPI.object(["lastLine":BrushAPI.enumeration(TypeParagraphFormatting.LastLine.allCases.map(\.rawValue)),"autoLeading":BrushAPI.number(0.1,10),"styleSheet":BrushAPI.number(0,Double(UInt32.max),integer:true)],required:[])}
  static var frame:[String:Any] { ["anyOf":[BrushAPI.object(["kind":BrushAPI.enumeration(["point","box"]),"x":BrushAPI.number(-1000000,1000000),"y":BrushAPI.number(-1000000,1000000),"width":BrushAPI.number(0.000001,32768),"height":BrushAPI.number(0.000001,32768)],required:["kind","x","y","width","height"]),["type":"null"]]] }
  static var sourceState:[String:Any] {
    BrushAPI.object(["cachePresent":BrushAPI.flag,"cacheIsPristine":BrushAPI.flag,
      "cacheX":BrushAPI.number(-1000000,1000000,integer:true),"cacheY":BrushAPI.number(-1000000,1000000,integer:true),
      "cacheWidth":BrushAPI.number(0,32768,integer:true),"cacheHeight":BrushAPI.number(0,32768,integer:true),
      "typeRecordBytes":BrushAPI.number(0,16777216,integer:true),"originalTextTransform":ShapeAPI.transform,
      "missingFonts":ShapeAPI.array(["type":"string","maxLength":256],4097)],
      required:["cachePresent","cacheIsPristine","cacheX","cacheY","cacheWidth","cacheHeight","typeRecordBytes","originalTextTransform","missingFonts"])
  }
  static var antialias:[String:Any]{["anyOf":[BrushAPI.enumeration(TypeAntialias.allCases.map(\.rawValue)),["type":"null"]]]}
}

extension Layer {
  var textSourceAPIState:Any? {
    guard let text=typeContent,let source=text.importedAppearance else{return nil}
    let fonts=Set(([text.typography?.defaultStyle] + (text.typography?.runs.map{Optional($0.style)} ?? [])).compactMap{$0?.font})
    return ["cachePresent":source.pixels != nil,"cacheIsPristine":source.isPristine(text),"cacheX":source.x,"cacheY":source.y,"cacheWidth":source.pixels?.width ?? 0,"cacheHeight":source.pixels?.height ?? 0,"typeRecordBytes":source.typeRecord?.count ?? 0,"originalTextTransform":BrushAPI.json(source.textTransform),"missingFonts":fonts.filter{NSFont(name:$0,size:12)==nil}.sorted()]as[String:Any]
  }
}
