import AppKit
import Observation
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

/// Reproduces SwiftUI's cached validation across a native sheet's dismissal boundary.
@MainActor private final class PanelValidationProbe {
  private let evaluate: @MainActor () -> Bool
  private(set) var value = false

  init(_ evaluate: @escaping @MainActor () -> Bool) {
    self.evaluate = evaluate
    refresh()
  }

  func refresh() {
    value = withObservationTracking {
      evaluate()
    } onChange: { [weak self] in
      Task { @MainActor in self?.refresh() }
    }
  }
}

final class SheetPanelValidationTests: XCTestCase {
  @MainActor private func sheet() -> NSWindow {
    let result = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    result.isReleasedWhenClosed = false
    return result
  }

  @MainActor private func settle() async throws {
    // Allow AppKit's native sheet completion and Observation's deferred reevaluation to run.
    try await Task.sleep(for: .milliseconds(300))
  }

  @MainActor func testNativeSheetInvalidatesObservedPanelAvailability() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let document = try DocumentWorkspaceTests().fixture(controller, name: "Native sheet")
    let group = try XCTUnwrap(controller.documentWindows.current)
    let window = try XCTUnwrap(group.window)
    let view = WorkspaceView(store: document.store, workspace: group.workspace)
    let probe = PanelValidationProbe { view.canOrganizePanels }
    XCTAssertTrue(probe.value)
    let modal = sheet()
    defer {
      window.endSheet(modal)
      modal.close()
    }

    window.beginSheet(modal, completionHandler: nil)
    try await settle()
    XCTAssertTrue(window.attachedSheet === modal)
    XCTAssertFalse(probe.value, "Native sheets must invalidate cached panel and drag validation")
    probe.refresh()
    XCTAssertFalse(probe.value)
    window.endSheet(modal)
    try await settle()
    XCTAssertNil(window.attachedSheet)
    XCTAssertTrue(view.canOrganizePanels)
    XCTAssertTrue(
      probe.value, "Sheet dismissal must notify observers without another document edit")
  }

  @MainActor func testPanelOptionsCancelDuringNativeDismissalRestoresObservedAvailability()
    async throws
  {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let document = try DocumentWorkspaceTests().fixture(controller, name: "Panel options")
    let group = try XCTUnwrap(controller.documentWindows.current)
    let window = try XCTUnwrap(group.window)
    // Control the native transition explicitly; keep the real owner/delegate and panel predicate.
    window.contentView = NSView()
    let view = WorkspaceView(store: document.store, workspace: group.workspace)
    let original = try document.data(ofType: CraftNSDocument.nativeType)
    let layout = document.store.workspaceLibrary.layout
    for channels in [true, false, true] {
      if channels {
        document.store.beginChannelPanelOptions()
      } else {
        document.store.beginLayerPanelOptions()
      }
      XCTAssertTrue(document.store.hasToneDraft)
      let modal = sheet()
      window.beginSheet(modal, completionHandler: nil)
      if channels {
        document.store.cancelChannelPanelOptions()
      } else {
        document.store.cancelLayerPanelOptions()
      }
      XCTAssertFalse(document.store.hasToneDraft)
      XCTAssertTrue(window.attachedSheet === modal)
      let probe = PanelValidationProbe { view.canOrganizePanels }
      XCTAssertFalse(probe.value)
      window.endSheet(modal)
      try await settle()
      XCTAssertNil(window.attachedSheet)
      XCTAssertTrue(probe.value)
      modal.close()
    }
    XCTAssertEqual(try document.data(ofType: CraftNSDocument.nativeType), original)
    XCTAssertEqual(document.store.workspaceLibrary.layout, layout)
    XCTAssertTrue(document.store.session.undoStack.isEmpty)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testEndingOneSheetKeepsOtherWindowAndDraftGuards() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let a = try DocumentWorkspaceTests().fixture(controller, name: "Docked")
    let b = try DocumentWorkspaceTests().fixture(controller, name: "Floating")
    let owner = controller.documentWindows
    owner.float(b)
    let frame = try XCTUnwrap(owner.applicationFrame)
    let floating = try XCTUnwrap(owner.current)
    let first = try XCTUnwrap(frame.window)
    let second = try XCTUnwrap(floating.window)
    first.contentView = NSView()
    second.contentView = NSView()
    let firstSheet = sheet()
    let secondSheet = sheet()
    defer {
      first.endSheet(firstSheet)
      firstSheet.close()
      second.endSheet(secondSheet)
      secondSheet.close()
    }
    first.beginSheet(firstSheet, completionHandler: nil)
    second.beginSheet(secondSheet, completionHandler: nil)
    let probe = PanelValidationProbe { owner.canChangeDocument }
    first.endSheet(firstSheet)
    try await settle()
    XCTAssertFalse(probe.value)
    XCTAssertFalse(owner.activate(a))
    b.store.showAI = true
    second.endSheet(secondSheet)
    try await settle()
    XCTAssertFalse(probe.value)
    XCTAssertFalse(owner.activate(a))
    b.store.showAI = false
    try await settle()
    XCTAssertTrue(probe.value)
    XCTAssertTrue(owner.activate(a))
    XCTAssertTrue([a, b].allSatisfy { !$0.isDocumentEdited && $0.store.session.undoStack.isEmpty })
  }
}
