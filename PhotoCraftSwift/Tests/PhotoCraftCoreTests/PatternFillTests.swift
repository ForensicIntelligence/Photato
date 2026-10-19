import Foundation
import PhotoCraftCore
import XCTest

final class PatternFillTests: XCTestCase {
  func fixture(linked: Bool = true) throws -> CraftDocument {
    var doc = try CraftDocument(width: 20, height: 12, depth: .u16)
    let pattern = try PatternPresets.make()[4]
    let layer = Layer(
      name: "Pattern", content: .patternFill(PatternFill(patternID: pattern.id, linked: linked)))
    try Command.addPatternFill(layer, pattern).apply(to: &doc)
    return doc
  }
  func fill(_ doc: CraftDocument) throws -> PatternFill {
    guard case .patternFill(let fill) = doc.layers.last?.content else {
      throw CraftError.invalid("Missing fill")
    }
    return fill
  }
  func testDocumentOwnsTileAndConflictingPresetDoesNotChangeExistingLayers() throws {
    let original = try fixture()
    var session = EditorSession(document: original)
    let old = try XCTUnwrap(original.patterns?.first)
    let changed = try RasterPattern(
      name: old.name,
      surface: Surface(width: 3, height: 2, depth: .f32, fill: Pixel(1.5, -0.2, 0.37)), id: old.id)
    let layer = Layer(name: "Another", content: .patternFill(PatternFill(patternID: old.id)))
    try session.execute(.addPatternFill(layer, changed))
    XCTAssertEqual(session.document.patterns?.count, 2)
    let newID = try fill(session.document).patternID
    XCTAssertNotEqual(newID, old.id)
    XCTAssertEqual(session.document.pattern(old.id), old)
    XCTAssertEqual(session.document.pattern(newID)?.surface, changed.surface)
    XCTAssertEqual(
      try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
    let result = session.document
    session.undo()
    XCTAssertEqual(session.document, original)
    session.redo()
    XCTAssertEqual(session.document, result)
    try session.execute(.duplicateLayer(layer.id))
    XCTAssertEqual(session.document.patterns?.count, 2)
    XCTAssertEqual(try fill(session.document).patternID, newID)
  }
  func testInvalidReferenceLockedTargetAndFailedAddLeaveDocumentUnchanged() throws {
    var doc = try fixture()
    let original = doc
    var missing = try fill(doc)
    missing.patternID = "missing"
    var session = EditorSession(document: doc)
    XCTAssertThrowsError(try session.execute(.setPatternFill(doc.layers.last!.id, missing, nil)))
    XCTAssertTrue(session.document == original)
    doc.layers[doc.layers.count - 1].locked = true
    let locked = doc
    session = EditorSession(document: doc)
    XCTAssertThrowsError(
      try session.execute(.setPatternFill(doc.layers.last!.id, try fill(doc), doc.patterns![0])))
    XCTAssertTrue(session.document == locked)
    var invalid = try fill(doc)
    invalid.placement.scale = .nan
    let bad = Layer(name: "Invalid", content: .patternFill(invalid))
    XCTAssertThrowsError(try session.execute(.addPatternFill(bad, PatternPresets.make()[1])))
    XCTAssertTrue(session.document == locked)
    XCTAssertTrue(session.undoStack.isEmpty)
  }
  func testLinkControlsLayerMoveButCanvasOperationsMoveEveryPattern() throws {
    for linked in [true, false] {
      var doc = try fixture(linked: linked)
      let id = doc.layers.last!.id
      try Command.move(id, 3, 2).apply(to: &doc)
      XCTAssertEqual(try fill(doc).flattenedPlacement().phaseX, linked ? 3 : 0)
      try Command.canvasSize(24, 16, .center, nil).apply(to: &doc)
      XCTAssertEqual(try fill(doc).flattenedPlacement().phaseX, linked ? 5 : 2)
      XCTAssertEqual(try fill(doc).flattenedPlacement().phaseY, linked ? 4 : 2)
      try Command.crop(.init(x: 1, y: 1, width: 20, height: 12)).apply(to: &doc)
      XCTAssertEqual(try fill(doc).flattenedPlacement().phaseX, linked ? 4 : 1)
      XCTAssertEqual(try fill(doc).flattenedPlacement().phaseY, linked ? 3 : 1)
      try Command.imageSize(40, 24, 72, .nearest).apply(to: &doc)
      XCTAssertEqual(try fill(doc).flattenedPlacement().phaseX, linked ? 8 : 2)
      XCTAssertEqual(try fill(doc).flattenedPlacement().scale, 200)
      try Command.imageSize(20, 24, 72, .nearest).apply(to: &doc)
      XCTAssertThrowsError(try fill(doc).flattenedPlacement())
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(doc)), doc)
    }
  }
  func testClipboardImportsOnlyReferencedTileAndRemapsCollisionAtEveryDestinationDepth() throws {
    var source = try fixture(linked: false)
    let originalPattern = source.patterns![0]
    source.layers.removeFirst()
    source.activeLayerID = source.layers[0].id
    try source.installPattern(PatternPresets.make()[1])
    let clip = try ClipboardContent(
      kind: .layers, document: source, bounds: .init(x: 0, y: 0, width: 20, height: 12))
    let portable = try ClipboardContent.decode(clip.encoded())
    for depth in PixelDepth.allCases {
      var target = try CraftDocument(width: 40, height: 24, depth: depth)
      let collision = try RasterPattern(
        name: "Unrelated", surface: Surface(width: 1, height: 1, fill: .white),
        id: originalPattern.id)
      try target.installPattern(collision)
      try Command.paste(portable, .centered, nil).apply(to: &target)
      let pasted = try fill(target)
      XCTAssertEqual(target.patterns?.count, 2)
      XCTAssertNotEqual(pasted.patternID, originalPattern.id)
      XCTAssertEqual(target.pattern(pasted.patternID)?.surface, originalPattern.surface)
      XCTAssertEqual(target.pattern(originalPattern.id), collision)
      XCTAssertEqual(try pasted.flattenedPlacement().phaseX, 10)
      XCTAssertEqual(try pasted.flattenedPlacement().phaseY, 6)
    }
  }
  func testCreationUsesSelectionMaskAndRegistryWithoutDestroyingSelection() throws {
    var doc = try CraftDocument(width: 20, height: 12)
    doc.selection = .init(x: 3, y: 4, width: 8, height: 5)
    let preset = try PatternPresets.make()[0]
    let layer = Layer(name: "Masked", content: .patternFill(PatternFill(patternID: preset.id)))
    try Command.addPatternFill(layer, preset, true).apply(to: &doc)
    let mask = try MaskSampler(layer: XCTUnwrap(doc.layers.last))
    XCTAssertEqual(mask.coverage(x: 2.5, y: 4.5), 0)
    XCTAssertEqual(mask.coverage(x: 3.5, y: 4.5), 1)
    XCTAssertEqual(mask.coverage(x: 11.5, y: 4.5), 0)
    XCTAssertEqual(doc.selection, .init(x: 3, y: 4, width: 8, height: 5))
    XCTAssertEqual(doc.patterns, [preset])
  }
}
