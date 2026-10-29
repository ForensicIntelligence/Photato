import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ImageProcessorTests: XCTestCase {
  func scan(name: String = "Owned.scan.png",width: Int = 80,height: Int = 40) throws -> CraftDocument {
    try DocumentCreation.blank(width:width,height:height,background:Pixel(0.2,0.4,0.6),name:name,resolution:240)
  }
  func settings() -> ImageProcessorSettings {
    var s = ImageProcessorSettings();s.jpeg = .init(enabled:true,resize:true,width:20,height:20);s.psd = .init(enabled:true,resize:true,width:40,height:40);s.tiff = .init(enabled:true);s.convertJPEGToSRGB = false;return s
  }
  func testMultipleFormatsFitDimensionsDuplicateNamesAndOriginalPreservation() throws {
    let document = try scan(),source = ActionBatchSource(document:document);var s = settings();s.copyright = "Owned test imagery"
    let output = try ImageProcessor.render([source,source],settings:s)
    XCTAssertEqual(output.records.count,6);XCTAssertEqual(Set(output.records.map{$0.file.lowercased()}).count,6)
    for (index,record) in output.records.enumerated() {
      XCTAssertEqual(record.width,[20,40,80][index%3]);XCTAssertEqual(record.height,[10,20,40][index%3])
      let file = try XCTUnwrap(output.files.first{$0.name == record.file}),read = try RasterIO.read(file.data)
      XCTAssertEqual(read.width,record.width);XCTAssertEqual(read.height,record.height);XCTAssertEqual(read.pixelsPerInch,240,accuracy:0.01)
      let pixel = try Renderer.composite(read).pixel(x:0,y:0)
      XCTAssertEqual(pixel.r,0.2,accuracy:0.015);XCTAssertEqual(pixel.g,0.4,accuracy:0.015);XCTAssertEqual(pixel.b,0.6,accuracy:0.015)
    }
    XCTAssertEqual(document,source.document)
    if let directory = ProcessInfo.processInfo.environment["PHOTATO_IMAGEPROCESSOR_OUTPUT"] {
      let url = URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
      try output.zip().write(to:url.appendingPathComponent("processed.zip"))
    }
  }
  func testActionsSettingsRoundTripAndValidation() throws {
    let document = try scan(),snapshot = document,action = RecordedAction(name:"Black",steps:[.init(name:"Fill",operation:.fill(.active,.black))])
    var s = settings();s.actionID = action.id;XCTAssertEqual(try ImageProcessorSettings.decode(s.encoded()),s)
    let output = try ImageProcessor.render([.init(document:document)],settings:s,action:action)
    for file in output.files where file.name.hasPrefix("TIFF/") {XCTAssertEqual(try Renderer.composite(RasterIO.read(file.data)).pixel(x:0,y:0),.black)}
    XCTAssertEqual(document,snapshot)
    XCTAssertThrowsError(try ImageProcessor.render([.init(document:document)],settings:s))
    s.actionID = nil;s.maximizeCompatibility = false;XCTAssertThrowsError(try s.validate());s.maximizeCompatibility = true
    s.jpeg.width = 0;XCTAssertThrowsError(try s.validate());s.jpeg.width = 20;s.jpegQuality = 13;XCTAssertThrowsError(try s.validate())
    XCTAssertThrowsError(try ImageProcessor.render([.init(document:document)],settings:settings(),maximumBytes:1))
    XCTAssertThrowsError(try ImageProcessor.render([],settings:settings()))
  }
  func testProfileReuseEmbeddingAndNoEnlargement() throws {
    var source = try scan(width:4,height:2)
    source.workingICC = try XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3)?.copyICCData() as Data?)
    var s = settings();s.jpeg.resize = true;s.jpeg.width = 200;s.jpeg.height = 200;s.convertJPEGToSRGB = true;s.includeICC = false
    let output = try ImageProcessor.render([.init(document:source)],settings:s)
    XCTAssertTrue(output.records.allSatisfy{$0.width == 4 && $0.height == 2})
    for file in output.files where file.name != "image-processor.json" {
      let read = try RasterIO.read(file.data);XCTAssertTrue(read.profileIsUntagged == true || read.sourceICC == nil,file.name)
    }
    s.includeICC = true;s.useFirstImageProfile = true;s.jpeg.enabled = false;s.psd.enabled = false
    let converted = try ImageProcessor.render([.init(document:source),.init(document:scan(name:"Second"))],settings:s)
    for file in converted.files where file.name.hasPrefix("TIFF/") {let read = try RasterIO.read(file.data);XCTAssertEqual(read.workingICC,source.workingICC)}
  }
  func testNativePublicationPreservesExistingFilesRejectsSymlinksAndRollsBack() throws {
    let root = try ActionBatchTests().folder();defer {try? FileManager.default.removeItem(at:root)}
    let output = try ImageProcessor.render([.init(document:scan())],settings:settings())
    let prepared = try PreparedImageProcessorFiles.prepare(output,parent:root);defer {prepared.discard()}
    let first = try prepared.commit(to:root),before = try first.map{try Data(contentsOf:root.appendingPathComponent($0))}
    let second = try prepared.commit(to:root);XCTAssertEqual(Set(first).intersection(second).count,0)
    for (i,path) in first.enumerated() {XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(path)),before[i])}
    var calls = 0
    XCTAssertThrowsError(try prepared.commit(to:root) {calls += 1;if calls == 2 {throw CraftError.invalid("Simulated publication revocation")}})
    let files = try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("JPEG").path);XCTAssertEqual(files.count,2)
    let bad = try ActionBatchTests().folder();defer {try? FileManager.default.removeItem(at:bad)}
    try FileManager.default.createSymbolicLink(at:bad.appendingPathComponent("JPEG"),withDestinationURL:root)
    let attempt = try PreparedImageProcessorFiles.prepare(output,parent:bad);defer {attempt.discard()};XCTAssertThrowsError(try attempt.commit(to:bad))
  }
  @MainActor func testNativeWorkspaceFilesOpenImagesSettingsAndMenu() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      first.store.session = EditorSession(document:try scan());let snapshot = first.store.document
      let directory = try ActionBatchTests().folder();defer {try? FileManager.default.removeItem(at:directory)}
      let model = ImageProcessorWorkspace(controller:service.controller);model.settings = settings();model.destination = directory;model.addOpen();XCTAssertEqual(model.sources.count,1)
      model.run();await model.task?.value;XCTAssertNil(model.error);XCTAssertEqual(model.outputs.count,3);XCTAssertEqual(first.store.document,snapshot)
      XCTAssertTrue(first.store.session.undoStack.isEmpty)
      let previous = NSApp.mainMenu;defer {NSApp.mainMenu = previous};AppDelegate().installPhotoshopMenus()
      let action = NSApp.mainMenu?.items.first{$0.title == "File"}?.submenu?.items.first{$0.title == "Scripts"}?.submenu?.items.first{$0.title == "Image Processor…"}?.action
      XCTAssertEqual(action,#selector(AppDelegate.imageProcessor))
      if let folder = ProcessInfo.processInfo.environment["PHOTATO_IMAGEPROCESSOR_OUTPUT"] {
        let host = NSHostingView(rootView:ImageProcessorView(model:model).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.light))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:900),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named:.aqua);window.contentView = host
        host.frame = NSRect(x:0,y:0,width:760,height:900);host.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:image)
        try XCTUnwrap(image.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:folder).appendingPathComponent("image-processor-controls.png"));window.close()
      }
    }
  }
  @MainActor func testFolderInputsCancellationAndChangedOpenSourcePublishNothing() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      let input = try ActionBatchTests().folder(),output = try ActionBatchTests().folder()
      defer {try? FileManager.default.removeItem(at:input);try? FileManager.default.removeItem(at:output)}
      let nested = input.appendingPathComponent("nested",isDirectory:true)
      try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:false)
      let pixels = try RasterIO.encoded(scan(),type:.png)
      try pixels.write(to:input.appendingPathComponent("First.scan.png"))
      try pixels.write(to:nested.appendingPathComponent("Second.png"))
      try Data("Ignore this text file".utf8).write(to:input.appendingPathComponent("notes.txt"))
      try FileManager.default.createSymbolicLink(at:input.appendingPathComponent("linked.png"),withDestinationURL:nested.appendingPathComponent("Second.png"))
      try FileManager.default.createSymbolicLink(at:input.appendingPathComponent("linked-folder"),withDestinationURL:nested)
      let model = ImageProcessorWorkspace(controller:service.controller)
      try model.addFiles([input],folder:true);XCTAssertEqual(model.sources.map(\.name),["First.scan.png"])
      model.clear();model.includeSubfolders = true;try model.addFiles([input],folder:true)
      XCTAssertEqual(Set(model.sources.map(\.name)),["First.scan.png","Second.png"])
      try model.addFiles([input.appendingPathComponent("First.scan.png")]);XCTAssertEqual(model.sources.count,2)
      model.destination = output;model.run();await model.task?.value
      XCTAssertNil(model.error);XCTAssertEqual(Set(model.outputs),["JPEG/First.scan.jpg","JPEG/Second.jpg"])
      model.clear();model.addOpen()
      let before = try FileManager.default.subpathsOfDirectory(atPath:output.path).sorted()
      model.run();model.cancel();await model.task?.value
      XCTAssertNotNil(model.error);XCTAssertTrue(model.outputs.isEmpty);XCTAssertFalse(model.busy)
      XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath:output.path).sorted(),before)
      model.run()
      var changed = first.store.document;changed.name = "Edited during processing"
      first.store.session = EditorSession(document:changed)
      await model.task?.value
      XCTAssertNotNil(model.error);XCTAssertTrue(model.outputs.isEmpty);XCTAssertFalse(model.busy)
      XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath:output.path).sorted(),before)
      XCTAssertEqual(first.store.document,changed)
    }
  }
  @MainActor func testHTTPExportMatchesNativePermissionsSchemaAndStaleSources() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,first in
      first.store.session = EditorSession(document:try scan());try service.share(first)
      let id = try XCTUnwrap(service.shares.first?.id),snapshot = first.store.document,s = settings()
      let params: [String:Any] = ["sources":[["id":id.uuidString,"revision":service.revision(first.store)]],"settings":try JSONSerialization.jsonObject(with:JSONEncoder().encode(s))]
      let denied = try await helper.edit(service,first,"document.imageProcessor",params);XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let result = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"document.imageProcessor","revision":service.revision(first.store),"parameters":params])
      XCTAssertEqual(result.0.statusCode,200,String(decoding:result.1.prefix(500),as:UTF8.self));XCTAssertEqual(result.1,try ImageProcessor.render([.init(document:snapshot)],settings:s).zip())
      var invalid = params;invalid["settings"] = ["unknown":true];let rejected = try await helper.edit(service,first,"document.imageProcessor",invalid);XCTAssertEqual(rejected,400)
      invalid = params;invalid["sources"] = [["id":id.uuidString,"revision":"stale"]];let stale = try await helper.edit(service,first,"document.imageProcessor",invalid);XCTAssertEqual(stale,409)
      XCTAssertEqual(first.store.document,snapshot);XCTAssertTrue(first.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPRevocationAndCancellationReturnNoArchive() async throws {
    let helper = AutomationTests()
    for revoke in [false,true] {
      try await helper.withService(pressedMouseButtons:{0}) {service,first in
        first.store.session = EditorSession(document:try scan(width:1600,height:1200));try service.share(first);service.setDocumentTransfersEnabled(true)
        let id = try XCTUnwrap(service.shares.first?.id),revision = service.revision(first.store),snapshot = first.store.document
        let operation = Task {try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"document.imageProcessor","revision":revision,"parameters":["sources":[["id":id.uuidString,"revision":revision]]]])}
        let deadline = Date().addingTimeInterval(10)
        while service.imageProcessorOperationID == nil && Date()<deadline {try await Task.sleep(for:.milliseconds(5))}
        let job = try XCTUnwrap(service.imageProcessorOperationID)
        if revoke {service.revoke(id)} else {let response = try await helper.edit(service,first,"document.imageProcessor.cancel",["operationID":job.uuidString]);XCTAssertEqual(response,200)}
        let response = try await operation.value;XCTAssertNotEqual(response.0.statusCode,200);XCTAssertEqual(first.store.document,snapshot);XCTAssertNil(service.imageProcessorTask);XCTAssertFalse(service.documentTransferBusy)
      }
    }
  }
}
