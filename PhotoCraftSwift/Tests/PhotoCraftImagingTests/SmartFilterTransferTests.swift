import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class SmartFilterTransferTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8, existing: Bool = true) throws -> CraftDocument {
    var d = try CraftDocument(width: 6, height: 4, depth: depth)
    var pixels = try Surface(width: 6, height: 4, depth: depth)
    for y in 0..<4 { for x in 0..<6 { pixels.setPixel(x:x, y:y, Pixel(Float(x)/6, Float(y)/4, 0.3, 0.8)) } }
    d.layers = [Layer(name:"Source", content:.raster(pixels)), Layer(name:"Target", content:.raster(pixels))]
    d.activeLayerID = d.layers[0].id
    for id in d.layers.map(\.id) { try SmartObjectIO.convert(in:d, selected:[id]).apply(to:&d) }
    var blur = RasterFilter(.boxBlur); blur.radius = 1
    var mosaic = RasterFilter(.mosaic); mosaic.cellSize = 2
    var stack = SmartFilterStack(); stack.filters = [.init(filter:blur, opacity:0.5, blendMode:.screen), .init(filter:mosaic, enabled:false)]
    stack.mask = try Surface(width:6, height:4, depth:.u16, fill:Pixel(0.3, 0.3, 0.3, 1))
    stack.maskProperties.transform = .translation(0.5, 1.25); stack.maskProperties.density = 0.65
    d.layers[0].smartFilters = stack
    if existing {
      var target = SmartFilterStack(); target.filters = [.init(filter:blur)]
      try target.createMask(in:d); target.maskProperties.density = 0.7; target.enabled = false
      d.layers[1].smartFilters = target
    }
    d.activeLayerID = d.layers[1].id; d.selection = .init(x:1, y:1, width:2, height:2)
    try d.validate(); return d
  }
  func request(_ d: CraftDocument, _ part: SmartFilterTransferRequest.Part, _ copy: Bool) -> SmartFilterTransferRequest {
    .init(sourceLayerID:d.layers[0].id, targetLayerID:d.layers[1].id, part:part, copy:copy)
  }
  func testWholeStackCopyPreservesProgramsOrderBitsSourceAndExistingMaskAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth), original = d.layers[0], oldTarget = d.layers[1]
      var result = d; try request(d, .stack, true).command(in:d).apply(to:&result)
      let stack = result.layers[1].smartFilters!
      XCTAssertEqual(result.layers[0], original)
      XCTAssertEqual(stack.filters.map(\.filter), (oldTarget.smartFilters!.filters + original.smartFilters!.filters).map(\.filter))
      XCTAssertEqual(stack.filters.suffix(2).map(\.opacity), original.smartFilters!.filters.map(\.opacity))
      XCTAssertEqual(stack.filters.suffix(2).map(\.blendMode), original.smartFilters!.filters.map(\.blendMode))
      XCTAssertEqual(stack.filters.suffix(2).map(\.enabled), original.smartFilters!.filters.map(\.enabled))
      XCTAssertTrue(Set(stack.filters.suffix(2).map(\.id)).isDisjoint(with:original.smartFilters!.filters.map(\.id)))
      XCTAssertEqual(stack.mask, oldTarget.smartFilters!.mask)
      XCTAssertEqual(stack.maskProperties, oldTarget.smartFilters!.maskProperties)
      XCTAssertEqual(stack.enabled, oldTarget.smartFilters!.enabled)
      XCTAssertEqual(result.layers.map(\.content), d.layers.map(\.content))
      XCTAssertEqual(result.layers.map(\.smartObject), d.layers.map(\.smartObject))
      XCTAssertEqual(result.selection, d.selection)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
    }
  }
  func testMoveToNewStackRetainsWholeMaskAndStateWithOneUndoAndRedo() throws {
    for depth in PixelDepth.allCases {
      var d = try fixture(depth, existing:false); d.layers[0].smartFilters?.enabled = false
      let original = d.layers[0].smartFilters
      var session = EditorSession(document:d)
      try session.execute(request(d, .stack, false).command(in:d))
      let result = session.document
      XCTAssertNil(result.layers[0].smartFilters); XCTAssertEqual(result.layers[1].smartFilters, original)
      XCTAssertEqual(session.undoStack.count, 1); try session.undo(); XCTAssertEqual(session.document, d)
      try session.redo(); XCTAssertEqual(session.document, result)
    }
  }
  func testMaskCopyAndMoveRetainExactCoverageAndPropertiesAndOnlyChangeMasks() throws {
    for depth in PixelDepth.allCases { for copy in [true, false] {
      let d = try fixture(depth); var result = d
      try request(d, .mask, copy).command(in:d).apply(to:&result)
      XCTAssertEqual(result.layers[1].smartFilters?.mask, d.layers[0].smartFilters?.mask)
      XCTAssertEqual(result.layers[1].smartFilters?.maskProperties, d.layers[0].smartFilters?.maskProperties)
      XCTAssertEqual(result.layers[1].smartFilters?.filters, d.layers[1].smartFilters?.filters)
      XCTAssertEqual(result.layers[0].smartFilters?.filters, d.layers[0].smartFilters?.filters)
      XCTAssertEqual(result.layers[0].smartFilters?.mask, copy ? d.layers[0].smartFilters?.mask : nil)
      XCTAssertEqual(result.layers.map(\.content), d.layers.map(\.content))
    } }
  }
  func testMovedFilterCollisionsAreRemappedWithoutChangingExistingDestinationIDs() throws {
    var d = try fixture(); let collision = d.layers[0].smartFilters!.filters[0].id
    d.layers[1].smartFilters?.filters[0].id = collision
    var result = d; try request(d, .stack, false).command(in:d).apply(to:&result)
    let stack = result.layers[1].smartFilters!
    XCTAssertEqual(stack.filters[0].id, d.layers[1].smartFilters!.filters[0].id)
    XCTAssertEqual(Set(stack.filters.map(\.id)).count, 3)
    XCTAssertNil(result.layers[0].smartFilters)
  }
  func testCapacityLocksMissingMasksAndSelfTargetsRejectWithoutAnyPartialEdit() throws {
    let d = try fixture(); var limited = d
    limited.layers[1].smartFilters?.filters = (0..<32).map { _ in .init(filter:RasterFilter(.boxBlur)) }
    XCTAssertThrowsError(try request(limited, .stack, false).command(in:limited))
    var locked = d; locked.layers[0].locked = true
    XCTAssertThrowsError(try request(locked, .stack, false).command(in:locked))
    XCTAssertNoThrow(try request(locked, .stack, true).command(in:locked))
    locked = d; locked.layers[1].locked = true
    XCTAssertThrowsError(try request(locked, .mask, true).command(in:locked))
    var missing = d; missing.layers[0].smartFilters?.mask = nil
    XCTAssertThrowsError(try request(missing, .mask, false).command(in:missing))
    XCTAssertThrowsError(try SmartFilterTransferRequest(sourceLayerID:d.layers[0].id, targetLayerID:d.layers[0].id, part:.stack, copy:true).command(in:d))
    var session = EditorSession(document:limited)
    XCTAssertThrowsError(try session.execute(request(limited, .stack, true).command(in:limited)))
    XCTAssertEqual(session.document, limited); XCTAssertTrue(session.undoStack.isEmpty)
  }
  func testPreparedMoveRejectsStaleSourceAndSemanticActionsResolveFreshLayerIdentities() throws {
    let original = try fixture(); let operation = try request(original, .mask, false).command(in:original)
    var stale = original; stale.name = "Changed"
    XCTAssertThrowsError(try operation.apply(to:&stale)); XCTAssertNotNil(stale.layers[0].smartFilters?.mask)
    var recorder = EditorSession(document:original); try recorder.startActionRecording(name:"Move mask")
    try recorder.execute(operation)
    let action = try XCTUnwrap(recorder.actionRecording?.snapshot); recorder.stopActionRecording()
    XCTAssertEqual(action.steps.count, 1)
    guard case .smartFilterTransfer = action.steps[0].operation else { return XCTFail("Missing semantic transfer") }
    var replay = original; for i in replay.layers.indices { replay.layers[i].id = UUID() }; replay.activeLayerID = replay.layers[1].id
    var session = EditorSession(document:replay); try session.execute(.action(action))
    XCTAssertNil(session.document.layers[0].smartFilters?.mask)
    XCTAssertEqual(session.document.layers[1].smartFilters?.mask, original.layers[0].smartFilters?.mask)
    XCTAssertEqual(session.undoStack.count, 1); try session.undo(); XCTAssertEqual(session.document, replay)
  }
  func testCopiedProgramProducesExactOwnCompositeOnEquivalentDestination() throws {
    var captured = Data()
    for depth in PixelDepth.allCases {
      let original = try fixture(depth, existing:false)
      var result = original; try request(original, .stack, true).command(in:original).apply(to:&result)
      let a = try Renderer.layerSurface(result.layers[0], in:result)
      let b = try Renderer.layerSurface(result.layers[1], in:result)
      XCTAssertEqual(try a.rgbaData(depth:.f32), try b.rgbaData(depth:.f32))
      captured.append(try b.rgbaData(depth:.f32))
    }
    if let directory = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try captured.write(to:URL(fileURLWithPath:directory).appendingPathComponent("smart-filter-transfer.f32"))
    }
  }
}
