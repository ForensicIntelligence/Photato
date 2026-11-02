import Foundation
import XCTest
@testable import PhotoCraftCore

final class AdvancedLayerEffectTests:XCTestCase {
  func style() -> LayerStyle {var e=LayerEffect(.dropShadow);e.advanced=LayerEffectAdvanced();var s=LayerStyle(effects:[e]);s.referenceOffset=PathPoint(1.375,-2.625);s.sourcePSDData=Data([7,19,33,255]);return s}
  func testAdvancedRecordsAndSharedLightSurviveNative75()throws {
    var d=try CraftDocument(width:8,height:8);d.layers[0].style=style();d.globalLight=GlobalLight(angle:113.375,altitude:41.25);XCTAssertEqual(d.minimumArchiveVersion,75)
    for bytes in [try NativeArchive.encode(d),try NativeArchive.encodeChunked(d)] {XCTAssertEqual(try NativeArchive.decode(bytes),d)}
    var legacy=try CraftDocument(width:8,height:8);legacy.layers[0].style=LayerStyle(effects:[LayerEffect(.dropShadow)]);XCTAssertEqual(legacy.minimumArchiveVersion,13);XCTAssertNil(try NativeArchive.decode(NativeArchive.encode(legacy)).globalLight)
  }
  func testMultiTargetLightAndStyleCommitUndoRedoAndRejectAtomically()throws {
    var d=try CraftDocument(width:8,height:8);d.layers.append(Layer(name:"Second",content:.raster(try Surface(width:8,height:8))));var session=EditorSession(document:d);let ids=Set(d.layers.map(\.id)),edit=LayerStyleEdit(layerIDs:ids,style:style(),globalLight:GlobalLight(angle:73.375,altitude:31.25))
    try session.execute(.layerStyles(edit));let changed=session.document;XCTAssertEqual(changed.layers.compactMap(\.style).count,2);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,changed)
    d.layers[1].locked=true;let locked=d;XCTAssertThrowsError(try Command.layerStyles(edit).apply(to:&d));XCTAssertEqual(d,locked)
    XCTAssertThrowsError(try Command.globalLight(GlobalLight(altitude:91)).apply(to:&d));XCTAssertEqual(d,locked)
  }
  func testClosedJSONAndSourceBoundsRejectInvalidRecords()throws {
    let bytes=try JSONEncoder().encode(style());XCTAssertEqual(try LayerStyle.decodeJSON(bytes),style())
    var object=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]),effects=object["effects"] as! [[String:Any]],advanced=effects[0]["advanced"] as! [String:Any];advanced["invented"]=1;effects[0]["advanced"]=advanced;object["effects"]=effects;XCTAssertThrowsError(try LayerStyle.decodeJSON(JSONSerialization.data(withJSONObject:object)))
    var s=style();s.effects[0].advanced?.contour.points=[[0,0],[2,1]];XCTAssertThrowsError(try s.validate());s=style();s.effects[0].advanced?.texture=EffectBevelTexture();XCTAssertThrowsError(try s.validate())
    s=style();s.sourcePSDData=Data(repeating:0,count:1_048_577);XCTAssertThrowsError(try s.validate())
  }
  func testRecordedTransactionsRetainIndependentStylesAndSharedLight()throws {
    var d=try CraftDocument(width:8,height:8);let second=Layer(name:"Second",content:.raster(try Surface(width:8,height:8)));d.layers.append(second);let before=d
    let edit=LayerStyleEdit(styles:[d.layers[0].id:style(),second.id:nil],globalLight:GlobalLight(angle:137.5,altitude:33.75)),recorded=RecordedStyleEdit(edit,in:d),decoded=try JSONDecoder().decode(RecordedStyleEdit.self,from:JSONEncoder().encode(recorded))
    try Command.layerStyles(decoded.resolved(in:d)).apply(to:&d);XCTAssertEqual(d.layers[0].style,style());XCTAssertNil(d.layers[1].style);XCTAssertEqual(d.globalLight,edit.globalLight);XCTAssertNotEqual(d,before)
  }
}
