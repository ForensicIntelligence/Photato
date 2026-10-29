import XCTest
@testable import PhotoCraftCore

final class CropGeometryTests: XCTestCase {
  func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var d = try CraftDocument(width:12,height:8,depth:depth),s = try Surface(width:16,height:12,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<12 { for x in 0..<16 { let p = Pixel(Float(x)/8,Float(y)/12,0.25,1);if depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) } } };d.layers[0].content = .raster(s);d.layers[0].x = -2;d.layers[0].y = -2;return d
  }
  func testExpandedCropRetainsStorageLocksAndExactPixels() throws {
    for depth in PixelDepth.allCases { var d = try fixture(depth);d.layers[0].locked = true
      var r = CropRequest(x:-4,y:-3,width:20,height:16);r.deleteCroppedPixels = false
      let result = try CropGeometry.applying(r,to:d);XCTAssertEqual(result.layers[0].content,d.layers[0].content);XCTAssertEqual(result.layers[0].x,2);XCTAssertEqual(result.layers[0].y,1);XCTAssertEqual(result.depth,depth);XCTAssertTrue(result.layers[0].locked)
      XCTAssertEqual(result.width,20);XCTAssertEqual(result.height,16)
    }
  }
  func testDeleteCropPreservesBitsAndUndoArchive() throws {
    for depth in PixelDepth.allCases { let d = try fixture(depth),r = CropRequest(x:2,y:1,width:5,height:4),result = try CropGeometry.applying(r,to:d)
      guard case .raster(let original) = d.layers[0].content,case .raster(let clipped) = result.layers[0].content else { return XCTFail("Missing raster") }
      XCTAssertEqual(clipped,try original.cropped(to:.init(x:4,y:3,width:5,height:4)));XCTAssertEqual(result.layers[0].x,0);XCTAssertEqual(result.layers[0].y,0)
      var session = EditorSession(document:d);try session.execute(.cropDocument(.init(source:d,result:result)));XCTAssertEqual(session.document,result);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,result)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
    }
  }
  func testStraightenMasksChannelsSelectionAndHDR() throws {
    var d = try fixture(.f32);d.layers[0].mask = try Surface(width:16,height:12,depth:.f32,fill:.white);var props = MaskProperties();props.linked = false;d.layers[0].maskProperties = props
    d.selection = .init(x:2,y:2,width:6,height:4);var session = EditorSession(document:d);try session.execute(.channel(.saveSelection(nil,"Saved",.replace)));d = session.document
    var r = CropRequest(x:-2,y:-2,width:16,height:12);r.angle = 15;r.deleteCroppedPixels = false
    let retained = try CropGeometry.applying(r,to:d);XCTAssertNil(retained.selection);XCTAssertEqual(retained.alphaChannels?.first?.pixels.width,16)
    XCTAssertEqual(retained.layers[0].maskCoordinateTransform,r.transform*d.layers[0].maskCoordinateTransform)
    XCTAssertEqual(retained.layers[0].content,d.layers[0].content);r.deleteCroppedPixels = true
    let deleted = try CropGeometry.applying(r,to:d);guard case .raster(let pixels) = deleted.layers[0].content else { return XCTFail("Missing raster") }
    var maximum: Float = 0;for y in 0..<pixels.height { for x in 0..<pixels.width { maximum = max(maximum,pixels.linearPixel(x:x,y:y).r) } };XCTAssertGreaterThan(maximum,1)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(deleted)),deleted)
  }
  func testInvalidAndCancelledCropNeverChangesSource() async throws {
    let d = try fixture(.u8)
    XCTAssertThrowsError(try CropGeometry.applying(.init(x:0,y:0,width:0,height:10),to:d))
    var r = CropRequest(x:0,y:0,width:10,height:10);r.angle = .nan;XCTAssertThrowsError(try CropGeometry.applying(r,to:d))
    let task = Task { try CropGeometry.applying(.init(x:-2,y:0,width:10,height:10),to:d) };task.cancel();do { _ = try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    let edit = CropEdit(source:d,result:try CropGeometry.applying(.init(x:0,y:0,width:4,height:4),to:d));var changed = d;changed.layers[0].name = "Changed";XCTAssertThrowsError(try edit.applied(to:changed))
  }
}
