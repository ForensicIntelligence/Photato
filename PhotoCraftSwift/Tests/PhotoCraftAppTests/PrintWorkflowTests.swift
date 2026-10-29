import AppKit
import CoreGraphics
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
import SwiftUI
@testable import PhotoCraft

final class PrintWorkflowTests: XCTestCase {
  @MainActor func testSettingsPDFAndAPILeavePixelsHistoryAndDirtyStateUntouched() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let store = document.store, before = store.document, revision = service.revision(store)
      let status = try await helper.edit(service, document, "print.configure", ["settings": ["paper": "a4", "orientation": "landscape", "scaleToFit": false, "scalePercent": 50]])
      XCTAssertEqual(status, 200); XCTAssertEqual(store.printSettings.paper, .a4); XCTAssertNotEqual(service.revision(store), revision)
      let id = try XCTUnwrap(service.shares.first?.id), response = try await helper.request(service, path: "/v1/documents/\(id)/print.pdf")
      XCTAssertEqual(response.0.statusCode, 200); XCTAssertEqual(response.0.mimeType, "application/pdf")
      let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: response.1 as CFData)!)); XCTAssertEqual(pdf.numberOfPages, 1); XCTAssertEqual(pdf.page(at: 1)?.getBoxRect(.mediaBox).width ?? 0, 841.89, accuracy: 0.001)
      XCTAssertEqual(store.document, before); XCTAssertTrue(store.session.undoStack.isEmpty); XCTAssertFalse(document.isDocumentEdited)
      let stale = try await helper.edit(service, document, "print.configure", ["settings": ["copies": 2]], revision: revision); XCTAssertEqual(stale, 409)
    }
  }
  @MainActor func testInvalidSettingsAtomicAndPDFUsesCommittedSettingsDuringDraft() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let original = document.store.printSettings
      for settings: [String: Any] in [["unknown": true], ["copies": 0], ["scalePercent": 0], ["marginLeft": 900], ["colorHandling": "photatoManages"], ["selectedArea": true]] {
        let status = try await helper.edit(service, document, "print.configure", ["settings": settings]); XCTAssertGreaterThanOrEqual(status, 400); XCTAssertEqual(document.store.printSettings, original)
      }
      document.beginPrint(); let model = try XCTUnwrap(document.store.printWorkspace); await model.task?.value
      model.settings.paper = .a3; model.refresh(); await model.task?.value
      let busy = try await helper.edit(service, document, "print.configure", ["settings": ["copies": 2]]); XCTAssertEqual(busy, 409)
      let id = try XCTUnwrap(service.shares.first?.id), response = try await helper.request(service, path: "/v1/documents/\(id)/print.pdf")
      let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: response.1 as CFData)!)); XCTAssertEqual(pdf.page(at: 1)?.getBoxRect(.mediaBox).width, 612)
      model.cancel(); XCTAssertEqual(document.store.printSettings, original); XCTAssertFalse(document.store.hasToneDraft)
    }
  }
  @MainActor func testPrinterPermissionAndInjectedSubmission() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let source = document.store.document; var received: PreparedPrint?
      document.printRunner = { output, info, done in received = output; XCTAssertEqual(info.scalingFactor, 1); XCTAssertEqual(info.leftMargin, 0); done(true) }
      let denied = try await helper.edit(service, document, "print.submit", [:]); XCTAssertEqual(denied, 403); XCTAssertNil(received)
      service.setPrintingEnabled(true)
      let result = try await helper.edit(service, document, "print.submit", [:]); XCTAssertEqual(result, 200)
      await document.printTask?.value
      XCTAssertNotNil(received); XCTAssertFalse(document.store.printBusy); XCTAssertEqual(document.store.printJobStatus, "completed"); XCTAssertEqual(document.store.document, source); XCTAssertFalse(document.isDocumentEdited)
      service.stop(); XCTAssertFalse(service.printingEnabled)
    }
  }
  @MainActor func testCancelledStaleAndUnauthorizedPreparationNeverSubmit() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { _, document in
    var calls = 0; document.printRunner = { _, _, done in calls += 1; done(true) }
    let id = try document.startPrinting(PrintSettings()); document.cancelPrintPreparation(id); await document.printTask?.value
    XCTAssertEqual(calls, 0); XCTAssertEqual(document.store.printJobStatus, "cancelled")
    try document.startPrinting(PrintSettings(), authorized: { false }); await document.printTask?.value
    XCTAssertEqual(calls, 0); XCTAssertEqual(document.store.printJobStatus, "failed")
    try document.startPrinting(PrintSettings()); document.store.printRevision = UUID(); await document.printTask?.value
    XCTAssertEqual(calls, 0); XCTAssertFalse(document.store.printBusy)
    }
  }
  @MainActor func testPrintSheetDoneCommitsOnlyOutputSettings() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let before = document.store.document; document.beginPrint(); let model = try XCTUnwrap(document.store.printWorkspace)
      model.settings.copies = 3; model.refresh(); await model.task?.value; XCTAssertNotNil(model.output, model.error ?? "Missing preview")
      model.accept(printNow: false); XCTAssertNil(document.store.printWorkspace); XCTAssertEqual(document.store.printSettings.copies, 3)
      XCTAssertEqual(document.store.document, before); XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertFalse(document.isDocumentEdited)
    }
  }
  @MainActor func testRevokingShareOrPrintPermissionCancelsOwnedPreparation() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var calls = 0; document.printRunner = { _, _, done in calls += 1; done(true) }
      for revokeShare in [false, true] {
        if service.shares.isEmpty { try service.share(document) }
        service.setPrintingEnabled(true)
        let share = try XCTUnwrap(service.shares.first)
        let command = try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": "print.submit", "revision": service.revision(document.store), "parameters": [:]]))
        _ = try service.executePrint(command, share: share, document: document)
        if revokeShare { service.revoke(share.id) } else { service.setPrintingEnabled(false) }
        await document.printTask?.value
        XCTAssertEqual(calls, 0); XCTAssertFalse(document.store.printBusy)
      }
    }
  }
  @MainActor func testNativePrintViewPDFPaginationUsesSharedRenderer() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { _, document in
      var original = document.store.document
      original.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(0.2, 0.6, 0.8)))
      let source = try original.convertingMode(.init(mode: .cmyk, depth: .u16))
      var settings = PrintSettings(); settings.content = .separations
      let output = try PrintOutput.prepare(source, settings: settings), view = PrintPageView(output)
      var range = NSRange(); XCTAssertTrue(view.knowsPageRange(&range)); XCTAssertEqual(range, NSRange(location: 1, length: 4))
      let info = try document.info(for: settings)
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/runs/20261028T185522Z-224-native-print")
      let url = root.appendingPathComponent("native-print-" + UUID().uuidString + ".pdf")
      info.jobDisposition = .save; info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
      // Exercise real AppKit pagination while forcing a file destination, never a printer.
      let operation = NSPrintOperation(view: view, printInfo: info)
      operation.showsPrintPanel = false; operation.showsProgressPanel = false
      XCTAssertEqual(operation.printInfo.jobDisposition, .save); XCTAssertTrue(operation.run())
      let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
      XCTAssertEqual(pdf.numberOfPages, 4)
      for n in 1...pdf.numberOfPages { XCTAssertEqual(pdf.page(at: n)?.getBoxRect(.mediaBox).size, output.layout.page.size) }
    }
  }
  @MainActor func testPrintWorkspaceWithUnavailablePrinterStillPreviewsAndCancelsDriverEdits() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { _, document in
      document.store.printSettings.printerName = "Owned missing printer fixture"
      let before = document.store.printSettings
      document.beginPrint(); let model = try XCTUnwrap(document.store.printWorkspace); await model.task?.value
      XCTAssertNotNil(model.output, model.error ?? "Missing preview"); XCTAssertNil(document.rememberedPrintInfo)
      model.driverInfo.paperSize = CGSize(width: 300, height: 400); model.cancel()
      XCTAssertEqual(document.store.printSettings, before); XCTAssertNil(document.rememberedPrintInfo); XCTAssertFalse(document.isDocumentEdited)
    }
  }
  @MainActor func testPrintSheetFitsOffscreen() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { _, document in
      document.beginPrint(); let model = try XCTUnwrap(document.store.printWorkspace); await model.task?.value
      let view = NSHostingView(rootView: PrintSheet(model: model))
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 830, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua); window.contentView = view
      defer { window.close(); model.cancel() }
      view.frame = NSRect(x: 0, y: 0, width: 830, height: 640); view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
      XCTAssertLessThanOrEqual(view.fittingSize.width, 830); XCTAssertLessThanOrEqual(view.fittingSize.height, 640)
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: bitmap)
      let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      try bytes.write(to: root.appendingPathComponent("artifacts/runs/20261028T185522Z-224-native-print/print-controls-" + UUID().uuidString + ".png"))
    }
  }
  @MainActor func testFactoryPrintMenusAndShortcuts() throws {
    let helper = PhotoshopMenuTests()
    try helper.withMenus { app, menu in
      let items = helper.allItems(menu)
      let printItem = try XCTUnwrap(items.first { $0.identifier?.rawValue == "File > Print…" })
      XCTAssertEqual(printItem.action, #selector(AppDelegate.printDocument)); XCTAssertEqual(printItem.keyEquivalent, "p"); XCTAssertEqual(printItem.keyEquivalentModifierMask, .command); XCTAssertFalse(app.validateMenuItem(printItem))
      let copy = try XCTUnwrap(items.first { $0.identifier?.rawValue == "File > Print One Copy" })
      XCTAssertEqual(copy.action, #selector(AppDelegate.printOneCopy)); XCTAssertEqual(copy.keyEquivalent, "p"); XCTAssertEqual(copy.keyEquivalentModifierMask, [.command, .option, .shift])
    }
  }
}
