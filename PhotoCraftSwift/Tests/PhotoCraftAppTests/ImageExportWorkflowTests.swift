import AppKit
import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging
@testable import PhotoCraft

final class ImageExportWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 4,height: 3,name:"owned")
    d.layers[0].content = .raster(try Surface(width:4,height:3,fill:Pixel(1,0,0))); return d
  }
  @MainActor func testNativeWorkspaceCancelPreviewAndSharedAPIExportLeaveHistoryUntouched() async throws {
    let source = try fixture(), native = EditorStore(document:source); defer { native.cancelImageExport(); native.renderTask?.cancel() }
    native.beginImageExport(); let draft = try XCTUnwrap(native.imageExportDraft); draft.settings = .init(); draft.settings.scales = [.init(),.init(2,suffix:"@2x")]; draft.refresh(); await draft.previewTask?.value
    XCTAssertEqual(draft.previewFiles.count,2); XCTAssertNotNil(draft.preview); XCTAssertFalse(native.canExportImages)
    let settings = draft.settings, output = try await native.encodedImageAssets(settings,draft:draft)
    XCTAssertEqual(native.document,source); XCTAssertTrue(native.session.undoStack.isEmpty); native.cancelImageExport(); XCTAssertTrue(native.canExportImages)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      document.store.session = EditorSession(document:source); try service.share(document); let id = service.shares.first!.id
      let parameters:[String:Any] = ["settings":BrushAPI.json(settings)]
      let denied = try await helper.edit(service,document,"image.export",parameters); XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let response = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"image.export","revision":service.revision(document.store),"parameters":parameters])
      XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1.prefix(400),as:UTF8.self)); XCTAssertEqual(response.1,output.zip)
      let archive = try PcraftZIP(response.1), manifest = try JSONSerialization.jsonObject(with:archive.read("photato-export-manifest.json")) as! [String:Any]
      XCTAssertEqual((manifest["files"] as? [Any])?.count,2)
      for file in output.files { XCTAssertEqual(try archive.read(file.name),file.data) }
      XCTAssertEqual(document.store.document,source); XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertNil(document.store.imageExportID)
      let state = ImageExportAPI.state(document.store); XCTAssertEqual(state["workspaceOpen"] as? Bool,false)
    }
  }
  @MainActor func testInvalidStaleBusyAndPreferenceSchemasAreExplicit() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      try service.share(document); service.setDocumentTransfersEnabled(true); let source = document.store.document, id = service.shares.first!.id
      let invalids: [[String: Any]] = [["settings":["bogus":1]],["settings":["width":1.5]],["settings":["ids":["bad"]]],["settings":["format":"psd"]]]
      for parameters in invalids {
        let status = try await helper.edit(service,document,"image.export",parameters); XCTAssertEqual(status,400,"\(parameters)")
      }
      let invalid = try await helper.edit(service,document,"image.export",["settings":["target":"layers","ids":[UUID().uuidString]]]); XCTAssertEqual(invalid,422)
      let stale = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"image.export","revision":"stale","parameters":[:]]); XCTAssertEqual(stale.0.statusCode,409)
      document.store.beginFileInfo(); let busy = try await helper.edit(service,document,"image.export",[:]); XCTAssertEqual(busy,409); document.store.fileInfoDraft = nil
      let badPrefs = try await helper.edit(service,document,"export.preferences",["settings":["width":20]]); XCTAssertEqual(badPrefs,400)
      XCTAssertEqual(document.store.document,source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testCancellationAndRevocationPublishNoOutputUsingDeterministicWorkerGate() async throws {
    let helper = AutomationTests()
    for revoke in [false,true] {
      let gate = ImageExportGate()
      try await helper.withService(pressedMouseButtons:{0}) { service,document in
        let source = try fixture(); document.store.session = EditorSession(document:source); try service.share(document); service.setDocumentTransfersEnabled(true)
        document.store.imageExportPreparation = { source,settings in gate.wait(); try Task.checkCancellation(); return try ImageExportPreparation.render(source,settings:settings) }
        defer { gate.release() }
        let id = service.shares.first!.id, revision = service.revision(document.store)
        let operation = Task { try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"image.export","revision":revision,"parameters":[:]]) }
        for _ in 0..<1000 { if document.store.imageExportID != nil { break }; try await Task.sleep(for:.milliseconds(2)) }
        let active = try XCTUnwrap(document.store.imageExportID)
        if revoke { service.revoke(id) } else {
          let cancelled = try await helper.edit(service,document,"image.export.cancel",["operationID":active.uuidString]); XCTAssertEqual(cancelled,200)
        }
        gate.release(); let response = try await operation.value; XCTAssertNotEqual(response.0.statusCode,200)
        XCTAssertEqual(document.store.document,source); XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertFalse(document.store.geometryBusy); XCTAssertNil(document.store.imageExportID)
      }
    }
  }
  @MainActor func testQuickPreferencesPersistenceCancelAndAPIEquivalence() async throws {
    let suite = "test.photato.export.\(UUID())", defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
    var settings = ImageExportSettings(); settings.format = .jpeg; settings.quality = 65; settings.width = 20
    try ImageExportPreferences.save(settings,defaults:defaults); let loaded = ImageExportPreferences.load(defaults); XCTAssertEqual(loaded.format,.jpeg); XCTAssertEqual(loaded.quality,65); XCTAssertNil(loaded.width)
    try ImageExportPreferences.saveLast(settings,defaults:defaults); XCTAssertNil(ImageExportPreferences.loadLast(defaults).width)
    let old = UserDefaults.standard.data(forKey:ImageExportPreferences.key); defer { if let old { UserDefaults.standard.set(old,forKey:ImageExportPreferences.key) } else { UserDefaults.standard.removeObject(forKey:ImageExportPreferences.key) } }
    let native = EditorStore(document:try fixture()); defer { native.cancelImageExport(); native.renderTask?.cancel() }
    native.beginImageExport(preferences:true); let draft = try XCTUnwrap(native.imageExportDraft); draft.settings = loaded; native.cancelImageExport(); XCTAssertEqual(UserDefaults.standard.data(forKey:ImageExportPreferences.key),old)
    native.beginImageExport(preferences:true); let saved = try XCTUnwrap(native.imageExportDraft); saved.settings = loaded; native.finishNativeImageExport(saved); let nativeValue = ImageExportPreferences.load()
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      try service.share(document)
      let denied = try await helper.edit(service,document,"export.preferences",["settings":["format":"jpeg","quality":65]]); XCTAssertEqual(denied,403)
      service.setPreferenceChangesEnabled(true)
      let status = try await helper.edit(service,document,"export.preferences",["settings":["format":"jpeg","quality":65]])
      XCTAssertEqual(status,200); XCTAssertEqual(ImageExportPreferences.load(),nativeValue); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertNotNil(ImageExportAPI.state(document.store)["preferences"])
    }
  }
  func testPublicationPreservesExistingFilesAndValidatesAllDestinationsBeforeWriting() throws {
    let output = try ImageExportPreparation.render(fixture(),settings:.init())
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:folder) }
    try ImageExportPublication.write(output.files,to:folder,directory:true)
    let path = folder.appendingPathComponent(output.files[0].name), existing = try Data(contentsOf:path)
    XCTAssertThrowsError(try ImageExportPublication.write(output.files,to:folder,directory:true)); XCTAssertEqual(try Data(contentsOf:path),existing)
    let destination = folder.appendingPathComponent("selected.png"); try Data("old".utf8).write(to:destination)
    try ImageExportPublication.write(output.files,to:destination,directory:false); XCTAssertEqual(try Data(contentsOf:destination),existing)
  }
  @MainActor func testFactoryExportMenusBindBothDocumentAndLayerShortcuts() throws {
    let helper = PhotoshopMenuTests()
    try helper.withMenus { _, menu in
      let items = helper.allItems(menu)
      for selector in [#selector(AppDelegate.export),#selector(AppDelegate.exportLayerAssets),#selector(AppDelegate.quickExportAssets),#selector(AppDelegate.quickExportLayerAssets),#selector(AppDelegate.exportPreferences)] { XCTAssertTrue(items.contains { $0.action == selector }) }
      let layer = try XCTUnwrap(items.first { $0.action == #selector(AppDelegate.exportLayerAssets) && !$0.isAlternate }); XCTAssertEqual(layer.keyEquivalent,"'"); XCTAssertTrue(layer.keyEquivalentModifierMask.contains([.command,.option,.shift]))
    }
  }
}
private final class ImageExportGate: @unchecked Sendable {
  let condition = NSCondition(); var released = false
  func wait() { condition.lock(); defer { condition.unlock() }; while !released { condition.wait() } }
  func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
