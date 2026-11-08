import Foundation
import XCTest
@testable import PhotoCraftCore

final class BlendChannelRestrictionsTests:XCTestCase {
  func style(_ channels:[Int])->LayerStyle {var s=LayerStyle();s.restrictedChannels=channels;return s}
  func testStrictJSONAndComponentValidationAndLegacyDefault()throws {
    XCTAssertNil(LayerStyle().restrictedChannels);XCTAssertEqual(try CraftDocument(width:4,height:3).minimumArchiveVersion,10)
    for text in [#"{"restrictedChannels":[0,0]}"#,#"{"restrictedChannels":[3]}"#,#"{"restrictedChannels":[-1]}"#,#"{"restrictedChannels":[true]}"#,#"{"restrictedChannels":[0.5]}"#,#"{"restrictedChannels":"red"}"#]{XCTAssertThrowsError(try LayerStyle.decodeJSON(Data(text.utf8)))}
    XCTAssertEqual(try LayerStyle.decodeJSON(Data(#"{"restrictedChannels":[0,2]}"#.utf8)).restrictedChannels,[0,2])
    let before=Pixel(0.125,0.25,0.5,0.75),after=Pixel(0.75,0.5,0.25,1)
    XCTAssertTrue(BlendChannelRestrictions.applying([0],after:after,before:before).hasSameBits(as:Pixel(0.125,0.5,0.25,1)))
    XCTAssertTrue(BlendChannelRestrictions.applying([0,1,2],after:after,before:before).hasSameBits(as:before))
    var gray=try CraftDocument(width:4,height:3);gray.modeDescriptor=try .init(mode:.grayscale,depth:.u8)
    XCTAssertThrowsError(try style([0]).validate(in:gray))
  }
  func testMaximumSparseStyleTransactionNative89AndUndoAreAtomic()throws {
    let d=try CraftDocument(width:300000,height:300000,depth:.f32),id=try XCTUnwrap(d.activeLayerID);var session=EditorSession(document:d)
    try session.execute(.layerStyle([id],style([0])));let changed=session.document
    XCTAssertEqual(changed.minimumArchiveVersion,89);XCTAssertEqual(changed.layers[0].content,d.layers[0].content)
    let bytes=try NativeArchive.encode(changed);XCTAssertLessThan(bytes.count,1024*1024);XCTAssertEqual(try NativeArchive.decode(bytes),changed)
    var effect=style([0]);effect.effects=[LayerEffect(.stroke)];XCTAssertThrowsError(try session.execute(.layerStyle([id],effect)));XCTAssertEqual(session.document,changed)
    try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,changed)
    var locked=changed;locked.layers[0].protection=[.all];let original=locked
    XCTAssertThrowsError(try Command.layerStyle([id],style([1])).apply(to:&locked));XCTAssertEqual(locked,original)
  }
  func testLayerCompAndLastStateRequireFeatureVersionWithoutCurrentStyle()throws {
    var d=try CraftDocument(width:4,height:3);d.layers[0].style=style([2]);let comp=LayerComp(name:"Owned",document:d)
    var comps=LayerComps();comps.comps=[comp];d.layerComps=comps;d.layers[0].style=nil
    XCTAssertEqual(d.minimumArchiveVersion,89);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    comps.comps=[];comps.lastDocumentState=comp.layers;d.layerComps=comps;XCTAssertEqual(d.minimumArchiveVersion,89)
  }
  func testChannelChoicesHoldAcrossNilAndDifferentStyleKeyframes()throws {
    let d=try CraftDocument(width:4,height:3);var first=d.layers[0],last=first;last.style=style([0])
    var keys=[VideoKeyframe(property:.style,time:0,layer:first),VideoKeyframe(property:.style,time:1,layer:last)]
    XCTAssertNil(try VideoKeyframe.evaluate(keys,property:.style,time:0.5)?.style)
    XCTAssertEqual(try VideoKeyframe.evaluate(keys,property:.style,time:1)?.style?.restrictedChannels,[0])
    first.style=style([1]);keys[0]=VideoKeyframe(property:.style,time:0,layer:first)
    XCTAssertEqual(try VideoKeyframe.evaluate(keys,property:.style,time:0.5)?.style?.restrictedChannels,[1])
    last.style=nil;keys[1]=VideoKeyframe(property:.style,time:1,layer:last)
    XCTAssertEqual(try VideoKeyframe.evaluate(keys,property:.style,time:0.5)?.style?.restrictedChannels,[1])
    XCTAssertNil(try VideoKeyframe.evaluate(keys,property:.style,time:1)?.style)
  }

}
