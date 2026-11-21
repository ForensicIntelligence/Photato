import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LocalGeneratedImageTests: XCTestCase {
  private func generated(_ pixel: Pixel) throws -> Surface {
    try Surface(width: LocalGenerativeFill.side, height: LocalGenerativeFill.side, depth: .f32, fill: pixel)
  }

  func testGenerationUsesOnlyPromptAndReopensAsEditableVariations() throws {
    let red = try generated(Pixel(0.9, 0.1, 0.2))
    let blue = try generated(Pixel(0.15, 0.25, 0.85))
    for depth in [PixelDepth.u8, .u16, .f32] {
      var original = try CraftDocument(width: 65, height: 30, depth: depth)
      original.selection = IntRect(x: 10, y: 6, width: 20, height: 15)
      var session = EditorSession(document: original)
      let command = try LocalGeneratedImage.prepare(original, prompt: "  a forest at blue hour  ", seed: .max, count: 2) {
        prompt, seeds, image, mask in
        XCTAssertEqual(prompt, "a forest at blue hour")
        XCTAssertEqual(seeds, [.max, 0])
        XCTAssertTrue(image.allSatisfy { $0 == 0 })
        XCTAssertTrue(mask.allSatisfy { $0 == 1 })
        return [red, blue]
      }
      try session.executePrepared(PreparedEdit(command: command, document: original))
      let edited = session.document
      XCTAssertEqual(session.undoStack.count, 1)
      XCTAssertEqual(edited.selection, original.selection)
      XCTAssertEqual(Array(edited.layers.dropLast()), original.layers)
      let image = try XCTUnwrap(edited.layers.last)
      XCTAssertEqual(edited.activeLayerID, image.id)
      XCTAssertNil(image.mask)
      let choices = try XCTUnwrap(GenerativeFillVariations.read(image))
      XCTAssertTrue(choices.isGeneratedImage)
      XCTAssertEqual(choices.entries.count, 2)
      let pixels = try Renderer.composite(edited)
      XCTAssertGreaterThan(pixels.pixel(x: 64, y: 29).r, 0.85)
      XCTAssertEqual(pixels.pixel(x: 64, y: 29).a, 1)
      try session.undo()
      XCTAssertEqual(session.document, original)

      for format in [DocumentIO.Format.native, .psd, .psb] {
        let reopened = try DocumentIO.decode(DocumentIO.encode(edited, format: format), native: format == .native, name: "Generated")
        let layer = try XCTUnwrap(reopened.layers.last)
        XCTAssertEqual(GenerativeFillVariations.read(layer)?.entries, choices.entries)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: depth), try pixels.rgbaData(depth: depth))
      }
      if depth == .u8 {
        var offCanvas = edited
        offCanvas.layers[offCanvas.layers.count - 1].x = 500
        let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(offCanvas, format: .psb))
        let restored = try XCTUnwrap(reopened.layers.last)
        XCTAssertEqual(restored.x, 500)
        XCTAssertEqual(GenerativeFillVariations.read(restored)?.entries, choices.entries)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8), try Renderer.composite(original).rgbaData(depth: .u8))
      }
    }
  }

  func testAfterReopenGenerateMoreAndSimilarRetainEarlierResults() throws {
    let original = try CraftDocument(width: 90, height: 111)
    let blue = try generated(Pixel(0.15, 0.25, 0.85))
    var edited = original
    try LocalGeneratedImage.prepare(original, prompt: "a blue ceramic bowl", seed: 4, count: 1) { _, _, _, _ in [blue] }
      .apply(to: &edited)
    edited = try PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: .psb))
    let target = try XCTUnwrap(edited.layers.last)
    let first = try XCTUnwrap(GenerativeFillVariations.read(target)?.entries.first)
    let red = try generated(Pixel(0.93, 0.2, 0.12))
    var result = edited
    try GenerativeFillVariations.append(to: target.id, in: edited, prompt: "a red bowl", seed: 5, count: 1) {
      prompt, seeds, image, mask in
      XCTAssertEqual(prompt, "a red bowl")
      XCTAssertEqual(seeds, [5])
      XCTAssertTrue(image.allSatisfy { $0 == 0 })
      XCTAssertTrue(mask.allSatisfy { $0 == 1 })
      return [red]
    }.apply(to: &result)
    let more = try XCTUnwrap(GenerativeFillVariations.read(try XCTUnwrap(result.layers.last)))
    XCTAssertEqual(more.entries.first, first)
    XCTAssertEqual(more.lastDocumentStateID, more.entries.last?.id)
    XCTAssertEqual(result.layers.last?.coordinateTransform, target.coordinateTransform)
    let beforeSimilar = result
    try GenerativeFillVariations.append(to: target.id, in: beforeSimilar, prompt: nil, seed: nil, count: 1,
      referenceVariationID: first.id) { prompt, seeds, image, mask in
        XCTAssertEqual(prompt, "a blue ceramic bowl")
        XCTAssertEqual(seeds, [6])
        XCTAssertGreaterThan(image.last ?? 0, 0.8)
        XCTAssertTrue(mask.allSatisfy { $0 == 1 })
        return [blue]
      }.apply(to: &result)
    let similar = try XCTUnwrap(GenerativeFillVariations.read(try XCTUnwrap(result.layers.last)))
    XCTAssertEqual(Array(similar.entries.dropLast()), more.entries)
    XCTAssertEqual(similar.entries.last?.referenceVariationID, first.id)
  }

  func testMaximumWidthGeneratedImageRetainsNativeResolutionAndEditablePlacement() throws {
    let width = Surface.maxDimension, height = 8
    let source = try CraftDocument(width: width, height: height)
    let blue = try generated(Pixel(0.12, 0.3, 0.92))
    var edited = source
    try LocalGeneratedImage.prepare(source, prompt: "a cobalt blue sky", seed: 6, count: 1) { _, _, _, _ in [blue] }
      .apply(to: &edited)
    let layer = try XCTUnwrap(edited.layers.last)
    XCTAssertEqual(layer.smartObject?.width, LocalGenerativeFill.side)
    XCTAssertEqual(layer.smartObject?.height, LocalGenerativeFill.side)
    let temporary = FileManager.default.temporaryDirectory.appending(path: "Photato-Generated-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let psb = temporary.appending(path: "Generated.psb")
    try PSDCodec.writeRasterLayers(edited, to: psb, format: .psb)
    let reopened = try DocumentIO.read(psb)
    let restored = try XCTUnwrap(reopened.layers.last)
    XCTAssertEqual(GenerativeFillVariations.read(layer)?.entries, GenerativeFillVariations.read(restored)?.entries)
    XCTAssertEqual(restored.coordinateTransform, layer.coordinateTransform)
    for x in [0, width - 4] {
      let region = IntRect(x: x, y: 0, width: 4, height: height)
      let before = try Renderer.composite(edited, region: region).cropped(to: region)
      let after = try Renderer.composite(reopened, region: region).cropped(to: region)
      XCTAssertEqual(try before.rgbaData(depth: .u8), try after.rgbaData(depth: .u8))
      XCTAssertEqual(after.pixel(x: 0, y: height - 1).a, 1)
    }
  }

  @MainActor func testRealLocalImageNativeAndHTTPMatchWithSameSeed() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_PROMPT_FILL_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional local prompt model.")
    }
    let key = GenerativeFillModelPreference.promptKey
    let saved = UserDefaults.standard.data(forKey: key)
    UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: path, isDirectory: true)), forKey: key)
    defer { UserDefaults.standard.set(saved, forKey: key) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let source = try CraftDocument(width: 160, height: 120)
      let store = shared.store
      store.session = EditorSession(document: source)
      try service.share(shared)
      store.beginGenerateImage()
      let draft = try XCTUnwrap(store.generativeFillDraft)
      XCTAssertTrue(draft.generateImage)
      draft.prompt = "an orange ceramic teapot in warm sunlight"
      draft.seed = 472126
      draft.variationCount = 2
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try Renderer.composite(store.document).rgbaData(depth: .u8)
      await store.undo()
      XCTAssertEqual(store.document, source)
      let status = try await helper.edit(service, shared, GenerativeFillAPI.image,
        ["prompt": draft.prompt, "seed": Int(draft.seed), "variationCount": draft.variationCount], timeout: 180)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), native)
      XCTAssertEqual(GenerativeFillVariations.read(try XCTUnwrap(store.activeLayer))?.entries.count, 2)
      await store.undo()
      XCTAssertEqual(store.document, source)
    }
  }
}
