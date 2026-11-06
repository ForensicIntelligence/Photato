import AppKit
import CoreText
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PathTextEditingGeometryTests:XCTestCase {
  func testFrozenOriginalRendererWordsAndMetricsRemainExact()throws {
    let root=try XCTUnwrap(Bundle.module.url(forResource:"manifest",withExtension:"json",subdirectory:"Fixtures/PathTextLegacy")).deletingLastPathComponent()
    let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json")))as! [String:Any]
    let cases=try XCTUnwrap(manifest["cases"]as?[[String:Any]]);XCTAssertEqual(cases.count,36)
    for c in cases {
      let mode=try XCTUnwrap(TextGeometry.Mode(rawValue:c["mode"]as!String)),text=PathTextLegacyTests.text(mode,c["variant"]as!Int),depth=PixelDepth.allCases[c["depthIndex"]as!Int]
      let doc=try CraftDocument(width:400,height:300,depth:depth),surface=try NativeTextLayout.render(text,document:doc),m=try NativeTextLayout.metrics(text,dpi:72)
      XCTAssertEqual(surface.width,c["width"]as?Int);XCTAssertEqual(surface.height,c["height"]as?Int);XCTAssertEqual([m.origin.x,m.origin.y],c["origin"]as?[Double]);XCTAssertEqual(m.overset,c["overset"]as?Bool)
      XCTAssertEqual(PathTextLegacyTests.words(surface),try Data(contentsOf:root.appendingPathComponent(c["file"]as!String)),"Original native \(mode) / \(depth) / \(c["variant"]!)")
    }
  }
  func testStraightMeasuredCoreTextInsertionOffsetsAndProjection()throws {
    let path=VectorPath(components:[.init(knots:[.init(.init(20,80)),.init(.init(320,80))])])
    var text=PathTextLegacyTests.text(.path,0);text.text="Alpha";text.typography?.geometry?.path=path
    let line=CTLineCreateWithAttributedString(try NativeTextLayout.attributed(text,dpi:72)),g=try ShapedTextLayout.pathEditingGeometry(text,dpi:72)
    XCTAssertEqual(g.carets.map(\.utf16Index),Array(0...5))
    for caret in g.carets {
      XCTAssertEqual(caret.baseline.x,20+CTLineGetOffsetForStringIndex(line,caret.utf16Index,nil),accuracy:1e-9)
      XCTAssertEqual(caret.baseline.y,80,accuracy:1e-9);XCTAssertLessThan(caret.top.y,caret.bottom.y)
      XCTAssertEqual(g.insertionIndex(at:caret.baseline),caret.utf16Index)
    }
    XCTAssertEqual(try XCTUnwrap(g.baseline.nearestFraction(to:.init(95,82),tolerance:3)),0.25,accuracy:1e-9)
    XCTAssertNil(g.baseline.nearestFraction(to:.init(95,90),tolerance:3));XCTAssertNil(g.baseline.nearestFraction(to:.init(.nan,80),tolerance:3))
    XCTAssertThrowsError(try PathTextBaseline(.init(knots:[])))
    XCTAssertTrue(g.selectionStrips(NSRange(location:Int.max,length:1)).isEmpty)
  }
  func testCurvedFittingReverseOffsetEmptyAndUnicodeSelectionBoundaries()throws {
    for mode in PathTextLegacyTests.modes {for variant in 0..<3 {
      var text=PathTextLegacyTests.text(mode,variant);text.text="fi A\u{301} \u{1F642}"
      let g=try ShapedTextLayout.pathEditingGeometry(text,dpi:72)
      XCTAssertEqual(g.carets.map(\.utf16Index),[0,1,2,3,5,6,8])
      XCTAssertFalse(g.carets.contains{$0.utf16Index==4 || $0.utf16Index==7})
      XCTAssertEqual(g.carets.first?.utf16Index,0);XCTAssertEqual(g.carets.last?.utf16Index,8)
      XCTAssertEqual(g.selectionStrips(NSRange(location:3,length:2)).count,1)
      for caret in g.carets where caret.visible {let coincident=g.carets.filter{$0.visible && hypot($0.baseline.x-caret.baseline.x,$0.baseline.y-caret.baseline.y)<1e-8};XCTAssertTrue(coincident.contains{$0.utf16Index==g.insertionIndex(at:caret.baseline)})}
      text.text="";let empty=try ShapedTextLayout.pathEditingGeometry(text,dpi:72)
      XCTAssertEqual(empty.carets.count,1);XCTAssertGreaterThan(hypot(empty.carets[0].top.x-empty.carets[0].bottom.x,empty.carets[0].top.y-empty.carets[0].bottom.y),1)
    }}
    var vertical=PathTextLegacyTests.text(.path,0);vertical.typography?.orientation = .vertical
    XCTAssertThrowsError(try ShapedTextLayout.pathEditingGeometry(vertical,dpi:72))
  }
}
