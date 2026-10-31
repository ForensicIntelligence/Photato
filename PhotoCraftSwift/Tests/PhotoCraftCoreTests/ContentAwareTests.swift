import XCTest
@testable import PhotoCraftCore

final class ContentAwareTests: XCTestCase {
  func testConstantImageAndAdaptationsPreserveKnownPixels() throws {
    let w = 24,h = 24,n = w*h
    var image = [Float](repeating:0,count:n*4),hole = [Bool](repeating:false,count:n)
    for y in 0..<h { for x in 0..<w { let i = y*w+x; for c in 0..<4 { image[i*4+c] = c == 3 ? 1:0.4 }; if (9..<15).contains(x) && (9..<15).contains(y) { hole[i] = true; image[i*4] = 1 } } }
    for rotation in ContentAwareSettings.Rotation.allCases {
      var settings = ContentAwareSettings(); settings.rotation = rotation; settings.scale = rotation == .full; settings.mirror = rotation == .full
      let result = try ContentAwareSynthesis.fill(width:w,height:h,image:image,hole:hole,source:Array(repeating:true,count:n),settings:settings)
      for i in hole.indices {
        if hole[i] { XCTAssertEqual(result[i*4],0.4,accuracy:0.002) }
        else { XCTAssertEqual(Array(result[(i*4)..<(i*4+4)]),Array(image[(i*4)..<(i*4+4)])) }
      }
    }
  }
  func testRestrictedSourceAndDeterminism() throws {
    let w = 32,h = 24,n = w*h
    var image = [Float](repeating:0,count:n*4),hole = [Bool](repeating:false,count:n),source = hole
    for y in 0..<h { for x in 0..<w { let i = y*w+x; image[i*4] = x < 16 ? 0.2:0.9; image[i*4+1] = Float(y%4)/4; image[i*4+3] = 1; hole[i] = (20..<25).contains(x) && (9..<14).contains(y); source[i] = x < 16 } }
    var settings = ContentAwareSettings(); settings.colorAdaptation = .none
    let result = try ContentAwareSynthesis.fill(width:w,height:h,image:image,hole:hole,source:source,settings:settings)
    XCTAssertEqual(result,try ContentAwareSynthesis.fill(width:w,height:h,image:image,hole:hole,source:source,settings:settings))
    for i in hole.indices where hole[i] { XCTAssertEqual(result[i*4],0.2,accuracy:0.001) }
    XCTAssertThrowsError(try ContentAwareSynthesis.fill(width:w,height:h,image:image,hole:hole,source:Array(repeating:false,count:n),settings:settings))
  }
  func testOutputCoverageHistoryGeometryDepthAndArchive() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width:12,height:8,depth:depth)
      d.layers[0].content = .raster(try Surface(width:6,height:4,depth:depth,fill:.black)); d.layers[0].x = 2; d.layers[0].y = 2
      let mask = try SelectionMask.make(.rectangle(.init(x:1,y:1,width:6,height:5)),width:12,height:8,antiAlias:false)
      let patch = try Surface(width:8,height:7,depth:depth,fill:.white,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for output in ContentAwareOutput.allCases {
        let edit = ContentAwareEdit(layerID:d.layers[0].id,output:output,window:.init(x:0,y:0,width:8,height:7),pixels:patch,selection:mask)
        var session = EditorSession(document:d); try session.execute(.contentAwareFill(edit))
        let result = session.document; XCTAssertEqual(result.layers.count,output == .current ? 1:2)
        if output != .current { XCTAssertEqual(result.layers[0],d.layers[0]) }
        XCTAssertEqual(result.selection,mask.bounds)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
        try session.undo(); XCTAssertEqual(session.document,d); try session.redo(); XCTAssertEqual(session.document,result)
      }
    }
  }
  func testSamplingStrokesValidationAndCancellation() async throws {
    let mask = try SelectionMask(width:24,height:16,bytes:Array(repeating:0,count:384))
    var stroke = ContentAwareStroke(); stroke.add = true; stroke.size = 6; stroke.points = [[4,8],[12,8]]
    let painted = try stroke.applying(to:mask); XCTAssertEqual(try painted.bytes[8*24+8],255)
    stroke.add = false; XCTAssertEqual(try stroke.applying(to:painted),mask)
    XCTAssertThrowsError(try ContentAwareSettings.decodeJSON(Data("{\"scale\":1}".utf8)))
    XCTAssertThrowsError(try ContentAwareSettings.decodeJSON(Data("{\"unknown\":1}".utf8)))
    let task = Task { try Task.checkCancellation(); return try ContentAwareSynthesis.fill(width:24,height:16,image:Array(repeating:1,count:1536),hole:Array(repeating:true,count:384),source:Array(repeating:true,count:384),settings:.init()) }
    task.cancel(); do { _ = try await task.value; XCTFail("Cancellation expected") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }
}
