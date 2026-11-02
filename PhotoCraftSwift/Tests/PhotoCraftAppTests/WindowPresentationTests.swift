import AppKit
import Darwin
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class WindowPresentationTests: XCTestCase {
  func threadCount() throws -> Int {
    var list: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else {
      throw CocoaError(.executableRuntimeMismatch)
    }
    for i in 0..<Int(count) { mach_port_deallocate(mach_task_self_, list[i]) }
    vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
      vm_size_t(Int(count) * MemoryLayout<thread_t>.size))
    return Int(count)
  }

  @MainActor func stressWindowLifecycles() throws -> Bool {
    _ = NSApplication.shared
    let baseline = try threadCount()
    for index in 0..<200 {
      autoreleasepool {
        let rect = NSRect(x: -10000, y: -10000, width: 160, height: 80)
        let window: NSWindow = index.isMultiple(of: 2)
          ? PhotatoWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
          : PhotatoPanel(contentRect: rect, styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSTextField(labelWithString: "Owned presentation stress")
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.003))
        window.close()
      }
    }
    let work = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async { work.signal() }
    let available = work.wait(timeout: .now() + 2) == .success
    XCTAssertTrue(available, "Opening/closing windows must not exhaust the queue used by document I/O.")
    XCTAssertLessThan(try threadCount() - baseline, 40, "Animation workers must not grow once per closed window.")
    return available
  }

  @MainActor func testRepeatedWindowLifecyclesLeaveWorkersAvailableForRecovery() async throws {
    guard try stressWindowLifecycles() else { return }
    let controller = RecoveryLifecycleTests().controller()
    let document = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 8, height: 5))
    controller.addDocument(document)
    defer { document.close() }
    try document.store.executeEditorCommand(.fill(document.store.document.activeLayerID!, .black))
    let expected = document.store.document, history = document.store.session.undoStack.count
    try await document.writeRecoverySnapshot()
    XCTAssertEqual(try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), expected)
    XCTAssertEqual(document.store.document, expected)
    XCTAssertEqual(document.store.session.undoStack.count, history)
    XCTAssertFalse(document.recoveryWriteBusy)
    XCTAssertTrue(document.isDocumentEdited)
  }

  @MainActor func testWorkspaceAndFloatingPanelsUseImmediatePresentationWithoutChangingResponderPolicy() throws {
    let controller = RecoveryLifecycleTests().controller()
    let document = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 4, height: 3))
    controller.addDocument(document); document.makeWindowControllers()
    defer { document.close() }
    let window = try XCTUnwrap(controller.documentWindows.group(for: document)?.window)
    XCTAssertEqual(window.animationBehavior, .none)
    XCTAssertEqual(window.title, document.photatoWindowTitle)
    XCTAssertTrue(window.canBecomeKey)
    let panel = FloatingPanelWindow(contentRect: .zero, styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
    defer { panel.close() }
    XCTAssertEqual(panel.animationBehavior, .none)
    XCTAssertTrue(panel.canBecomeKey)
    XCTAssertFalse(panel.canBecomeMain)
    let progress = DocumentOpeningProgress(opening: controller.documentOpening)
    defer { progress.close() }
    XCTAssertEqual(try XCTUnwrap(progress.window).animationBehavior, .none)
    XCTAssertNotNil(AutomationService.recoveryCapabilities["windowPresentation"])
  }
}
