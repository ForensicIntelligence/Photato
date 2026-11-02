import AppKit
import CoreGraphics
import ImageIO
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LayerCompsWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 6, height: 4)
    d.layers[0].content = .raster(try Surface(width: 6, height: 4, depth: .u8, fill: Pixel(1, 0, 0)))
    let red = UUID(), blue = UUID()
    try Command.layerComp(.capture(id: red, name: "Red / variation", comment: "First", options: .init())).apply(to: &d)
    d.layers.append(Layer(name: "Blue", content: .raster(try Surface(width: 6, height: 4, depth: .u8, fill: Pixel(0, 0, 1)))))
    // Recapture the first comp with both stable layer identities, hiding the blue layer.
    d.layers[1].visible = false
    try Command.layerComp(.update(red, name: "Red / variation", comment: "First", options: .init(), recapture: true)).apply(to: &d)
    d.layers[1].visible = true
    try Command.layerComp(.capture(id: blue, name: "Blue : variation", comment: "Second", options: .init())).apply(to: &d)
    return d
  }
  func testIndependentVariationsInAllSixFormatsPreserveSourceAndNativeComps() throws {
    let d = try fixture(), original = d
    for format in ["photato", "psd", "psb", "png", "tiff", "jpeg"] {
      let output = try LayerCompExport.render(d, options: .init(format: format))
      XCTAssertEqual(output.contentType, "application/zip"); XCTAssertEqual(output.files.count, 3)
      let metadata = try XCTUnwrap(try JSONSerialization.jsonObject(with: output.files.last!.data) as? [String: Any]); XCTAssertEqual((metadata["comps"] as? [[String: Any]])?.count, 2)
      for (index, file) in output.files.dropLast().enumerated() {
        XCTAssertFalse(file.name.contains("/") || file.name.contains(":")); XCTAssertTrue(file.name.contains(String(format: "_%04d_", index)))
        let read: CraftDocument = try format == "photato" ? NativeArchive.decode(file.data) : [.psd, .psb].contains(DocumentIO.Format(rawValue: format)!) ? PSDCodec.read(file.data) : RasterIO.read(file.data)
        XCTAssertEqual(read.width, 6); XCTAssertEqual(read.height, 4)
        let p = try Renderer.composite(read).pixel(x: 1, y: 1)
        XCTAssertEqual(p.r, index == 0 ? 1 : 0, accuracy: format == "jpeg" ? 0.02 : 0.00001)
        XCTAssertEqual(p.b, index == 0 ? 0 : 1, accuracy: format == "jpeg" ? 0.02 : 0.00001)
        if format == "photato" { XCTAssertEqual(read.layerComps?.comps, d.layerComps?.comps); XCTAssertEqual(read.minimumArchiveVersion, 79) }
        else { XCTAssertNil(read.layerComps) }
      }
      XCTAssertEqual(d, original)
    }
    for format in [DocumentIO.Format.psd, .psb] { XCTAssertEqual(try PSDCodec.read(DocumentIO.encode(d, format: format)).layerComps?.comps.map(\.name), d.layerComps?.comps.map(\.name)) }
  }
  func testPDFPageCountOrderDimensionsAndSubsetUseIndependentCoreGraphicsReader() throws {
    let d = try fixture(), output = try LayerCompExport.render(d, options: .init(format: "pdf"))
    XCTAssertEqual(output.contentType, "application/pdf")
    let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: output.data as CFData)!)); XCTAssertEqual(pdf.numberOfPages, 2)
    for index in 0..<2 {
      let page = try XCTUnwrap(pdf.page(at: index + 1)); XCTAssertEqual(page.getBoxRect(.mediaBox), CGRect(x: 0, y: 0, width: 6, height: 4))
      var bytes = [UInt8](repeating: 0, count: 6 * 4 * 4)
      bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: 6, height: 4, bitsPerComponent: 8, bytesPerRow: 24, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.drawPDFPage(page)
      }
      XCTAssertEqual(bytes[0], index == 0 ? 255 : 0); XCTAssertEqual(bytes[2], index == 0 ? 0 : 255); XCTAssertEqual(bytes[3], 255)
    }
    let id = d.layerComps!.comps[1].id, selected = try LayerCompExport.render(d, options: .init(format: "pdf", ids: [id]))
    XCTAssertEqual(CGPDFDocument(CGDataProvider(data: selected.data as CFData)!)?.numberOfPages, 1)
  }
  func testSelectionBudgetsUnsafeNamesAndMissingLayersRejectBeforeAnyFilePublication() throws {
    var d = try fixture(); let ids = d.layerComps!.comps.map(\.id)
    for options in [LayerCompExportOptions(ids: [ids[0], ids[0]]), .init(ids: [UUID()]), .init(prefix: "../escape"), .init(format: "unsupported")] { XCTAssertThrowsError(try LayerCompExport.render(d, options: options)) }
    XCTAssertThrowsError(try LayerCompExport.render(d, options: .init(), maximumBytes: 20))
    let selected = try LayerCompExport.render(d, options: .init(ids: [ids[1]])); XCTAssertEqual(selected.files.count, 2)
    let removed = d.layers.removeLast(); d.activeLayerID = d.layers[0].id
    XCTAssertThrowsError(try LayerCompExport.render(d, options: .init())); XCTAssertEqual(d.layerComps?.comps[0].missingLayers(in: d), [removed.id])
  }
  func testCancelledExportDoesNotYieldOutput() async throws {
    let d = try fixture()
    let worker = Task.detached { () throws -> LayerCompExportOutput in
      withUnsafeCurrentTask { $0?.cancel() }
      return try LayerCompExport.render(d, options: .init())
    }
    do { _ = try await worker.value; XCTFail("Cancelled comp export returned output") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }
  func testNativeExportPublishesCompleteNewFolderAndPreservesExistingDestination() throws {
    let output = try LayerCompExport.render(fixture(), options: .init())
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: parent) }
    let destination = parent.appendingPathComponent("owned-comps"), prepared = try PreparedSequenceFolder.prepare(.init(files: output.files), destination: destination)
    defer { prepared.discard() }; XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path)); try prepared.commit()
    for file in output.files { XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(file.name)), file.data) }
    let second = try PreparedSequenceFolder.prepare(.init(files: output.files), destination: destination); defer { second.discard() }
    XCTAssertThrowsError(try second.commit())
    for file in output.files { XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(file.name)), file.data) }
  }
  @MainActor func testAPIExportCancellationAndRevocationReturnNoArchiveOrHistoryChange() async throws {
    let helper = AutomationTests()
    for revoke in [false, true] {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        var source = try CraftDocument(width: 1600, height: 1200)
        for i in 0..<16 { try Command.layerComp(.capture(id: UUID(), name: "Comp \(i)", comment: "", options: .init())).apply(to: &source) }
        document.store.session = EditorSession(document: source); try service.share(document); service.setDocumentTransfersEnabled(true)
        let id = try XCTUnwrap(service.shares.first?.id), revision = service.revision(document.store)
        let operation = Task { try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "layerComps.export", "revision": revision, "parameters": ["format": "png"]]) }
        let deadline = Date().addingTimeInterval(10)
        while document.store.layerCompExportID == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let job = try XCTUnwrap(document.store.layerCompExportID)
        if revoke { service.revoke(id) }
        else {
          let cancelled = try await helper.edit(service, document, "layerComps.export.cancel", ["operationID": job.uuidString]); XCTAssertEqual(cancelled, 200)
        }
        let response = try await operation.value; XCTAssertNotEqual(response.0.statusCode, 200)
        XCTAssertEqual(document.store.document, source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
        XCTAssertNil(document.store.layerCompExportWorker); XCTAssertNil(document.store.layerCompExportID); XCTAssertFalse(document.store.geometryBusy)
      }
    }
  }
  @MainActor func testNativeAPIHistoryEquivalenceAndInvalidBusyStaleRequests() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let shareID = try XCTUnwrap(service.shares.first?.id), id = UUID(), original = document.store.document
      @MainActor func send(_ parameters: [String: Any], revision: String? = nil) async throws -> (HTTPURLResponse, Data) {
        try await helper.request(service, path: "/v1/documents/\(shareID)/commands", body: ["command": "layerComps.edit", "revision": revision ?? service.revision(document.store), "parameters": parameters])
      }
      let result = try await send(["operation": "capture", "id": id.uuidString, "name": "API layout", "comment": ""]); XCTAssertEqual(result.0.statusCode, 200, String(decoding: result.1, as: UTF8.self))
      let native = EditorStore(document: original); defer { native.renderTask?.cancel() }
      try native.editLayerComp(.capture(id: id, name: "API layout", comment: "", options: .init()))
      XCTAssertEqual(document.store.document, native.document)
      let saved = native.document
      let invalidCases: [(Int, [String: Any])] = [
        (400, ["operation": "bad"]), (400, ["operation": "apply", "id": "bad"]),
        (400, ["operation": "clear", "name": "irrelevant"]),
        (422, ["operation": "capture", "name": "   ", "visibility": false, "position": false, "appearance": false]),
        (422, ["operation": "capture", "name": "x", "id": id.uuidString])
      ]
      for (status, bad) in invalidCases {
        let invalid = try await send(bad); XCTAssertEqual(invalid.0.statusCode, status, String(decoding: invalid.1, as: UTF8.self)); XCTAssertEqual(document.store.document, saved)
      }
      let stale = try await send(["operation": "clear"], revision: "stale"); XCTAssertEqual(stale.0.statusCode, 409)
      document.store.geometryBusy = true; let busy = try await send(["operation": "clear"]); XCTAssertEqual(busy.0.statusCode, 409); document.store.geometryBusy = false
      let undo = try await helper.request(service, path: "/v1/documents/\(shareID)/commands", body: ["command": "history.undo", "revision": service.revision(document.store), "parameters": [:]])
      XCTAssertEqual(undo.0.statusCode, 200); XCTAssertEqual(document.store.document, original)
    }
  }
  @MainActor func testAPIExportsTransferPermissionsNative79AdmissionAndObservableState() async throws {
    let helper = AutomationTests(), source = try fixture()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: source); try service.share(document); let id = try XCTUnwrap(service.shares.first?.id)
      @MainActor func export(_ format: String) async throws -> (HTTPURLResponse, Data) {
        try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "layerComps.export", "revision": service.revision(document.store), "parameters": ["format": format]])
      }
      let denied = try await export("png"); XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let download = try await export("png"), expected = try LayerCompExport.render(source, options: .init())
      XCTAssertEqual(download.0.statusCode, 200); XCTAssertEqual(download.1, expected.data); XCTAssertEqual(document.store.document, source); XCTAssertNil(document.store.layerCompExportID)
      let pdf = try await export("pdf"); XCTAssertEqual(pdf.0.statusCode, 200); XCTAssertEqual(CGPDFDocument(CGDataProvider(data: pdf.1 as CFData)!)?.numberOfPages, 2)
      let old = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "78"]); XCTAssertEqual(old.0.statusCode, 422)
      let file = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "79"]); XCTAssertEqual(file.0.statusCode, 200, String(decoding: file.1.prefix(300), as: UTF8.self)); XCTAssertEqual(try NativeArchive.decode(file.1), source)
      let state = LayerCompsAPI.state(source); XCTAssertEqual((state["comps"] as? [[String: Any]])?.count, 2)
      XCTAssertNil(document.store.layerCompExportWorker); XCTAssertFalse(document.store.geometryBusy)
    }
  }
  @MainActor func testPhotoshopFactoryMenuBindingsDoNotInventShortcuts() throws {
    try PhotoshopMenuTests().withMenus { _, menu in
      let all = PhotoshopMenuTests().allItems(menu)
      for (title, selector) in [("Layer Comps", #selector(AppDelegate.showLayerComps)), ("Layer Comps to Files…", #selector(AppDelegate.exportLayerCompFiles)), ("Layer Comps to PDF…", #selector(AppDelegate.exportLayerCompPDF))] {
        let item = try XCTUnwrap(all.first { $0.title == title }); XCTAssertEqual(item.action, selector); XCTAssertTrue(item.keyEquivalent.isEmpty)
      }
    }
  }
}
