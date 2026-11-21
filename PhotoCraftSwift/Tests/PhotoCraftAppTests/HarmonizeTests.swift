import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class HarmonizeTests: XCTestCase {
  private func scene(width: Int = 96, height: Int = 72, depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: height, depth: depth)
    document.layers[0].content = .fill(Pixel(0.72, 0.52, 0.31))
    var layer = Layer(name: "Owned Subject",
      content: .raster(try Surface(width: 36, height: 32, depth: depth, fill: Pixel(0.22, 0.35, 0.62))))
    layer.x = width / 2 - 18
    layer.y = height / 2 - 20
    var mask = try Surface(width: 36, height: 32, fill: .black)
    try mask.mapPixels(in: .init(x: 4, y: 2, width: 28, height: 28)) { x, _, _ in
      x == 4 ? Pixel(0.5, 0.5, 0.5) : .white
    }
    layer.mask = mask
    document.layers.append(layer)
    document.activeLayerID = layer.id
    return document
  }

  func testVariationsKeepOriginalCoverageAndAreOneUndoEach() throws {
    let original = try scene(), source = original.layers[1]
    var session = EditorSession(document: original)
    let command = try Harmonize.apply(in: original, foregroundID: source.id)
    try session.executePrepared(PreparedEdit(command: command, document: original))
    let result = session.document
    let choices = try XCTUnwrap(Harmonize.choices(in: result))
    XCTAssertEqual(choices.selected, .balanced)
    XCTAssertEqual(choices.variations, [.subtle, .balanced, .ambient])
    var hidden = source
    hidden.visible = false
    XCTAssertEqual(result.layers[1], hidden)
    let participant = try XCTUnwrap(result.children(of: choices.groupID).first { $0.name == "Harmonized Subject" })
    XCTAssertEqual(participant.content, source.content)
    XCTAssertEqual(participant.mask, source.mask)
    XCTAssertEqual(participant.coordinateTransform, source.coordinateTransform)
    let expected = try Renderer.composite(result)
    let before = try Renderer.composite(original)
    XCTAssertGreaterThan(expected.pixel(x: 48, y: 26).r, before.pixel(x: 48, y: 26).r)
    XCTAssertLessThan(expected.pixel(x: 48, y: 26).b, before.pixel(x: 48, y: 26).b)
    XCTAssertLessThan(expected.pixel(x: 48, y: 50).r, before.pixel(x: 48, y: 50).r)
    XCTAssertTrue(expected.pixel(x: 1, y: 1).hasSameBits(as: before.pixel(x: 1, y: 1)))
    let alternate = try Harmonize.select(.ambient, in: result, groupID: choices.groupID)
    try session.executePrepared(PreparedEdit(command: alternate, document: result))
    XCTAssertEqual(Harmonize.choices(in: session.document)?.selected, .ambient)
    XCTAssertGreaterThan(try Renderer.composite(session.document).pixel(x: 48, y: 26).r, expected.pixel(x: 48, y: 26).r)
    try session.undo()
    XCTAssertEqual(session.document, result)
    try session.undo()
    XCTAssertEqual(session.document, original)
    try session.redo()
    XCTAssertEqual(session.document, result)
  }

  func testAlternativesRemainEditableAndRendersSurviveNativeAndPhotoshopFormats() throws {
    for depth in [PixelDepth.u8, .u16, .f32] {
      let original = try scene(depth: depth)
      let source = try XCTUnwrap(original.activeLayerID)
      var edited = original
      try Harmonize.apply(in: original, foregroundID: source, variation: .subtle).apply(to: &edited)
      let expected = try Renderer.composite(edited).rgbaData(depth: depth)
      let outputs = try [NativeArchive.decode(NativeArchive.encodeChunked(edited)),
        PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: .psd)),
        PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: .psb))]
      for (index, opened) in outputs.enumerated() {
        let group = try XCTUnwrap(opened.layers.first { $0.isGroup && $0.name == "Harmonize" })
        let choices = try XCTUnwrap(Harmonize.choices(in: opened, groupID: group.id))
        XCTAssertEqual(choices.selected, .subtle)
        XCTAssertEqual(choices.variations.count, 3)
        XCTAssertEqual(try Renderer.composite(opened).rgbaData(depth: depth), expected, "\(depth), \(index)")
        var alternate = opened
        try Harmonize.select(.ambient, in: opened, groupID: group.id).apply(to: &alternate)
        XCTAssertEqual(Harmonize.choices(in: alternate, groupID: group.id)?.selected, .ambient)
        XCTAssertNotEqual(try Renderer.composite(alternate).rgbaData(depth: depth), expected)
      }
    }
  }

  func testTransparentOrClippedTargetsCannotCommit() throws {
    var original = try scene()
    let subject = try XCTUnwrap(original.activeLayerID)
    original.layers[1].clipped = true
    XCTAssertNil(Harmonize.foreground(in: original))
    original.layers[1].clipped = false
    original.layers[1].mask = try Surface(width: 36, height: 32, fill: .black)
    XCTAssertThrowsError(try Harmonize.apply(in: original, foregroundID: subject))
    original.layers[0].visible = false
    XCTAssertNil(Harmonize.foreground(in: original))
  }

  @MainActor func testNativeAndHTTPFromMaskUseSamePixelsAndHistory() async throws {
    let source = try scene(), subject = try XCTUnwrap(source.activeLayerID)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let store = shared.store
      store.session = EditorSession(document: source)
      try service.share(shared)
      store.selectMask(subject)
      XCTAssertEqual(store.harmonizeTarget, subject)
      store.applyHarmonize()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try Renderer.composite(store.document).rgbaData(depth: .u8)
      await store.undo()
      store.selectMask(subject)
      let status = try await helper.edit(service, shared, HarmonizeAPI.apply, ["foregroundLayerID": subject.uuidString])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), native)
      let choice = try XCTUnwrap(Harmonize.choices(in: store.document))
      let switched = try await helper.edit(service, shared, HarmonizeAPI.variation,
        ["groupID": choice.groupID.uuidString, "variation": "ambient"])
      XCTAssertEqual(switched, 200)
      XCTAssertEqual(store.session.undoStack.count, 2)
      XCTAssertEqual(Harmonize.choices(in: store.document)?.selected, .ambient)
      let bad = try await helper.edit(service, shared, HarmonizeAPI.variation,
        ["groupID": choice.groupID.uuidString, "variation": "unknown"])
      XCTAssertEqual(bad, 400)
      await store.undo()
      await store.undo()
      XCTAssertEqual(store.document, source)
    }
  }
}
