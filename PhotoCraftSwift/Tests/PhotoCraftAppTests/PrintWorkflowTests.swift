import AppKit
import CoreGraphics
import PDFKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
import SwiftUI
@testable import PhotoCraft

final class PrintWorkflowTests: XCTestCase {
  @MainActor func testAcceptedDefaultsApplyAcrossDocumentsAndPreferenceReloadWithoutCarryingSelection() async throws {
    let name = "Photato.PrintTests." + UUID().uuidString
    let persisted = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { persisted.removePersistentDomain(forName: name) }
    let defaults = PrintPreferences(defaults: persisted)
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(), printPreferences: defaults)
    var selected = try CraftDocument(width: 40, height: 30)
    selected.selection = .init(x: 1, y: 1, width: 20, height: 10)
    let first = CraftNSDocument(model: selected)
    let second = CraftNSDocument(model: try CraftDocument(width: 40, height: 30))
    controller.addDocument(first)
    controller.addDocument(second)
    defer { controller.removeDocument(second); controller.removeDocument(first) }
    let before = first.store.document

    first.beginPrint()
    let cancelled = try XCTUnwrap(first.store.printWorkspace)
    cancelled.settings.paper = .tabloid
    cancelled.cancel()
    XCTAssertEqual(defaults.settings.paper, .letter)

