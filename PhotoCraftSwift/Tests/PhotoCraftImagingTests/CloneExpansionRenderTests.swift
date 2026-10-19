import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class CloneExpansionRenderTests: XCTestCase {
  func testExpandedPixelsAndMasksPersistThroughNativeAndPSD() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 80, height: 60, depth: depth)
      d.layers[0].content = .raster(try Surface(width: 4, height: 3, depth: depth, fill: .black))
      d.layers[0].x = 30
      d.layers[0].y = 20
      d.layers[0].mask = try Surface(width: 4, height: 3, depth: depth, fill: .white)
      var properties = MaskProperties()
      properties.outside = 1
      properties.linked = false
      d.layers[0].maskProperties = properties
      var brush = CloneBrush()
      brush.size = 9
      brush.hardness = 1
      let source = try Surface(width: 80, height: 60, depth: depth, fill: .white)
      var stroke = CloneStroke(
        source: .init(surface: source), mapping: .init(source: .init(0, 0), anchor: .init(0, 0)),
        brush: brush, points: [.init(x: 12.5, y: 12.5), .init(x: 65.5, y: 44.5)])
      let id = d.layers[0].id
      let before = try Renderer.render(d)
      try Command.cloneStamp(id, stroke).apply(to: &d)
      stroke.mask = true
      stroke.source = .init(
        surface: try Surface(width: 80, height: 60, depth: depth, fill: .black), outside: .white)
      stroke.points = [.init(x: 62.5, y: 42.5)]
      try Command.cloneStamp(id, stroke).apply(to: &d)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
      let full = try Renderer.composite(d)
      let incremental = try Renderer.render(d, reusing: before)
      XCTAssertEqual(incremental.update, .full)
      XCTAssertEqual(try incremental.surface.rgbaData(depth: .f32), try full.rgbaData(depth: .f32))
      let psd = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      XCTAssertEqual(psd.layers[0].x, d.layers[0].x)
      XCTAssertEqual(psd.layers[0].y, d.layers[0].y)
      XCTAssertEqual(psd.layers[0].effectiveMaskProperties.outside, 1)
      XCTAssertEqual(psd.layers[0].effectiveMaskProperties.linked, false)
      let restored = try Renderer.composite(psd)
      // Black/white integer opaque centers are exact; RGB/32 interchange uses a linear transfer.
      XCTAssertEqual(restored.pixel(x: 12, y: 12), full.pixel(x: 12, y: 12))
      XCTAssertEqual(restored.pixel(x: 62, y: 42), full.pixel(x: 62, y: 42))
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      try PSDCodec.writeRasterLayers(d).write(
        to: root.appendingPathComponent(
          "artifacts/native-expanded-clone-\(depth.rawValue.prefix(2).trimmingCharacters(in: .whitespaces)).psd"
        ))
    }
  }

  func testCroppedMaskSourceSamplesOutsideAndIgnoresStoredAlpha() throws {
    var d = try CraftDocument(width: 30, height: 20)
    var mask = try Surface(width: 2, height: 2, fill: .black)
    mask.setPixel(x: 0, y: 0, Pixel(0.4, 0.9, 0.1, 0))
    d.layers[0].mask = mask
    var properties = MaskProperties()
    properties.transform = .translation(8, 7)
    properties.outside = 1
    d.layers[0].maskProperties = properties
    let sample = try Renderer.cloneSample(
      in: d, layerID: d.layers[0].id, sampling: .all, mask: true)
    XCTAssertEqual(sample.outside, .white)
    var brush = CloneBrush()
    brush.size = 1
    brush.hardness = 1
    for (source, expected) in [(PathPoint(8.5, 7.5), Float(0.4)), (.init(2.5, 2.5), Float(1))] {
      var output = try Surface(width: 1, height: 1)
      let stroke = CloneStroke(
        source: sample, mapping: .init(source: source, anchor: .init(0.5, 0.5)), brush: brush,
        points: [.init(x: 0.5, y: 0.5)], mask: true)
      try ClonePainter.paint(stroke, on: &output, transform: .identity)
      XCTAssertEqual(output.pixel(x: 0, y: 0), Pixel(expected, expected, expected).quantized(.u8))
    }
  }
}
