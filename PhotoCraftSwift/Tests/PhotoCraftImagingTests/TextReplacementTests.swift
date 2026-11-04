import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class TextReplacementTests:XCTestCase {
  func fixture(depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:400,height:200,depth:depth);d.resolution=144
    var text=TextContent(text:"cat cat",size:24,color:.black);var type=TextTypography();type.defaultStyle.size=18;type.defaultStyle.color = .black;text.typography=type
    var a=Layer(name:"Body",content:.text(text));a.x=30;a.y=20;a.affine = .translation(0.25,0.5);a.mask=try Surface(width:400,height:200,depth:depth,fill:.white)
    var b=Layer(name:"Caption",content:.text(text));b.x=50;b.y=90;d.layers=[a,b];d.activeLayerID=b.id;return d
  }
  func testAllDepthsUseNativeShapingAnchorMasksOneUndoAndPersistence()throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(depth:depth),request=RecordedTextReplacement(settings:.init(find:"cat"),replacement:"elephant")
      let result=try TextReplacementPreparation.prepare(source,request:request);XCTAssertEqual(result.occurrences,4);XCTAssertEqual(result.layers,2)
      var expected=source
      for layer in source.layers {guard case .text(var text)=layer.content else{return XCTFail()};text.text="elephant elephant";try ShapedTextLayout.replacement(layer,content:text,document:expected).apply(to:&expected)}
      var session=EditorSession(document:source);try session.execute(result.command);XCTAssertEqual(session.document,expected)
      XCTAssertEqual(session.undoStack.count,1);XCTAssertEqual(session.undoStack.last?.label,"Replace All Text")
      for layer in session.document.layers {XCTAssertEqual(layer.mask,source.layers.first{$0.id==layer.id}?.mask)}
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)),session.document)
      try session.undo();XCTAssertEqual(session.document,source);try session.redo();XCTAssertEqual(session.document,expected)
    }
  }
  func testSingleMatchFromCursorAndNoOpRetainsPristineDocument()throws {
    let source=try fixture(),id=source.layers[0].id
    let request=RecordedTextReplacement(settings:.init(find:"cat"),replacement:"dog",target:.init(id,in:source,preferActive:false),start:3,replaceAll:false)
    var session=EditorSession(document:source);let result=try TextReplacementPreparation.prepare(source,request:request);try session.execute(result.command)
    guard case .text(let text)=session.document.layers[0].content else{return XCTFail()};XCTAssertEqual(text.text,"cat dog");XCTAssertEqual(result.occurrences,1)
    let noop=RecordedTextReplacement(settings:.init(find:"absent"),replacement:"dog")
    let prepared=try TextReplacementPreparation.prepare(source,request:noop);var empty=EditorSession(document:source);try empty.execute(prepared.command)
    XCTAssertEqual(empty.document,source);XCTAssertTrue(empty.undoStack.isEmpty)
  }
  func testRecordedQueryReplaysDifferentContentsAndIDs()throws {
    let source=try fixture();var session=EditorSession(document:source);try session.startActionRecording(name:"Update terms")
    let request=RecordedTextReplacement(settings:.init(find:"cat"),replacement:"dog")
    try session.execute(TextReplacementPreparation.prepare(source,request:request).command)
    let action=try XCTUnwrap(session.actionRecording?.snapshot);XCTAssertEqual(action.steps.count,1)
    var target=try fixture();target.layers[0].content = .text(.init(text:"catapult cat",size:24,color:.black))
    let rendered=try RecordedActionRenderer.prepare(action,in:target);try rendered.command.apply(to:&target)
    guard case .text(let text)=target.layers[0].content else{return XCTFail()};XCTAssertEqual(text.text,"dogapult dog");XCTAssertNotEqual(target.id,source.id)
  }
  func testLaterOverflowAndLockedLayerAreAtomic()throws {
    var source=try fixture();source.layers[0].content = .text(.init(text:String(repeating:"cat",count:25000),size:10))
    let original=source;let request=RecordedTextReplacement(settings:.init(find:"cat"),replacement:"elephant")
    XCTAssertThrowsError(try TextReplacementPreparation.prepare(source,request:request));XCTAssertEqual(source,original)
    source.layers[0].protection = .image
    let result=try TextReplacementPreparation.prepare(source,request:request);XCTAssertEqual(result.layers,1);XCTAssertEqual(result.occurrences,2)
    var session=EditorSession(document:source);try session.execute(result.command);XCTAssertEqual(session.document.layers[0],source.layers[0])
  }
}
