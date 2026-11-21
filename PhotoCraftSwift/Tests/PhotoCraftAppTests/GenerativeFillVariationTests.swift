import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GenerativeFillVariationTests: XCTestCase {
  func testThreeVariantsSwitchAndRoundTripWithTheOuterMaskAtEveryRGBDepth() throws {
    let colors = [Pixel(0.97, 0.13, 0.08), Pixel(0.17, 0.28, 0.93), Pixel(0.19, 0.77, 0.47)]
    let seeds: [UInt32] = [.max, 0, 1]
    for depth in PixelDepth.allCases {
      let document = try CraftDocument(width: 29, height: 25, depth: depth)
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var mask = try Surface(width: 15, height: 10, fill: .white)
      mask.setPixel(x: 0, y: 0, .black)
      mask.setPixel(x: 0, y: 1, Pixel(0.5, 0.5, 0.5))
      let alternatives = try colors.map { color in
        let fill = encoding == .linearRGB ? SRGBTransfer.linear(color) : color
        var layer = Layer(name: "Generative Fill", content: .raster(
          try Surface(width: 15, height: 10, depth: depth, fill: fill, colorEncoding: encoding)))
        layer.x = 7
        layer.y = 11
        layer.mask = mask
        return layer
      }
      let expected = try alternatives.map { layer in
        var document = document
        try Command.generativeFill(layer).apply(to: &document)
        return try Renderer.composite(document).rgbaData(depth: depth, colorEncoding: encoding)
      }
      let layer = try GenerativeFillVariations.pack(alternatives, in: document, prompt: "Owned colors", seeds: seeds)
      let metadata = try XCTUnwrap(GenerativeFillVariations.read(layer))
      XCTAssertEqual(metadata.entries.map(\.seed), seeds)
      var session = EditorSession(document: document)
      try session.executePrepared(PreparedEdit(command: .generativeFill(layer), document: document))
      let initial = session.document
      XCTAssertEqual(try Renderer.composite(initial).rgbaData(depth: depth, colorEncoding: encoding), expected[0])
      for item in metadata.entries.dropFirst() {
        try session.execute(SmartObjectLayerCompIO.selection(in: session.document, layerID: layer.id, compID: item.id))
      }
      let selected = session.document
      try session.undo()
      try session.undo()
      XCTAssertEqual(session.document, initial)
      try session.undo()
      XCTAssertEqual(session.document, document)
      let reopenings = try [
        NativeArchive.decode(NativeArchive.encode(selected)),
        PSDCodec.read(PSDCodec.writeRasterLayers(selected, format: .psd)),
        PSDCodec.read(PSDCodec.writeRasterLayers(selected, format: .psb))
      ]
      for reopened in reopenings {
        let loaded = try XCTUnwrap(reopened.layers.last)
        let record = try XCTUnwrap(GenerativeFillVariations.read(loaded))
        XCTAssertEqual(record, metadata)
        try assertSameCoverage(layer, loaded, width: document.width, height: document.height)
        XCTAssertEqual(loaded.smartObject?.layerComps?.selectedID, record.entries.last?.id)
        for (index, entry) in record.entries.enumerated() {
          var choice = reopened
          try SmartObjectLayerCompIO.selection(in: reopened, layerID: loaded.id, compID: entry.id).apply(to: &choice)
          try assertSameCoverage(layer, XCTUnwrap(choice.layers.last), width: document.width, height: document.height)
          XCTAssertEqual(try Renderer.composite(choice).rgbaData(depth: depth, colorEncoding: encoding), expected[index])
        }
      }
    }
  }

  private func assertSameCoverage(_ expected: Layer, _ actual: Layer, width: Int, height: Int) throws {
    let expectedMask = try MaskSampler(layer: expected), actualMask = try MaskSampler(layer: actual)
    for y in 0..<height { for x in 0..<width {
      let cx = Double(x) + 0.5, cy = Double(y) + 0.5
      XCTAssertEqual(actualMask.coverage(x: cx, y: cy).bitPattern, expectedMask.coverage(x: cx, y: cy).bitPattern)
    } }
  }

  func testInferenceWorkerFailureReturnsAnErrorToTheCaller() throws {
    let model = FileManager.default.temporaryDirectory
    XCTAssertThrowsError(try GenerativeFillWorker.run(model: model, prompt: "Fixture", seeds: [0, 1],
      image: [], mask: [], executable: URL(fileURLWithPath: "/usr/bin/false"))) { error in
      XCTAssertEqual(error as? CraftError, .unavailable("Local model inference stopped unexpectedly. Try Generate again."))
    }
  }
}
