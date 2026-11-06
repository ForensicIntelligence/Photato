import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ChannelThumbnailOptionsTests: XCTestCase {
  func model(depth: PixelDepth = .u8, kind: String = "alpha") throws -> (CraftDocument, AlphaChannel) {
    var document = try CraftDocument(width: 8, height: 6, depth: depth)
    document.layers[0].content = .raster(try Surface(width: 8, height: 6, depth: depth, fill: Pixel(0.25, 0.5, 0.75)))
    document.selection = .init(x: 1, y: 1, width: 3, height: 2)
    if kind == "quick" {
      try Command.channel(.quickMask(true, .init())).apply(to: &document)
      return (document, try XCTUnwrap(document.quickMask))
    }
    let channel = try kind == "spot"
      ? document.newSpotChannel(name: "Varnish", ink: SpotInk(color: Pixel(0, 1, 1), solidity: 0.5), density: 0.375)
      : AlphaChannel(name: "Owned selection", pixels: Surface(width: 8, height: 6, depth: depth, fill: Pixel(0.375, 0.375, 0.375)))
    document.alphaChannels = [channel]
    return (document, channel)
  }
  func modifiers(_ bits: Int) -> NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    for (index, flag) in [NSEvent.ModifierFlags.control, .command, .option, .shift].enumerated()
      where bits & (1 << index) != 0 { flags.insert(flag) }
    return flags
  }
  @MainActor func testNativeOptionsMatchHTTPBytesCancelHistoryAndPixelsAtEveryDepth() async throws {
    for depth in PixelDepth.allCases { for kind in ["alpha", "spot", "quick"] {
      let (original, channel) = try model(depth: depth, kind: kind)
      let native = EditorStore(document: original, quickMaskPreferences: QuickMaskPreferences())
      defer { native.renderTask?.cancel(); native.cancelChannelDialog() }
      let context = AuxiliaryChannelActivation(store: native, channel: channel, quick: kind == "quick")
      let pixels = try Renderer.composite(original).rgbaData(depth: .f32)
      context.activate(in: native, clickCount: 2, modifiers: [])
      let cancelled = try XCTUnwrap(native.channelDialog)
      XCTAssertEqual(cancelled.kind, kind == "quick" ? .quickOptions : .options)
      cancelled.options.opacity = 0.25
      native.cancelChannelDialog()
      native.commitChannelDialog(cancelled)
      XCTAssertEqual(native.document, original); XCTAssertTrue(native.session.undoStack.isEmpty)
      XCTAssertTrue(context.openOptions(in: native))
      let draft = try XCTUnwrap(native.channelDialog)
      var parameters: [String: Any] = ["action": kind == "quick" ? "quickMaskOptions" : "configure"]
      if kind != "quick" { parameters["target"] = channel.id.uuidString }
      if kind == "spot" {
        draft.spotColor = Pixel(1, 0, 1); draft.solidity = 0.25
        parameters["spot"] = ["color": [1, 0, 1], "solidity": 0.25]
      } else {
        draft.options.color = Pixel(0, 1, 0); draft.options.opacity = 0.375
        parameters["overlayColor"] = [0, 1, 0]; parameters["opacity"] = 0.375
      }
      native.commitChannelDialog(draft)
      XCTAssertNil(native.channelDialog); XCTAssertNil(native.error)
      let committed = native.document
      XCTAssertEqual(native.session.undoStack.count, 1)
      XCTAssertEqual(try Renderer.composite(committed).rgbaData(depth: .f32), pixels)
      XCTAssertEqual(try committed.channel(context.target).pixels, channel.pixels)
      let helper = AutomationTests()
      try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
        file.store.session = EditorSession(document: original)
        let preferences = file.store.quickMaskOptions
        defer { file.store.quickMaskOptions = preferences }
        try service.share(file)
        let status = try await helper.edit(service, file, "channel.edit", parameters)
        XCTAssertEqual(status, 200); XCTAssertEqual(file.store.document, committed)
        XCTAssertEqual(try NativeArchive.encodeChunked(file.store.document), try NativeArchive.encodeChunked(committed))
        XCTAssertEqual(file.store.session.undoStack.count, 1)
        let undo = try await helper.edit(service, file, "history.undo")
        XCTAssertEqual(undo, 200); XCTAssertEqual(file.store.document, original)
        let redo = try await helper.edit(service, file, "history.redo")
        XCTAssertEqual(redo, 200); XCTAssertEqual(file.store.document, committed)
      }
      await native.undo(); XCTAssertEqual(native.document, original)
      await native.redo(); XCTAssertEqual(native.document, committed)
    } }
  }
  @MainActor func testAllModifierClicksRetainLegacyRoutingAndOnlyPlainDoubleClickOpensOptions() throws {
    for kind in ["alpha", "quick"] { for bits in 0..<16 { for count in [1, 2] {
      let (source, channel) = try model(kind: kind), flags = modifiers(bits)
      let native = EditorStore(document: source, quickMaskPreferences: QuickMaskPreferences())
      let legacy = EditorStore(document: source, quickMaskPreferences: QuickMaskPreferences())
      defer { native.renderTask?.cancel(); legacy.renderTask?.cancel() }
      let context = AuxiliaryChannelActivation(store: native, channel: channel, quick: kind == "quick")
      context.activate(in: native, clickCount: count, modifiers: flags)
      if kind == "quick" { try legacy.selectQuickMaskChannel() }
      else { legacy.channelThumbnail(channel.id, modifiers: flags) }
      XCTAssertEqual(native.document, legacy.document, "\(kind)/\(bits)/\(count)")
      XCTAssertEqual(native.session.undoStack.count, legacy.session.undoStack.count)
      XCTAssertEqual(native.editingChannel, legacy.editingChannel)
      XCTAssertEqual(native.alphaOverlay, legacy.alphaOverlay)
      XCTAssertEqual(native.channelDialog != nil, count == 2 && bits == 0)
      native.cancelChannelDialog()
    } } }
    XCTAssertTrue(AuxiliaryChannelActivation.opensOptions(clickCount: 2, modifiers: .capsLock))
    XCTAssertFalse(AuxiliaryChannelActivation.opensOptions(clickCount: 3, modifiers: []))
  }
  @MainActor func testHostedNativeDoubleClickAndStaleBusyModalDeletedSessionGuards() async throws {
    _ = NSApplication.shared
    let (source, channel) = try model(kind: "quick")
    let store = EditorStore(document: source, quickMaskPreferences: QuickMaskPreferences())
    defer { store.renderTask?.cancel(); store.cancelChannelDialog() }
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 275, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: AuxiliaryChannelRow(store: store, channel: channel, quick: true, eyeTracking: ChannelEyeTracking()))
    window.contentView = host
    try await LayerRevealTests().settle(window)
    let button = try XCTUnwrap(QuickMaskColorControlTests().descendants(host, AuxiliaryChannelThumbnailButton.self).first)
    XCTAssertEqual(button.accessibilityIdentifier(), "channels.thumbnail.quickMask")
    XCTAssertGreaterThan(button.bounds.width, 0); XCTAssertLessThanOrEqual(host.bounds.width, 275)
    let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
      location: button.convert(.init(x: 8, y: 8), to: nil), modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
    button.mouseDown(with: click)
    XCTAssertEqual(store.channelDialog?.kind, .quickOptions)
    XCTAssertEqual(store.document, source); XCTAssertTrue(store.session.undoStack.isEmpty)
    let draft = try XCTUnwrap(store.channelDialog)
    button.mouseDown(with: click)
    XCTAssertTrue(store.channelDialog === draft, "A modal dialog must not be replaced by another click.")
    store.cancelChannelDialog()
    for state in ["busy", "modal", "deleted", "session", "document", "foreign"] {
      let (original, alpha) = try model()
      let candidate = EditorStore(document: original, quickMaskPreferences: QuickMaskPreferences())
      defer { candidate.renderTask?.cancel(); candidate.cancelChannelDialog() }
      let context = AuxiliaryChannelActivation(store: candidate, channel: alpha, quick: false)
      var existing: ChannelDialog?
      if state == "busy" { candidate.geometryBusy = true }
      if state == "modal" { candidate.beginChannelDialog(.quickOptions); existing = candidate.channelDialog }
      if state == "deleted" { try candidate.executeEditorCommand(.channel(.delete(alpha.id))) }
      if state == "session" { candidate.session = EditorSession(document: original) }
      if state == "document" { var replacement = original; replacement.id = UUID(); candidate.session = EditorSession(document: replacement) }
      let actual = state == "foreign" ? EditorStore(document: original) : candidate
      defer { actual.renderTask?.cancel() }
      let before = actual.document, history = actual.session.undoStack.count
      XCTAssertFalse(context.openOptions(in: actual), state)
      XCTAssertTrue(actual.channelDialog === existing, state)
      XCTAssertEqual(actual.document, before); XCTAssertEqual(actual.session.undoStack.count, history)
    }
    XCTAssertNotNil(ChannelAPI.capabilities["nativeThumbnailOptions"])
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: ChannelAPI.capabilities))
    XCTAssertEqual(AutomationCommand.definitions.count, 250)
  }
}
