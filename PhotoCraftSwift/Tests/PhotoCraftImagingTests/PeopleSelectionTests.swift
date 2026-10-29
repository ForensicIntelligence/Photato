import XCTest
import PhotoCraftCore
import PhotoCraftImaging

final class PeopleSelectionTests: XCTestCase {
  func testWholePersonUnionSoftEdgesModesHistoryAndNativeSaving() throws {
    let d = try CraftDocument(width:4,height:2), source = ObjectFinderSource(d,layerID:d.activeLayerID,sampleAllLayers:false)
    let a = try SelectionMask(width:4,height:2,bytes:[0,127,128,255,0,0,200,255])
    let b = try SelectionMask(width:4,height:2,bytes:[255,0,240,255,0,0,0,0])
    let scene = try PeopleScene(source:source,input:Surface(width:4,height:2,fill:.white),masks:[.init(instanceID:7,mask:b),.init(instanceID:2,mask:a)])
    XCTAssertEqual(scene.people.map(\.instanceID),[2,7]); XCTAssertEqual(scene.thumbnails.count,2)
    XCTAssertTrue(scene.thumbnails.values.allSatisfy{$0.width<=96 && $0.height<=96})
    let union = try scene.coverage(instanceIDs:[7,2],hardEdge:false)
    XCTAssertEqual(union.bytes,[255,127,240,255,0,0,200,255])
    XCTAssertEqual(try scene.coverage(instanceIDs:[2],hardEdge:true).bytes,[0,0,255,255,0,0,255,255])
    for mode in SelectionMode.allCases {
      var session = EditorSession(document:d); try session.execute(.selection(.init(x:0,y:0,width:2,height:2)))
      let before = session.document
      try session.execute(scene.command(instanceIDs:[2,7],mode:mode,hardEdge:false)); let after = session.document
      var expected = before; try Command.selectionCoverage(union,mode).apply(to:&expected); XCTAssertEqual(after,expected)
      XCTAssertEqual(after.layers,d.layers); try session.undo(); XCTAssertEqual(session.document,before); try session.redo(); XCTAssertEqual(session.document,after)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(after)),after)
    }
  }
  func testEmptyDetectionInvalidMasksAndInvalidSelection() throws {
    let d = try CraftDocument(width:2,height:1), key = ObjectFinderSource(d,layerID:d.activeLayerID,sampleAllLayers:false), input = try Surface(width:2,height:1)
    let empty = try PeopleScene(source:key,input:input,masks:[]); XCTAssertTrue(empty.people.isEmpty)
    XCTAssertThrowsError(try empty.coverage(instanceIDs:[1],hardEdge:false))
    let mask = try SelectionMask(width:2,height:1,bytes:[255,0]), scene = try PeopleScene(source:key,input:input,masks:[.init(instanceID:1,mask:mask)])
    for ids in [[],[1,1],[0],[99]] { XCTAssertThrowsError(try scene.coverage(instanceIDs:ids,hardEdge:false)) }
    for masks in [[DetectedObjectMask(instanceID:0,mask:mask)],[.init(instanceID:1,mask:mask),.init(instanceID:1,mask:mask)]] { XCTAssertThrowsError(try PeopleScene(source:key,input:input,masks:masks)) }
    XCTAssertThrowsError(try PeopleScene(source:key,input:Surface(width:1,height:1),masks:[]))
  }
}
