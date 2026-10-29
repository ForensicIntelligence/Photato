import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GeometryRenderTests: XCTestCase {
  func testCanvasRotationsMatchIndependentPixelMapsAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 6, height: 4, depth: depth)
      var p = try Surface(width: 3, height: 2, depth: depth)
      for y in 0..<2 {
        for x in 0..<3 { p.setPixel(x: x, y: y, Pixel(Float(x + 1) / 4, Float(y + 1) / 3, 0.2)) }
      }
      var l = Layer(name: "Asymmetric", content: .raster(p))
      l.x = 2
      l.y = 1
      l.mask = try Surface(width: 3, height: 2, fill: .white)
      l.mask?.setPixel(x: 1, y: 0, .black)
      let shape = Layer(
        name: "Shape",
        content: .shape(ShapeContent(kind: .rectangle, width: 1, height: 2, color: Pixel(0, 1, 0))))
      d.layers = [l, shape]
      d.activeLayerID = l.id
      let before = try Renderer.composite(d)
      for turn in CanvasTurn.allCases {
        var session = EditorSession(document: d)
        try session.execute(.rotateCanvas(turn))
        let after = try Renderer.composite(session.document)
        for y in 0..<4 {
          for x in 0..<6 {
            let nx: Int
            let ny: Int
            switch turn {
            case .clockwise: (nx, ny) = (3 - y, x)
            case .counterclockwise: (nx, ny) = (y, 5 - x)
            case .half: (nx, ny) = (5 - x, 3 - y)
            case .horizontal: (nx, ny) = (5 - x, y)
            case .vertical: (nx, ny) = (x, 3 - y)
            }
            XCTAssertEqual(
              before.pixel(x: x, y: y), after.pixel(x: nx, y: ny), "\(depth) \(turn) \(x),\(y)")
          }
        }
        try session.undo()
        XCTAssertEqual(session.document, d)
      }
    }
  }
  func testPSDResolutionMetadataRoundTrip() throws {
    var doc = try CraftDocument(width: 3, height: 2)
    doc.resolution = 300
    let data = try PSDCodec.writeRasterLayers(doc)
    XCTAssertEqual(try PSDCodec.read(data).pixelsPerInch, 300)
  }
  func testResolutionMetadataSurvivesRasterExport() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: url) }
    try RasterIO.write(Surface(width: 2, height: 2, fill: .white), to: url, resolution: 300)
    XCTAssertEqual(try RasterIO.read(url).pixelsPerInch, 300, accuracy: 0.02)
  }

  func testLiveTextAndShapeGeometrySurvivesResizeAndArchive() throws {
    var d = try CraftDocument(width: 120, height: 80)
    let text = Layer(name: "Text", content: .text(TextContent(text: "AB", size: 20, color: .black)))
    let shape = Layer(
      name: "Shape",
      content: .shape(ShapeContent(kind: .ellipse, width: 20, height: 10, color: Pixel(1, 0, 0))))
    d.layers = [text, shape]
    d.activeLayerID = shape.id
    let textBefore = try Renderer.layerSurface(text, in: d)
    var s = EditorSession(document: d)
    try s.execute(.imageSize(240, 160, 144, .bilinear))
    guard case .text(let t) = s.document.layers[0].content,
      case .shape = s.document.layers[1].content
    else { return XCTFail("Live content was rasterized") }
    XCTAssertEqual(t.size, 20)
    XCTAssertEqual(t.layoutWidth, 120)
    XCTAssertEqual(try Renderer.layerSurface(s.document.layers[0], in: s.document), textBefore)
    let round = try NativeArchive.decode(NativeArchive.encode(s.document))
    XCTAssertEqual(try Renderer.composite(round), try Renderer.composite(s.document))
    XCTAssertNotNil(round.layers[1].affine)
  }
}
