import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ComponentToolPersistenceTests:XCTestCase {
  func testMaximumPreparedComponentFillPersistsAndRejectsStaleCommit() throws {
    let original=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,background:.clear,mode:.lab),id=original.layers[0].id
    let command=Command.modeComponents(.init(layerID:id,components:[0,2],operation:.fill(0.25,1)))
    let prepared=try PreparedEdit(command:command,document:original)
    var session=EditorSession(document:original);try session.executePrepared(prepared)
    XCTAssertEqual(session.document.layers[0].nativeMode?.rawWord(component:0,index:89_999_999_999),16384)
    XCTAssertEqual(session.document.layers[0].nativeMode?.rawWord(component:2,index:89_999_999_999),16384)
    let saved=try NativeArchive.encode(session.document)
    XCTAssertEqual(try NativeArchive.decodePaged(saved),session.document)
    try session.undo();XCTAssertEqual(session.document,original);try session.redo()
    var stale=EditorSession(document:original);try stale.execute(.renameLayer(id,"Changed"));let before=stale.document
    XCTAssertThrowsError(try stale.executePrepared(prepared));XCTAssertEqual(stale.document,before)
  }
}
