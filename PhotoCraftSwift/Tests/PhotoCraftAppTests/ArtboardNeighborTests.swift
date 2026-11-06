import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ArtboardNeighborTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try ArtboardWorkflowTests().fixture(depth)
    let id = d.artboards[0].id
    var board = d.artboards[0].artboard!
    board.background = Pixel(0.2, 0.4, 0.6, 0.8)
    board.guides = [.init(axis: .vertical, position: 3)]
    try Command.artboard(.settings(id, board)).apply(to: &d)
    return d
  }
  func testAllSidesCreateAndDuplicateAtAllDepthsPreservePixelsHistoryAndArchive() throws {
    for depth in PixelDepth.allCases { for side in ArtboardSide.allCases { for duplicate in [false, true] {
      let source = try fixture(depth), id = source.artboards[0].id
      var session = EditorSession(document: source)
      let request = ArtboardNeighborRequest(layerID: id, side: side, duplicate: duplicate, spacing: 7, name: "Neighbor")
      try session.execute(request.command(in: source))
      let result = session.document, neighbor = try XCTUnwrap(result.artboards.first { $0.id != id })
      let expected: IntRect
      switch side {
      case .top: expected = .init(x: 10, y: -12, width: 20, height: 10)
      case .right: expected = .init(x: 37, y: 5, width: 20, height: 10)
      case .bottom: expected = .init(x: 10, y: 22, width: 20, height: 10)
      case .left: expected = .init(x: -17, y: 5, width: 20, height: 10)
      }
      XCTAssertEqual(result.logicalArtboardBounds(neighbor), expected)
      XCTAssertEqual(result.logicalArtboardBounds(try XCTUnwrap(result.artboards.first { $0.id == id })), source.logicalArtboardBounds(source.artboards[0]))
      XCTAssertEqual(neighbor.name, "Neighbor"); XCTAssertEqual(neighbor.artboard?.background, source.artboards[0].artboard?.background)
      XCTAssertEqual(result.layers[0].content, source.layers[0].content)
      let children = result.layers.filter { $0.parentID == neighbor.id }
      XCTAssertEqual(children.count, duplicate ? 1 : 0)
      XCTAssertEqual(neighbor.artboard?.guides.map(\.position), duplicate ? [3] : [])
      if duplicate {
        XCTAssertNotEqual(children[0].id, source.layers[0].id)
        XCTAssertEqual(children[0].content, source.layers[0].content)
        XCTAssertEqual(try Renderer.composite(result.extractedArtboard(neighbor.id)), try Renderer.composite(source.extractedArtboard(id)))
      }
      let bytes = try NativeArchive.encodeChunked(result, minimumVersion: 86)
      XCTAssertEqual(try NativeArchive.decode(bytes), result)
      XCTAssertEqual(try NativeArchive.encodeChunked(NativeArchive.decode(bytes), minimumVersion: 86), bytes)
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo(); XCTAssertEqual(session.document, source)
      try session.redo(); XCTAssertEqual(session.document, result)
    } } }
  }
  func testLimitsLocksAndNegativeCoordinatesRejectAtomically() throws {
    var source = try fixture(), session = EditorSession(document: source)
    let id = source.artboards[0].id
    for spacing in [-1, 32769, Int.max] {
      XCTAssertThrowsError(try session.execute(ArtboardNeighborRequest(layerID: id, side: .left, spacing: spacing).command(in: source)))
      XCTAssertEqual(session.document, source); XCTAssertTrue(session.undoStack.isEmpty)
    }
    XCTAssertThrowsError(try ArtboardNeighborRequest(layerID: UUID(), side: .left).command(in: source))
    let index = try XCTUnwrap(source.layers.firstIndex { $0.id == id })
    source.layers[index].locked = true
    XCTAssertThrowsError(try ArtboardNeighborRequest(layerID: id, side: .right).command(in: source))
    var large = try CraftDocument(width: 300000, height: 1)
    try Command.artboard(.create(name: "Maximum", bounds: .init(x: 0, y: 0, width: 300000, height: 1), background: .clear, children: [])).apply(to: &large)
    for side in [ArtboardSide.left, .right] {
      XCTAssertThrowsError(try ArtboardNeighborRequest(layerID: large.artboards[0].id, side: side, spacing: 0).command(in: large))
    }
    session = EditorSession(document: large)
    try session.execute(ArtboardNeighborRequest(layerID: large.artboards[0].id, side: .bottom, spacing: 0).command(in: large))
    XCTAssertEqual(session.document.width, 300000); XCTAssertEqual(session.document.height, 2)
  }
  @MainActor func canvas() async throws -> (EditorStore, CraftCanvas, NSWindow) {
    _ = NSApplication.shared; _ = CraftDocumentController(workspaces: WorkspaceLibrary())
    let store = EditorStore(document: try fixture(), actions: ActionLibrary())
    store.tool = .artboard
    let canvas = CraftCanvas(store: store); canvas.frame = .init(x: 0, y: 0, width: 700, height: 420)
    let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = canvas
    store.updateViewport(size: canvas.bounds.size, backingScale: 1); store.setZoom(4, center: true)
    await store.renderTask?.value
    return (store, canvas, window)
  }
  @MainActor func close(_ store: EditorStore, _ canvas: CraftCanvas, _ window: NSWindow) {
    store.geometryTask?.cancel(); store.renderTask?.cancel(); canvas.clearCursorInput()
    window.contentView = nil; window.close()
  }
  @MainActor func mouse(_ type: NSEvent.EventType, _ side: ArtboardSide, _ canvas: CraftCanvas, flags: NSEvent.ModifierFlags = [], outside: Bool = false) throws -> NSEvent {
    let point = outside ? CGPoint.zero : try XCTUnwrap(canvas.artboardNeighborCenter(side))
    return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: flags, timestamp: 1, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
  }
  @MainActor func testNativeClicksCaptureOptionAndCommitExactlyOnceWithUndo() async throws {
    for bits in 0..<16 {
      let (store, canvas, window) = try await canvas(); defer { close(store, canvas, window) }
      let mods: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
      let flags = mods.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element) }
      let source = store.document
      canvas.cursorLocationInView = canvas.artboardNeighborCenter(.right)
      canvas.updateCursorModifiers(flags)
      XCTAssertEqual(canvas.toolCursor, .artboardNeighbor(duplicate: flags.contains(.option), available: true))
      canvas.mouseDown(with: try mouse(.leftMouseDown, .right, canvas, flags: flags))
      XCTAssertNotNil(store.artboardNeighborPress); XCTAssertEqual(store.document, source)
      XCTAssertTrue(store.hasToneDraft)
      canvas.updateCursorModifiers(flags.symmetricDifference(.option))
      XCTAssertEqual(canvas.toolCursor, .artboardNeighbor(duplicate: flags.contains(.option), available: true))
      canvas.mouseUp(with: try mouse(.leftMouseUp, .right, canvas, flags: flags.symmetricDifference(.option)))
      await store.geometryTask?.value
      XCTAssertNil(store.artboardNeighborPress); XCTAssertNil(store.error)
      XCTAssertEqual(store.document.artboards.count, 2)
      let board = try XCTUnwrap(store.document.artboards.first { $0.id != source.artboards[0].id })
      XCTAssertEqual(store.document.logicalArtboardBounds(board), .init(x: 130, y: 5, width: 20, height: 10))
      XCTAssertEqual(store.document.layers.filter { $0.parentID == board.id }.count, flags.contains(.option) ? 1 : 0)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let undone = await store.requestHistory(redo: false).value; XCTAssertTrue(undone); XCTAssertEqual(store.document, source)
    }
  }
  @MainActor func testNativeCancelStaleFocusToolSpaceAndOutsideReleaseDoNotEdit() async throws {
    let (store, canvas, window) = try await canvas(); defer { close(store, canvas, window) }
    let source = store.document
    for reason in 0..<7 {
      store.tool = .artboard; canvas.synchronizeTool(); canvas.spaceHeld = false
      canvas.mouseDown(with: try mouse(.leftMouseDown, .left, canvas))
      XCTAssertNotNil(store.artboardNeighborPress)
      switch reason {
      case 0:
        canvas.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
      case 1: canvas.clearCursorInput()
      case 2: store.tool = .move; store.tool = .artboard
      case 3: store.session = EditorSession(document: source)
      case 4: canvas.spaceHeld = true
      case 5: var deselected = source; deselected.activeLayerID = nil; store.session = EditorSession(document: deselected); store.selectedLayerIDs = []
      default: break
      }
      canvas.mouseUp(with: try mouse(.leftMouseUp, .left, canvas, outside: reason == 6 || reason == 5))
      await store.geometryTask?.value
      XCTAssertNil(store.artboardNeighborPress); XCTAssertEqual(store.document.artboards.count, 1); XCTAssertTrue(store.session.undoStack.isEmpty)
      store.session = EditorSession(document: source); store.selectedLayerIDs = [source.artboards[0].id]
    }
    canvas.spaceHeld = true; canvas.cursorLocationInView = canvas.artboardNeighborCenter(.right)
    XCTAssertEqual(canvas.toolCursor, .openHand)
  }
  @MainActor func testAPIAdjacentMatchesNativePixelsAndHistoryAndExposesStrictSchemas() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try self.fixture()); await document.store.renderTask?.value
      try service.share(document)
      for duplicate in [false, true] {
        let source = document.store.document, id = source.artboards[0].id
        let native = EditorStore(document: source, actions: ActionLibrary()); defer { native.renderTask?.cancel() }
        native.addArtboardNeighbor(.init(layerID: id, side: .left, duplicate: duplicate, spacing: 7, name: "API Neighbor"))
        await native.geometryTask?.value; XCTAssertNil(native.error)
        let status = try await helper.edit(service, document, "artboard.edit", ["operation": "adjacent", "layerID": id.uuidString, "side": "left", "duplicate": duplicate, "spacing": 7, "name": "API Neighbor"])
        XCTAssertEqual(status, 200)
        let actual = document.store.document
        XCTAssertEqual(actual.width, native.document.width); XCTAssertEqual(actual.height, native.document.height)
        XCTAssertEqual(actual.artboardOrigin, native.document.artboardOrigin)
        XCTAssertEqual(actual.artboards.map(\.name), native.document.artboards.map(\.name))
        XCTAssertEqual(actual.artboards.map { actual.logicalArtboardBounds($0) }, native.document.artboards.map { native.document.logicalArtboardBounds($0) })
        XCTAssertEqual(try Renderer.composite(actual), try Renderer.composite(native.document))
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(actual, minimumVersion: 86)), actual)
        let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, source)
        let redo = try await helper.edit(service, document, "history.redo"); XCTAssertEqual(redo, 200); XCTAssertEqual(document.store.document, actual)
        _ = try await helper.edit(service, document, "history.undo")
      }
      let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == "artboard.edit" })
      let envelope = try XCTUnwrap(definition.schema["properties"] as? [String: Any])
      let parameters = try XCTUnwrap(envelope["parameters"] as? [String: Any])
      let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
      for key in ["side", "duplicate", "spacing"] { XCTAssertNotNil(properties[key]) }
      XCTAssertTrue((Artboard.apiCapabilities["operations"] as? [String])?.contains("adjacent") == true)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: definition.schema))
    }
  }
  @MainActor func testAPIInvalidBusyStaleAndUnsharedDoNotMutate() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try self.fixture()); await document.store.renderTask?.value
      try service.share(document)
      let source = document.store.document, id = source.artboards[0].id
      let valid: [String: Any] = ["operation": "adjacent", "layerID": id.uuidString, "side": "right"]
      for bad in [["side": "diagonal"], ["duplicate": "yes"], ["spacing": -1], ["spacing": 1.5], ["spacing": 32769], ["bounds": ["x": 0, "y": 0, "width": 1, "height": 1]]] as [[String: Any]] {
        let status = try await helper.edit(service, document, "artboard.edit", valid.merging(bad) { _, new in new }); XCTAssertEqual(status, 400)
        XCTAssertEqual(document.store.document, source)
      }
      document.store.artboardNeighborPress = .init(request: .init(layerID: id, side: .right), generation: document.store.sessionGeneration)
      let busy = try await helper.edit(service, document, "artboard.edit", valid); XCTAssertEqual(busy, 409)
      document.store.artboardNeighborPress = nil
      let path = "/v1/documents/\(try XCTUnwrap(service.shares.first?.id))/commands"
      let stale = try await helper.request(service, path: path, body: ["command": "artboard.edit", "revision": "stale", "parameters": valid]); XCTAssertEqual(stale.0.statusCode, 409)
      service.revoke(try XCTUnwrap(service.shares.first?.id))
      let missing = try await helper.request(service, path: path, body: ["command": "artboard.edit", "revision": service.revision(document.store), "parameters": valid]); XCTAssertEqual(missing.0.statusCode, 404)
      XCTAssertEqual(document.store.document, source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  func testAPIBoundsAcceptCurrentSparseMaximumAndRejectOverflow() throws {
    let source = try CraftDocument(width: 1, height: 1)
    func command(_ width: Int) throws -> AutomationCommand {
      try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": "artboard.edit", "revision": "test", "parameters": ["operation": "create", "name": "Sparse", "bounds": ["x": 0, "y": 0, "width": width, "height": 1]]]))
    }
    for width in [32769, 300000] {
      var result = source; try command(width).artboardCommand(source).apply(to: &result)
      XCTAssertEqual(result.artboards[0].artboard?.width, width)
    }
    XCTAssertThrowsError(try command(300001).artboardCommand(source))
  }

  @MainActor func testNativeControlsHitRegionsClippingAndOwnedOffscreenCapture() async throws {
    let (store, canvas, window) = try await canvas(); defer { close(store, canvas, window) }
    for side in ArtboardSide.allCases {
      let center = try XCTUnwrap(canvas.artboardNeighborCenter(side))
      XCTAssertEqual(canvas.artboardNeighborHit(center), side)
      XCTAssertNil(canvas.artboardNeighborHit(.init(x: center.x + 11, y: center.y)))
    }
    let namedTop = try XCTUnwrap(canvas.artboardNeighborCenter(.top))
    store.showArtboardNames = false
    let unnamedTop = try XCTUnwrap(canvas.artboardNeighborCenter(.top))
    XCTAssertEqual(unnamedTop.y - namedTop.y, 16)
    store.showArtboardNames = true
    XCTAssertNil(canvas.artboardNeighborHit(.init(x: -1, y: -1)))
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"], let image = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
      canvas.cacheDisplay(in: canvas.bounds, to: image)
      try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent("artboard-neighbors.png"))
    }
    store.tool = .move; XCTAssertNil(canvas.artboardNeighborCenter(.right))
  }
}
