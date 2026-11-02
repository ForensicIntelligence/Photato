import AppKit
import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging
@testable import PhotoCraft

final class LayerFileWorkflowTests: XCTestCase {
  @MainActor func testNativeRunAndAPIArchiveMatchFilesWithoutChangingSourceOrHistory() async throws {
    let helper = AutomationTests(), fixture = LayerFileExportTests(), source = try fixture.fixture(), native = EditorStore(document:source), directory = try fixture.folder()
    defer { native.cancelLayerFiles(); native.renderTask?.cancel(); try? FileManager.default.removeItem(at:directory) }
    native.beginLayerFiles(); let draft = try XCTUnwrap(native.layerFileDraft); draft.destination=directory; draft.settings.format = .png24; draft.settings.prefix="owned"; draft.settings.includeICC=false
    let options = draft.settings
    native.runLayerFiles(draft)
    let deadline = Date().addingTimeInterval(10)
    while native.layerFileDraft != nil && Date() < deadline { try await Task.sleep(for:.milliseconds(3)) }
    XCTAssertNil(native.layerFileDraft,draft.error ?? "Native export did not finish"); XCTAssertEqual(native.document,source); XCTAssertTrue(native.session.undoStack.isEmpty); XCTAssertFalse(native.geometryBusy)
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      document.store.session = EditorSession(document:source); try service.share(document); let id = service.shares.first!.id
      let denied = try await helper.edit(service,document,"layers.export",["settings":BrushAPI.json(options)]); XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let response = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"layers.export","revision":service.revision(document.store),"parameters":["settings":BrushAPI.json(options)]])
      XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1.prefix(400),as:UTF8.self))
      let zip = try PcraftZIP(response.1), manifest = try JSONSerialization.jsonObject(with:zip.read("photato-layer-files.json")) as! [String:Any]
      let records = try XCTUnwrap(manifest["files"] as? [[String:Any]]); XCTAssertEqual(records.count,4)
      for record in records { let name = record["file"] as! String; XCTAssertEqual(try zip.read(name),try Data(contentsOf:directory.appendingPathComponent(name))) }
      XCTAssertEqual(document.store.document,source); XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertEqual(document.store.layerFilesProgress.completed,4); XCTAssertNil(document.store.layerFilesID)
    }
  }
  @MainActor func testSettingsInvalidStaleBusyAndCodecOptionsAreValidated() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      try service.share(document); service.setDocumentTransfersEnabled(true); let id=service.shares.first!.id, source=document.store.document
      let invalid:[[String:Any]] = [["format":"bad"],["jpegQuality":13],["ids":["bad"]],["paletteColors":1],["unknown":true]]
      for fields in invalid { let status = try await helper.edit(service,document,"layers.export",["settings":fields]); XCTAssertEqual(status,400,"\(fields)") }
      let invalidID = try await helper.edit(service,document,"layers.export",["settings":["ids":[UUID().uuidString]]]); XCTAssertEqual(invalidID,422)
      let profile = try await helper.edit(service,document,"layers.export",["settings":["format":"bmp","includeICC":true]]); XCTAssertEqual(profile,422)
      let stale = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"layers.export","revision":"stale","parameters":[:]]); XCTAssertEqual(stale.0.statusCode,409)
      document.store.beginLayerFiles(); let busy = try await helper.edit(service,document,"layers.export",[:]); XCTAssertEqual(busy,409); document.store.cancelLayerFiles()
      let cancel = try await helper.edit(service,document,"layers.export.cancel",["operationID":UUID().uuidString]); XCTAssertEqual(cancel,409)
      XCTAssertEqual(document.store.document,source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let implicitCommand = try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"layers.export","revision":service.revision(document.store),"parameters":["settings":["format":"tga"]]]))
      XCTAssertFalse(try implicitCommand.layerFileSettings().includeICC)
    }
  }
  @MainActor func testCancellationAndRevocationDiscardPrivateStagingAndReturnNoZIP() async throws {
    let helper = AutomationTests()
    for revoke in [false,true] {
      let gate = LayerFileGate()
      try await helper.withService(pressedMouseButtons:{0}) { service,document in
        let source = try LayerFileExportTests().fixture(); document.store.session=EditorSession(document:source); try service.share(document); service.setDocumentTransfersEnabled(true)
        document.store.layerFilePreparation = { source,settings,directory,progress in gate.wait(directory); try Task.checkCancellation(); return try LayerFileExport.prepare(source,options:settings,directory:directory,progress:progress) }
        defer { gate.release() }
        let id=service.shares.first!.id, revision=service.revision(document.store)
        let operation = Task { try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"layers.export","revision":revision,"parameters":[:]]) }
        for _ in 0..<1000 { if document.store.layerFilesID != nil { break }; try await Task.sleep(for:.milliseconds(2)) }
        let current = try XCTUnwrap(document.store.layerFilesID)
        if revoke { service.revoke(id) } else { let result=try await helper.edit(service,document,"layers.export.cancel",["operationID":current.uuidString]); XCTAssertEqual(result,200) }
        gate.release(); let response=try await operation.value; XCTAssertNotEqual(response.0.statusCode,200)
        if let directory=gate.directory() { XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path)) }
        XCTAssertEqual(document.store.document,source); XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertNil(document.store.layerFilesID); XCTAssertFalse(document.store.geometryBusy)
      }
    }
  }
  @MainActor func testChangedNativeSourceRejectsBeforePublicationAndPreservesNewDocument() async throws {
    let fixture=LayerFileExportTests(), source=try fixture.fixture(), directory=try fixture.folder(), store=EditorStore(document:source), gate=LayerFileGate()
    defer { gate.release(); store.cancelLayerFiles(); store.renderTask?.cancel(); try? FileManager.default.removeItem(at:directory) }
    store.layerFilePreparation = { source,settings,directory,progress in gate.wait(directory); return try LayerFileExport.prepare(source,options:settings,directory:directory,progress:progress) }
    var options=LayerFileExportSettings(); options.format = .png24
    let operation=Task { try await store.exportedLayerFiles(options,directory:directory,publish:true) }
    for _ in 0..<1000 { if store.layerFilesID != nil { break }; try await Task.sleep(for:.milliseconds(2)) }
    XCTAssertNotNil(store.layerFilesID)
    var changed=source; changed.name="Externally replaced"; store.session=EditorSession(document:changed); gate.release()
    do { _=try await operation.value; XCTFail("Stale native export published files") } catch {}
    XCTAssertEqual(store.document,changed); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty); XCTAssertFalse(store.geometryBusy)
  }
  @MainActor func testNativeCancelAndFactoryMenuPreserveHistoryAndShortcuts() throws {
    let source=try LayerFileExportTests().fixture(), store=EditorStore(document:source); defer { store.cancelLayerFiles(); store.renderTask?.cancel() }
    XCTAssertTrue(store.canExportLayerFiles); store.beginLayerFiles(); XCTAssertNotNil(store.layerFileDraft); XCTAssertFalse(store.canExportLayerFiles); store.layerFileDraft?.settings.trim=true; store.cancelLayerFiles()
    XCTAssertEqual(store.document,source); XCTAssertTrue(store.session.undoStack.isEmpty); XCTAssertTrue(store.canExportLayerFiles)
    let menus=PhotoshopMenuTests(); try menus.withMenus { _,menu in let item=try XCTUnwrap(menus.allItems(menu).first { $0.action == #selector(AppDelegate.exportLayersToFiles) }); XCTAssertEqual(item.title,"Layers to Files…"); XCTAssertEqual(item.keyEquivalent,"") }
    XCTAssertTrue(AutomationCommand.definitions.contains { $0.name == "layers.export" }); XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
  }
}
private final class LayerFileGate: @unchecked Sendable {
  private let condition=NSCondition(); private var released=false; private var target:URL?
  func wait(_ directory:URL) { condition.lock(); defer { condition.unlock() }; target=directory; while !released { condition.wait() } }
  func directory()->URL? { condition.lock(); defer { condition.unlock() }; return target }
  func release() { condition.lock(); released=true; condition.broadcast(); condition.unlock() }
}
