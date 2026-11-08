import Foundation
import XCTest
@testable import PhotoCraftCore

final class ContentAwareSelectionModeTests: XCTestCase {
  func testExplicitSelectionCombinationsAndLegacyJSONRemainCompatible() throws {
    let old = try SelectionMask.make(.rectangle(.init(x:2,y:2,width:6,height:6)),width:12,height:10,antiAlias:false)
    var stroke=ContentAwareStroke();stroke.target = .selection;stroke.kind = .lasso;stroke.points=[[5,2],[10,2],[10,8],[5,8]]
    let shape=try SelectionMask.make(.rectangle(.init(x:5,y:2,width:5,height:6)),width:12,height:10,antiAlias:false)
    for mode in SelectionMode.allCases {
      stroke.selectionMode=mode
      let result=try stroke.applying(to:old)
      for y in 0..<10 {for x in 0..<12 {
        let range:Range<Int>
        switch mode {case .replace:range=5..<10;case .add:range=2..<10;case .subtract:range=2..<5;case .intersect:range=5..<8}
        let expected:UInt8=(2..<8).contains(y) && range.contains(x) ? 255:0
        XCTAssertEqual(result.byte(at:y*12+x),expected,"\(mode) at \(x),\(y)")
      }}
    }
    stroke.selectionMode=nil;stroke.add=true
    let legacy=try JSONEncoder().encode(stroke)
    XCTAssertFalse(String(decoding:legacy,as:UTF8.self).contains("selectionMode"))
    XCTAssertEqual(try JSONDecoder().decode(ContentAwareStroke.self,from:legacy),stroke)
    XCTAssertEqual(try stroke.applying(to:old),try shape.combined(with:old,mode:.add))
    stroke.target = .sampling;stroke.selectionMode = .replace
    XCTAssertThrowsError(try stroke.validate())
  }
  func testBrushNewSelectionReplacesOldAreaWithoutChangingLegacySampling() throws {
    let old=try SelectionMask.make(.rectangle(.init(x:1,y:1,width:3,height:3)),width:16,height:12,antiAlias:false)
    var s=ContentAwareStroke();s.target = .selection;s.selectionMode = .replace;s.size=4;s.points=[[11,6]]
    let next=try s.applying(to:old)
    XCTAssertEqual(next.byte(at:2*16+2),0);XCTAssertEqual(next.byte(at:6*16+11),255)
    s.target = .sampling;s.selectionMode=nil;s.add=false
    XCTAssertEqual(try s.applying(to:old),old)
    s.selectionMode = .add
    XCTAssertThrowsError(try s.applying(to:old))
  }
}
