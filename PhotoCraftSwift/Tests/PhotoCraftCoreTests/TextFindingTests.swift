import Foundation
import XCTest
@testable import PhotoCraftCore

final class TextFindingTests:XCTestCase {
  func testLiteralCaseUnicodeWholeWordsAndTransparentStart()throws {
    let text="cat scatter Cat cat_cat cat’s 😀cat"
    let all=try TextSearchSettings(find:"cat").ranges(in:text)
    XCTAssertEqual(all.count,7)
    let words=try TextSearchSettings(find:"cat",wholeWord:true).ranges(in:text)
    XCTAssertEqual(words.map{(text as NSString).substring(with:$0)},["cat","Cat","cat"])
    XCTAssertTrue(try TextSearchSettings(find:"cat",wholeWord:true).ranges(in:"bobcat",start:3).isEmpty)
    XCTAssertEqual(try TextSearchSettings(find:"Cat",caseSensitive:true).ranges(in:text).count,1)
    XCTAssertEqual(try TextSearchSettings(find:".").ranges(in:"a.b.*").map(\.location),[1,3])
    XCTAssertEqual(try TextSearchSettings(find:"😀").ranges(in:"A😀B😀").map(\.location),[1,4])
  }
  func testReplacementsKeepRichRunsAndUnicodeScalarBoundaries()throws {
    var text=TextContent(text:"A😀B cat C");var type=TextTypography();var red=TypeStyle();red.color=Pixel(1,0,0)
    var blue=red;blue.color=Pixel(0,0,1);var para=TypeParagraph();para.alignment = .right
    type.runs=[.init(length:4,style:red),.init(length:6,style:blue,paragraph:para)];text.typography=type
    let result=try NativeTextSearch.replacing(text,ranges:[.init(location:1,length:3)],with:"猫")
    XCTAssertEqual(result.text,"A猫 cat C");XCTAssertEqual(result.typography?.runs,[.init(length:2,style:red),.init(length:6,style:blue,paragraph:para)])
    let deleted=try NativeTextSearch.replacing(text,ranges:[.init(location:5,length:3)],with:"")
    XCTAssertEqual(deleted.text,"A😀B  C");XCTAssertEqual(deleted.typography?.runs,[.init(length:4,style:red),.init(length:3,style:blue,paragraph:para)])
    XCTAssertThrowsError(try NativeTextSearch.replacing(text,ranges:[.init(location:2,length:1)],with:"X"))
    XCTAssertEqual(text.text,"A😀B cat C")
  }
  func testVisibleUnlockedLayerScopePaginationAndZeroOpacity()throws {
    func text(_ name:String)->Layer {Layer(name:name,content:.text(.init(text:"cat cat")))}
    var hiddenGroup=Layer(name:"Hidden group",content:.group(.init()));hiddenGroup.visible=false
    var nested=text("Hidden child");nested.parentID=hiddenGroup.id
    var locked=text("Locked");locked.protection = .image
    var zero=text("Zero opacity");zero.opacity=0;zero.protection = .position
    let top=text("Top")
    var d=try CraftDocument(width:120,height:80);d.layers=[nested,hiddenGroup,locked,zero,top];d.activeLayerID=top.id;try d.validate()
    let result=try NativeTextSearch.scan(d,settings:.init(find:"cat"),offset:1,limit:2)
    XCTAssertEqual(result.total,4);XCTAssertTrue(result.hasMore);XCTAssertEqual(result.matches.map(\.layerID),[top.id,zero.id]);XCTAssertEqual(result.matches.map(\.location),[4,0])
    XCTAssertTrue(try NativeTextSearch.scan(d,settings:.init(find:"cat"),layerID:nested.id).matches.isEmpty)
    XCTAssertEqual(try NativeTextSearch.scan(d,settings:.init(find:"cat"),layerID:top.id,start:3).total,1)
    XCTAssertThrowsError(try NativeTextSearch.scan(d,settings:.init(find:"cat"),start:1))
  }
  func testChangedGlyphOverrideIsRemovedButUntouchedGlyphIsRetained()throws {
    var text=TextContent(text:"fi cat");var type=TextTypography();var special=TypeStyle();special.glyphOverride = .init(glyph:12,baseString:"fi")
    type.runs=[.init(length:2,style:special),.init(length:4,style:.init())];text.typography=type;try text.validate()
    let tail=try NativeTextSearch.replacing(text,ranges:[.init(location:3,length:3)],with:"dog")
    XCTAssertEqual(tail.typography?.runs.first?.style.glyphOverride,special.glyphOverride)
    let changed=try NativeTextSearch.replacing(text,ranges:[.init(location:1,length:1)],with:"o")
    XCTAssertEqual(changed.text,"fo cat");XCTAssertTrue(changed.typography!.runs.allSatisfy{$0.style.glyphOverride==nil});try changed.validate()
  }
  func testUnicodeLayerNamesRetainExistingNativeCapacity()throws {
    let name=String(repeating:"層",count:400)
    let request=RecordedTextReplacement(settings:.init(find:"cat"),replacement:"dog",target:.named(name,occurrence:0))
    XCTAssertNoThrow(try request.validate())
    var invalid=request;invalid.target = .named(String(repeating:"x",count:65536),occurrence:0);XCTAssertThrowsError(try invalid.validate())
    invalid=request;invalid.target = .named(name,occurrence:-1);XCTAssertThrowsError(try invalid.validate())
  }
  func testNoOpValidationLimitsAndPreparedRecordingWithoutUndo()throws {
    let text=TextContent(text:"cat");XCTAssertEqual(try NativeTextSearch.replacing(text,ranges:[.init(location:0,length:3)],with:"cat"),text)
    XCTAssertThrowsError(try TextSearchSettings(find:"").validate())
    XCTAssertThrowsError(try TextSearchSettings(find:"😀").ranges(in:"😀",start:1))
    XCTAssertThrowsError(try NativeTextSearch.replacing(text,ranges:[.init(location:0,length:3)],with:String(repeating:"a",count:100001)))
    let d=try CraftDocument(width:8,height:8);var session=EditorSession(document:d);try session.startActionRecording(name:"Future text")
    let request=RecordedTextReplacement(settings:.init(find:"cat"),replacement:"dog")
    try session.execute(.preparedAction(.init(source:d,result:d,title:"Replace All Text",recording:.replaceText(request))))
    XCTAssertEqual(session.document,d);XCTAssertTrue(session.undoStack.isEmpty)
    guard case .replaceText(let recorded)=try XCTUnwrap(session.actionRecording?.snapshot.steps.first).operation else{return XCTFail("Semantic search operation required")}
    XCTAssertEqual(recorded,request)
  }
}
