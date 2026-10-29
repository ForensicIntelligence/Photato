import XCTest
@testable import PhotoCraftCore

final class ContentAwareScaleTests: XCTestCase {
  func testProtectedContentShrinkExpandAndTwoAxis() throws {
    let w = 9,h = 6;var image = [Float](repeating:0,count:w*h),protect = image
    for y in 0..<h { image[y*w+4] = 1;protect[y*w+4] = 1 }
    let out = try SeamCarving.resize(width:w,height:h,channels:1,image:image,protect:protect,newWidth:5,newHeight:h)
    for y in 0..<h { XCTAssertEqual(out[(y*5)..<(y*5+5)].filter { $0 == 1 }.count,1) }
    let expanded = try SeamCarving.resize(width:w,height:h,channels:1,image:image,protect:protect,newWidth:14,newHeight:8)
    XCTAssertEqual(expanded.count,112);XCTAssertTrue(expanded.allSatisfy { $0 >= 0 && $0 <= 1 });XCTAssertEqual(expanded,try SeamCarving.resize(width:w,height:h,channels:1,image:image,protect:protect,newWidth:14,newHeight:8))
    let protected = try SeamCarving.resize(width:3,height:1,channels:1,image:[0,0.01,0.11],protect:[1,0,0],newWidth:2,newHeight:1)
    XCTAssertEqual(protected,[0,0.01])
    XCTAssertEqual(try SeamCarving.resize(width:3,height:1,channels:1,image:[0,0.01,0.11],newWidth:2,newHeight:1),[0.01,0.11])
  }
  func testAmountIdentitySinglePixelAndValidation() async throws {
    let input: [Float] = [0,1,0,1,0,1,0,1]
    let plain = try SeamCarving.resize(width:4,height:2,channels:1,image:input,newWidth:2,newHeight:3,amount:0)
    let carve = try SeamCarving.resize(width:4,height:2,channels:1,image:input,newWidth:2,newHeight:3)
    let mix = try SeamCarving.resize(width:4,height:2,channels:1,image:input,newWidth:2,newHeight:3,amount:0.5)
    for i in mix.indices { XCTAssertEqual(mix[i],plain[i]+(carve[i]-plain[i])*0.5) }
    XCTAssertEqual(try SeamCarving.resize(width:1,height:1,channels:4,image:[4,2,1,1],newWidth:8,newHeight:6),Array(repeating:[Float](arrayLiteral:4,2,1,1),count:48).flatMap { $0 })
    XCTAssertEqual(try SeamCarving.resize(width:4,height:2,channels:1,image:input,newWidth:4,newHeight:2),input)
    XCTAssertThrowsError(try SeamCarving.resize(width:0,height:2,channels:1,image:[],newWidth:2,newHeight:2))
    XCTAssertThrowsError(try SeamCarving.resize(width:4,height:2,channels:1,image:input,newWidth:2,newHeight:2,amount:101))
    let task = Task { try SeamCarving.resize(width:4,height:2,channels:1,image:input,newWidth:2,newHeight:3) };task.cancel();do { _ = try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }
  func testLayerSelectionHistoryArchiveAndHDR() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width:12,height:10,depth:depth),pixels = try Surface(width:6,height:6,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<6 { for x in 0..<6 { let p = Pixel(depth == .f32 ? 3:0.8,0.3,0.2,1);if depth == .f32 { pixels.setLinearPixel(x:x,y:y,p) } else { pixels.setPixel(x:x,y:y,p) } } }
      d.layers[0].content = .raster(pixels);d.layers[0].x = 2;d.layers[0].y = 1
      var request = ContentAwareScaleRequest(width:8,height:4,x:1,y:2);request.protectSkinTones = true
      let edit = try ContentAwareScaleEdit.prepare(d,layerID:d.layers[0].id,request:request);var session = EditorSession(document:d);try session.execute(.contentAwareScale(edit));let result = session.document
      guard case .raster(let scaled) = result.layers[0].content else { return XCTFail("Raster missing") };XCTAssertEqual(scaled.width,8);XCTAssertEqual(scaled.height,4);XCTAssertEqual(result.layers[0].x,1)
      if depth == .f32 { XCTAssertEqual(scaled.linearPixel(x:2,y:2).r,3,accuracy:0.0001) }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,result)
      d.selection = .init(x:3,y:2,width:3,height:3);request = .init(width:2,height:2,x:8,y:6)
      let selected = try ContentAwareScaleEdit.prepare(d,layerID:d.layers[0].id,request:request).applied(to:d)
      XCTAssertEqual(selected.selection,.init(x:8,y:6,width:2,height:2));guard case .raster(let s) = selected.layers[0].content else { return XCTFail("Raster missing") }
      XCTAssertEqual(s.pixel(x:0,y:0),pixels.pixel(x:0,y:0));XCTAssertEqual(s.pixel(x:1,y:1).a,0)
      request.x = 40;XCTAssertNoThrow(try ContentAwareScaleEdit.prepare(d,layerID:d.layers[0].id,request:request).applied(to:d))
    }
  }
  func testSavedProtectionMaskGeometryAndLocks() throws {
    var d = try CraftDocument(width:12,height:8);d.layers[0].mask = try Surface(width:12,height:8,fill:.white)
    var session = EditorSession(document:d);try session.execute(.channel(.saveSelection(nil,"Protected",.replace)));d = session.document
    var request = ContentAwareScaleRequest(width:9,height:8);request.protectChannelID = d.alphaChannels!.first!.id
    let result = try ContentAwareScaleEdit.prepare(d,layerID:d.layers[0].id,request:request).applied(to:d);XCTAssertNotNil(result.layers[0].maskProperties);XCTAssertEqual(result.alphaChannels,d.alphaChannels)
    for protection: LayerProtection in [.image,.position,.transparency] { var locked = d;locked.layers[0].protection = protection;XCTAssertThrowsError(try ContentAwareScaleEdit.prepare(locked,layerID:locked.layers[0].id,request:request)) }
    XCTAssertEqual(SeamCarving.skin(Pixel(0.7,0.45,0.3)),1);XCTAssertEqual(SeamCarving.skin(Pixel(0.1,0.2,0.8)),0)
  }
}
