import Darwin
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

  func testCancellingBusyPromptWorkerReapsChildAndRemovesScratch() async throws {
    let files = FileManager.default
    let folder = files.temporaryDirectory.appending(path: "Photato-Worker-Test-\(UUID())", directoryHint: .isDirectory)
    try files.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? files.removeItem(at: folder) }
    let fixture = folder.appending(path: "stall")
    let marker = folder.appending(path: "stall.started")
    try """
    #!/bin/sh
    trap '' TERM
    printf '%s\\n%s\\n' "$$" "$2" > "$0.started"
    exec /bin/sleep 60

    """.write(to: fixture, atomically: true, encoding: .utf8)
    try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
    let job = Task.detached {
      try GenerativeFillWorker.run(model: folder, prompt: "Fixture", seeds: [0],
        image: [], mask: [], executable: fixture)
    }
    defer { job.cancel() }
    let deadline = ContinuousClock.now + .seconds(4)
    while !files.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    let info = try String(contentsOf: marker, encoding: .utf8).split(separator: "\n")
    let pid = try XCTUnwrap(info.first.flatMap { Int32($0) })
    let scratch = try XCTUnwrap(info.last.map { String($0) })
    XCTAssertTrue(files.fileExists(atPath: scratch))
    job.cancel()
    do {
      _ = try await job.value
      XCTFail("Cancelled inference returned pixels.")
    } catch is CancellationError {
      XCTAssertEqual(Darwin.kill(pid, 0), -1)
      XCTAssertFalse(files.fileExists(atPath: scratch))
    }
  }

  func testRealPromptWorkerReusePreservesSeededPixelsAcrossRequests() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_PROMPT_FILL_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional prompt model.")
    }
    let model = URL(fileURLWithPath: path, isDirectory: true)
    let side = LocalGenerativeFill.side, area = side * side
    var image = Array(repeating: Float(0.6), count: area * 3)
    for index in 0..<area {
      image[index + area] = Float(index % side) / 1024 + 0.2
    }
    let first = (0..<area).map { Float($0 % side >= side * 3 / 4 ? 1 : 0) }
    let second = (0..<area).map { Float($0 / side >= side * 3 / 4 ? 1 : 0) }
    let prompt = "plain painted background, warm afternoon light"
    let expectedFirst = try GenerativeFillWorker.run(model: model, prompt: prompt, seeds: [472122], image: image, mask: first)
    let expectedSecond = try GenerativeFillWorker.run(model: model, prompt: prompt, seeds: [472123], image: image, mask: second, mode: .similar)
    try GenerativeFillWorker.withSession(model: model) { session in
      let initial = try session.predict(prompt: prompt, seeds: [472122], image: image, mask: first)
      let later = try session.predict(prompt: prompt, seeds: [472123], image: image, mask: second, mode: .similar)
      let repeated = try session.predict(prompt: prompt, seeds: [472122], image: image, mask: first)
      XCTAssertEqual(try initial[0].rgbaData(depth: .f32), try expectedFirst[0].rgbaData(depth: .f32))
      XCTAssertEqual(try later[0].rgbaData(depth: .f32), try expectedSecond[0].rgbaData(depth: .f32))
      XCTAssertEqual(try repeated[0].rgbaData(depth: .f32), try initial[0].rgbaData(depth: .f32))
      XCTAssertNotEqual(initial[0], later[0])
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

  func testSimilarUsesExplicitReferenceAndPreservesSavedContextAfterReopen() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 27, height: 24, depth: depth)
      let region = IntRect(x: 7, y: 8, width: 13, height: 10)
      document.setCoverageSelection(try SelectionMask.sampledCoverage(width: 27, height: 24, regions: [region]) { x, y in
        region.contains(x, y) && (x > 7 || y > 8) ? (x == 7 || y == 8 ? 127 : 255) : 0
      })
      let (recipe, coverage) = try LocalGenerativeFill.capture(document)
      let red = try Surface(width: 512, height: 512, depth: .f32, fill: Pixel(1, 0.12, 0.07))
      let blue = try Surface(width: 512, height: 512, depth: .f32, fill: Pixel(0.01, 0.37, 0.9))
      let green = try Surface(width: 512, height: 512, depth: .f32, fill: Pixel(0.05, 0.8, 0.17))
      var initialImage = [Float](), initialMask = [Float]()
      let patch = try recipe.patches(in: document) { image, mask in
        initialImage = image
        initialMask = mask
        return [red]
      }[0]
      var generated = Layer(name: "Generative Fill", content: .raster(patch))
      generated.x = region.x
      generated.y = region.y
      generated.mask = coverage
      let layer = try GenerativeFillVariations.pack([generated], in: document, prompt: "Red subject", seeds: [21], context: recipe.encoded())
      try Command.generativeFill(layer).apply(to: &document)
      let addBlue = try GenerativeFillVariations.append(to: layer.id, in: document, prompt: "Blue subject", seed: nil, count: 1) { _, _, _, _ in [blue] }
      try addBlue.apply(to: &document)
      var reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(document))
      reopened.setCoverageSelection(nil)
      let target = try XCTUnwrap(reopened.layers.last)
      let before = try XCTUnwrap(GenerativeFillVariations.read(target))
      let chosen = before.entries[0].id
      XCTAssertEqual(target.smartObject?.layerComps?.selectedID, before.entries[1].id)
      XCTAssertThrowsError(try GenerativeFillVariations.append(to: target.id, in: reopened, prompt: nil, seed: nil, count: 1,
        referenceVariationID: UUID()) { _, _, _, _ in XCTFail("An unknown reference must fail before inference"); return [green] })
      let similar = try GenerativeFillVariations.append(to: target.id, in: reopened, prompt: nil, seed: nil, count: 1,
        referenceVariationID: chosen) { prompt, seeds, image, mask in
        XCTAssertEqual(prompt, "Red subject")
        XCTAssertEqual(seeds, [23])
        XCTAssertTrue(mask == initialMask)
        let cells = mask.count
        XCTAssertTrue(image.indices.allSatisfy { mask[$0 % cells] == 1 || image[$0].bitPattern == initialImage[$0].bitPattern })
        XCTAssertTrue(mask.indices.contains { mask[$0] == 1 && image[$0] > image[$0 + cells * 2] })
        XCTAssertTrue(image != initialImage)
        return [green]
      }
      var session = EditorSession(document: reopened)
      try session.executePrepared(PreparedEdit(command: similar, document: reopened))
      let changed = try XCTUnwrap(session.document.layers.last)
      let history = try XCTUnwrap(GenerativeFillVariations.read(changed))
      XCTAssertEqual(history.entries.count, 3)
      XCTAssertEqual(Array(history.entries.prefix(2)), before.entries)
      XCTAssertEqual(history.entries[2].referenceVariationID, chosen)
      XCTAssertEqual(changed.mask, target.mask)
      let roundTrips = try [
        NativeArchive.decode(NativeArchive.encode(session.document)),
        PSDCodec.read(PSDCodec.writeRasterLayers(session.document)),
        PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: .psb))
      ]
      for copy in roundTrips {
        XCTAssertEqual(copy.layers.last.flatMap(GenerativeFillVariations.read), history)
      }
      try session.undo()
      XCTAssertTrue(session.document == reopened)
    }
  }
}
