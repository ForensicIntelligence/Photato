import AppKit
import CoreText
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class AdvancedTypographyTests:XCTestCase {
  func sample(_ string:String="Typography") -> TextContent {
    var text=TextContent(text:string);text.typography=TextTypography();text.typography?.defaultStyle.size=24;return text
  }
  func document(_ text:TextContent,depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:320,height:320,depth:depth);d.layers=[Layer(name:"Type",content:.text(text))];d.activeLayerID=d.layers[0].id;return d
  }
  func testVerticalLayoutRenderingAndEditablePSD()throws {
    var text=sample("Vertical native type")
    let horizontal=try NativeTextLayout.metrics(text,dpi:72)
    text.typography?.orientation = .vertical
    let vertical=try NativeTextLayout.metrics(text,dpi:72)
    XCTAssertGreaterThan(horizontal.width,horizontal.height)
    XCTAssertGreaterThan(vertical.height,vertical.width)
    for depth in [PixelDepth.u8,.u16,.f32] {
      let d=try document(text,depth:depth),render=try NativeTextLayout.render(text,document:d)
      XCTAssertEqual(render.width,vertical.width);XCTAssertEqual(render.height,vertical.height)
      let ink=(0..<render.height).reduce(0){n,y in n+(0..<render.width).filter{render.pixel(x:$0,y:y).a>0.1}.count}
      XCTAssertGreaterThan(ink,80)
      XCTAssertEqual(d.minimumArchiveVersion,34)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
    }
    for kind in [TextTypography.Kind.point,.paragraph] {
      text.typography?.kind=kind
      if kind == .paragraph{text.layoutWidth=80;text.layoutHeight=200}
      var d=try document(text);d.layers[0].affine = .translation(25,35) * .scale(1.1,0.9)
      let restored=try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      guard case .text(let result)=restored.layers[0].content else{return XCTFail("Type flattened")}
      XCTAssertEqual(result.typography?.writingOrientation,.vertical)
      XCTAssertEqual(result.typography?.kind,kind)
      XCTAssertEqual(restored.layers[0].coordinateTransform.tx,d.layers[0].coordinateTransform.tx,accuracy:0.00001)
      XCTAssertEqual(restored.layers[0].coordinateTransform.ty,d.layers[0].coordinateTransform.ty,accuracy:0.00001)
    }
  }
  func testVariableFontChangesActualMetricsAndRejectsInvalidAxis()throws {
    var text=sample("MMMMMMMM");text.typography?.defaultStyle.font="Skia"
    let axis=try XCTUnwrap(NativeFonts.axes("Skia").first{$0.name.lowercased().contains("width")})
    var options=TypeFontOptions();options.variations=[.init(axis.id,axis.minimum)]
    text.typography?.defaultStyle.fontOptions=options
    let narrow=try NativeTextLayout.metrics(text,dpi:72)
    options.variations=[.init(axis.id,axis.maximum)];text.typography?.defaultStyle.fontOptions=options
    XCTAssertGreaterThan(try NativeTextLayout.metrics(text,dpi:72).width,narrow.width)
    let restored=try NativeTextLayout.content(NativeTextLayout.attributed(text,dpi:72),template:text,dpi:72)
    XCTAssertEqual(restored.typography?.defaultStyle.fontOptions,options)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(document(text)))
    options.variations=[.init(axis.id,axis.maximum+1)];text.typography?.defaultStyle.fontOptions=options
    XCTAssertThrowsError(try NativeTextLayout.metrics(text,dpi:72))
  }
  func testLigaturesAndExplicitPSDFlags()throws {
    var text=sample("office ffi");text.typography?.defaultStyle.font="HelveticaNeue"
    func glyphCount(_ text:TextContent)throws->Int {
      let line=CTLineCreateWithAttributedString(try NativeTextLayout.attributed(text,dpi:72));return CTLineGetGlyphCount(line)
    }
    var options=TypeFontOptions();options.features=[.init("liga",0)];text.typography?.defaultStyle.fontOptions=options
    let unligated=try glyphCount(text)
    options.features=[.init("liga",1)];text.typography?.defaultStyle.fontOptions=options
    XCTAssertLessThan(try glyphCount(text),unligated)
    options.features=[.init("calt",0),.init("dlig",1),.init("liga",0),.init("smcp",1)];text.typography?.defaultStyle.fontOptions=options
    let reopened=try PSDCodec.read(PSDCodec.writeRasterLayers(document(text)))
    guard case .text(let result)=reopened.layers[0].content else{return XCTFail()}
    XCTAssertEqual(result.typography?.defaultStyle.fontOptions,options)
  }
  func testGlyphIdentityRepeatedInsertionAndMalformedMetadata()throws {
    let font=try XCTUnwrap(NSFont(name:"HelveticaNeue",size:24))
    var character:UniChar=66,glyph:CGGlyph=0
    XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont,&character,&glyph,1))
    var style=TypeStyle();style.size=24;style.glyphOverride = .init(glyph:glyph,baseString:"A")
    let value=NSAttributedString(string:"AA",attributes:try NativeTextLayout.attributes(style,paragraph:.init(),dpi:72))
    let text=try NativeTextLayout.content(value,template:sample(""),dpi:72)
    XCTAssertEqual(text.typography?.runs.map(\.length),[1,1])
    XCTAssertEqual(text.typography?.runs.last?.style.glyphOverride?.glyph,glyph)
    let line=CTLineCreateWithAttributedString(try NativeTextLayout.attributed(text,dpi:72))
    let runs=CTLineGetGlyphRuns(line) as! [CTRun]
    var glyphs=[CGGlyph](repeating:0,count:2);CTRunGetGlyphs(runs[0],CFRange(location:0,length:0),&glyphs)
    XCTAssertEqual(glyphs[0],glyph)
    let doc=try document(text)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
    var bad=text;bad.text="BA";XCTAssertThrowsError(try bad.validate())
    var options=TypeFontOptions();options.features=[.init("liga"),.init("liga")];XCTAssertThrowsError(try options.validate())
    options.features=[.init("bad")];XCTAssertThrowsError(try options.validate())
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(document(text)))
  }
}
