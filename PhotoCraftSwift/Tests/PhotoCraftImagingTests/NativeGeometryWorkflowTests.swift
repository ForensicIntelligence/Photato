import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class NativeGeometryWorkflowTests:XCTestCase {
  func model() throws -> CraftDocument {
    var d=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,background:.clear,mode:.cmyk)
    var native=try XCTUnwrap(d.layers[0].nativeMode)
    try native.set(0.75,component:3,index:90_000_000_000-1)
    try native.set(1,component:4,index:90_000_000_000-1)
    d.layers[0].nativeMode=native;d.layers[0].content = .raster(try native.surface());return d
  }
  func testMaximumTrimPreparationAndNativePersistenceKeepNumericalInk() throws {
    let original=try model()
    let prepared=try CanvasEdgePreparation.command(original,operation:.trim(.init(basis:.transparent)))
    var session=EditorSession(document:original);try session.execute(prepared)
    let result=session.document
    XCTAssertEqual(result.width,1);XCTAssertEqual(result.height,1)
    XCTAssertEqual(result.layers[0].nativeMode?.rawWord(component:3,index:0),49151)
    XCTAssertEqual(result.layers[0].nativeMode?.rawWord(component:4,index:0),65535)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encode(result)),result)
    try session.undo();XCTAssertEqual(session.document,original)
    try session.redo();XCTAssertEqual(session.document,result)
  }
  func testMaximumWholeDocumentTurnsAndInterpolationRetainHistoryAndProfile() throws {
    let original=try model();var session=EditorSession(document:original)
    try session.execute(.rotateCanvas(.clockwise))
    let turned=session.document,at=299999*300000
    XCTAssertEqual(turned.layers[0].nativeMode?.rawWord(component:3,index:at),49151)
    XCTAssertEqual(turned.layers[0].nativeMode?.profile,original.layers[0].nativeMode?.profile)
    try session.undo();XCTAssertEqual(session.document,original)
    try session.execute(.imageSize(150000,150000,144,.nearest))
    XCTAssertEqual(session.document.layers[0].nativeMode?.rawWord(component:3,index:22_500_000_000-1),49151)
    XCTAssertEqual(session.document.pixelsPerInch,144)
    try session.undo();XCTAssertEqual(session.document,original)
    try session.execute(.imageSize(13,7,72,.bicubic))
    XCTAssertEqual(session.document.width,13);XCTAssertEqual(session.document.height,7)
    XCTAssertEqual(session.document.colorMode,.cmyk)
    try session.undo();XCTAssertEqual(session.document,original)
  }
}
