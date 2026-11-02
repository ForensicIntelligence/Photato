import XCTest
@testable import PhotoCraftCore

final class DocumentGuideTests:XCTestCase {
  func testCommandsNative78HistoryAndAtomicValidation()throws {
    let d=try CraftDocument(width:32,height:24);var session=EditorSession(document:d)
    let a=DocumentGuide(axis:.horizontal,position:-0.0,color:Pixel(1,0.25,0.5)),b=DocumentGuide(axis:.vertical,position:12.125)
    try session.execute(.guides(.add([a,b])));let created=session.document
    XCTAssertEqual(created.minimumArchiveVersion,78);XCTAssertEqual(created.layers,d.layers)
    for bytes in [try NativeArchive.encode(created),try NativeArchive.encodeChunked(created)] {
      let decoded=try NativeArchive.decode(bytes);XCTAssertEqual(decoded,created);XCTAssertEqual(decoded.guides?.first?.position.bitPattern,Double(-0.0).bitPattern)
    }
    try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,created)
    XCTAssertThrowsError(try session.execute(.guides(.add([a]))));XCTAssertEqual(session.document,created)
    var invalid=b;invalid.position = .nan;XCTAssertThrowsError(try session.execute(.guides(.update([invalid]))));XCTAssertEqual(session.document,created)
    XCTAssertThrowsError(try session.execute(.guides(.delete([UUID()]))));XCTAssertEqual(session.document,created)
    try session.execute(.guides(.delete([a.id])));XCTAssertEqual(session.document.guides,[b])
  }
  func testLayoutMatchesManualColumnGutterAndMarginCoordinates()throws {
    var layout=GuideLayout();layout.columns=3;layout.rows=2;layout.columnGutter=15;layout.rowGutter=20;layout.left=50;layout.right=50;layout.top=10;layout.bottom=10
    let lines=try layout.guides(width:1000,height:600)
    XCTAssertEqual(lines.filter{$0.axis == .vertical}.map(\.position),[50,340,355,645,660,950])
    XCTAssertEqual(lines.filter{$0.axis == .horizontal}.map(\.position),[10,290,310,590])
    layout.columnGutter=500;XCTAssertThrowsError(try layout.guides(width:1000,height:600))
    layout.columnGutter=15;layout.left=600;layout.right=600;XCTAssertThrowsError(try layout.guides(width:1000,height:600))
  }
  func testWholeDocumentGeometryMapsGuidesAndRejectsObliqueLoss()throws {
    var d=try CraftDocument(width:20,height:10);d.guides=[.init(axis:.vertical,position:5),.init(axis:.horizontal,position:3)]
    var session=EditorSession(document:d);try session.execute(.imageSize(40,20,72,.nearest));XCTAssertEqual(session.document.guides?.map(\.position),[10,6])
    try session.undo();try session.execute(.crop(.init(x:2,y:1,width:10,height:7)));XCTAssertEqual(session.document.guides?.map(\.position),[3,2])
    var mapped=d;try mapped.mapGuides(.rotation(90));XCTAssertEqual(mapped.guides?.map(\.axis),[.horizontal,.vertical]);XCTAssertEqual(mapped.guides?.map(\.position),[5,-3])
    XCTAssertThrowsError(try mapped.mapGuides(.rotation(20)))
  }
  func testSnappingUsesBoundsCentersToleranceAndStableTies()throws {
    var d=try CraftDocument(width:100,height:80);d.guides=[.init(axis:.vertical,position:30),.init(axis:.horizontal,position:40)]
    let snapped=d.snappedToGuides(.init(x:10,y:20,width:10,height:10),dx:9,dy:8,tolerance:2)
    XCTAssertEqual(snapped.0,10);XCTAssertEqual(snapped.1,10)
    let unchanged=d.snappedToGuides(.init(x:10,y:20,width:10,height:10),dx:3,dy:3,tolerance:1)
    XCTAssertEqual(unchanged.0,3);XCTAssertEqual(unchanged.1,3)
    d.guides=[.init(axis:.vertical,position:9),.init(axis:.vertical,position:11)]
    XCTAssertEqual(d.snappedToGuides(.init(x:0,y:0,width:1,height:1),dx:9.5,dy:0,tolerance:1).0,9)
  }
  func testPositionUnitsLimitsAndLegacyDocumentDecoding()throws {
    for (text,expected) in [("1 in",300.0),("2.54 cm",300),("25.4 mm",300),("72 pt",300),("6 pc",300),("25%",50),("-7.5 px",-7.5)] {
      XCTAssertEqual(try GuidePosition.parse(text,extent:200,resolution:300),expected,accuracy:1e-9)
    }
    for text in ["nan","inf","1 banana","1000001px"] {XCTAssertThrowsError(try GuidePosition.parse(text,extent:200,resolution:300))}
    let d=try CraftDocument(width:4,height:4);XCTAssertNil(try NativeArchive.decode(NativeArchive.encode(d)).guides)
    var bad=DocumentGuide(axis:.vertical,position:0);bad.color=Pixel(2,0,0);XCTAssertThrowsError(try bad.validate())
    XCTAssertThrowsError(try CraftDocument.validateGuides(Array(repeating:.init(axis:.vertical,position:0),count:DocumentGuide.maximumCount+1)))
  }
}