    first.beginPrint()
    let accepted = try XCTUnwrap(first.store.printWorkspace)
    accepted.settings.paper = .a4
    accepted.settings.orientation = .landscape
    accepted.settings.sixteenBit = true
    accepted.settings.selectedArea = true
    accepted.settings.copies = 3
    accepted.refresh()
    await accepted.task?.value
    XCTAssertNotNil(accepted.output, accepted.error ?? "Missing preview.")
    accepted.accept(printNow: false)
    XCTAssertEqual(first.store.printSettings.paper, .a4)
    XCTAssertTrue(first.store.printSettings.selectedArea)
    XCTAssertEqual(second.store.printSettings.paper, .a4)
    XCTAssertEqual(second.store.printSettings.orientation, .landscape)
    XCTAssertTrue(second.store.printSettings.sixteenBit)
    XCTAssertFalse(second.store.printSettings.selectedArea)
    XCTAssertNil(first.store.inheritedPrintRevision)
    XCTAssertEqual(second.store.inheritedPrintRevision, defaults.revision)
    XCTAssertEqual(PrintPreferences(defaults: persisted).settings, second.store.printSettings)
    XCTAssertEqual(first.store.document, before)
    XCTAssertTrue(first.store.session.undoStack.isEmpty)
    XCTAssertFalse(first.isDocumentEdited)
    var oneCopy = first.store.printSettings
    oneCopy.copies = 1
    first.printRunner = { output, _, finish in
      XCTAssertEqual(output.settings.copies, 1)
      finish(true)
    }
    try first.startPrinting(oneCopy)
    await first.printTask?.value
    XCTAssertEqual(first.store.printSettings.copies, 3)
    XCTAssertEqual(defaults.settings.copies, 3)
  }

  @MainActor func testPhotoshopAuthoredPrintRecordRestoresItsSharedFieldsThroughNativeOpen() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/ColorProfiles/photoshop-owned-gradient-fill-p3-applecmm.psd")
    let document = CraftNSDocument(model: try CraftDocument(width: 1, height: 1))
    var shared = PrintSettings()
    shared.paper = .a5
    shared.sixteenBit = true
    shared.intent = .perceptual
    shared.registrationMarks = true
    shared.labels = true
    try document.store.printPreferences.remember(shared)
    try document.read(from: fixture, ofType: DocumentIO.Format.psd.typeIdentifier)
    XCTAssertEqual(document.store.printState["settingsSource"] as? String, "photoshopFile")
    let settings = document.store.printSettings
    XCTAssertEqual(settings.paper, .a5)
    XCTAssertEqual(settings.intent, .relativeColorimetric)
    XCTAssertFalse(settings.sixteenBit)
    XCTAssertFalse(settings.registrationMarks)
    XCTAssertFalse(settings.labels)
    XCTAssertEqual(document.store.printPreferences.settings, shared)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testLargeSelectedAreaCanBePreviewedAndDownloadedThroughHTTP() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let side = Surface.maxDimension
      var source = try CraftDocument(width: side, height: side)
      source.resolution = 72
      let region = IntRect(x: side - 31, y: side - 17, width: 31, height: 17)
      source.selection = region
      let store = document.store
      store.session = EditorSession(document: source)
      try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let path = "/v1/documents/\(id)/print.pdf"
      let before = try await helper.request(service, path: path)
      XCTAssertGreaterThanOrEqual(before.0.statusCode, 400)

      document.beginPrint()
      let preview = try XCTUnwrap(store.printWorkspace)
      XCTAssertFalse(preview.settings.selectedArea)
      XCTAssertTrue(try XCTUnwrap(preview.error).contains("Print Selected Area"))
      preview.settings.selectedArea = true
      preview.refresh()
      await preview.task?.value
      XCTAssertEqual(try XCTUnwrap(preview.output, preview.error ?? "").layout.source, region)
      XCTAssertFalse(store.printSettings.selectedArea)
      preview.cancel()

      let configured = try await helper.edit(service, document, "print.configure", ["settings": ["selectedArea": true]])
      XCTAssertEqual(configured, 200)
      XCTAssertTrue(store.printSettings.selectedArea)
      let disabled = try await helper.edit(service, document, "print.configure", ["settings": ["selectedArea": false]])
      XCTAssertGreaterThanOrEqual(disabled, 400)
      XCTAssertTrue(store.printSettings.selectedArea)
      let response = try await helper.request(service, path: path)
      XCTAssertEqual(response.0.statusCode, 200)
      XCTAssertEqual(try XCTUnwrap(PDFDocument(data: response.1)).pageCount, 1)
      let full = try await helper.edit(service, document, "print.configure", ["settings": [
        "selectedArea": false, "scaleToFit": false, "customWidth": 120, "customHeight": 120, "paper": "custom"
      ]])
      XCTAssertEqual(full, 200)
      let clippedPDF = try await helper.request(service, path: path)
      XCTAssertEqual(clippedPDF.0.statusCode, 200)
      let clippedPage = try XCTUnwrap(PDFDocument(data: clippedPDF.1)?.page(at: 0))
      XCTAssertEqual(clippedPage.bounds(for: .mediaBox).size, CGSize(width: 120, height: 120))
      XCTAssertEqual(store.document, source)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertFalse(document.isDocumentEdited)
      XCTAssertEqual(PrintAPI.capabilities["pixelLimitAppliesTo"] as? String, "outputRegion")
    }
  }

  @MainActor func testNativeSeparationPreviewAndHTTPPDFIncludeTheSameNamedSpotPage() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      var source = try store.document.convertingMode(.init(mode: .cmyk, depth: .u16))
      let spot = try source.newSpotChannel(name: "Spot Indigo", ink: .init(color: Pixel(0, 0, 1), solidity: 0.7), density: 0.5)
      let mask = AlphaChannel(name: "Saved Selection", pixels: try Surface(width: source.width, height: source.height, depth: .u16))
      source.alphaChannels = [mask, spot]
      store.session = EditorSession(document: source)
      try service.share(document)

      document.beginPrint()
      let preview = try XCTUnwrap(store.printWorkspace)
      await preview.task?.value
      preview.settings.content = .separations
      preview.settings.sixteenBit = true
      preview.refresh()
      await preview.task?.value
      let pages = try XCTUnwrap(preview.output, preview.error ?? "No plate preview.").pages
      let names = ["Cyan", "Magenta", "Yellow", "Black", spot.name]
      XCTAssertEqual(pages.map(\.label), names)
      preview.accept(printNow: false)
      XCTAssertEqual(store.printSettings.content, .separations)

      let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await helper.request(service, path: "/v1/documents/\(id)/print.pdf")
      XCTAssertEqual(response.0.statusCode, 200)
      let pdf = try XCTUnwrap(PDFDocument(data: response.1))
      XCTAssertEqual(pdf.pageCount, names.count)
      for (index, name) in names.enumerated() {
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: index)?.string).contains(name))
      }
      XCTAssertEqual(store.document, source)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertFalse(document.isDocumentEdited)
      let capability = try XCTUnwrap(PrintAPI.capabilities["separations"] as? [String: Any])
      XCTAssertEqual(capability["savedSpotChannels"] as? Bool, true)
    }
  }

  @MainActor func testSettingsPDFAndAPILeavePixelsHistoryAndDirtyStateUntouched() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let store = document.store, before = store.document, revision = service.revision(store)
      let status = try await helper.edit(service, document, "print.configure", ["settings": ["paper": "a4", "orientation": "landscape", "scaleToFit": false, "scalePercent": 50]])
      XCTAssertEqual(status, 200); XCTAssertEqual(store.printSettings.paper, .a4); XCTAssertNotEqual(service.revision(store), revision)
      XCTAssertEqual(store.printState["settingsSource"] as? String, "document")
      XCTAssertEqual(store.printPreferences.settings.paper, .letter)
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
      var missing = document.store.printSettings
      missing.printerName = "Owned missing printer fixture"
      try document.store.setPrintSettings(missing)
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
