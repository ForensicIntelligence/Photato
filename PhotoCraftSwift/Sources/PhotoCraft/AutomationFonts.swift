import Foundation
import AppKit
import CoreText
import PhotoCraftCore
import PhotoCraftImaging

enum FontAPI {
  static let commands=["font.inspect","text.glyph"]
  static var options:[String:Any]{BrushAPI.object(["features":ShapeAPI.array(BrushAPI.object(["tag":["type":"string","minLength":4,"maxLength":4],"value":BrushAPI.number(0,65535,integer:true)],required:["tag","value"]),64),"variations":ShapeAPI.array(BrushAPI.object(["axis":BrushAPI.number(0,Double(UInt32.max),integer:true),"value":BrushAPI.number(-1_000_000,1_000_000)],required:["axis","value"]),32),"language":["type":"string","minLength":1,"maxLength":64]])}
  static var glyphOverride:[String:Any]{BrushAPI.object(["glyph":BrushAPI.number(1,65535,integer:true),"baseString":["type":"string","minLength":1,"maxLength":16]],required:["glyph","baseString"])}
  static func schema(_ key:String)->[String:Any]{switch key {
    case "start":return BrushAPI.number(1,65535,integer:true)
    case "count":return BrushAPI.number(1,512,integer:true)
    case "glyphID":return BrushAPI.number(1,65535,integer:true)
    case "location","length":return BrushAPI.number(0,100000,integer:true)
    case "layerID":return ["type":"string","format":"uuid"]
    default:return ["type":"string","minLength":1,"maxLength":256]
  }}
  static var capabilities:[String:Any]{["commands":commands,"optionsSchema":options,"glyphOverrideSchema":glyphOverride,"nativeArchiveVersion":34,"coordinates":"Font feature tags use four ASCII characters and integer selectors; axes use the font's UInt32 identifiers and declared ranges. Glyph insertion uses UTF-16 location/length, defaults to appending, and preserves glyph identity in native text. Font data comes only from fonts installed on this Mac.","inspectionResultSchema":["type":"object","required":["revision","font","features","axes","glyphs","glyphCount"],"properties":["revision":["type":"string"],"font":schema("font"),"features":ShapeAPI.array(["type":"string"],4096),"axes":ShapeAPI.array(BrushAPI.object(["id":BrushAPI.number(0,Double(UInt32.max),integer:true),"name":["type":"string"],"minimum":BrushAPI.number(-1000000,1000000),"maximum":BrushAPI.number(-1000000,1000000),"defaultValue":BrushAPI.number(-1000000,1000000)],required:["id","name","minimum","maximum","defaultValue"]),32),"glyphs":ShapeAPI.array(BrushAPI.object(["id":schema("glyphID"),"name":["type":"string"],"unicode":["type":"string"]],required:["id","name"]),512),"glyphCount":BrushAPI.number(0,65536,integer:true)]],"limitations":"Exact Adobe composers/kerning/antialiasing remain unqualified. PSD preserves vertical orientation and a limited OpenType flag set; variation axes, arbitrary feature tags and glyph overrides reject editable PSD export. Native glyph enumeration maps BMP characters where available; unmapped glyphs retain their identity with a replacement-character base string."]}
}
extension AutomationCommand {
  func insertTypeGlyph(_ document:CraftDocument)throws->Command {
    let id=try actionUUID("layerID")
    guard let layer=document.layers.first(where:{$0.id==id}),case .text(let original)=layer.content else{throw AutomationFailure(status:404,message:"Type layer not found.")}
    let name=try string("font"),glyph=try integer("glyphID",range:1...65535),choices=try NativeFonts.glyphs(name,start:glyph,count:1)
    guard let choice=choices.first else{throw AutomationFailure(status:400,message:"Glyph does not exist in this font.")}
    let text=original.promoted(dpi:document.pixelsPerInch),length=text.text.utf16.count
    let location=try parameters["location"].map{_ in try integer("location",range:0...Double(length))} ?? length,count=try parameters["length"].map{_ in try integer("length",range:0...Double(length-location))} ?? 0
    guard TextTypography.isBoundary(location,in:text.text),TextTypography.isBoundary(location+count,in:text.text) else{throw AutomationFailure(status:400,message:"Glyph insertion splits a Unicode scalar.")}
    let attributed=NSMutableAttributedString(attributedString:try NativeTextLayout.attributed(text,dpi:document.pixelsPerInch))
    var style=text.typography!.defaultStyle,paragraph=text.typography!.defaultParagraph
    if attributed.length>0{(style,paragraph)=NativeTextLayout.styles(attributed.attributes(at:min(location,length-1),effectiveRange:nil),dpi:document.pixelsPerInch)}
    let replacement=try NativeTextLayout.glyphString(style:style,paragraph:paragraph,font:name,glyph:choice,dpi:document.pixelsPerInch,orientation:text.typography!.writingOrientation)
    attributed.replaceCharacters(in:.init(location:location,length:count),with:replacement)
    let content=try NativeTextLayout.content(attributed,template:text,dpi:document.pixelsPerInch);_ = try NativeTextLayout.metrics(content,dpi:document.pixelsPerInch)
    return try ShapedTextLayout.replacement(layer,content:content,document:document)
  }
}
extension AutomationService {
  func inspectFont(_ command:AutomationCommand,store:EditorStore)throws->[String:Any]{
    let name=try command.string("font"),start=try command.parameters["start"].map{_ in try command.integer("start",range:1...65535)} ?? 1,count=try command.parameters["count"].map{_ in try command.integer("count",range:1...512)} ?? 128
    guard let font=NSFont(name:name,size:12) else{throw AutomationFailure(status:404,message:"Font is not installed.")}
    return ["revision":revision(store),"font":name,"features":try NativeFonts.availableFeatures(name),"axes":try NativeFonts.axes(name).map{BrushAPI.json($0)},"glyphs":try NativeFonts.glyphs(name,start:start,count:count).map{BrushAPI.json($0)},"glyphCount":CTFontGetGlyphCount(font as CTFont)]
  }
}
