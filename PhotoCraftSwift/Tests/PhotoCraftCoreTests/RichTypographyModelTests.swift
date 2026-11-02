import XCTest
@testable import PhotoCraftCore

final class RichTypographyModelTests:XCTestCase {
  func testOriginalByteRunNormalizationAndIndependentUnicodeBoundaries()throws {
    let rows=try TypeSourceRuns.normalize([.init(2,10),.init(1,20)],text:"héllo",default:5)
    XCTAssertEqual(rows,[.init(start:0,length:2,value:10),.init(start:2,length:3,value:20)])
    let scalar="A😀e\u{301}B",runs=try TypeSourceRuns.normalize([.init(2,"first"),.init(0,"dropped"),.init(2,"last")],text:scalar,default:"base")
    XCTAssertEqual(runs.map(\.utf16Length),[3,3]);XCTAssertTrue(runs.allSatisfy{TextTypography.isBoundary($0.utf16Start+$0.utf16Length,in:scalar)})
    XCTAssertEqual(try TypeSourceRuns.normalize([.init(0,33)],text:"",default:12),[.init(start:0,length:0,value:33)])
    XCTAssertThrowsError(try TypeSourceRuns.normalize([.init(-1,0)],text:"abc",default:0))
    XCTAssertEqual(try TypeSourceRuns.normalize([.init(Int.max,3)],text:"😀x",default:0).first?.utf16Length,3)
  }
  func testIndependentCharacterParagraphMergingPreservesScalarBoundaries()throws {
    var first=TypeStyle(),second=TypeStyle();first.size=12;second.size=24
    var para=TypeParagraph();para.firstIndent = -2.5;para.formatting = .init();para.formatting?.lastLine = .right
    let string="A😀e\u{301}B",characters=try TypeSourceRuns.normalize([.init(5,first),.init(4,second)],text:string,default:first),paragraphs=try TypeSourceRuns.normalize([.init(1,TypeParagraph()),.init(8,para)],text:string,default:para)
    let merged=try TypeSourceRuns.merge(characters:characters,paragraphs:paragraphs,text:string)
    XCTAssertEqual(merged.map(\.length),[1,2,3]);XCTAssertEqual(merged.last?.style.size,24);XCTAssertEqual(merged.last?.paragraph.firstIndent,-2.5)
    var type=TextTypography();type.runs=merged;try type.validate(text:string)
  }
  func text()throws->TextContent {
    var text=TextContent(text:"Owned 😀",fontName:"HelveticaNeue",size:18,color:.black),type=TextTypography()
    type.defaultStyle.characterFormatting = .init();type.defaultStyle.characterFormatting?.kerning = .optical;type.defaultStyle.characterFormatting?.fauxItalic=true
    type.defaultParagraph.formatting = .init();type.defaultParagraph.firstIndent = -1.25;type.sourceFrame = .init();type.antialiasMode = .crisp;text.typography=type
    return text
  }
  func testNative69CacheBitsBaselineMasksNoOpAndHistory()throws {
    var value=try text(),cache=try Surface(width:8,height:4,depth:.f32,colorEncoding:.linearRGB);cache.setLinearPixel(x:1,y:2,Pixel(-0.0,4,-0.25,0.5))
    let logical=Transform2D.translation(10.25,20.5) * .rotation(0.1)
    value.importedAppearance = .init(content:value,pixels:cache,x:12,y:9,textTransform:logical,typeRecord:Data("owned TySh".utf8))
    var layer=Layer(name:"Source type",content:.text(value));layer.x=12;layer.y=9
    var doc=try CraftDocument(width:64,height:64,depth:.f32);doc.layers=[layer];doc.activeLayerID=layer.id;try doc.validate();XCTAssertEqual(doc.minimumArchiveVersion,69)
    let round=try NativeArchive.decode(NativeArchive.encodeChunked(doc));XCTAssertTrue(round==doc);XCTAssertTrue(round.layers[0].typeContent!.pristineSourceAppearance!.pixels!.linearPixel(x:1,y:2).hasSameBits(as:cache.linearPixel(x:1,y:2)))
    XCTAssertEqual(try layer.sourceTypeTransform(),logical);XCTAssertGreaterThan(doc.estimatedBytes,cache.allocatedBytes)
    var session=EditorSession(document:doc);try session.execute(.mask(layer.id,Surface(width:8,height:4,depth:.f32,fill:.white)));let before=session.document,mask=before.layers[0].maskCoordinateTransform
    var edited=value;edited.text="Edited";edited.importedAppearance=nil
    try session.execute(.importedType(.init(layerID:layer.id,content:edited,origin:.init(0,-10))))
    XCTAssertNil(session.document.layers[0].typeContent?.importedAppearance);XCTAssertEqual(session.document.layers[0].coordinateTransform,logical * .translation(0,-10));XCTAssertEqual(session.document.layers[0].maskCoordinateTransform,mask)
    try session.undo();XCTAssertTrue(session.document==before);try session.redo()
  }
  func testLegacyOptionalFieldsAndNewValidationStayDistinct()throws {
    let plain=TypeStyle(),encoded=try JSONEncoder().encode(plain);XCTAssertFalse(String(decoding:encoded,as:UTF8.self).contains("characterFormatting"))
    var character=TypeCharacterFormatting();character.weight=99;XCTAssertThrowsError(try character.validate())
    var paragraph=TypeParagraph();paragraph.startIndent = -4;try paragraph.validate();paragraph.formatting = .init();paragraph.formatting?.autoLeading=0;XCTAssertThrowsError(try paragraph.validate())
    var frame=TypeSourceFrame();frame.width = .infinity;XCTAssertThrowsError(try frame.validate())
    var doc=try CraftDocument(width:64,height:64),layer=Layer(name:"Retained",content:.text(try text()));let key=VideoKeyframe(property:.content,time:0,layer:layer)
    layer.content = .raster(try Surface(width:64,height:64));layer.videoKeyframes=[key];doc.layers=[layer];doc.activeLayerID=layer.id;XCTAssertEqual(doc.minimumArchiveVersion,69)
  }
}
