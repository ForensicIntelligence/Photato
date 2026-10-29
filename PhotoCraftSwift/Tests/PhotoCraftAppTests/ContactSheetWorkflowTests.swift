import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ContactSheetWorkflowTests: XCTestCase {
  func settings() -> ContactSheetSettings {
    var s = ContactSheetSettings();s.units = .pixels;s.width = 24;s.height = 16;s.resolution = 72;s.columns = 1;s.rows = 1;s.autoSpacing = false;s.horizontal = 0;s.vertical = 0;s.caption = false;s.flatten = false;return s
  }
  @MainActor func setup(_ service: AutomationService,_ first: CraftNSDocument) throws -> [CraftNSDocument] {
    first.store.session = EditorSession(document:try DocumentCreation.blank(width:2,height:2,background:Pixel(1,0,0),name:"Red.png"))
    try service.share(first)
    let second = CraftNSDocument(model:try DocumentCreation.blank(width:2,height:2,background:Pixel(0,0,1),name:"Blue.png"));service.controller.addDocument(second);try service.share(second)
    return [first,second]
  }
  @MainActor func cleanup(_ service: AutomationService,_ first: CraftNSDocument) {service.controller.cancelContactSheet();HDRMergeWorkflowTests().cleanup(service.controller,except:first)}
  @MainActor func params(_ service: AutomationService,_ s: ContactSheetSettings) throws -> [String:Any] {
    ["sources":service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]},"settings":try JSONSerialization.jsonObject(with:JSONEncoder().encode(s))]
  }
  func testStrictSchemaSettingsAndUUIDs() throws {
    func parse(_ params: [String:Any]) throws -> AutomationCommand.ContactSheetOptions {
      try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"document.contactSheet","revision":"test","parameters":params])).contactSheetOptions()
    }
    let sources = [["id":UUID().uuidString,"revision":"test"]]
    let parsed = try parse(["sources":sources,"settings":["units":"pixels","width":64,"height":64,"columns":1,"rows":1,"caption":false]])
    XCTAssertEqual(try parsed.settings.layout().width,64)
    XCTAssertThrowsError(try parse(["sources":[["id":"invalid","revision":"test"]]]))
    let badSettings: [[String:Any]] = [["unknown":true],["columns":1.5],["flatten":"false"],["depth":"bogus"],["profile":"invalid"]]
    for bad in badSettings {XCTAssertThrowsError(try parse(["sources":sources,"settings":bad]))}
    XCTAssertThrowsError(try parse(["sources":sources+sources]))
  }
  @MainActor func testNativePreviewStaleCommitCancelAndMenu() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      let docs = try setup(service,first);defer {cleanup(service,first)}
      let originals = docs.map{$0.store.document};service.controller.beginContactSheet(display:false)
      let model = try XCTUnwrap(service.controller.contactSheetWorkspace);model.settings = settings();model.addOpenDocuments();model.refresh();await model.task?.value
      XCTAssertTrue(model.ready,model.error ?? "not ready");XCTAssertEqual(model.result?.documents.count,2)
      service.controller.beginImageStack(display:false);XCTAssertNil(service.controller.imageStackWorkspace)
      model.showPage(1);await model.task?.value;XCTAssertEqual(model.page,1);XCTAssertTrue(model.ready)
      try first.store.session.execute(.renameLayer(first.store.document.layers[0].id,"Changed"));XCTAssertThrowsError(try model.commit(display:false));XCTAssertEqual(service.controller.documents.count,2)
      first.store.session = EditorSession(document:originals[0]);model.refresh();await model.task?.value
      let prepared = try XCTUnwrap(model.result).documents
      let created = try model.commit(display:false);XCTAssertEqual(created.map{$0.store.document},prepared);XCTAssertTrue(created.allSatisfy{$0.fileURL == nil && $0.isDocumentEdited})
      for (i,d) in docs.enumerated() {XCTAssertEqual(d.store.document,originals[i]);XCTAssertTrue(d.store.session.undoStack.isEmpty)}
      XCTAssertFalse(model.ready);XCTAssertThrowsError(try model.commit(display:false))
      let previousMenu = NSApp.mainMenu;defer {NSApp.mainMenu = previousMenu}
      let delegate = AppDelegate();delegate.installPhotoshopMenus()
      let action = NSApp.mainMenu?.items.first{$0.title == "File"}?.submenu?.items.first{$0.title == "Automate"}?.submenu?.items.first{$0.title == "Contact Sheet II…"}?.action
      XCTAssertEqual(action,#selector(AppDelegate.contactSheet))
    }
  }
  @MainActor func testHTTPAtomicPagesMatchNativeAndGuards() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,first in
      let docs = try setup(service,first);defer {cleanup(service,first)}
      let snapshots = docs.map{$0.store.document},s = settings(),parameters = try params(service,s)
      let disabled = try await helper.edit(service,first,"document.contactSheet",parameters);XCTAssertEqual(disabled,403)
      service.setDocumentTransfersEnabled(true)
      var badFont = parameters;badFont["settings"] = ["units":"pixels","width":200,"height":200,"resolution":72,"columns":1,"rows":1,"caption":true,"font":"PhotatoMissingContactSheetFont","flatten":false]
      let missingFont = try await helper.edit(service,first,"document.contactSheet",badFont);XCTAssertEqual(missingFont,422);XCTAssertEqual(service.controller.documents.count,2)
      first.store.geometryBusy = true;let busy = try await helper.edit(service,first,"document.contactSheet",parameters);XCTAssertEqual(busy,409);first.store.geometryBusy = false
      let response = try await helper.request(service,path:"/v1/documents/\(service.shares[0].id)/commands",body:["command":"document.contactSheet","revision":service.revision(first.store),"parameters":try params(service,s)])
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self));guard response.0.statusCode == 201 else{return}
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any]);XCTAssertEqual(json["pages"] as? Int,2)
      let native = try ContactSheet.prepare(snapshots.map{.init(document:$0)},settings:s)
      let created = Array(service.shares.suffix(2)).compactMap(\.document)
      for (i,d) in created.enumerated() {XCTAssertEqual(try Renderer.composite(d.store.document),try Renderer.composite(native.documents[i]));XCTAssertEqual(d.store.document.layers.map(\.name),native.documents[i].layers.map(\.name));XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d.store.document)),d.store.document)}
      for (i,d) in docs.enumerated() {XCTAssertEqual(d.store.document,snapshots[i]);XCTAssertTrue(d.store.session.undoStack.isEmpty)}
      var stale = parameters;stale["sources"] = [["id":service.shares[0].id.uuidString,"revision":"stale"]]
      let rejected = try await helper.edit(service,first,"document.contactSheet",stale);XCTAssertEqual(rejected,409);XCTAssertEqual(service.controller.documents.count,4)
    }
  }
  @MainActor func testFolderAtomicImportAndCancel() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      defer {cleanup(service,first)}
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:folder)}
      try NativeArchive.encodeChunked(first.store.document).write(to:folder.appendingPathComponent("One.photato"))
      service.controller.beginContactSheet(display:false);let model = try XCTUnwrap(service.controller.contactSheetWorkspace);model.settings = settings();model.load([folder],folder:true);await model.loadingTask?.value;XCTAssertEqual(model.sources.count,1)
      let nested = folder.appendingPathComponent("nested",isDirectory:true)
      try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:false)
      let second = nested.appendingPathComponent("Two.photato")
      try NativeArchive.encodeChunked(first.store.document).write(to:second)
      try FileManager.default.createSymbolicLink(at:folder.appendingPathComponent("linked.photato"),withDestinationURL:second)
      try FileManager.default.createSymbolicLink(at:folder.appendingPathComponent("linked-folder"),withDestinationURL:nested)
      model.includeSubfolders = true;model.load([folder],folder:true);await model.loadingTask?.value
      XCTAssertNil(model.error);XCTAssertEqual(Set(model.sources.map(\.title)),["One.photato","Two.photato"])
      let bad = folder.appendingPathComponent("Bad.photato");try Data("broken".utf8).write(to:bad)
      model.load([bad]);await model.loadingTask?.value;XCTAssertNotNil(model.error);XCTAssertEqual(model.sources.count,2)
      model.refresh();service.controller.cancelContactSheet();await model.task?.value;XCTAssertFalse(model.ready);XCTAssertEqual(service.controller.documents.count,1)
    }
  }
  @MainActor func testAPICancellationAndRevocationPublishNothing() async throws {
    let helper = AutomationTests()
    for revoke in [false,true] {
      try await helper.withService(pressedMouseButtons:{0}) {service,first in
        defer {cleanup(service,first)}
        first.store.session = EditorSession(document:try DocumentCreation.blank(width:1024,height:1024,background:Pixel(0.2,0.4,0.7),name:"Owned"))
        try service.share(first)
        let original = first.store.document
        var s = settings();s.width = 1600;s.height = 1600;s.flatten = true
        let parameters = try params(service,s);service.setDocumentTransfersEnabled(true)
        let id = try XCTUnwrap(service.shares.first?.id)
        let task = Task {try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"document.contactSheet","revision":service.revision(first.store),"parameters":parameters])}
        let deadline = Date().addingTimeInterval(10)
        while service.contactSheetOperationID == nil && Date() < deadline {try await Task.sleep(for:.milliseconds(5))}
        let operation = try XCTUnwrap(service.contactSheetOperationID)
        if revoke {service.revoke(id)}
        else {
          let cancelled = try await helper.edit(service,first,"document.contactSheet.cancel",["operationID":operation.uuidString]);XCTAssertEqual(cancelled,200)
        }
        let response = try await task.value;XCTAssertEqual(response.0.statusCode,409)
        XCTAssertEqual(service.controller.documents.count,1);XCTAssertEqual(first.store.document,original);XCTAssertTrue(first.store.session.undoStack.isEmpty);XCTAssertFalse(first.store.geometryBusy);XCTAssertNil(service.contactSheetOperationID)
      }
    }
  }
  @MainActor func testOffscreenControlsAndCapacity() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      defer {cleanup(service,first)}
      let docs = try setup(service,first)
      service.controller.beginContactSheet(display:false)
      let model = try XCTUnwrap(service.controller.contactSheetWorkspace);model.settings = settings();model.settings.width = 200;model.settings.height = 160;model.settings.caption = true;model.addOpenDocuments();model.refresh();await model.task?.value
      XCTAssertTrue(model.ready,model.error ?? "No preview")
      let preview = try RasterIO.surface(XCTUnwrap(model.image))
      let captionInk = (142..<160).reduce(0) {n,y in n+(0..<200).filter {x in let p = preview.pixel(x:x,y:y);return p.r < 0.4 && p.g < 0.4 && p.b < 0.4}.count}
      XCTAssertGreaterThan(captionInk,0,"The background-rendered preview must show its filename caption")
      if let path = ProcessInfo.processInfo.environment["PHOTATO_CONTACT_SHEET_ARTIFACTS"] {
        try RasterIO.encoded(preview).write(to:URL(fileURLWithPath:path).appendingPathComponent("caption-preview.png"))
        try RasterIO.encoded(XCTUnwrap(model.result?.documents.first)).write(to:URL(fileURLWithPath:path).appendingPathComponent("caption-document.png"))
      }
      let host = NSHostingView(rootView:ContactSheetView(model:model).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.light));host.appearance = NSAppearance(named:.aqua)
      let window = NSWindow(contentRect:NSRect(x:0,y:0,width:870,height:730),styleMask:.borderless,backing:.buffered,defer:false);window.isReleasedWhenClosed = false;window.contentView = host;defer {window.close()}
      host.frame = NSRect(x:0,y:0,width:870,height:730);host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(70));host.layoutSubtreeIfNeeded()
      XCTAssertEqual(host.fittingSize.width,870,accuracy:2);XCTAssertEqual(host.fittingSize.height,730,accuracy:2)
      if let path = ProcessInfo.processInfo.environment["PHOTATO_CONTACT_SHEET_ARTIFACTS"] {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:path).appendingPathComponent("contact-sheet-controls.png"))
      }
      service.controller.cancelContactSheet();service.setDocumentTransfersEnabled(true)
      for _ in 0..<5 {let d = CraftNSDocument(model:docs[0].store.document);service.controller.addDocument(d);try service.share(d)}
      let sources = Array(service.shares.prefix(2)).map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]}
      let raw = try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings()))
      let status = try await AutomationTests().edit(service,first,"document.contactSheet",["sources":sources,"settings":raw]);XCTAssertEqual(status,429);XCTAssertEqual(service.controller.documents.count,7)
    }
  }

}
