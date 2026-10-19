import CoreGraphics
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers
import XCTest

@testable import PhotoCraftImaging

final class ImagingTests: XCTestCase {
  func testLayerOrderOpacityOffsetAndMask() throws {
    var d = try CraftDocument(width: 4, height: 4, depth: .f32)
    var l = Layer(
      name: "Red",
      content: .raster(try Surface(width: 2, height: 2, depth: .f32, fill: Pixel(1, 0, 0))))
    l.x = 1
    l.y = 1
    l.opacity = 0.5
    l.mask = try Surface(width: 2, height: 2, depth: .f32, fill: Pixel(0.5, 0.5, 0.5))
    d.layers.append(l)
    let output = try Renderer.composite(d)
    XCTAssertEqual(output.pixel(x: 0, y: 0), .white)
    // HDR composition has 0.75 linear green, represented in the sRGB working space.
    XCTAssertEqual(output.pixel(x: 1, y: 1).g, 0.88082502, accuracy: 1e-5)
    d.layers[1].visible = false
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 1, y: 1), .white)
  }
  func testCGImagePreservesOrientationAlphaAndColor() throws {
    var s = try Surface(width: 2, height: 2, depth: .f32)
    s.setPixel(x: 0, y: 0, Pixel(1, 0, 0))
    s.setPixel(x: 1, y: 0, Pixel(0, 1, 0, 0.5))
    s.setPixel(x: 0, y: 1, Pixel(0, 0, 1))
    let round = try RasterIO.surface(RasterIO.cgImage(s), depth: .f32)
    for y in 0..<2 {
      for x in 0..<2 {
        let a = s.pixel(x: x, y: y)
        let b = round.pixel(x: x, y: y)
        XCTAssertEqual(a.r, b.r, accuracy: 0.002)
        XCTAssertEqual(a.g, b.g, accuracy: 0.002)
        XCTAssertEqual(a.b, b.b, accuracy: 0.002)
        XCTAssertEqual(a.a, b.a, accuracy: 0.002)
      }
    }
  }
  func testPNGAndTIFFRoundTrip() throws {
    for type in [UTType.png, .tiff] {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(type.preferredFilenameExtension ?? "png")
      defer { try? FileManager.default.removeItem(at: url) }
      var s = try Surface(width: 3, height: 2, depth: .u16, fill: Pixel(0.15, 0.6, 0.75))
      s.setPixel(x: 1, y: 0, Pixel(0.8, 0.1, 0.2, 0.5))
      try RasterIO.write(s, to: url, type: type)
      let d = try RasterIO.read(url)
      let result = try Renderer.composite(d)
      XCTAssertEqual(d.depth, .u16)
      XCTAssertEqual(result.pixel(x: 1, y: 0).r, 0.8, accuracy: 0.003)
      XCTAssertEqual(result.pixel(x: 1, y: 0).a, 0.5, accuracy: 0.001)
      XCTAssertEqual(result.pixel(x: 0, y: 1).g, 0.6, accuracy: 0.003)
    }
  }
  func testJPEGTransparentExportIsWhite() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".jpg")
    defer { try? FileManager.default.removeItem(at: url) }
    try RasterIO.write(Surface(width: 4, height: 4), to: url, type: .jpeg)
    let p = try Renderer.composite(RasterIO.read(url)).pixel(x: 0, y: 0)
    XCTAssertEqual(p.r, 1, accuracy: 0.02)
    XCTAssertEqual(p.a, 1)
  }
  func testNonDestructiveAdjustmentAndTextShape() throws {
    var d = try CraftDocument(width: 180, height: 100, depth: .f32)
    d.layers = [
      Layer(name: "Base", content: .fill(Pixel(0.5, 0.25, 0.1))),
      Layer(name: "Invert", content: .adjustment(.invert)),
    ]
    d.activeLayerID = d.layers[0].id
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0).b, 0.9, accuracy: 1e-5)
    let text = Layer(
      name: "Text", content: .text(TextContent(text: "Native", size: 40, color: .black)))
    let ts = try Renderer.layerSurface(text, in: d)
    XCTAssertGreaterThan(ts.tileCount, 0)
    let ellipse = Layer(
      name: "Ellipse",
      content: .shape(ShapeContent(kind: .ellipse, width: 20, height: 20, color: .white)))
    let es = try Renderer.layerSurface(ellipse, in: d)
    XCTAssertEqual(es.pixel(x: 0, y: 0).a, 0)
    XCTAssertEqual(es.pixel(x: 10, y: 10).a, 1)
  }
  func testBlurAndResize() throws {
    var s = try Surface(width: 9, height: 9, depth: .f32, fill: .black)
    s.setPixel(x: 4, y: 4, .white)
    let blur = try Renderer.gaussianBlur(s, radius: 1)
    XCTAssertLessThan(blur.pixel(x: 4, y: 4).r, 1)
    XCTAssertGreaterThan(blur.pixel(x: 3, y: 4).r, 0)
    XCTAssertThrowsError(try Renderer.gaussianBlur(s, radius: .nan))
    let resized = try Renderer.resize(s, width: 18, height: 18)
    XCTAssertEqual(resized.width, 18)
  }
  func testLayeredFormatsAreNeverSilentlyFlattened() {
    XCTAssertThrowsError(try RasterIO.read(URL(fileURLWithPath: "/tmp/image.psd")))
  }
}
extension ImagingTests {
  func testDisplayPreviewKeepsWhiteWhiteWithoutChangingHDRWorkingData() throws {
    let surface = try Surface(width: 2, height: 2, depth: .f32, fill: Pixel(2, 1, 0.5))
    let image = try RasterIO.displayImage(surface)
    XCTAssertEqual(image.bitsPerComponent, 8)
    let pixels = try RasterIO.surface(image, depth: .f32)
    XCTAssertEqual(pixels.pixel(x: 0, y: 0).r, 1, accuracy: 0.001)
    XCTAssertEqual(pixels.pixel(x: 0, y: 0).g, 1, accuracy: 0.001)
    XCTAssertEqual(surface.pixel(x: 0, y: 0).r, 2)
  }
}
