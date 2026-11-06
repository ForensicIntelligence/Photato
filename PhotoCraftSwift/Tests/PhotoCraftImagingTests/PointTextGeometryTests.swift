import AppKit
import CoreText
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PointTextGeometryTests:XCTestCase {
  static func text(_ alignment:TypeParagraph.Alignment = .left,vertical:Bool=false)->TextContent {
    var text=TextContent(text:"Alpha"),type=TextTypography();type.defaultStyle.font="HelveticaNeue";type.defaultStyle.size=16
    type.defaultParagraph.alignment=alignment;if vertical{type.orientation = .vertical};text.typography=type;return text
  }
  func testFrozenLeftPointAndParagraphRGBAWordsRemainExact()throws {
    let root=try XCTUnwrap(Bundle.module.url(forResource:"manifest",withExtension:"json",subdirectory:"Fixtures/PointTextLegacy")).deletingLastPathComponent()
    let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json")))as! [String:Any]
    let cases=try XCTUnwrap(manifest["cases"]as?[[String:Any]]);XCTAssertEqual(cases.count,15)
    for record in cases {
      let text=PointTextLegacyTests.text(record["kind"]as!String),depth=PixelDepth.allCases[record["depthIndex"]as!Int]
      let document=try CraftDocument(width:180,height:140,depth:depth),surface=try NativeTextLayout.render(text,document:document)
      let metrics=try NativeTextLayout.metrics(text,dpi:72)
      XCTAssertEqual(surface.width,record["width"]as?Int);XCTAssertEqual(surface.height,record["height"]as?Int)
      XCTAssertEqual([metrics.origin.x,metrics.origin.y],record["origin"]as?[Double])
      XCTAssertEqual(metrics.firstBaseline,record["firstBaseline"]as?Double)
      let expected=try Data(contentsOf:root.appendingPathComponent(record["file"]as!String))
      XCTAssertEqual(PointTextLegacyTests.words(surface),expected,"Frozen prior-native \(record["kind"]!) / \(depth)")
    }
  }
  func testCommonPointAnchorUsesMeasuredGlyphAdvanceWithoutVirtualCanvas()throws {
    let plain=Self.text(),base=try NativeTextLayout.metrics(plain,dpi:72)
    let attributed=try NativeTextLayout.attributed(plain,dpi:72),line=CTLineCreateWithAttributedString(attributed)
    let advance=CTLineGetTypographicBounds(line,nil,nil,nil)
    for vertical in [false,true] {for alignment in [TypeParagraph.Alignment.center,.right] {
      let text=Self.text(alignment,vertical:vertical),metrics=try NativeTextLayout.metrics(text,dpi:72)
      let displacement=alignment == .center ? -advance/2:-advance
      XCTAssertEqual(vertical ? metrics.origin.y:metrics.origin.x,floor(displacement))
      XCTAssertLessThan(metrics.width,100);XCTAssertLessThan(metrics.height,100)
      XCTAssertGreaterThan(metrics.layoutOrigin.x,32000)
      for depth in PixelDepth.allCases {
        let surface=try NativeTextLayout.render(text,document:CraftDocument(width:180,height:140,depth:depth))
        XCTAssertEqual(surface.width,metrics.width);XCTAssertEqual(surface.height,metrics.height)
        var nonzero=0
        for y in 0..<surface.height{for x in 0..<surface.width{if surface.pixel(x:x,y:y).a>0{nonzero += 1}}}
        XCTAssertGreaterThan(nonzero,30)
      }
    }}
    XCTAssertEqual(base.origin,.init(0,0));XCTAssertFalse(NativeTextLayout.usesPointAnchoring(plain))
  }
  func testMixedAlignmentsNewlineEmptyAndRichLastLineStayBounded()throws {
    var text=Self.text(.right);text.text="Alpha\nBeta"
    let type=try XCTUnwrap(text.typography)
    var left=type.defaultParagraph;left.alignment = .left
    text.typography?.runs=[.init(length:6,style:type.defaultStyle,paragraph:type.defaultParagraph),.init(length:4,style:type.defaultStyle,paragraph:left)]
    let metrics=try NativeTextLayout.metrics(text,dpi:72)
    XCTAssertEqual(metrics.origin.x,-41);XCTAssertLessThan(metrics.width,100);XCTAssertGreaterThan(metrics.width,60)
    for value in ["","\n","  ","Alpha\n"] {for alignment in [TypeParagraph.Alignment.center,.right] {
      var sample=Self.text(alignment);sample.text=value
      let current=try NativeTextLayout.metrics(sample,dpi:72)
      XCTAssertLessThan(current.width,100);XCTAssertLessThan(current.height,100)
    }}
    for last in [TypeParagraphFormatting.LastLine.center,.right] {
      var rich=Self.text(.justified);rich.typography?.defaultParagraph.formatting = .init();rich.typography?.defaultParagraph.formatting?.lastLine=last
      let current=try NativeTextLayout.metrics(rich,dpi:72)
      XCTAssertLessThan(current.width,100);XCTAssertEqual(current.origin.x,last == .center ? -21:-41)
    }
  }
  func testSourceFramesOutlineAndLayerOriginRetainLogicalAnchor()throws {
    var text=Self.text(.right),frame=TypeSourceFrame();frame.x=12.5;frame.y=25.25;text.typography?.sourceFrame=frame
    let metrics=try NativeTextLayout.metrics(text,dpi:72)
    XCTAssertEqual(metrics.origin.x,12.5-41);XCTAssertEqual(metrics.origin.y,25.25-metrics.firstBaseline)
    let path=try NativeTextLayout.outline(text,dpi:72),bounds=path.boundingBoxOfPath
    XCTAssertGreaterThanOrEqual(bounds.minX,-1);XCTAssertLessThan(bounds.maxX,CGFloat(metrics.width)+1)
    var document=try CraftDocument(width:200,height:100);var layer=Layer(name:"Point",content:.text(Self.text()))
    layer.x=70;layer.y=30;layer.affine=layer.coordinateTransform * .scale(1.2,0.8);layer.x=0;layer.y=0;document.layers=[layer];document.activeLayerID=layer.id
    let original=layer.coordinateTransform.point(0,0)
    let changed=Self.text(.right),command=try ShapedTextLayout.replacement(layer,content:changed,document:document)
    try command.apply(to:&document)
    let result=document.layers[0],new=try NativeTextLayout.metrics(changed,dpi:72)
    let anchor=result.coordinateTransform.point(-new.origin.x,-new.origin.y)
    XCTAssertEqual(anchor.x,original.x,accuracy:1e-10);XCTAssertEqual(anchor.y,original.y,accuracy:1e-10)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)),document)
  }
}
