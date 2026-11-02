import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class SourceLayerEffectImportTests:XCTestCase {
  let helper=SourceLayerEffectTests()
  func testOriginalEffectsAndGlobalLightRemainEditableInNative75()throws {
    let entries=try helper.rows();XCTAssertEqual(entries.count,138)
    for row in entries {
      let bytes=try helper.bytes(row["project"] as! String),d=try PcraftImport.read(bytes);XCTAssertEqual(d.layers.count,2)
      let style=try XCTUnwrap(d.layers[1].style);XCTAssertFalse(style.effects.isEmpty);XCTAssertTrue(style.effects.allSatisfy{$0.advanced != nil});XCTAssertEqual(style.fillOpacity,0.625);XCTAssertEqual(d.layers[1].opacity,0.8125);XCTAssertEqual(d.globalLight,GlobalLight(angle:113.375,altitude:41.25));XCTAssertEqual(d.minimumArchiveVersion,75)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d);XCTAssertEqual(try helper.bytes(row["project"] as! String),bytes)
      let rendered=try Renderer.composite(d);XCTAssertTrue(rendered.pixel(x:15,y:11).isFinite)
      var session=EditorSession(document:d);try session.execute(.globalLight(GlobalLight(angle:73.375,altitude:21.25)));try session.undo();XCTAssertEqual(session.document,d)
    }
  }
  func testMissingPatternHintsAndReferenceAreRetainedWithoutSubstitution()throws {
    let missing=try XCTUnwrap(helper.rows().first{$0["name"] as? String == "pattern-unresolved"});let d=try PcraftImport.read(helper.bytes(missing["project"] as! String));let p=try XCTUnwrap(d.layers[1].style?.effects.first?.advanced?.paint?.pattern);XCTAssertNil(p.patternID);XCTAssertEqual(p.sourceID,"unresolved");XCTAssertEqual(p.sourceName,"Missing")
    let bound=try XCTUnwrap(helper.rows().first{$0["name"] as? String == "pattern-rotated"});let b=try PcraftImport.read(helper.bytes(bound["project"] as! String));let pattern=try XCTUnwrap(b.layers[1].style?.effects.first?.advanced?.paint?.pattern);XCTAssertEqual(pattern.patternID,"owned-fx");let reference=try XCTUnwrap(b.layers[1].style?.referenceOffset),absolute=b.layers[1].coordinateTransform.point(reference.x,reference.y);XCTAssertEqual(absolute.x,2.375);XCTAssertEqual(absolute.y,-1.625)
  }
  func testUnknownEffectFieldsAndInvalidGlobalLightRejectWholeImport()throws {
    let row=try XCTUnwrap(helper.rows().first),bytes=try helper.bytes(row["project"] as! String)
    let invalidEffect=try PcraftImportTests().source(bytes){d in var layers=d["layers"] as! [[String:Any]],effects=layers[1]["effects"] as! [String:Any];effects["bogus"]=1;layers[1]["effects"]=effects;d["layers"]=layers}
    XCTAssertThrowsError(try PcraftImportTests().convert(invalidEffect))
    let invalidLight=try PcraftImportTests().source(bytes){d in d["global_light"]=["angle":12,"altitude":91]};XCTAssertThrowsError(try PcraftImportTests().convert(invalidLight));XCTAssertEqual(try helper.bytes(row["project"] as! String),bytes)
  }
  func testCancelledSourceEffectsImportAndBudgetLeaveInputUntouched()async throws {
    let row=try XCTUnwrap(helper.rows().first),bytes=try helper.bytes(row["project"] as! String);XCTAssertThrowsError(try PcraftImport.read(bytes,rasterByteLimit:1))
    let task=Task.detached {withUnsafeCurrentTask{$0?.cancel()};return try PcraftImport.read(bytes)}
    do {_ = try await task.value;XCTFail("Cancelled import")}catch{XCTAssertTrue(error is CancellationError)};XCTAssertEqual(try helper.bytes(row["project"] as! String),bytes)
  }
}
