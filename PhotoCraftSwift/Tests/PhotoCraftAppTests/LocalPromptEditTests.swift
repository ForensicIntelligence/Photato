import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LocalPromptEditTests: XCTestCase {
  private func document(depth: PixelDepth = .u8) throws -> CraftDocument {
    var source = try CraftDocument(width: 90, height: 47, depth: depth)
    let raster = try Surface(width: 70, height: 35, depth: depth, fill: Pixel(0.85, 0.2, 0.08))
    var layer = Layer(name: "Artwork", content: .raster(raster))
    layer.x = 5
    layer.y = 3
    source.layers.append(layer)
    source.activeLayerID = layer.id
    return source
  }

  private func prediction(_ pixel: Pixel) throws -> Surface {
    try Surface(width: LocalGenerativeFill.side, height: LocalGenerativeFill.side, depth: .f32, fill: pixel)
  }

  func testWholeSelectionEligibilityRejectsPartialOrFeatheredCoverage() throws {
    var source = try document()
    let canvas = IntRect(x: 0, y: 0, width: 90, height: 47)
    XCTAssertNotNil(LocalPromptEdit.target(in: source))
    source.selection = .init(x: 2, y: 0, width: 88, height: 47)
    XCTAssertNil(LocalPromptEdit.target(in: source))
    source.selection = canvas
    XCTAssertNotNil(LocalPromptEdit.target(in: source))
    var coverage = [UInt8](repeating: 255, count: 90 * 47)
    coverage[17] = 128
    source.selectionMask = try SelectionMask(width: 90, height: 47, bytes: coverage)
    XCTAssertEqual(source.selectionMask?.bounds, canvas)
    XCTAssertNil(LocalPromptEdit.target(in: source))
    coverage[17] = 255
    source.selectionMask = try SelectionMask(width: 90, height: 47, bytes: coverage)
    XCTAssertNotNil(LocalPromptEdit.target(in: source))
  }

  func testEditRetainsOriginalTransparencyAndReopensEditableAcrossFormats() throws {
    let blue = try prediction(Pixel(0.15, 0.32, 0.9))
    let green = try prediction(Pixel(0.15, 0.8, 0.24))
    for depth in [PixelDepth.u8, .u16, .f32] {
      let source = try document(depth: depth), original = try XCTUnwrap(source.layers.last)
      var session = EditorSession(document: source)
      let edit = try LocalPromptEdit.prepare(source, targetID: original.id, prompt: " turn the artwork blue ", seed: 17, count: 2) {
        prompt, seeds, image, mask in
        XCTAssertEqual(prompt, "turn the artwork blue")
        XCTAssertEqual(seeds, [17, 18])
        XCTAssertTrue(image.contains { $0 > 0.8 })
        XCTAssertTrue(mask.allSatisfy { $0 == 1 })
        return [blue, green]
      }
      try session.executePrepared(PreparedEdit(command: edit, document: source))
      let edited = session.document
      XCTAssertEqual(session.undoStack.count, 1)
      XCTAssertEqual(edited.layers[0], source.layers[0])
      var hidden = original
      hidden.visible = false
      XCTAssertEqual(edited.layers[1], hidden)
      let layer = try XCTUnwrap(edited.layers.last)
      let choices = try XCTUnwrap(GenerativeFillVariations.read(layer))
      XCTAssertTrue(choices.isPromptEdit)
      XCTAssertEqual(choices.model, LocalGenerativeFill.instructionModelIdentifier)
      let before = try Renderer.composite(source)
      let after = try Renderer.composite(edited)
      XCTAssertEqual(before.pixel(x: 0, y: 0), after.pixel(x: 0, y: 0))
      XCTAssertGreaterThan(after.pixel(x: 49, y: 21).b, 0.8)
      for format in [DocumentIO.Format.native, .psd, .psb] {
        let reopened = try DocumentIO.decode(DocumentIO.encode(edited, format: format), native: format == .native, name: "Prompt edit")
        XCTAssertEqual(GenerativeFillVariations.read(try XCTUnwrap(reopened.layers.last))?.entries, choices.entries)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: depth), try after.rgbaData(depth: depth))
      }
      try session.undo()
      XCTAssertEqual(session.document, source)
    }
  }

  func testAfterReopenUsesSavedOriginalOrExplicitlySelectedVariation() throws {
    let original = try document()
    let target = try XCTUnwrap(original.activeLayerID)
    let blue = try prediction(Pixel(0.12, 0.28, 0.9)), green = try prediction(Pixel(0.1, 0.89, 0.24))
    var inputs = [Float]()
    var edited = original
    try LocalPromptEdit.prepare(original, targetID: target, prompt: "make it blue", seed: 1, count: 1) { _, _, image, _ in
      inputs = image
      return [blue]
    }.apply(to: &edited)
    let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: .psb))
    let targetLayer = try XCTUnwrap(saved.layers.last)
    let record = try XCTUnwrap(GenerativeFillVariations.read(targetLayer))
    var rewrote = saved
    try GenerativeFillVariations.append(to: targetLayer.id, in: saved, prompt: "make it green", seed: 2, count: 1) { _, _, image, _ in
      XCTAssertTrue(image == inputs)
      return [green]
    }.apply(to: &rewrote)
    let savedVariation = try XCTUnwrap(record.entries.first?.id)
    let previous = rewrote
    try GenerativeFillVariations.append(to: targetLayer.id, in: previous, prompt: "warm up the blue", seed: 3, count: 1,
      referenceVariationID: savedVariation) { _, _, image, _ in
        XCTAssertFalse(image == inputs)
        return [blue]
      }.apply(to: &rewrote)
    let final = try XCTUnwrap(GenerativeFillVariations.read(try XCTUnwrap(rewrote.layers.last)))
    XCTAssertEqual(final.entries.first, record.entries.first)
    XCTAssertEqual(final.entries.last?.referenceVariationID, savedVariation)
    XCTAssertEqual(rewrote.layers.last?.coordinateTransform, targetLayer.coordinateTransform)
  }

  @MainActor func testRealInstructionNativeAndHTTPMatchWithSameSeed() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let model = env["PHOTATO_TEST_PROMPT_EDIT_MODEL"], let image = env["PHOTATO_TEST_PROMPT_EDIT_IMAGE"],
      LocalGenerativeFill.supported else { throw XCTSkip("Requires the optional model and owned artwork fixture.") }
    let source = try DocumentIO.read(URL(fileURLWithPath: image))
    let layerID = try XCTUnwrap(source.activeLayerID)
    let key = GenerativeFillModelPreference.instructionKey
    let saved = UserDefaults.standard.data(forKey: key)
    UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: model, isDirectory: true)), forKey: key)
    defer { UserDefaults.standard.set(saved, forKey: key) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      let store = doc.store
      store.session = EditorSession(document: source)
      try service.share(doc)
      store.beginPromptToEdit()
      let draft = try XCTUnwrap(store.generativeFillDraft)
      XCTAssertEqual(draft.instructionSourceID, layerID)
      draft.prompt = "Make the orange teapot blue."
      draft.seed = 32
      draft.variationCount = 1
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try Renderer.composite(store.document).rgbaData(depth: .u8)
      XCTAssertNotEqual(native, try Renderer.composite(source).rgbaData(depth: .u8))
      await store.undo()
      XCTAssertEqual(store.document, source)
      let status = try await helper.edit(service, doc, GenerativeFillAPI.promptEdit,
        ["sourceLayerID": layerID.uuidString, "prompt": draft.prompt, "seed": Int(draft.seed), "variationCount": 1], timeout: 180)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), native)
      await store.undo()
      XCTAssertEqual(store.document, source)
    }
  }
}
