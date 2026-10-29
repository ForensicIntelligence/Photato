import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VariableWorkflowTests: XCTestCase {
  func parse(_ name: String, _ parameters: [String: Any]) throws -> AutomationCommand {
    try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": name, "revision": "test", "parameters": parameters]))
  }
  func rawDefinitions(_ definitions: [VariableDefinition]) -> [[String: Any]] {
    definitions.map { ["id": $0.id.uuidString, "name": $0.name, "layerID": $0.layerID.uuidString, "kind": $0.kind.rawValue] }
  }
  func rawRows(_ rows: [VariableDataSet]) -> [[String: Any]] { rows.map { ["id": $0.id.uuidString, "name": $0.name, "values": VariablesAPI.values($0.values)] } }
  func largeTemplate() throws -> CraftDocument {
    var model = try CraftDocument(width: 512, height: 512)
    try Command.variables(.define([.init(name: "show", layerID: model.layers[0].id, kind: .visibility)])).apply(to: &model)
    try Command.variables(.dataSets((0..<100).map { .init(name: "Row \($0)", values: ["show": .visibility($0 % 2 == 0)]) }, append: false)).apply(to: &model)
    return model
  }
  func testMalformedNestedUUIDsAndStrictShapesRejectWithoutCrashing() throws {
    let model = try VariableDataExportTests().template()
    for key in ["id", "layerID"] {
      var definitions = rawDefinitions(model.variables!.definitions); definitions[0][key] = "broken"
      XCTAssertThrowsError(try parse("variables.define", ["definitions": definitions]).variableCommand(in: model))
    }
    var rows = rawRows(model.variables!.dataSets); rows[0]["id"] = "broken"
    XCTAssertThrowsError(try parse("variables.dataSets", ["dataSets": rows]).variableCommand(in: model))
    let badValue: [String: Any] = ["variable": "photo", "kind": "pixelReplacement", "imageID": "broken"]
    XCTAssertThrowsError(try parse("variables.dataSets", ["dataSets": [["name": "Bad", "values": [badValue]]]]).variableCommand(in: model))
    for bad in [["variable": "show", "kind": "visibility", "visible": "true"], ["variable": "show", "kind": "visibility", "visible": true, "text": "extra"]] as [[String: Any]] {
      XCTAssertThrowsError(try parse("variables.dataSets", ["dataSets": [["name": "Bad", "values": [bad]]]]))
    }
    XCTAssertThrowsError(try parse("variables.import", ["text": "show,photo\ntrue,x", "imageReferences": [["reference": "x", "imageID": "bad"]]]).variableCommand(in: model))
    XCTAssertThrowsError(try parse("variables.export", ["format": "gif"]))
    XCTAssertThrowsError(try parse("variables.define", ["definitions": [], "extra": true]))
    var definitions = rawDefinitions(model.variables!.definitions); definitions[1]["pixelOptions"] = ["method": "fill"]
    XCTAssertThrowsError(try parse("variables.define", ["definitions": definitions]).variableCommand(in: model))
  }
  @MainActor func testDesktopDraftConfigurePreviewCancelAndHistoryMatchAPI() async throws {
    let source = try VariableDataExportTests().template(), model = VariableEditorModel(source, dataSets: true)
    model.rowID = source.variables!.dataSets[0].id; model.setRowName("Changed draft")
    model.setValue(.visibility(false), for: "show")
    XCTAssertEqual(model.source, source)
    let native = try model.command(apply: true)
    let api = try parse("variables.configure", ["definitions": rawDefinitions(model.settings.definitions), "dataSets": rawRows(model.settings.dataSets), "dataSetID": model.rowID!.uuidString]).variableCommand(in: source)
    var a = source, b = source; try native.apply(to: &a); try api.apply(to: &b); XCTAssertEqual(a, b)
    model.refreshPreview()
    for _ in 0..<100 where model.preview == nil && model.error == nil { try await Task.sleep(for: .milliseconds(5)) }
    XCTAssertNotNil(model.preview); XCTAssertNil(model.error); XCTAssertEqual(model.source, source)
    model.cancel(); XCTAssertEqual(model.source, source)
    let store = EditorStore(document: source); defer { store.renderTask?.cancel() }
    store.performGeometry(native); await store.geometryTask?.value
    XCTAssertEqual(store.document, a); XCTAssertEqual(store.session.undoStack.count, 1)
    try store.session.undo(); XCTAssertEqual(store.document, source)
    try store.session.redo(); XCTAssertEqual(store.document, a)
    model.layerID = source.layers[0].id; model.rename(.visibility, "visible")
    XCTAssertEqual(model.selectedRow?.values["visible"], .visibility(false)); XCTAssertNil(model.selectedRow?.values["show"])
    model.addRow(duplicate: true); XCTAssertEqual(model.settings.dataSets.count, 4); model.deleteRow(); XCTAssertEqual(model.settings.dataSets.count, 3)
    model.setEnabled(.pixelReplacement, false); XCTAssertFalse(model.settings.variableNames.contains("photo"))
  }
  @MainActor func testOffscreenSheetLayoutAndMenuBindings() async throws {
    _ = NSApplication.shared
    let model = VariableEditorModel(try VariableDataExportTests().template(), dataSets: true)
    defer { model.cancel() }
    model.refreshPreview()
    for _ in 0..<100 where model.preview == nil && model.error == nil { try await Task.sleep(for: .milliseconds(5)) }
    XCTAssertNotNil(model.preview)
    let host = NSHostingView(rootView: VariablesSheet(model: model, window: { nil }).background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 465), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = host
    defer { window.close() }
    host.frame = NSRect(x: 0, y: 0, width: 780, height: 465); host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
    XCTAssertEqual(host.fittingSize.width, 780, accuracy: 2); XCTAssertEqual(host.fittingSize.height, 465, accuracy: 2)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_VARIABLES_OUTPUT_DIR"], let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("variables-sheet.png")) }
    let delegate = AppDelegate(); delegate.installPhotoshopMenus()
    func item(_ names: [String], in menu: NSMenu?) -> NSMenuItem? {
      guard let first = names.first, let found = menu?.items.first(where: { $0.title == first }) else { return nil }
      return names.count == 1 ? found : item(Array(names.dropFirst()), in: found.submenu)
    }
    let paths = ["Image > Variables > Define…", "Image > Variables > Data Sets…", "Image > Apply Data Set…", "File > Import > Variable Data Sets…", "File > Export > Data Sets as Files…"]
    for path in paths { XCTAssertNotNil(item(path.components(separatedBy: " > "), in: NSApp.mainMenu)?.action, path) }
  }
  @MainActor func testHTTPCommandsSchemaImportApplyUndoAndAtomicFailure() async throws {
    let helper = AutomationTests(), original = try VariableDataExportTests().template()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: original); try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let rename = try await helper.edit(service, document, "variables.rename", ["oldName": "show", "newName": "visible"]); XCTAssertEqual(rename, 200)
      let image = try CraftDocument(width: 8, height: 8), bytes = try DocumentIO.encode(image, format: .png)
      XCTAssertGreaterThan(bytes.base64EncodedString().count, 256)
      let uploadID = UUID(), upload = try await helper.edit(service, document, "variables.image", ["name": "Uploaded", "imageID": uploadID.uuidString, "data": bytes.base64EncodedString()]); XCTAssertEqual(upload, 200)
      let csv = "DataSet,photo,visible\n\"Line one\nLine two\",uploaded,true\nHidden,uploaded,false"
      let imported = try await helper.edit(service, document, "variables.import", ["text": csv, "firstColumnNames": true, "imageReferences": [["reference": "uploaded", "imageID": uploadID.uuidString]]]); XCTAssertEqual(imported, 200)
      let configured = document.store.document, rowID = configured.variables!.dataSets[1].id
      var expected = configured; try Command.variables(.apply(rowID)).apply(to: &expected)
      let beforeHistory = document.store.session.undoStack.count
      let applied = try await helper.edit(service, document, "variables.apply", ["dataSetID": rowID.uuidString]); XCTAssertEqual(applied, 200); XCTAssertEqual(document.store.document, expected)
      XCTAssertEqual(document.store.session.undoStack.count, beforeHistory + 1)
      let state = VariablesAPI.state(document.store.document)
      let json = try JSONSerialization.data(withJSONObject: state), value = try JSONDecoder().decode(AutomationValue.self, from: json)
      _ = try BrushAPI.merge(value, schema: VariablesAPI.stateSchema)
      XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("allocatedBytes"))
      let response = try await helper.request(service, path: "/v1/documents/\(id)")
      XCTAssertEqual(response.0.statusCode, 200)
      let stateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any]); XCTAssertNotNil(stateJSON["variables"])
      let stale = try await helper.edit(service, document, "variables.clear", [:], revision: "old"); XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "variables.clear", [:]); XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      let removeUsed = try await helper.edit(service, document, "variables.image.remove", ["imageID": uploadID.uuidString]); XCTAssertNotEqual(removeUsed, 200); XCTAssertEqual(document.store.document, expected)
      let invalid = try await helper.edit(service, document, "variables.dataSets", ["dataSets": [["name": "Unknown", "values": [["variable": "unknown", "kind": "visibility", "visible": true]]]]]); XCTAssertNotEqual(invalid, 200); XCTAssertEqual(document.store.document, expected)
      try document.store.session.undo(); XCTAssertEqual(document.store.document, configured)
      let cleared = try await helper.edit(service, document, "variables.clear", [:]); XCTAssertEqual(cleared, 200); XCTAssertNil(document.store.document.variables)
    }
  }
  @MainActor func testHTTPDraftPreviewDoesNotCommitAndMatchesNativePNG() async throws {
    let helper = AutomationTests(), model = try VariableDataExportTests().template()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: model); try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id), revision = service.revision(document.store)
      var rows = model.variables!.dataSets; rows[0].values["show"] = .visibility(false)
      let parameters: [String: Any] = ["definitions": rawDefinitions(model.variables!.definitions), "dataSets": rawRows(rows), "dataSetID": rows[0].id.uuidString]
      let response = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "variables.preview", "revision": revision, "parameters": parameters])
      XCTAssertEqual(response.0.statusCode, 200); XCTAssertEqual(response.0.value(forHTTPHeaderField: "Content-Type"), "image/png")
      var candidate = model; try parse("variables.configure", parameters).variableCommand(in: model).apply(to: &candidate)
      XCTAssertEqual(response.1, try AutomationService.png(candidate))
      XCTAssertEqual(document.store.document, model); XCTAssertEqual(service.revision(document.store), revision); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      service.previewBusy = true; let busy = try await helper.edit(service, document, "variables.preview", parameters); XCTAssertEqual(busy, 429); service.previewBusy = false
      let stale = try await helper.edit(service, document, "variables.preview", parameters, revision: "old"); XCTAssertEqual(stale, 409)
    }
  }
  @MainActor func testHTTPExportMatchesNativeAndPreservesTemplate() async throws {
    let helper = AutomationTests(), model = try VariableDataExportTests().template()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: model); try service.share(document)
      let denied = try await helper.edit(service, document, "variables.export", ["format": "png"]); XCTAssertEqual(denied, 403)
      service.setDocumentTransfersEnabled(true)
      let id = try XCTUnwrap(service.shares.first?.id), revision = service.revision(document.store)
      let response = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "variables.export", "revision": revision, "parameters": ["format": "png"]])
      XCTAssertEqual(response.0.statusCode, 200, String(decoding: response.1.prefix(120), as: UTF8.self))
      XCTAssertEqual(response.1, try VariableDataExport.render(model, options: .init(format: .png)).zip())
      XCTAssertEqual(document.store.document, model); XCTAssertEqual(service.revision(document.store), revision); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertNil(document.store.variableExportID); XCTAssertFalse(document.store.geometryBusy)
    }
  }
  @MainActor func testActiveCancellationAndTransferRevocationStopWorkers() async throws {
    let helper = AutomationTests(), model = try largeTemplate()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: model); try service.share(document); service.setDocumentTransfersEnabled(true)
      for revoke in [false, true] {
        let job = Task { try await helper.edit(service, document, "variables.export", ["format": "png"]) }
        for _ in 0..<200 where document.store.variableExportID == nil { try await Task.sleep(for: .milliseconds(5)) }
        let operation = try XCTUnwrap(document.store.variableExportID), worker = try XCTUnwrap(document.store.variableExportWorker)
        if revoke { service.setDocumentTransfersEnabled(false); XCTAssertTrue(worker.isCancelled) }
        else { let cancel = try await helper.edit(service, document, "variables.export.cancel", ["operationID": operation.uuidString]); XCTAssertEqual(cancel, 200) }
        let result = try await job.value; XCTAssertEqual(result, 409)
        XCTAssertNil(document.store.variableExportID); XCTAssertFalse(document.store.geometryBusy); XCTAssertTrue(service.variableExportShares.isEmpty)
        XCTAssertEqual(document.store.document, model); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      }
    }
  }
}
