import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class InkChannelWorkflowTests: XCTestCase {
  func source(_ depth: PixelDepth = .u16, duotone: Bool = false) throws -> CraftDocument {
    let helper = InkModeControlsTests()
    var document = try helper.source(duotone ? .grayscale : .cmyk, depth: duotone ? .u8 : depth)
    var request = InkModeRequest(duotone ? .duotone : .multichannel, document: document)
    if duotone { request.settings = helper.settings() }
    try request.command(in: document).apply(to: &document)
    return document
  }
  func request(_ name: String, _ fields: [String: Any]) throws -> AutomationCommand { try InkModeControlsTests().command(name, fields) }
  func testNumericViewsRetainRawPlatesAndValidateTargets() throws {
    for depth in [PixelDepth.u8, .u16] {
      let d = try source(depth), plates = try d.multichannelRaster().plates
      for plate in plates {
        let pixels = try InkChannelPresentation.surface(d, visible: [.plate(plate.id)])
        XCTAssertTrue(pixels == (try plate.samples.surface(inverted: true)))
      }
      XCTAssertTrue(try InkChannelPresentation.surface(d) == Renderer.composite(d))
      XCTAssertEqual(try InkChannelPresentation.thumbnails(d, maximumSize: 12).count, 4)
      XCTAssertThrowsError(try InkChannelPresentation.surface(d, visible: []))
      XCTAssertThrowsError(try InkChannelPresentation.surface(d, visible: [.duotone]))
    }
    let duo = try source(duotone: true)
    XCTAssertTrue(try InkChannelPresentation.surface(duo, visible: [.duotone]) == Renderer.composite(duo))
  }
  @MainActor func testDesktopSelectionFillBrushPreviewCommitAndUndo() async throws {
    for duotone in [false, true] {
      let original = try source(duotone: duotone), store = EditorStore(document: original), target = original.inkChannelTargets[0]
      defer { store.cancelBrush(); store.renderTask?.cancel() }
      try store.selectInkChannels([target]); XCTAssertFalse(store.usesModeChannels)
      XCTAssertEqual(store.visibleInkTargets, [target]); XCTAssertTrue(store.session.undoStack.isEmpty)
      store.fill(color: .black, opacity: 0.4)
      var expected = original; try Command.inkChannel(.edit([target], .fill(0, 0.4))).apply(to: &expected)
      XCTAssertTrue(store.document == expected); XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertTrue(store.document == original)
      store.tool = .brush; store.brush.size = 3; store.brush.hardness = 1; store.brush.color = .black
      store.beginBrush(.init(x: 3.5, y: 4.5), zoom: 1)
      let gesture = try XCTUnwrap(store.brushGesture); await store.renderTask?.value
      XCTAssertThrowsError(try store.selectInkChannels([])); XCTAssertTrue(store.document == original)
      var preview = original; try XCTUnwrap(store.brushPreviewCommand).apply(to: &preview)
      store.finishBrush(); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertTrue(store.document == preview)
      let c = try request("ink.channel.edit", ["targets": [target.key], "action": "stroke", "points": BrushAPI.json(gesture.points), "brush": BrushAPI.json(gesture.brush)])
      var api = original; try c.inkChannelCommand(in: original).apply(to: &api); XCTAssertTrue(api == preview)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(store.document)) == store.document)
      await store.undo(); XCTAssertTrue(store.document == original)
      XCTAssertTrue(store.canUseMenuFill); XCTAssertTrue(store.canBeginFilterKind(.average)); XCTAssertFalse(store.canBeginFilterKind(.lensBlur))
      store.beginFilter(.average); await store.renderTask?.value
      XCTAssertNotNil(store.filterDraft); XCTAssertTrue(store.document == original)
      store.cancelFilter(); XCTAssertTrue(store.document == original)
      store.beginFilter(.average); var filtered = original; try XCTUnwrap(store.filterDraft).command(in: original).apply(to: &filtered)
      store.commitFilter(); await store.geometryTask?.value; XCTAssertNil(store.error); XCTAssertTrue(store.document == filtered)
      await store.undo(); XCTAssertTrue(store.document == original)
      store.clear(); var cleared = original; try Command.inkChannel(.edit([target], .fill(1, 1))).apply(to: &cleared)
      XCTAssertTrue(store.document == cleared); await store.undo(); XCTAssertTrue(store.document == original)
      if !duotone { XCTAssertTrue(store.document.layers.isEmpty) }
    }
  }
  @MainActor func testSpotOptionsCreationCancellationStaleSourceAndHistory() async throws {
    let original = try source(), store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    let plate = try original.multichannelRaster().plates[0]
    store.beginInkChannelOptions(plate.id); let draft = try XCTUnwrap(store.inkChannelOptions)
    draft.name = "Spot blue"; draft.color = Pixel(0.2, 0.3, 0.8); draft.solidity = 0.7
    XCTAssertFalse(store.canEditInkChannels); store.commitInkChannelOptions(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(try store.document.inkChannel(.plate(plate.id)), plate.samples)
    XCTAssertEqual(try store.document.multichannelRaster().plates[0].name, "Spot blue")
    await store.undo(); XCTAssertTrue(store.document == original)
    store.beginInkChannelOptions(); let new = try XCTUnwrap(store.inkChannelOptions); new.density = 0.25
    store.commitInkChannelOptions(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.effectiveInkTargets, [.plate(new.plateID)])
    XCTAssertEqual(try store.document.multichannelRaster().plates.count, 5)
    await store.undo(); XCTAssertTrue(store.document == original)
    store.beginInkChannelOptions(); store.inkChannelOptions = nil; XCTAssertTrue(store.document == original)
    store.beginInkChannelOptions(plate.id); try store.session.execute(.inkChannel(.write(.plate(plate.id), 0, [1])))
    let changed = store.document; store.commitInkChannelOptions(); await store.geometryTask?.value
    XCTAssertNotNil(store.error); XCTAssertTrue(store.document == changed)
  }
  @MainActor func testHostedInkPanelsAndOptionsFitTheirBounds() async throws {
    let helper = LayerRevealTests()
    for duotone in [false, true] {
      let d = try source(duotone: duotone), store = EditorStore(document: d)
      defer { store.renderTask?.cancel() }; store.surface = try Renderer.composite(d)
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 275, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; defer { window.close() }
      window.appearance = NSAppearance(named: .darkAqua)
      let host = NSHostingView(rootView: ChannelsPanel(store: store).background(StudioTheme.panel).foregroundStyle(Color(white: 0.88)).preferredColorScheme(.dark))
      window.contentView = host; try await helper.settle(window)
      XCTAssertEqual(host.bounds.width, 275, accuracy: 0.5); XCTAssertEqual(host.bounds.height, 420, accuracy: 0.5)
      try helper.capture(window, named: duotone ? "ink-duotone-channels" : "ink-multichannel-channels")
      XCTAssertTrue(store.document == d); XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPSelectionReadWritePreviewAndUndoMatchDesktop() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let original = try self.source(), target = original.inkChannelTargets[0]
      document.store.session = EditorSession(document: original)
      let desktop = EditorStore(document: original); defer { desktop.renderTask?.cancel() }
      let selected = try await helper.edit(service, document, "ink.channel.select", ["targets": [target.key]])
      XCTAssertEqual(selected, 200); try desktop.selectInkChannels([target])
      let share = try XCTUnwrap(service.shares.first)
      let read = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "ink.channel.read", "revision": service.revision(document.store), "parameters": ["target": target.key, "offset": 1, "count": 3]])
      XCTAssertEqual(read.0.statusCode, 200)
      let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: read.1) as? [String: Any])
      let expectedValues = (1..<4).map { Double(try! original.inkChannel(target).value(at: $0)) }
      XCTAssertEqual(raw["values"] as? [Double], expectedValues)
      desktop.fill(color: .black, opacity: 0.5)
      let edited = try await helper.edit(service, document, "ink.channel.edit", ["targets": [target.key], "action": "fill", "value": 0, "opacity": 0.5])
      XCTAssertEqual(edited, 200); XCTAssertTrue(document.store.document == desktop.document)
      let preview = try await helper.request(service, path: "/v1/documents/\(share.id)/channel-preview.png")
      XCTAssertEqual(preview.0.statusCode, 200); XCTAssertEqual(preview.1, try AutomationService.png(desktop.document, inkVisibility: [target]))
      let write = try await helper.edit(service, document, "ink.channel.write", ["target": target.key, "offset": 1, "values": [0, 1]])
      XCTAssertEqual(write, 200); XCTAssertEqual(try document.store.document.inkChannel(target).value(at: 1), 0)
      for _ in 0..<2 { let undone = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undone, 200) }
      XCTAssertTrue(document.store.document == original)
      let view = try await helper.edit(service, document, "ink.channel.visibility", ["targets": original.inkChannelTargets.map(\.key)])
      XCTAssertEqual(view, 200); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let state = service.state(share, document: document)
      XCTAssertEqual((state["inkMode"] as? [String: Any])?["editingTargets"] as? [String], [target.key])
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: InkChannelAPI.capabilities))
    }
  }
  @MainActor func testHTTPManagementFilterSelectionAndInvalidRequests() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let original = try self.source(), target = original.inkChannelTargets[0], id = try XCTUnwrap(UUID(uuidString: target.key)), newID = UUID()
      let cases: [(String, [String: Any])] = [
        ("ink.channel.manage", ["action": "create", "newID": newID.uuidString, "name": "Spot", "density": 0.25]),
        ("ink.channel.manage", ["action": "duplicate", "plateID": id.uuidString, "newID": newID.uuidString]),
        ("ink.channel.manage", ["action": "move", "plateID": id.uuidString, "index": 2]),
        ("ink.channel.manage", ["action": "delete", "plateID": id.uuidString]),
        ("ink.channel.manage", ["action": "options", "plateID": id.uuidString, "name": "Ink", "color": BrushAPI.json(Pixel(0.8, 0.1, 0.4)), "solidity": 0.8]),
        ("ink.channel.edit", ["action": "invert", "targets": [target.key]]),
        ("ink.channel.edit", ["action": "filter", "targets": [target.key], "filter": ["kind": "average"]]),
        ("ink.channel.edit", ["action": "selection", "targets": [target.key], "mode": SelectionMode.replace.rawValue, "invert": true])]
      for (name, fields) in cases {
        document.store.session = EditorSession(document: original)
        var expected = original; try self.request(name, fields).inkChannelCommand(in: original).apply(to: &expected)
        let result = try await helper.edit(service, document, name, fields)
        XCTAssertEqual(result, 200, name); XCTAssertTrue(document.store.document == expected, name)
        XCTAssertEqual(document.store.session.undoStack.count, 1)
      }
      document.store.session = EditorSession(document: original)
      var defaultSelection = original
      try self.request("ink.channel.edit", ["action": "selection", "targets": [target.key]]).inkChannelCommand(in: original).apply(to: &defaultSelection)
      var explicitSelection = original; try Command.inkChannel(.loadSelection(target, .replace, false)).apply(to: &explicitSelection)
      XCTAssertTrue(defaultSelection == explicitSelection)
      for fields: [String: Any] in [["action": "invert", "targets": []], ["action": "invert", "targets": [target.key, target.key]], ["action": "invert", "targets": [target.key], "value": 0], ["action": "fill", "targets": [target.key], "value": 2], ["action": "selection", "targets": original.inkChannelTargets.map(\.key)]] {
        let status = try await helper.edit(service, document, "ink.channel.edit", fields)
        XCTAssertEqual(status, 400); XCTAssertTrue(document.store.document == original)
      }
      let stale = try await helper.edit(service, document, "ink.channel.select", ["targets": []], revision: "old"); XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "ink.channel.select", ["targets": []]); XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      let alpha = try AlphaChannel(name: "Mask", pixels: Surface(width: original.width, height: original.height, depth: original.depth))
      try document.store.session.execute(.channel(.create(alpha))); try document.store.selectAlphaChannel(alpha.id)
      let saved = document.store.document
      let wrong = try await helper.edit(service, document, "ink.channel.edit", ["action": "invert", "targets": [target.key]])
      XCTAssertEqual(wrong, 422); XCTAssertTrue(document.store.document == saved)
    }
  }
  @MainActor func testRevokedInkWriteCannotCommit() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var original = try CraftNSDocument.blankModel(width: 512, height: 512, background: Pixel(0.1, 0.6, 0.9))
      try InkModeRequest(.multichannel, document: original).command(in: original).apply(to: &original)
      document.store.session = EditorSession(document: original); try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let revoke = Task { @MainActor in
        for _ in 0..<10000 { if document.store.geometryBusy { service.revoke(id); return }; await Task.yield() }
        XCTFail("Ink edit never entered the worker")
      }
      let status = try await helper.edit(service, document, "ink.channel.edit", ["action": "invert", "targets": original.inkChannelTargets.map(\.key)])
      await revoke.value; XCTAssertEqual(status, 409); XCTAssertTrue(document.store.document == original)
      XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertFalse(document.store.geometryBusy)
    }
  }
}
