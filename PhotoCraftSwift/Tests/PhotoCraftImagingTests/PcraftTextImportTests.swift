import AppKit
import CoreText
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PcraftTextImportTests:XCTestCase {
  func file(_ name:String)throws->Data{try PcraftImportTests().fixture(name,folder:"PcraftText")}
  func fonts()throws {
    let folder=try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("PcraftText/fonts")
    for name in ["Inter-Regular.ttf","Inter-Medium.ttf","Inter-SemiBold.ttf"]{var error:Unmanaged<CFError>?;_ = CTFontManagerRegisterFontsForURL(folder.appendingPathComponent(name)as CFURL,.process,&error)}
    XCTAssertNotNil(NSFont(name:"Inter-Regular",size:12))
  }
  func expected(_ bits:String)throws->[[String:Any]]{try XCTUnwrap(JSONSerialization.jsonObject(with:file("expected-\(bits).json"))as?[[String:Any]])}
  func testAllSourceTextFieldsRunsFramesCachesAndArchiveAtEveryDepth()throws {
    try fonts()
    for bits in ["u8","u16","f32"] {
      let doc=try PcraftImport.read(file("text-\(bits).pcraft"));XCTAssertEqual(doc.layers.count,12);XCTAssertEqual(doc.minimumArchiveVersion,69)
      let rich=try XCTUnwrap(doc.layers.first{$0.name=="rich-box"}?.typeContent),type=try XCTUnwrap(rich.typography),style=type.runs[0].style
      XCTAssertEqual(type.kind,.paragraph);XCTAssertEqual(type.sourceFrame?.width,135.5);XCTAssertEqual(type.sourceFrame?.height,70.75);XCTAssertEqual(type.sourceFrame?.x,1.25);XCTAssertEqual(type.sourceFrame?.y,-2.5)
      XCTAssertEqual(type.runs.map(\.length),[2,rich.text.utf16.count-2]);XCTAssertEqual(style.characterFormatting?.weight,600);XCTAssertEqual(style.characterFormatting?.manualKerning,-30);XCTAssertEqual(style.characterFormatting?.kerning,.off)
      XCTAssertTrue(style.characterFormatting?.fauxBold==true);XCTAssertTrue(style.characterFormatting?.fauxItalic==true);XCTAssertEqual(style.fontOptions?.language,"fr-CA");XCTAssertEqual(style.fontOptions?.features.first?.tag,"tnum")
      XCTAssertEqual(type.defaultParagraph.firstIndent,-2.5);XCTAssertEqual(type.defaultParagraph.endIndent,-1.5);XCTAssertEqual(type.defaultParagraph.formatting?.lastLine,.center)
      XCTAssertEqual(rich.importedAppearance?.typeRecord,Data("OWNED-PHOTATO-TYPE".utf8));XCTAssertNotNil(rich.pristineSourceAppearance?.pixels)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(doc)) == doc,"Extended source text archive must preserve the complete model and original caches")
      let point=try XCTUnwrap(doc.layers.first{$0.name=="point"});XCTAssertEqual(try point.sourceTypeTransform(),.translation(12.25,28.5))
    }
  }
  func testOriginalCachedTextWordsMatchInDeclaredDocumentWindow()throws {
    try fonts();var metrics:[[String:Any]]=[]
    for bits in ["u8","u16","f32"] {let doc=try PcraftImport.read(file("text-\(bits).pcraft"))
      for entry in try expected(bits) where entry["cached"]as?Bool == true {
        let name=entry["name"]as!String,layer=try XCTUnwrap(doc.layers.first{$0.name==name}),surface=try Renderer.layerSurface(layer,in:doc),inverse=try layer.coordinateTransform.inverted(),expected=(entry["float_bits"]as![NSNumber]).map(\.uint32Value);var changed=0,index=0
        for y in 0..<150{for x in 0..<180{let p=inverse.point(Double(x)+0.5,Double(y)+0.5),pixel=doc.depth == .f32 ? surface.linearPixel(x:Int(floor(p.x)),y:Int(floor(p.y))):surface.pixel(x:Int(floor(p.x)),y:Int(floor(p.y)));for word in [pixel.r.bitPattern,pixel.g.bitPattern,pixel.b.bitPattern,pixel.a.bitPattern]{if word != expected[index]{changed+=1};index+=1}}}
        XCTAssertEqual(changed,0,"\(bits)/\(name) original cached words");metrics.append(["depth":bits,"name":name,"words":index,"changed":changed])
      }
    }
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathComponent("source-text-cache-words.json"))}
  }
  func testNativeCapsAttributesOpticalArithmeticAndNegativeIndents()throws {
    try fonts();var text=TextContent(text:"Straße AV",fontName:"Inter-Regular",size:20,color:.black),type=TextTypography();type.defaultStyle.font="Inter-Regular";type.defaultStyle.size=20;type.defaultStyle.characterFormatting = .init();type.defaultStyle.characterFormatting?.caps = .allCaps;type.defaultParagraph.formatting = .init();type.defaultParagraph.firstIndent = -2.5;text.typography=type
    XCTAssertEqual(try NativeTextLayout.attributed(text,dpi:72).string,text.text);XCTAssertEqual(try NativeTextLayout.attributed(text,dpi:72,rendering:true).string,"STRASSE AV")
    let attrs=try NativeTextLayout.attributes(type.defaultStyle,paragraph:type.defaultParagraph,dpi:72),decoded=NativeTextLayout.styles(attrs,dpi:72);XCTAssertEqual(decoded.0,type.defaultStyle);XCTAssertEqual(decoded.1,type.defaultParagraph)
    let expected=try XCTUnwrap(JSONSerialization.jsonObject(with:file("optical.json"))as?[String:Any]);XCTAssertEqual(NativeOpticalKerning.kern(features:(0.08,0.02),reference:(0.14,0.01)).bitPattern,(expected["kern_bits"]as!NSNumber).uint32Value)
    XCTAssertEqual([Float(12),24,48,96].map{NativeOpticalKerning.sizeAdjustment($0).bitPattern},(expected["size_adjust_bits"]as![NSNumber]).map(\.uint32Value))
    type.defaultStyle.characterFormatting?.kerning = .optical;type.defaultStyle.characterFormatting?.caps = .normal;text.typography=type;XCTAssertNoThrow(try NativeTextLayout.metrics(text,dpi:72))
  }
  func testMissingImportedFontUsesNativeFallbackWithoutLosingIdentity()throws {
    let name="Photato-Owned-Uninstalled-Font-306";XCTAssertNil(NSFont(name:name,size:12))
    var text=TextContent(text:"Editable missing font",fontName:name,size:20,color:.black),type=TextTypography()
    type.defaultStyle.font=name;type.defaultStyle.characterFormatting = .init();type.defaultStyle.characterFormatting?.sourceFontReference=name
    type.defaultStyle.fontOptions=TypeFontOptions();type.defaultStyle.fontOptions?.language="en-CA";text.typography=type
    let metrics=try NativeTextLayout.metrics(text,dpi:72);XCTAssertGreaterThan(metrics.width,1)
    let attributed=try NativeTextLayout.attributed(text,dpi:72),decoded=NativeTextLayout.styles(attributed.attributes(at:0,effectiveRange:nil),dpi:72)
    XCTAssertEqual(decoded.0.font,name);XCTAssertEqual(decoded.0.characterFormatting?.sourceFontReference,name)
    var ordinary=type.defaultStyle;ordinary.characterFormatting=nil
    XCTAssertThrowsError(try NativeFonts.font(ordinary,dpi:72),"Ordinary uninstalled fonts keep their explicit failure behavior")
  }
  func testUncachedSourceTextCompositeMatchesExactOriginalWords()throws {
    try fonts();var comparisons:[[String:Any]]=[]
    for bits in ["u8","u16","f32"]{var doc=try PcraftImport.read(file("text-\(bits).pcraft"));let layer=try XCTUnwrap(doc.layers.first{$0.name=="uncached"}),entry=try XCTUnwrap(expected(bits).first{$0["name"]as?String=="uncached"}),wanted=(entry["float_bits"]as![NSNumber]).map(\.uint32Value);doc.layers=[layer];doc.activeLayerID=layer.id
      let surface=try Renderer.composite(doc);var index=0,changed=0,nativeBounds=[180,150,-1,-1],sourceBounds=[180,150,-1,-1]
      func include(_ bounds:inout[Int],_ x:Int,_ y:Int){bounds[0]=min(bounds[0],x);bounds[1]=min(bounds[1],y);bounds[2]=max(bounds[2],x);bounds[3]=max(bounds[3],y)}
      for y in 0..<150{for x in 0..<180{let pixel=doc.depth == .f32 ? surface.linearPixel(x:x,y:y):surface.pixel(x:x,y:y);if pixel.a>0{include(&nativeBounds,x,y)};if Float(bitPattern:wanted[index+3])>0{include(&sourceBounds,x,y)};for word in [pixel.r.bitPattern,pixel.g.bitPattern,pixel.b.bitPattern,pixel.a.bitPattern]{if word != wanted[index]{changed+=1};index+=1}}};XCTAssertEqual(changed,0,"\(bits): uncached text strict source comparison")
      let metrics=try NativeTextLayout.editingMetrics(try XCTUnwrap(layer.typeContent),dpi:doc.pixelsPerInch)
      comparisons.append(["depth":bits,"words":index,"changed":changed,"nativeBounds":nativeBounds,"sourceBounds":sourceBounds,"sourceRect":entry["rect"] ?? NSNull(),"nativeMetrics":[metrics.width,metrics.height],"nativeOrigin":[metrics.origin.x,metrics.origin.y]])
    }
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:comparisons,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathComponent("source-text-uncached-comparisons.json"))}
  }
  func testUnsupportedMetadataBadFramesBudgetsAndCancellationRejectWithoutSourceChanges()async throws {
    try fonts();let bytes=try file("text-u8.pcraft")
    for key in ["unknown","shape"]{let project=try PcraftImportTests().source(bytes){doc in var layers=doc["layers"]as![[String:Any]],content=layers[0]["content"]as![String:Any];content[key]=key=="unknown" ? true:["Box":["x":0,"y":0,"width":1e30,"height":1e30]];layers[0]["content"]=content;doc["layers"]=layers};XCTAssertThrowsError(try PcraftImportTests().convert(project))}
    XCTAssertThrowsError(try PcraftImport.read(bytes,rasterByteLimit:1));let task=Task{while !Task.isCancelled{await Task.yield()};return try PcraftImport.read(bytes)};task.cancel();do{_ = try await task.value;XCTFail("Cancelled source text import")}catch{XCTAssertTrue(error is CancellationError)};XCTAssertEqual(try file("text-u8.pcraft"),bytes)
  }
}
