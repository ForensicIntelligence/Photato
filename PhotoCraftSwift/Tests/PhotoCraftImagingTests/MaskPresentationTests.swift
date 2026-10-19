import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class MaskPresentationTests: XCTestCase {
  func fixture() throws -> Layer {
    var layer = Layer(name: "Channel", content: .raster(try Surface(width: 2, height: 1)))
    layer.mask = try Surface(width: 2, height: 1, depth: .f32, fill: Pixel(0.25, 1, 0, 0))
    layer.mask?.setPixel(x: 1, y: 0, Pixel(1, 0, 0, 0))
    layer.x = 1
    layer.maskProperties = MaskProperties()
    layer.maskProperties?.outside = 0.75
    layer.maskProperties?.enabled = false
    layer.maskProperties?.density = 0
    layer.maskProperties?.feather = 5
    layer.opacity = 0
    return layer
  }
  func testGrayUsesRawChannelAndGeometryWithoutMutatingLayer() throws {
    let layer = try fixture()
    let before = layer
    let image = try Renderer.maskPresentation(layer, mode: .gray, width: 4, height: 1)
    XCTAssertEqual(
      (0..<4).map { image.pixel(x: $0, y: 0) },
      [Pixel(0.75, 0.75, 0.75), Pixel(0.25, 0.25, 0.25), .white, Pixel(0.75, 0.75, 0.75)])
    XCTAssertEqual(layer, before)
  }
  func testOverlayIsRedHalfOpacityOnHiddenAreasAndInvertsOutside() throws {
    var layer = try fixture()
    layer.maskProperties?.inverted = true
    let image = try Renderer.maskPresentation(layer, mode: .overlay, width: 4, height: 1)
    XCTAssertEqual(
      (0..<4).map { image.pixel(x: $0, y: 0) },
      [Pixel(1, 0, 0, 0.375), Pixel(1, 0, 0, 0.125), Pixel(1, 0, 0, 0.5), Pixel(1, 0, 0, 0.375)])
  }
  func testLoadedPixelSelectionQuantizesRawCoverageAndRetainsOutside() throws {
    var layer = try fixture()
    layer.maskProperties?.transform = .translation(1, 0)
    let selection = try Renderer.maskSelection(layer, kind: .pixel, width: 5, height: 1)
    XCTAssertEqual(selection.bytes, [191, 191, 64, 255, 191])
  }
  func testVectorSelectionUsesDocumentCoordinatesAndIgnoresDisabledDensityFeather() throws {
    var layer = try fixture()
    layer.x = 100
    var mask = VectorMask(
      path: VectorPath(components: [
        PathComponent(
          knots: [
            PathKnot(PathPoint(1, 0)), PathKnot(PathPoint(3, 0)), PathKnot(PathPoint(3, 1)),
            PathKnot(PathPoint(1, 1)),
          ], closed: true)
      ]))
    mask.enabled = false
    mask.density = 0
    mask.feather = 4
    layer.vectorMask = mask
    XCTAssertEqual(
      try Renderer.maskSelection(layer, kind: .vector, width: 4, height: 1).bytes,
      [0, 255, 255, 0])
    layer.vectorMask?.path.inverted = true
    XCTAssertEqual(
      try Renderer.maskSelection(layer, kind: .vector, width: 4, height: 1).bytes,
      [255, 0, 0, 255])
  }
  func testMissingMasksAndInvalidDimensionsFail() throws {
    var layer = try fixture()
    layer.mask = nil
    XCTAssertThrowsError(try Renderer.maskPresentation(layer, mode: .gray, width: 4, height: 1))
    XCTAssertThrowsError(try Renderer.maskSelection(layer, kind: .pixel, width: 4, height: 1))
    XCTAssertThrowsError(try Renderer.maskSelection(layer, kind: .vector, width: 4, height: 1))
    XCTAssertThrowsError(try Renderer.maskSelection(fixture(), kind: .pixel, width: 0, height: 1))
  }
}
