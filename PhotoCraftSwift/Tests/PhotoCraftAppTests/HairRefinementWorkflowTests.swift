import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class HairRefinementWorkflowTests: XCTestCase {
  private let width = 128
  private let height = 112

  private func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: height, depth: depth)
    var surface = try Surface(width: width, height: height, depth: depth)
    let subject = IntRect(x: 49, y: 45, width: 42, height: 45)
    let foreground = SIMD3<Float>(0.16, 0.09, 0.05)
    for y in 0..<height {
      for x in 0..<width {
        let variation: Float = (x / 5 + y / 7).isMultiple(of: 2) ? 0.17 : 0
        let backing = SIMD3<Float>(0.44 + variation, 0.54 + variation, 0.73)
        let strand: Float = (55...57).contains(x) && (28...44).contains(y) ? 0.63 : 0
        let alpha: Float = subject.contains(x, y) ? 1 : strand
        let color = foreground * alpha + backing * (1 - alpha)
        surface.setPixel(x:x, y:y, Pixel(color.x, color.y, color.z))
      }
    }
    document.layers[0].content = .raster(surface)
    document.selection = subject
    return document
  }

  func testHairRecoversConnectedCoverageWithoutChangingTheInputOrDistantPixels() throws {
    for depth in PixelDepth.allCases {
      let document = try fixture(depth)
      let input = try SelectionRefinementInput.prepare(document, layerID: document.layers[0].id)
      let plain = try input.refined(settings: .init())
      let options = try SelectionRefinement.decodeJSON(Data(#"{"refineHair":true}"#.utf8))
      let refined = try input.refined(settings: options)
      XCTAssertEqual(plain.byte(at: 37 * width + 56), 0)
      XCTAssertGreaterThan(refined.byte(at: 37 * width + 56), 100)
      XCTAssertEqual(refined.byte(at: 30 * width + 59), 0)
      XCTAssertEqual(refined.byte(at: 64 * width + 60), 255)
      XCTAssertEqual(refined.byte(at: 2 * width + 2), 0)
      XCTAssertEqual(input.original, document)
      XCTAssertEqual(try input.hairRefinedMask(), refined)
    }
    XCTAssertThrowsError(try SelectionRefinement.decodeJSON(Data(#"{"refineHair":1}"#.utf8)))
    XCTAssertThrowsError(try SelectionRefinement.decodeJSON(Data(#"{"refineHair":null}"#.utf8)))
    var empty = try fixture(.u8)
    empty.selection = nil
    let input = try SelectionRefinementInput.prepare(empty, layerID: empty.layers[0].id)
    XCTAssertThrowsError(try input.hairRefinedMask())

    let photo = try fixture(.u8)
    let guide = try SelectionRefinementInput.prepare(photo, layerID: photo.layers[0].id)
    var pixels = guide.guide
    let detached = 25 * width + 101
    pixels.setPixel(x: 101, y: 25, Pixel(0.16, 0.09, 0.05))
    var softSelection = try guide.mask.bytes
    softSelection[detached] = 17
    let soft = try SelectionMask(width: width, height: height, bytes: softSelection)
    let filtered = try SelectionHairMatting.refine(soft, guide: pixels)
    XCTAssertEqual(filtered.byte(at: detached), 17)
  }

  @MainActor func testHairRefinementAndBrushMatchTheAPIAndKeepEditableHistory() async throws {
    let source = try fixture(.u8)
    let layerID = source.layers[0].id
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let store = shared.store
      store.session = EditorSession(document: source)
      store.beginSelectMask()
      let model = try XCTUnwrap(store.selectMaskDraft)
      defer { store.cancelSelectMask() }
      let ready = SelectMaskWorkflowTests()
      await ready.ready(model)
      XCTAssertTrue(model.canRefineHair)
      model.refineHair()
      await model.detectionTask?.value
      await ready.ready(model)
      XCTAssertNil(model.error)
      let refined = try XCTUnwrap(model.state.hairMask)
      XCTAssertEqual(model.undoStates.count, 1)
      XCTAssertFalse(model.canRefineHair)
      model.undo()
      await ready.ready(model)
      XCTAssertNil(model.state.hairMask)
      model.redo()
      await ready.ready(model)
      XCTAssertEqual(model.refinedMask, refined)

      let subtract = SelectionRefinementStroke(tool: .subtract, size: 4, hardness: 1, points: [[56.5, 37.5]])
      var state = model.state
      state.strokes.append(subtract)
      state.output = .layerMask
      model.change(state)
      await ready.ready(model)
      XCTAssertEqual(model.refinedMask?.byte(at: 37 * width + 56), 0)
      store.commitSelectMask()
      await model.commitTask?.value
      XCTAssertNil(model.error)
      let native = store.document
      XCTAssertNotNil(native.layers[0].mask)
      XCTAssertEqual(native.layers[0].content, source.layers[0].content)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()
      XCTAssertEqual(store.document, source)

      try service.share(shared)
      let code = try await helper.edit(service, shared, "selection.refine",
        ["layerID": layerID.uuidString, "output": "layerMask", "settings": ["refineHair": true],
         "strokes": [["tool": "subtract", "size": 4, "hardness": 1, "points": [[56.5, 37.5]]]]],
        timeout: 30)
      XCTAssertEqual(code, 200)
      XCTAssertEqual(store.document, native)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let restored = try NativeArchive.decode(NativeArchive.encodeChunked(native))
      XCTAssertEqual(restored.layers[0].mask, native.layers[0].mask)
      await store.undo()
      XCTAssertEqual(store.document, source)
    }
  }
}
