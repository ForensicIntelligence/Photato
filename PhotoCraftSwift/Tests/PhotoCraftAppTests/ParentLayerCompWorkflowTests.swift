import AppKit
import CoreGraphics
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor ParentCompGate {
  var entered = false
  func mark() { entered = true }
}
final class ParentLayerCompWorkflowTests: XCTestCase {
  func fixture() throws -> (parent: CraftDocument, source: CraftDocument, red: UUID, blue: UUID) {
    let f = try SmartObjectLayerCompWorkflowTests().fixture(); var d = f.parent
    let layer = d.layers[0].id, red = UUID(), blue = UUID()
    try SmartObjectLayerCompIO.selection(in: d, layerID: layer, compID: f.source.layerComps!.comps[0].id).apply(to: &d)
    try Command.layerComp(.capture(id: red, name: "Red", comment: "", options: .init(smartObjects: true))).apply(to: &d)
    try SmartObjectLayerCompIO.selection(in: d, layerID: layer, compID: f.source.layerComps!.comps[1].id).apply(to: &d)
    try Command.layerComp(.capture(id: blue, name: "Blue", comment: "", options: .init(smartObjects: true))).apply(to: &d)
    try SmartObjectLayerCompIO.selection(in: d, layerID: layer, compID: nil).apply(to: &d)
    return (d, f.source, red, blue)
  }
  @MainActor func testNativeAndHTTPParentApplyRestoreAndHistoryAreIdentical() async throws {
    let f = try fixture(), helper = AutomationTests(), native = EditorStore(document: f.parent)
    defer { native.renderTask?.cancel() }
    try native.editLayerComp(.apply(f.red)); await native.geometryTask?.value; XCTAssertNil(native.error)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: f.parent); try service.share(document)
      let apply = try await helper.edit(service, document, "layerComps.edit", ["operation": "apply", "id": f.red.uuidString]); XCTAssertEqual(apply, 200)
      XCTAssertEqual(document.store.document, native.document); XCTAssertEqual(document.store.session.undoStack.count, 1)
      let state = LayerCompsAPI.state(document.store.document), comps = state["comps"] as! [[String: Any]]
      XCTAssertEqual(comps[0]["smartObjects"] as? Bool, true); XCTAssertEqual(comps[0]["unavailableSmartObjectLayerIDs"] as? [String], [])
      let applied = native.document
      let undo = try await helper.edit(service, document, "history.undo", [:]); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, f.parent)
      let redo = try await helper.edit(service, document, "history.redo", [:]); XCTAssertEqual(redo, 200); XCTAssertEqual(document.store.document, applied)
      try native.editLayerComp(.restoreLast); await native.geometryTask?.value
      let restore = try await helper.edit(service, document, "layerComps.edit", ["operation": "restoreLast"]); XCTAssertEqual(restore, 200)
      XCTAssertEqual(document.store.document, native.document); XCTAssertEqual(document.store.document.layers, f.parent.layers)
    }
  }
  @MainActor func testSmartOnlyAPIFlagSchemaInvalidBusyStaleAndNative81Negotiation() async throws {
    let f = try fixture(), helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: f.parent); try service.share(document); let id = service.shares.first!.id
      let compID = UUID(), parameters: [String: Any] = ["operation": "capture", "id": compID.uuidString, "name": "Smart only", "visibility": false, "position": false, "appearance": false, "smartObjects": true]
      let capture = try await helper.edit(service, document, "layerComps.edit", parameters); XCTAssertEqual(capture, 200)
      XCTAssertEqual(document.store.document.layerComps?.comps.last?.options, .init(visibility: false, position: false, appearance: false, smartObjects: true))
      let saved = document.store.document
      var bad = parameters; bad["id"] = UUID().uuidString; bad["smartObjects"] = "yes"
      let invalid = try await helper.edit(service, document, "layerComps.edit", bad); XCTAssertEqual(invalid, 400); XCTAssertEqual(document.store.document, saved)
      let stale = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "layerComps.edit", "revision": "stale", "parameters": ["operation": "apply", "id": f.red.uuidString]]); XCTAssertEqual(stale.0.statusCode, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "layerComps.edit", ["operation": "apply", "id": f.red.uuidString]); XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      let definition = AutomationCommand.definitions.first { $0.name == "layerComps.edit" }!
      let props = definition.schema["properties"] as! [String: Any], parameterSchema = props["parameters"] as! [String: Any], fields = parameterSchema["properties"] as! [String: Any]
      XCTAssertEqual((fields["smartObjects"] as? [String: Any])?["type"] as? String, "boolean")
      service.setDocumentTransfersEnabled(true)
      let old = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "80"]); XCTAssertEqual(old.0.statusCode, 422)
      let file = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "81"]); XCTAssertEqual(file.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(file.1), saved)
    }
  }
  func testRasterNativeAndPDFExportsRenderChildChoicesFromIndependentSourceSnapshots() throws {
    let f = try fixture(), before = f.parent
    for format in ["png", "photato"] {
      let output = try LayerCompExport.render(f.parent, options: .init(format: format)); XCTAssertEqual(output.files.count, 3)
      for (i, file) in output.files.dropLast().enumerated() {
        let d = try format == "photato" ? NativeArchive.decode(file.data) : RasterIO.read(file.data)
        let pixel = try Renderer.composite(d).pixel(x: 3, y: 2)
        XCTAssertEqual(pixel.r, i == 0 ? 1 : 0); XCTAssertEqual(pixel.b, i == 0 ? 0 : 1)
        if format == "photato" { XCTAssertEqual(d.minimumArchiveVersion, 81); XCTAssertEqual(d.layerComps?.comps, f.parent.layerComps?.comps) }
      }
    }
    let output = try LayerCompExport.render(f.parent, options: .init(format: "pdf"))
    let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: output.data as CFData)!)); XCTAssertEqual(pdf.numberOfPages, 2)
    for i in 0..<2 {
      let page = try XCTUnwrap(pdf.page(at: i + 1)); var rgba = [UInt8](repeating: 0, count: 8 * 6 * 4)
      rgba.withUnsafeMutableBytes { b in
        let c = CGContext(data: b.baseAddress, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.drawPDFPage(page)
      }
      let index = (2 * 8 + 3) * 4
      XCTAssertEqual(rgba[index], i == 0 ? 255 : 0); XCTAssertEqual(rgba[index + 2], i == 0 ? 0 : 255)
    }
    XCTAssertEqual(f.parent, before)
  }
  @MainActor func testReopenedLinkedParentApplyAndExportRequireSessionApprovedFiles() async throws {
    let f = try fixture(), helper = AutomationTests(), bytes = try NativeArchive.encode(f.source)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("Owned.photato"); try bytes.write(to: url)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let registry = LinkedSourceRegistry(persistent: false), grant = try registry.authorize(url), file = try LinkedArtworkRead.read(grant)
      var linked = f.parent; linked.layers[0].smartObject?.data = bytes; linked.layers[0] = try LinkedSmartObjectIO.linked(linked.layers[0], reference: file.reference)
      let d = try NativeArchive.decode(NativeArchive.encode(linked)); document.store.session = EditorSession(document: d); document.store.linkedSourceRegistry = registry
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let parameters: [String: Any] = ["operation": "apply", "id": f.red.uuidString]
      let denied = try await helper.edit(service, document, "layerComps.edit", parameters); XCTAssertEqual(denied, 403)
      let deniedExport = try await helper.edit(service, document, "layerComps.export", ["format": "png"]); XCTAssertEqual(deniedExport, 403)
      _ = try service.authorizeLinkedArtwork(url, registry: registry)
      let allowed = try await helper.edit(service, document, "layerComps.edit", parameters); XCTAssertEqual(allowed, 200)
      document.store.session = EditorSession(document: d)
      let exported = try await helper.edit(service, document, "layerComps.export", ["format": "png"]); XCTAssertEqual(exported, 200); XCTAssertEqual(document.store.document, d)
      try Data([1, 2, 3]).write(to: url)
      let changed = try await helper.edit(service, document, "layerComps.edit", parameters); XCTAssertEqual(changed, 422); XCTAssertEqual(document.store.document, d)
    }
  }
  @MainActor func testConfirmedLiveParentPreparationCancelsForTaskShareAndFileRevocation() async throws {
    let f = try fixture(), helper = AutomationTests(), bytes = try NativeArchive.encode(f.source)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("Owned.photato"); try bytes.write(to: url)
    for mode in 0..<3 {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        let registry = LinkedSourceRegistry(persistent: false)
        let grant = try registry.authorize(url), file = try LinkedArtworkRead.read(grant)
        _ = try service.authorizeLinkedArtwork(url, registry: registry)
        var linked = f.parent; linked.layers[0].smartObject?.data = bytes; linked.layers[0] = try LinkedSmartObjectIO.linked(linked.layers[0], reference: file.reference)
        let d = try NativeArchive.decode(NativeArchive.encode(linked)); document.store.session = EditorSession(document: d); document.store.linkedSourceRegistry = registry
        try service.share(document); let id = service.shares.first!.id, gate = ParentCompGate()
        service.parentLayerCompPreparation = { operation, original, data in
          await gate.mark(); try await Task.sleep(for: .seconds(30)); return try LayerCompIO.command(operation, in: original, sourceData: data)
        }
        let request = Task { try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "layerComps.edit", "revision": service.revision(document.store), "parameters": ["operation": "apply", "id": f.red.uuidString]]) }
        let deadline = Date().addingTimeInterval(3)
        while !(await gate.entered), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let entered = await gate.entered; XCTAssertTrue(entered)
        if mode == 0 { document.store.geometryTask?.cancel() } else if mode == 1 { service.revoke(id) } else { service.clearLinkedArtwork() }
        let response = try await request.value; XCTAssertEqual(response.0.statusCode, 409); XCTAssertEqual(document.store.document, d)
        XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertFalse(document.store.geometryBusy)
      }
    }
  }
}
