import XCTest
@testable import PhotoCraftCore

final class ModeComponentEditingTests: XCTestCase {
  func fixture(_ mode: DocumentColorMode, _ depth: PixelDepth) throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 3, depth: depth)
    document = try document.convertingMode(.init(mode: mode, depth: depth))
    var native = try XCTUnwrap(document.layers[0].nativeMode)
    for c in try native.planes.indices { for i in 0..<12 {
      try native.set(Float((i + c * 2) % 11) / 10, component: c, index: i)
    } }
    document.layers[0].nativeMode = native
    document.layers[0].content = .raster(try native.surface())
    return document
  }
  func testFillPreservesEveryUntargetedPlaneAndAlphaAtEveryModeDepth() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let before = try fixture(mode, depth), id = try XCTUnwrap(before.activeLayerID)
      let source = try XCTUnwrap(before.layers[0].nativeMode)
      var session = EditorSession(document: before)
      try session.execute(.modeComponents(.init(layerID: id, components: [0], operation: .fill(0.25, 1))))
      let after = try XCTUnwrap(session.document.layers[0].nativeMode)
      for c in 1..<(try source.planes.count) { XCTAssertEqual(try after.planes[c], try source.planes[c]) }
      for i in 0..<12 { XCTAssertEqual(after.value(component: 0, index: i), depth.quantize(mode == .cmyk ? 0.75 : 0.25)) }
      XCTAssertEqual(session.undoStack.count, 1)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
      try session.undo(); XCTAssertEqual(session.document, before)
      try session.redo(); XCTAssertEqual(session.document.layers[0].nativeMode, after)
    } }
  }
  func testSelectionMapsThroughMovedLayerAndMultiChannelEditIsOneUndo() throws {
    var before = try fixture(.cmyk, .u16)
    before.layers[0].x = 1; before.layers[0].y = 1
    before.selection = IntRect(x: 2, y: 2, width: 1, height: 1)
    let id = try XCTUnwrap(before.activeLayerID), source = try XCTUnwrap(before.layers[0].nativeMode)
    var session = EditorSession(document: before)
    try session.execute(.modeComponents(.init(layerID: id, components: [0, 3], operation: .fill(0, 1))))
    let result = try XCTUnwrap(session.document.layers[0].nativeMode)
    for c in try source.planes.indices { for i in 0..<12 {
      XCTAssertEqual(result.value(component: c, index: i), (c == 0 || c == 3) && i == 5 ? 1 : source.value(component: c, index: i))
    } }
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo(); XCTAssertEqual(session.document, before)
  }
  func testStrokeAndEraseChangeGrayViewWithoutDestroyingCMYKBlackOrAlpha() throws {
    let before = try fixture(.cmyk, .u8), id = try XCTUnwrap(before.activeLayerID)
    let source = try XCTUnwrap(before.layers[0].nativeMode)
    for erase in [false, true] {
      var brush = Brush(); brush.size = 1; brush.hardness = 1; brush.opacity = 1
      brush.color = .black; brush.erase = erase; brush.backgroundColor = .white
      var session = EditorSession(document: before)
      try session.execute(.modeComponents(.init(layerID: id, components: [0], operation: .stroke([.init(x: 1.5, y: 1.5)], brush))))
      let result = try XCTUnwrap(session.document.layers[0].nativeMode)
      XCTAssertEqual(result.value(component: 0, index: 5), erase ? 0 : 1)
      for c in 1..<5 { XCTAssertEqual(try result.planes[c], try source.planes[c]) }
      try session.undo(); XCTAssertEqual(session.document, before)
    }
  }
  func testInvertAndFilterRetainOtherComponentsAndFloatExtendedRange() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      var before = try fixture(mode, depth)
      if depth == .f32 {
        try before.layers[0].nativeMode!.set(2, component: 0, index: 0)
        before.layers[0].content = .raster(try before.layers[0].nativeMode!.surface())
      }
      let id = try XCTUnwrap(before.activeLayerID), source = try XCTUnwrap(before.layers[0].nativeMode)
      for operation in [ModeComponentEdit.Operation.invert, .filter(RasterFilter(.average))] {
        var session = EditorSession(document: before)
        try session.execute(.modeComponents(.init(layerID: id, components: [0], operation: operation)))
        let result = try XCTUnwrap(session.document.layers[0].nativeMode)
        for c in 1..<(try source.planes.count) { XCTAssertEqual(try result.planes[c], try source.planes[c]) }
        if case .invert = operation {
          XCTAssertEqual(result.value(component: 0, index: 0), depth.quantize(1 - source.value(component: 0, index: 0)))
        }
        try session.undo(); XCTAssertEqual(session.document, before)
      }
    } }
  }
  func testInvalidAndLockedRequestsAreAtomic() throws {
    let before = try fixture(.lab, .u16), id = try XCTUnwrap(before.activeLayerID)
    for edit in [ModeComponentEdit(layerID: id, components: [], operation: .invert),
      .init(layerID: id, components: [3], operation: .invert),
      .init(layerID: id, components: [0], operation: .fill(.nan, 1)),
      .init(layerID: id, components: [0], operation: .filter(RasterFilter(.cameraRaw)))] {
      var session = EditorSession(document: before)
      XCTAssertThrowsError(try session.execute(.modeComponents(edit)))
      XCTAssertEqual(session.document, before); XCTAssertTrue(session.undoStack.isEmpty)
    }
    var locked = before; locked.layers[0].locked = true
    var session = EditorSession(document: locked)
    XCTAssertThrowsError(try session.execute(.modeComponents(.init(layerID: id, components: [0], operation: .invert))))
    XCTAssertEqual(session.document, locked); XCTAssertTrue(session.undoStack.isEmpty)
  }
}
