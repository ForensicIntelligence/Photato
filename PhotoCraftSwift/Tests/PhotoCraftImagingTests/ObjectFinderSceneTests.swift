import XCTest
import PhotoCraftCore
import PhotoCraftImaging

final class ObjectFinderSceneTests: XCTestCase {
  func testHitCoverageThresholdTieBreakingAndHardEdge() throws {
    let d = try CraftDocument(width:4,height:2), source = ObjectFinderSource(d,layerID:d.activeLayerID,sampleAllLayers:false)
    let a = try SelectionMask(width:4,height:2,bytes:[0,127,128,255,0,0,200,255])
    let b = try SelectionMask(width:4,height:2,bytes:[0,0,240,255,0,0,0,0])
    let scene = try ObjectFinderScene(source:source,masks:[.init(instanceID:7,mask:b),.init(instanceID:2,mask:a)])
    XCTAssertEqual(scene.objects.map(\.instanceID),[2,7]); XCTAssertNil(scene.object(at:.init(1,0)))
    XCTAssertEqual(scene.object(at:.init(2,0))?.instanceID,7); XCTAssertEqual(scene.object(at:.init(3,0))?.instanceID,2)
    XCTAssertNil(scene.object(at:.init(-1,0))); XCTAssertNil(scene.object(at:.init(.infinity,0)))
    XCTAssertEqual(try ObjectFinderScene.coverage(a,hardEdge:true).bytes,[0,0,255,255,0,0,255,255])
    XCTAssertEqual(try ObjectFinderScene.coverage(a,hardEdge:false),a)
    for mode in SelectionMode.allCases {
      var result = d; try scene.command(instanceID:2,mode:mode,hardEdge:false).apply(to:&result)
      var expected = d; try Command.selectionCoverage(a,mode).apply(to:&expected); XCTAssertEqual(result,expected)
    }
    XCTAssertThrowsError(try scene.command(instanceID:99,mode:.replace,hardEdge:false))
  }
  func testSourceIgnoresSelectionButInvalidatesPixelsAndSampling() throws {
    let d = try CraftDocument(width:8,height:6), key = ObjectFinderSource(d,layerID:d.activeLayerID,sampleAllLayers:false)
    var selected = d; selected.selection = .init(x:0,y:0,width:2,height:2); selected.activeLayerID = nil
    XCTAssertEqual(ObjectFinderSource(selected,layerID:d.activeLayerID,sampleAllLayers:false),key)
    selected.layers[0].x = 1; XCTAssertNotEqual(ObjectFinderSource(selected,layerID:d.activeLayerID,sampleAllLayers:false),key)
    XCTAssertNotEqual(ObjectFinderSource(d,layerID:d.activeLayerID,sampleAllLayers:true),key)
  }
  func testInvalidInstancesAndResourceBounds() throws {
    let d = try CraftDocument(width:2,height:1), source = ObjectFinderSource(d,layerID:d.activeLayerID,sampleAllLayers:false)
    let mask = try SelectionMask(width:2,height:1,bytes:[255,0])
    for masks: [DetectedObjectMask] in [[],[.init(instanceID:0,mask:mask)],[.init(instanceID:256,mask:mask)],[.init(instanceID:1,mask:mask),.init(instanceID:1,mask:mask)], [.init(instanceID:1,mask:try SelectionMask(width:1,height:1,bytes:[255]))]] {
      XCTAssertThrowsError(try ObjectFinderScene(source:source,masks:masks))
    }
  }
}
