import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class QuickMaskColorControlTests: XCTestCase {
  @MainActor func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }

  @MainActor func host(_ content: AnyView) async throws -> (NSWindow, NSHostingView<AnyView>, ColorSwatchButton) {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: content)
    window.contentView = host
    window.setContentSize(host.fittingSize)
    try await LayerRevealTests().settle(window)
    return (window, host, try XCTUnwrap(descendants(host, ColorSwatchButton.self).first))
  }

  @MainActor func resetPanel() {
    CompactColorWell.Coordinator.panelOwner = nil
    NSColorPanel.shared.setTarget(nil)
    NSColorPanel.shared.setAction(nil)
    NSColorPanel.shared.orderOut(nil)
  }

  @MainActor func testHostedColorButtonOpensPanelAndCancelDiscardsCustomDraft() async throws {
    let store = EditorStore(document: try QuickMaskSelectionWorkflowTests().model(),
      quickMaskPreferences: QuickMaskPreferences())
    defer { store.cancelChannelDialog(); store.renderTask?.cancel(); resetPanel() }
    let before = store.document, options = store.quickMaskOptions
    store.beginChannelDialog(.quickOptions)
    let draft = try XCTUnwrap(store.channelDialog)
    let (window, host, button) = try await self.host(AnyView(ChannelDialogSheet(store: store, draft: draft)))
    defer { window.close() }
    XCTAssertEqual(button.accessibilityLabel(), "Quick Mask overlay color")
    button.performClick(nil)
    let panel = NSColorPanel.shared
    XCTAssertTrue(panel.isVisible)
    XCTAssertFalse(panel.showsAlpha)
    let coordinator = try XCTUnwrap(button.target as? CompactColorWell.Coordinator)
    panel.color = NSColor(srgbRed: 32.0 / 255, green: 192.0 / 255, blue: 96.0 / 255, alpha: 1)
    coordinator.changed(panel)
    XCTAssertEqual(draft.options.color.r, 32.0 / 255, accuracy: 0.000001)
    XCTAssertEqual(draft.options.color.g, 192.0 / 255, accuracy: 0.000001)
    XCTAssertEqual(draft.options.color.b, 96.0 / 255, accuracy: 0.000001)
    XCTAssertEqual(store.document, before)
    XCTAssertEqual(store.quickMaskOptions, options)
    store.cancelChannelDialog()
    host.rootView = AnyView(EmptyView())
    try await LayerRevealTests().settle(window)
    XCTAssertFalse(panel.isVisible)
    XCTAssertNil(CompactColorWell.Coordinator.panelOwner)
    let cancelled = draft.options
    panel.color = .blue
    coordinator.changed(panel)
    XCTAssertEqual(draft.options, cancelled, "An old panel callback must not modify the cancelled draft.")
    XCTAssertEqual(store.quickMaskOptions, options)
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testHostedCustomColorCommitPersistsAllOptionsAndEntersMask() async throws {
    let suite = "Photato400-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); resetPanel() }
    let preferences = QuickMaskPreferences(defaults: defaults)
    let store = EditorStore(document: try QuickMaskSelectionWorkflowTests().model(), quickMaskPreferences: preferences)
    defer { store.cancelChannelDialog(); store.renderTask?.cancel() }
    let original = store.document
    store.beginChannelDialog(.quickOptions)
    let draft = try XCTUnwrap(store.channelDialog)
    let (window, host, button) = try await self.host(AnyView(ChannelDialogSheet(store: store, draft: draft)))
    defer { window.close() }
    button.performClick(nil)
    let panel = NSColorPanel.shared
    let coordinator = try XCTUnwrap(button.target as? CompactColorWell.Coordinator)
    panel.color = NSColor(srgbRed: 32.0 / 255, green: 192.0 / 255, blue: 96.0 / 255, alpha: 1)
    coordinator.changed(panel)
    draft.options.opacity = 0.37
    draft.options.indicates = .selectedAreas
    let expected = draft.options
    store.commitChannelDialog(draft)
    host.rootView = AnyView(EmptyView())
    try await LayerRevealTests().settle(window)
    XCTAssertFalse(panel.isVisible)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(QuickMaskPreferences(defaults: defaults).value, expected)
    store.toggleQuickMask()
    XCTAssertEqual(store.document.quickMask?.options, expected)
    XCTAssertEqual(store.document.layers, original.layers)
  }

  @MainActor func testRemovingDialogDoesNotCloseAColorPanelClaimedByAnotherControl() async throws {
    let store = EditorStore(document: try QuickMaskSelectionWorkflowTests().model(),
      quickMaskPreferences: QuickMaskPreferences())
    defer { store.cancelChannelDialog(); store.renderTask?.cancel(); resetPanel() }
    store.beginChannelDialog(.quickOptions)
    let draft = try XCTUnwrap(store.channelDialog)
    let (window, host, button) = try await self.host(AnyView(ChannelDialogSheet(store: store, draft: draft)))
    defer { window.close() }
    button.performClick(nil)
    let oldCoordinator = try XCTUnwrap(button.target as? CompactColorWell.Coordinator)
    var otherColor = Color.blue
    let other = CompactColorWell(color: Binding(get: { otherColor }, set: { otherColor = $0 }), label: "Other color")
    let (otherWindow, otherHost, otherButton) = try await self.host(AnyView(other))
    defer { otherWindow.close() }
    otherButton.performClick(nil)
    let otherCoordinator = try XCTUnwrap(otherButton.target as? CompactColorWell.Coordinator)
    let unchanged = draft.options
    store.cancelChannelDialog()
    host.rootView = AnyView(EmptyView())
    try await LayerRevealTests().settle(window)
    XCTAssertTrue(NSColorPanel.shared.isVisible)
    XCTAssertTrue(CompactColorWell.Coordinator.panelOwner === otherCoordinator)
    NSColorPanel.shared.color = .green
    oldCoordinator.changed(NSColorPanel.shared)
    XCTAssertEqual(draft.options, unchanged)
    otherCoordinator.changed(NSColorPanel.shared)
    XCTAssertEqual(NSColor(otherColor).usingColorSpace(.sRGB)?.greenComponent, 1)
    otherHost.rootView = AnyView(EmptyView())
    try await LayerRevealTests().settle(otherWindow)
    XCTAssertTrue(NSColorPanel.shared.isVisible, "Existing ordinary color controls retain their previous panel lifecycle.")
  }

  @MainActor func testHTTPCustomOptionsMatchNativeCommitAndInvalidColorIsAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let original = try QuickMaskSelectionWorkflowTests().model()
      document.store.session = EditorSession(document: original)
      try service.share(document)
      let previous = document.store.quickMaskOptions
      defer { document.store.quickMaskOptions = previous }
      let native = EditorStore(document: original, quickMaskPreferences: QuickMaskPreferences())
      defer { native.renderTask?.cancel() }
      native.beginChannelDialog(.quickOptions)
      let draft = try XCTUnwrap(native.channelDialog)
      draft.options.color = Pixel(32.0 / 255, 192.0 / 255, 96.0 / 255)
      draft.options.opacity = 0.37
      draft.options.indicates = .selectedAreas
      native.commitChannelDialog(draft)
      let status = try await helper.edit(service, document, "channel.edit", ["action": "quickMaskOptions",
        "overlayColor": [32.0 / 255, 192.0 / 255, 96.0 / 255], "opacity": 0.37, "indicates": "selectedAreas"])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(document.store.quickMaskOptions, native.quickMaskOptions)
      XCTAssertEqual(document.store.document, original)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let configured = document.store.quickMaskOptions
      let invalid = try await helper.edit(service, document, "channel.edit",
        ["action": "quickMaskOptions", "overlayColor": [1.01, 0, 0]])
      XCTAssertEqual(invalid, 400)
      XCTAssertEqual(document.store.quickMaskOptions, configured)
      XCTAssertEqual(document.store.document, original)
      let entered = try await helper.edit(service, document, "channel.edit", ["action": "quickMask", "enabled": true])
      XCTAssertEqual(entered, 200)
      XCTAssertEqual(document.store.document.quickMask?.options, configured)
    }
  }
}
