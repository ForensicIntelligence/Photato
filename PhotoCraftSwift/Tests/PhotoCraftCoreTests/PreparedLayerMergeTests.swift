import Foundation
import XCTest
@testable import PhotoCraftCore

final class PreparedLayerMergeTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    d.layers.append(Layer(name:"Shape",content:.shape(.init(kind:.rectangle,width:2,height:2,color:Pixel(0,0,1)))))
    d.activeLayerID=d.layers.last?.id;return d
  }
  func testRichDownRequiresPixelBaseAndResolvesUnrelatedGroups()throws {
    var d=try fixture();let id=d.layers[1].id
    XCTAssertTrue(LayerMerge.canApply(.down,layerIDs:[id],in:d))
    d.layers[0].content = .fill(.white)
    XCTAssertThrowsError(try LayerMergePlan(.down,layerIDs:[id],in:d))
    d=try fixture();let top=d.layers[1];try Command.newGroup(.init(name:"Other"),children:[d.layers[0].id]).apply(to:&d)
    XCTAssertThrowsError(try LayerMergePlan(.down,layerIDs:[top.id],in:d))
    XCTAssertTrue(LayerMerge.canApply(.selected,layerIDs:Set(d.layers.map(\.id)),in:d))
  }
  func testSiblingGroupsCanonicalizeDescendantsAndRetainParent()throws {
    var d=try fixture();let ids=Set(d.layers.map(\.id))
    try Command.newGroup(.init(name:"Group"),children:Array(ids)).apply(to:&d)
    let group=try XCTUnwrap(d.activeLayerID)
    let plan=try LayerMergePlan(.selected,layerIDs:ids.union([group]),in:d)
    XCTAssertEqual(plan.rootIDs,[group]);XCTAssertEqual(plan.removedIDs,ids.union([group]))
    let children=try LayerMergePlan(.selected,layerIDs:ids,in:d)
    XCTAssertEqual(children.parentID,group)
    var large=try CraftDocument(width:1,height:1)
    let pixel=try Surface(width:1,height:1)
    large.layers=(0..<LayerLimits.maximumLayers).map{n in var l=Layer(name:"Layer \(n)",content:.raster(pixel));l.clipped=n>0;return l}
    large.activeLayerID=large.layers.last?.id
    let chain=try LayerMergePlan(.visible,layerIDs:[],in:large)
    XCTAssertEqual(chain.removedIDs.count,LayerLimits.maximumLayers)
  }
  func testLockedHiddenClippingAndDifferentParentsRejectWithoutMutation()throws {
    var d=try fixture();let original=d
    d.layers[1].clipped=true;XCTAssertThrowsError(try LayerMergePlan(.selected,layerIDs:[d.layers[1].id],in:d))
    XCTAssertNoThrow(try LayerMergePlan(.down,layerIDs:[d.layers[1].id],in:d))
    d=original;d.layers[1].locked=true;XCTAssertFalse(LayerMerge.canApply(.down,layerIDs:[d.layers[1].id],in:d))
    d=original;try Command.newGroup(.init(name:"Group"),children:[d.layers[1].id]).apply(to:&d)
    d.layers[0].visible=false;d.activeLayerID=d.layers.last?.id
    XCTAssertThrowsError(try LayerMergePlan(.selected,layerIDs:[d.layers[0].id,d.layers[1].id],in:d))
    d.layers[1].visible=false
    XCTAssertThrowsError(try LayerMergePlan(.visible,layerIDs:[],in:d))
  }
  func testSourceBoundPreparedMergeUndoAndCancellation()async throws {
    let source=try fixture();var result=source;result.name="Prepared"
    let edit=PreparedLayerMerge(source:source,result:result,layerIDs:[source.layers[1].id],operation:.down)
    var s=EditorSession(document:source);try s.execute(.preparedLayerMerge(edit));XCTAssertEqual(s.document,result)
    try s.undo();XCTAssertEqual(s.document,source);try s.redo();XCTAssertEqual(s.document,result)
    XCTAssertThrowsError(try edit.applied(to:result))
    let task=Task {withUnsafeCurrentTask{$0?.cancel()};return try edit.applied(to:source)}
    do{_=try await task.value;XCTFail("Cancelled merge committed")}catch is CancellationError{}
  }
}
