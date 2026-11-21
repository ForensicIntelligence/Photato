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

  func testSavedContextAppendsToReopenedLayersAfterDocumentEditsAtEveryRGBDepth() throws {
    for depth in PixelDepth.allCases {
      var original = try CraftDocument(width: 48, height: 35, depth: depth)
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      original.layers[0].content = .raster(try Surface(width: 48, height: 35, depth: depth,
        fill: Pixel(0.23, 0.58, 0.41), colorEncoding: encoding))
      let selection = IntRect(x: 15, y: 9, width: 19, height: 17)
      original.setCoverageSelection(try SelectionMask.sampledCoverage(width: 48, height: 35, regions: [selection]) { x, y in
        guard selection.contains(x, y) else { return 0 }
        return x == selection.x || y == selection.y ? 95 : 255
      })
      let (recipe, mask) = try LocalGenerativeFill.capture(original)
      let dimensions = 512
      let first = try Surface(width: dimensions, height: dimensions, depth: .f32, fill: Pixel(0.9, 0.8, 0.5))
      let next = try Surface(width: dimensions, height: dimensions, depth: .f32, fill: Pixel(0.3, 0.3, 0.9))
      var initialModelImage = [Float](), initialModelMask = [Float]()
      let patch = try recipe.patches(in: original) { image, mask in
        initialModelImage = image; initialModelMask = mask
        return [first]
      }[0]
      var firstLayer = Layer(name: "Generative Fill", content: .raster(patch))
      firstLayer.x = selection.x; firstLayer.y = selection.y; firstLayer.mask = mask
      let layer = try GenerativeFillVariations.pack([firstLayer], in: original, prompt: "First subject", seeds: [.max], context: recipe.encoded())
      try Command.generativeFill(layer).apply(to: &original)
      let reopenings = try [
        NativeArchive.decode(NativeArchive.encode(original)),
        PSDCodec.read(PSDCodec.writeRasterLayers(original, format: .psd)),
        PSDCodec.read(PSDCodec.writeRasterLayers(original, format: .psb))
      ]
      for var reopened in reopenings {
        reopened.setCoverageSelection(nil)
        reopened.layers[0].content = .raster(try Surface(width: 48, height: 35, depth: depth,
          fill: Pixel(0.7, 0.11, 0.21), colorEncoding: encoding))
        let position = reopened.layers.count - 1
        reopened.layers[position].x += 2
        reopened.layers[position].opacity = 0.8
        let editedLayer = reopened.layers[position]
        let record = try XCTUnwrap(GenerativeFillVariations.read(editedLayer))
        let previous = try Renderer.composite(reopened).rgbaData(depth: depth, colorEncoding: encoding)
        let append = try GenerativeFillVariations.append(to: editedLayer.id, in: reopened, prompt: "Second subject", seed: nil, count: 1) {
          prompt, seeds, image, modelMask in
          XCTAssertEqual(prompt, "Second subject")
          XCTAssertEqual(seeds, [0])
          XCTAssertTrue(image == initialModelImage && modelMask == initialModelMask)
          return [next]
        }
        var session = EditorSession(document: reopened)
        try session.executePrepared(PreparedEdit(command: append, document: reopened))
        let changed = session.document.layers[position]
        let metadata = try XCTUnwrap(GenerativeFillVariations.read(changed))
        XCTAssertEqual(changed.id, editedLayer.id)
        XCTAssertEqual(changed.x, editedLayer.x)
        XCTAssertEqual(changed.opacity, editedLayer.opacity)
        XCTAssertEqual(changed.mask, editedLayer.mask)
        XCTAssertEqual(metadata.entries.first, record.entries.first)
        XCTAssertEqual(metadata.entries.map(\.seed), [.max, 0])
        XCTAssertEqual(metadata.prompt(for: metadata.entries[1].id), "Second subject")
        XCTAssertEqual(changed.smartObject?.layerComps?.selectedID, metadata.entries[1].id)
        var earlier = session.document
        try SmartObjectLayerCompIO.selection(in: earlier, layerID: changed.id, compID: record.entries[0].id).apply(to: &earlier)
        XCTAssertEqual(try Renderer.composite(earlier).rgbaData(depth: depth, colorEncoding: encoding), previous)
        let again = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: .psb))
        let reloaded = try XCTUnwrap(again.layers.last)
        XCTAssertEqual(GenerativeFillVariations.read(reloaded), metadata)
        var defaultState = again
        try SmartObjectLayerCompIO.selection(in: defaultState, layerID: reloaded.id, compID: nil).apply(to: &defaultState)
        let defaultLayer = try XCTUnwrap(defaultState.layers.last)
        let defaultRecord = try XCTUnwrap(GenerativeFillVariations.read(defaultLayer))
        XCTAssertNil(defaultLayer.smartObject?.layerComps?.selectedID)
        XCTAssertEqual(defaultRecord.selectedID(nil), metadata.entries[1].id)
        XCTAssertEqual(defaultRecord.prompt(for: nil), "Second subject")
        XCTAssertThrowsError(try GenerativeFillVariations.append(to: defaultLayer.id, in: defaultState, prompt: nil, seed: nil, count: 1) {
          prompt, _, _, _ in
          XCTAssertEqual(prompt, "Second subject")
          throw CancellationError()
        })
        XCTAssertThrowsError(try GenerativeFillVariations.append(to: reloaded.id, in: again, prompt: nil, seed: 0, count: 1) {
          _, _, _, _ in XCTFail("Duplicate seed must fail before prediction"); return [next]
        })
        try session.undo()
        XCTAssertEqual(session.document, reopened)
      }
    }
  }
}
