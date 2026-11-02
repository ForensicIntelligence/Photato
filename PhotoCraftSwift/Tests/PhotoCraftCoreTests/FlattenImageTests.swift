import XCTest
@testable import PhotoCraftCore

final class FlattenImageTests: XCTestCase {
  func testOpaqueImplicitAndSparseSourcesRetainRawWordsAtMaximumExtent() throws {
    for depth in PixelDepth.allCases {
      let fill = Pixel(1,0,0,1)
      var s = try Surface(width:300000,height:300000,depth:depth,fill:fill)
      s.setPixel(x:150000,y:150000,Pixel(0,1,0,1))
      let result = try BackgroundLayer.opaque(s,over:.white)
      XCTAssertEqual(result,s); XCTAssertLessThan(result.allocatedBytes,2*1024*1024)
    }
  }
  func testPartialImplicitAndStoredTileOpacityAreResolvedWithoutDenseAllocation() throws {
    let raw = Pixel(4,-0.25,0.5,0.5)
    var s = try Surface(width:300000,height:300000,depth:.f32,fill:raw).interpretingSamples(as:.linearRGB)
    s.setLinearPixel(x:100,y:100,Pixel(8,-0.0,2,1)); s.setLinearPixel(x:101,y:100,Pixel(99,22,33,0))
    let result = try BackgroundLayer.opaque(s,over:.white)
    XCTAssertTrue(result.linearPixel(x:0,y:0).hasSameBits(as:Pixel(2.5,0.375,0.75,1)))
    XCTAssertTrue(result.linearPixel(x:100,y:100).hasSameBits(as:s.linearPixel(x:100,y:100)))
    XCTAssertEqual(result.linearPixel(x:101,y:100),.white)
    XCTAssertTrue(try result.isOpaque()); XCTAssertLessThan(result.allocatedBytes,2*1024*1024); XCTAssertLessThan(result.tileCount,5)
  }
  func testHiddenLayersFollowParentEyesAndDoNotTreatZeroOpacityAsHidden() throws {
    var d = try CraftDocument(width:2,height:1)
    let child = d.layers[0]; var group = Layer(name:"Hidden group",content:.group(.init())); group.visible=false
    d.layers[0].parentID=group.id; d.layers.append(group)
    var zero = Layer(name:"Visible zero opacity",content:.raster(try Surface(width:2,height:1)));zero.opacity=0;d.layers.append(zero)
    XCTAssertEqual(FlattenImageEdit.hiddenLayerIDs(in:d),[child.id,group.id])
  }
  func testSourceBoundEditHistoryAndSemanticOperationDoNotPermitStaleCommit() throws {
    let source = try CraftDocument(width:2,height:1)
    var result = source; result.layers[0].name="Background"; result.layers[0].background=true
    let command = Command.flattenImage(.init(source:source,result:result))
    var session = EditorSession(document:source); try session.execute(command)
    XCTAssertEqual(session.document,result); XCTAssertEqual(session.undoStack.count,1)
    try session.undo();XCTAssertEqual(session.document,source);try session.redo();XCTAssertEqual(session.document,result)
    var stale = source; stale.name="Changed"; let before=stale
    XCTAssertThrowsError(try command.apply(to:&stale)); XCTAssertEqual(stale,before)
    let operation = ActionOperation(recording:command,in:source)
    guard case .flattenImage = operation else {return XCTFail("Semantic operation")}
    XCTAssertThrowsError(try operation.command(in:source))
    XCTAssertNoThrow(try JSONDecoder().decode(ActionOperation.self,from:JSONEncoder().encode(operation)))
  }
  func testIntegerQuantizationAndFloatingStorageKeepEncodingAndPaging() throws {
    var s = try Surface(width:100000,height:500,depth:.f32,fill:Pixel(0.1,0.3,0.5))
    s.setPixel(x:90000,y:400,Pixel(1,0,0))
    for depth in [PixelDepth.u8,.u16] {
      let result = try s.quantizedStoredDepth(depth)
      XCTAssertEqual(result.depth,depth);XCTAssertEqual(result.colorEncoding,.sRGB)
      XCTAssertTrue(result.pixel(x:0,y:0).hasSameBits(as:Pixel(0.1,0.3,0.5).quantized(depth)))
      XCTAssertLessThan(result.allocatedBytes,2*1024*1024)
    }
  }
}
