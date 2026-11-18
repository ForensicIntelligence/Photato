import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class ColorRegionRenderTests: XCTestCase {
  func testBucketActionResamplesCompositeAfterEarlierStepOnDifferentCanvas() throws {
    let outputName = String(repeating: "Paint Bucket output ", count: 70) + "layer"
    func fixture(width: Int, wall: Int) throws -> CraftDocument {
      var document = try CraftDocument(width: width, height: 10)
      var base = try Surface(width: width, height: 10, fill: .white)
      for y in 0..<10 { base.setPixel(x: wall, y: y, .black) }
      document.layers[0].content = .raster(base)
      let cover = Layer(name: "Cover", content: .raster(try Surface(width: width, height: 10, fill: .black)))
      let output = Layer(name: outputName, content: .raster(try Surface(width: width, height: 10)))
      document.layers += [cover, output]
      return document
    }
    let original = try fixture(width: 12, wall: 4), outputID = original.layers[2].id
    var options = BucketOptions()
    options.sampleAllLayers = true
    options.match.tolerance = 0
    options.match.antiAlias = false
    let request = PaintBucketRequest(layerID: outputID, point: .init(2.5, 3.5), color: Pixel(1, 0, 0),
      options: options, mask: false, pattern: nil, placement: .init())
    let operation = try ActionOperation(recording: request.command(in: original), in: original)
    guard case .paintBucket(let recipe) = operation else { return XCTFail("Expected a portable bucket recipe") }
    XCTAssertEqual(recipe.target, .named(outputName, occurrence: 0))
    let action = RecordedAction(name: "Reveal then Fill", steps: [
      .init(name: "Hide cover", operation: .visibility(.named("Cover", occurrence: 0), false)),
      .init(name: "Fill visible region", operation: operation),
    ])
    var replay = try fixture(width: 18, wall: 7)
    replay.selection = .init(x: 1, y: 1, width: 16, height: 8)
    let source = replay
    XCTAssertNotEqual(replay.layers[2].id, outputID)
    let prepared = try RecordedActionRenderer.prepare(action, in: replay)
    try prepared.command.apply(to: &replay)
    XCTAssertFalse(replay.layers[1].visible)
    XCTAssertEqual(replay.layers[0], source.layers[0])
    XCTAssertEqual(replay.selection, source.selection)
    guard case .raster(let pixels) = replay.layers[2].content else { return XCTFail("Expected pixel layer") }
    XCTAssertEqual(pixels.pixel(x: 0, y: 3), .clear)
    XCTAssertEqual(pixels.pixel(x: 2, y: 3), Pixel(1, 0, 0))
    XCTAssertEqual(pixels.pixel(x: 6, y: 3), Pixel(1, 0, 0))
    XCTAssertEqual(pixels.pixel(x: 7, y: 3), .clear)
    XCTAssertEqual(pixels.pixel(x: 8, y: 3), .clear)
  }

  func testBucketActionAtIneligibleSeedFailsBeforePublishingAnyStep() throws {
    var original = try CraftDocument(width: 12, height: 9)
    original.layers[0].content = .raster(try Surface(width: 12, height: 9, fill: .white))
    let request = PaintBucketRequest(layerID: original.layers[0].id, point: .init(10.5, 6.5), color: .black,
      options: .init(), mask: false, pattern: nil, placement: .init())
    let action = RecordedAction(name: "Pixel-position Fill", steps: [
      .init(name: "Rename", operation: .rename(.active, "Before Bucket")),
      try .init(name: "Bucket", operation: .init(recording: request.command(in: original), in: original)),
    ])
    let smaller = try CraftDocument(width: 8, height: 5)
    XCTAssertThrowsError(try RecordedActionRenderer.prepare(action, in: smaller)) { error in
      XCTAssertTrue(error.localizedDescription.contains("step 2"))
      XCTAssertTrue(error.localizedDescription.contains("Sample inside the document"))
    }
  }

  func testAllLayersBucketNativeAndPSDAndIncrementalRenderingAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 96, height: 80, depth: depth)
      var s = try Surface(width: 96, height: 80, depth: depth, fill: .white)
      for y in 0..<80 { s.setPixel(x: 40, y: y, .black) }
      d.layers[0].content = .raster(s)
      let empty = Layer(
        name: "Fill", content: .raster(try Surface(width: 96, height: 80, depth: depth)))
      d.layers.append(empty)
      d.activeLayerID = empty.id
      let baseline = try Renderer.render(d)
      let sample = try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .all)
      var options = BucketOptions()
      options.sampleAllLayers = true
      let fill = BucketFill(
        source: sample, seed: .init(10, 10), color: Pixel(0.25, 0.5, 0.75), options: options)
      try Command.paintBucket(empty.id, fill).apply(to: &d)
      XCTAssertEqual(d.layers[0].content, .raster(s))
      let full = try Renderer.composite(d)
      let regional = try Renderer.render(d, reusing: baseline)
      if case .region = regional.update {} else { XCTFail("Expected regional update") }
      XCTAssertEqual(try full.rgbaData(depth: .f32), try regional.surface.rgbaData(depth: .f32))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
      let restored = try Renderer.composite(PSDCodec.read(PSDCodec.writeRasterLayers(d)))
      for y in 0..<80 {
        for x in 0..<96 {
          let a = full.pixel(x: x, y: y)
          let b = restored.pixel(x: x, y: y)
          let tolerance: Float = depth == .u8 ? 1.0 / 255 : depth == .u16 ? 1.0 / 65535 : 0.000002
          XCTAssertEqual(a.r, b.r, accuracy: tolerance)
          XCTAssertEqual(a.g, b.g, accuracy: tolerance)
          XCTAssertEqual(a.b, b.b, accuracy: tolerance)
          XCTAssertEqual(a.a, b.a, accuracy: tolerance)
        }
      }
    }
  }
}
