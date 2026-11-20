import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LinkedArtworkWorkflowTests:XCTestCase {
  func artwork(_ color:Pixel=Pixel(0.8,0.2,0.1))throws->Data {try RasterIO.encoded(Surface(width:4,height:3,fill:color))}
  func folder()throws->URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("Photato-linked-tests-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url.resolvingSymlinksInPath()
  }
  @MainActor func linkedFixture(_ file:LinkedArtworkRead)throws->CraftDocument {
    var d=try CraftDocument(width:16,height:12)
    let layer=try LinkedSmartObjectIO.place(file.data,fileName:file.fileName,reference:file.reference,in:d,fit:false)
    try Command.addLayer(layer).apply(to:&d);return d
  }
  @MainActor func testPrivateRegistryPersistsRevokesAndRejectsSymlinkSubstitution()throws {
    let dir=try folder();defer{try? FileManager.default.removeItem(at:dir)}
    let url=dir.appendingPathComponent("source.png"),bytes=try artwork();try bytes.write(to:url)
    let registry=LinkedSourceRegistry(storageURL:dir.appendingPathComponent("private/grants.json")),grant=try registry.authorize(url)
    let file=try LinkedArtworkRead.read(grant);XCTAssertEqual(file.data,bytes)
    let reopened=LinkedSourceRegistry(storageURL:registry.storageURL),resolved=try reopened.resolve(file.reference)
    XCTAssertEqual(try LinkedArtworkRead.read(resolved).data,bytes)
    let replacement=try artwork(Pixel(0.1,0.3,0.9));try replacement.write(to:url,options:.atomic)
    let changed=try LinkedArtworkRead.read(registry.resolve(file.reference));XCTAssertEqual(changed.data,replacement);XCTAssertNotEqual(changed.signature,file.signature)
    let other=dir.appendingPathComponent("other.png");try bytes.write(to:other);try FileManager.default.removeItem(at:url)
    try FileManager.default.createSymbolicLink(at:url,withDestinationURL:other)
    XCTAssertThrowsError(try LinkedArtworkRead.read(grant));XCTAssertThrowsError(try registry.resolve(file.reference))
    try registry.revoke(grant.id);XCTAssertFalse(registry.stillAuthorizes(grant));XCTAssertThrowsError(try registry.resolve(file.reference))
  }
  @MainActor func testNativeLinkedPlacementPreviewCancelCommitAndEmbedUndo()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {_,document in
      let dir=try self.folder();defer{try? FileManager.default.removeItem(at:dir)}
      let url=dir.appendingPathComponent("source.png");try self.artwork().write(to:url)
      let store=document.store;store.linkedSourceRegistry=LinkedSourceRegistry(persistent:false);store.onChange=nil
      let grant=try store.linkedSourceRegistry.authorize(url),original=store.document
      store.placeEmbeddedSource(url,linkedGrant:grant);await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertNotNil(store.embeddedPlacement);XCTAssertEqual(store.document,original)
      store.cancelTransform();XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
      store.placeEmbeddedSource(url,linkedGrant:grant);await store.geometryTask?.value
      store.commitTransform();await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertNotNil(store.activeLayer?.smartObject?.linkedSource);XCTAssertEqual(store.session.undoStack.count,1);XCTAssertFalse(store.geometryBusy)
      let linked=store.document;store.embedLinkedArtwork();await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertNil(store.activeLayer?.smartObject?.linkedSource);XCTAssertEqual(store.session.undoStack.count,2);XCTAssertFalse(store.geometryBusy)
      await store.undo();XCTAssertEqual(store.document,linked)
      store.linkedSourceController?.stop()
    }
  }

  @MainActor func testLargeLinkedPSBThroughPlacementRefreshPackageAndTransferLimits() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let directory = try self.folder()
      let url = directory.appendingPathComponent("Linked.psb")
      let store = document.store
      defer {
        store.linkedSourceController?.stop()
        try? FileManager.default.removeItem(at: directory)
      }
      if let fixture = ProcessInfo.processInfo.environment["PHOTATO_LARGE_LINKED_FIXTURE"] {
        try FileManager.default.copyItem(at: URL(fileURLWithPath: fixture), to: url)
      } else {
        var child = try CraftDocument(width: 1024, height: 4097, depth: .f32)
        var samples = try Surface(width: child.width, height: child.height, depth: .f32,
          fill: Pixel(0.3125, 0.625, 0.25, 0.5))
        samples.setPixel(x: child.width - 1, y: child.height - 1, Pixel(0.75, 0.125, 0.5))
        child.layers[0].content = .raster(samples)
        try PSDCodec.writeRasterLayers(child, to: url, format: .psb)
      }
      store.linkedSourceRegistry = LinkedSourceRegistry(persistent: false)
      store.session = EditorSession(document: try CraftDocument(width: 96, height: 72, depth: .f32))
      store.onChange = nil
      try service.share(document)
      let asset = try service.authorizeLinkedArtwork(url, registry: store.linkedSourceRegistry)
      let grant = try XCTUnwrap(service.linkedArtworkAssets[asset])
      let original = try LinkedArtworkRead.read(grant)
      XCTAssertTrue(original.original.isFileBacked)
      XCTAssertGreaterThan(original.data.count, SmartObject.maximumSourceBytes)
      print("Approved PSB bytes:", original.data.count)
      XCTAssertThrowsError(try LinkedArtworkRead.readForTransfer(grant)) { error in
        XCTAssertEqual((error as? AutomationFailure)?.status, 413)
      }

      let before = store.document
      let nativeStart = ContinuousClock.now
      store.placeEmbeddedSource(url, linkedGrant: grant)
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertNotNil(store.transformDraft)
      store.commitTransform()
      await store.geometryTask?.value
      let placed = try XCTUnwrap(store.activeLayer)
      let placedSource = try XCTUnwrap(placed.smartObject)
      XCTAssertTrue(placedSource.sourceBytes.isFileBacked)
      XCTAssertEqual(placedSource.dataFingerprint, original.fingerprint)
      XCTAssertEqual(placedSource.linkedSource?.byteLength, UInt64(original.data.count))
      print("Native Place Linked:", nativeStart.duration(to: .now))
      let parent = store.document
      let shareID = try XCTUnwrap(service.shares.first?.id)
      for route in ["source", "linked-source"] {
        let response = try await helper.request(service, path: "/v1/documents/\(shareID)/smart-objects/\(placed.id)/\(route)")
        XCTAssertEqual(response.0.statusCode, 413)
      }
      await store.undo()
      XCTAssertEqual(store.document, before)
      let apiStart = ContinuousClock.now
      let code = try await helper.edit(service, document, "smartObject.linked.place", [
        "assetID": asset.uuidString, "fingerprint": original.fingerprint,
      ], timeout: 180)
      XCTAssertEqual(code, 200)
      print("HTTP Place Linked:", apiStart.duration(to: .now))
      let linked = try XCTUnwrap(store.activeLayer)
      let linkedSource = try XCTUnwrap(linked.smartObject)
      XCTAssertTrue(linkedSource.sourceBytes.isFileBacked)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .f32),
        try Renderer.composite(parent).rgbaData(depth: .f32))
      XCTAssertLessThan(store.document.minimumArchiveVersion, SmartObject.largeSourceArchiveVersion)

      let saved = try NativeArchive.encodeChunked(store.document)
      let reopened = try NativeArchive.decodePaged(saved)
      XCTAssertTrue(reopened.layers.last?.smartObject?.data.isEmpty == true)
      var rehydrated = EditorSession(document: reopened)
      try rehydrated.hydrateLinkedSmartObject(linkedSource.sourceID, original: original.original)
      let retained = try XCTUnwrap(rehydrated.document.layers.last?.smartObject)
      XCTAssertTrue(retained.sourceBytes.isFileBacked)
      XCTAssertEqual(retained.revision, linkedSource.revision)
      XCTAssertTrue(rehydrated.undoStack.isEmpty)

      store.linkedSourceController?.stop()
      let monitor = LinkedSourceController(store: store)
      store.linkedSourceController = monitor
      monitor.acknowledge([linkedSource.sourceID: original])
      var child = try SmartObjectIO.sourceDocument(retained)
      child.layers[0].name = "Updated linked child"
      guard case .raster(var changed) = child.layers.first?.content else {
        return XCTFail("Expected an editable raster layer in the linked PSB.")
      }
      changed.setPixel(x: child.width - 1, y: child.height - 1, Pixel(0.125, 0.75, 0.5))
      child.layers[0].content = .raster(changed)
      try PSDCodec.writeRasterLayers(child, to: url, format: .psb)
      await monitor.scan()
      let updated = try XCTUnwrap(store.activeLayer?.smartObject)
      XCTAssertTrue(updated.sourceBytes.isFileBacked)
      XCTAssertNotEqual(updated.dataFingerprint, original.fingerprint)
      XCTAssertEqual(updated.sourceID, linkedSource.sourceID)
      XCTAssertEqual(try SmartObjectIO.sourceDocument(updated).layers.first?.name, "Updated linked child")
      XCTAssertEqual(store.session.undoStack.count, 2)
      print("Automatic linked-source refresh retained the new child")

      let package = try PreparedLinkedPackage.prepare(store.document, grants: [updated.sourceID: grant],
        parent: directory, options: .init(name: "Package", format: .psb))
      try package.validateSources()
      try package.directory.commit()
      let packaged = try XCTUnwrap(package.sources.first)
      let packageFile = package.folderURL.appendingPathComponent("Links/" + packaged.name)
      XCTAssertEqual(LinkedSmartObjectSource.fingerprint(try Data(contentsOf: packageFile, options: .alwaysMapped)), updated.dataFingerprint)
      let packagedDocument = try PSDCodec.read(package.documentURL)
      XCTAssertTrue(packagedDocument.layers.last?.smartObject?.data.isEmpty == true)
      XCTAssertEqual(packagedDocument.layers.last?.smartObject?.linkedSource?.reference, "Links/" + packaged.name)
      let repeated = try PreparedLinkedPackage.prepare(store.document, grants: [updated.sourceID: grant],
        parent: directory, options: .init(name: "Package", format: .psb, replaceExisting: true))
      try repeated.directory.commit()
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: packageFile.deletingLastPathComponent().path), [packaged.name])
      print("PSB package reused its existing original")

      let packagedGrant = try store.linkedSourceRegistry.authorize(packageFile)
      store.relinkArtwork(linked.id, grant: packagedGrant)
      await store.geometryTask?.value
      let relinked = try XCTUnwrap(store.activeLayer?.smartObject)
      XCTAssertNil(store.error)
      XCTAssertEqual(relinked.linkedSource?.authorizationID, packagedGrant.id)
      XCTAssertTrue(relinked.sourceBytes.isFileBacked)
      XCTAssertEqual(relinked.dataFingerprint, updated.dataFingerprint)
      store.embedLinkedArtwork()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.activeLayer?.smartObject?.dataFingerprint, updated.dataFingerprint)
      XCTAssertTrue(store.activeLayer?.smartObject?.sourceBytes.isFileBacked == true)
      XCTAssertNil(store.activeLayer?.smartObject?.linkedSource)
      await store.undo()
      XCTAssertEqual(store.activeLayer?.smartObject, relinked)
      print("Linked PSB byte count:", original.data.count, "original SHA-256:", original.fingerprint,
        "updated SHA-256:", updated.dataFingerprint)
    }
  }
  @MainActor func testMonitorUpdatesSharedInstancesAndUndoDoesNotReapplyObservedVersion()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {_,document in
      let dir=try self.folder();defer{try? FileManager.default.removeItem(at:dir)}
      let url=dir.appendingPathComponent("source.png");try self.artwork().write(to:url)
      let store=document.store;store.linkedSourceRegistry=LinkedSourceRegistry(persistent:false);store.onChange=nil
      let grant=try store.linkedSourceRegistry.authorize(url),file=try LinkedArtworkRead.read(grant)
      var original=try self.linkedFixture(file);var duplicate=original.layers.last!;duplicate.id=UUID();duplicate.name="Shared instance";original.layers.append(duplicate)
      store.session=EditorSession(document:original)
      let monitor=LinkedSourceController(store:store);store.linkedSourceController=monitor;defer{monitor.stop()}
      await monitor.scan();XCTAssertEqual(monitor.state(original.layers.last!.smartObject!).status,.current)
      try self.artwork(Pixel(0.1,0.6,0.3)).write(to:url,options:.atomic);await monitor.scan()
      XCTAssertFalse(store.geometryBusy);XCTAssertEqual(store.session.undoStack.count,1);XCTAssertNotEqual(store.document,original)
      let updated=store.document;XCTAssertEqual(updated.layers[1].smartObject,updated.layers[2].smartObject)
      await store.undo();XCTAssertEqual(store.document,original);await monitor.scan();XCTAssertEqual(store.document,original)
      XCTAssertEqual(monitor.state(original.layers.last!.smartObject!).status,.modified)
      try await monitor.update(original.layers.last!.id);XCTAssertEqual(store.document,updated)
      try FileManager.default.removeItem(at:url);await monitor.scan();XCTAssertEqual(monitor.state(updated.layers.last!.smartObject!).status,.missing)
    }
  }
  @MainActor func testNativeConvertToLinkedOverwritesApprovedDestinationAndLockedSharedInstanceWritesNothing()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {_,document in
      let dir=try self.folder();defer{try? FileManager.default.removeItem(at:dir)}
      let url=dir.appendingPathComponent("converted.png"),old=Data("old destination".utf8),bytes=try self.artwork();try old.write(to:url)
      let store=document.store;store.linkedSourceRegistry=LinkedSourceRegistry(persistent:false);store.onChange=nil
      var d=try CraftDocument(width:16,height:12);let layer=try SmartObjectIO.placed(data:bytes,fileName:"source.png",in:d)
      try Command.addLayer(layer).apply(to:&d);store.session=EditorSession(document:d)
      store.saveLinkedArtworkSource(layer.id,object:layer.smartObject!,url:url);await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertFalse(store.geometryBusy);XCTAssertEqual(try Data(contentsOf:url),bytes)
      XCTAssertNotNil(store.activeLayer?.smartObject?.linkedSource);XCTAssertEqual(store.session.undoStack.count,1)
      store.linkedSourceController?.stop();await store.undo();XCTAssertEqual(store.document,d)
      var locked=d;var copy=layer;copy.id=UUID();copy.locked=true;locked.layers.append(copy);store.session=EditorSession(document:locked)
      try old.write(to:url,options:.atomic);store.saveLinkedArtworkSource(layer.id,object:layer.smartObject!,url:url);await store.geometryTask?.value
      XCTAssertNotNil(store.error);XCTAssertEqual(store.document,locked);XCTAssertEqual(try Data(contentsOf:url),old)
    }
  }
  @MainActor func testHTTPApprovedPlaceStateSchemaFingerprintAndRevocation()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let dir=try self.folder();defer{try? FileManager.default.removeItem(at:dir)}
      let url=dir.appendingPathComponent("logo.png"),bytes=try self.artwork();try bytes.write(to:url)
      let store=document.store;store.onChange=nil;store.linkedSourceRegistry=LinkedSourceRegistry(persistent:false);try service.share(document)
      let asset=try service.authorizeLinkedArtwork(url,registry:store.linkedSourceRegistry),hash=LinkedSmartObjectSource.fingerprint(bytes)
      let list=try await helper.request(service,path:"/v1/linked-artwork");XCTAssertEqual(list.0.statusCode,200)
      let text=String(decoding:list.1,as:UTF8.self);XCTAssertTrue(text.contains(hash));XCTAssertFalse(text.contains(dir.path));XCTAssertFalse(text.contains("authorizationID"))
      var parameters:[String:Any]=["assetID":asset.uuidString,"fingerprint":hash,"fit":false]
      let original=store.document;var code=try await helper.edit(service,document,"smartObject.linked.place",parameters);XCTAssertEqual(code,200)
      XCTAssertEqual(store.activeLayer?.smartObject?.data,bytes);XCTAssertEqual(store.selectedLayerIDs,Set(store.document.activeLayerID.map{[$0]} ?? []));XCTAssertEqual(store.session.undoStack.count,1)
      let state=service.state(try XCTUnwrap(service.shares.first),document:document);XCTAssertNotNil(state["linkedArtwork"])
      for definition in LinkedArtworkAPI.definitions {XCTAssertNotNil(definition.schema["properties"])}
      await store.undo();XCTAssertEqual(store.document,original)
      parameters["fingerprint"]=String(repeating:"0",count:64);code=try await helper.edit(service,document,"smartObject.linked.place",parameters);XCTAssertEqual(code,409);XCTAssertEqual(store.document,original)
      parameters["fingerprint"]=true;code=try await helper.edit(service,document,"smartObject.linked.place",parameters);XCTAssertEqual(code,400)
      parameters["fingerprint"]=hash;parameters["path"]=url.path;code=try await helper.edit(service,document,"smartObject.linked.place",parameters);XCTAssertEqual(code,400);parameters.removeValue(forKey:"path")
      code=try await helper.edit(service,document,"smartObject.linked.place",parameters,revision:"stale");XCTAssertEqual(code,409)
      store.geometryBusy=true;code=try await helper.edit(service,document,"smartObject.linked.place",parameters);XCTAssertEqual(code,409);store.geometryBusy=false
      service.clearLinkedArtwork();code=try await helper.edit(service,document,"smartObject.linked.place",parameters);XCTAssertEqual(code,403)
      XCTAssertEqual(store.document,original);store.linkedSourceController?.stop()
    }
  }
  @MainActor func testHTTPUpdateRelinkEmbedConvertMatchNativePreserveMaskAndRequireSessionApproval()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let dir=try self.folder();defer{try? FileManager.default.removeItem(at:dir)}
      let url=dir.appendingPathComponent("logo.png"),bytes=try self.artwork();try bytes.write(to:url)
      let store=document.store;store.onChange=nil;store.linkedSourceRegistry=LinkedSourceRegistry(persistent:false)
      let asset=try service.authorizeLinkedArtwork(url,registry:store.linkedSourceRegistry),grant=try service.linkedArtworkGrant(asset,store:store),file=try LinkedArtworkRead.read(grant)
      var original=try self.linkedFixture(file);let id=original.layers.last!.id;original.layers[1].mask=try Surface(width:16,height:12,fill:.white)
      store.session=EditorSession(document:original);store.maskEditingLayerID=id;try service.share(document)
      let next=try self.artwork(Pixel(0.2,0.4,0.8));try next.write(to:url,options:.atomic)
      var expected=original;let nextFile=try LinkedArtworkRead.read(grant)
      try LinkedSmartObjectIO.replacement(next,fileName:nextFile.fileName,reference:nextFile.reference,in:original,layerID:id).apply(to:&expected)
      var code=try await helper.edit(service,document,"smartObject.linked.update",["layerID":id.uuidString]);XCTAssertEqual(code,200);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.maskEditingLayerID,id)
      store.linkedSourceController?.stop()
      code=try await helper.edit(service,document,"smartObject.linked.embed",["layerID":id.uuidString]);XCTAssertEqual(code,200);XCTAssertNil(store.activeLayer?.smartObject?.linkedSource);XCTAssertEqual(store.maskEditingLayerID,id)
      let embedded=store.document,hash=LinkedSmartObjectSource.fingerprint(next)
      code=try await helper.edit(service,document,"smartObject.linked.convert",["layerID":id.uuidString,"assetID":asset.uuidString,"fingerprint":hash]);XCTAssertEqual(code,200);XCTAssertEqual(store.document,expected)
      store.linkedSourceController?.stop();await store.undo();XCTAssertEqual(store.document,embedded)
      let relink=try await helper.edit(service,document,"smartObject.linked.relink",["layerID":id.uuidString,"assetID":asset.uuidString,"fingerprint":hash]);XCTAssertEqual(relink,200);XCTAssertEqual(store.document,expected)
      store.linkedSourceController?.stop();service.clearLinkedArtwork()
      code=try await helper.edit(service,document,"smartObject.linked.update",["layerID":id.uuidString]);XCTAssertEqual(code,403);XCTAssertEqual(store.document,expected)
    }
  }
  @MainActor func testReopenMissingSourceNeverFollowsDocumentPathAndCacheHydrationHasNoHistory()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let dir=try self.folder();defer{try? FileManager.default.removeItem(at:dir)}
      let url=dir.appendingPathComponent("source.png");try self.artwork().write(to:url)
      let store=document.store;store.onChange=nil;store.linkedSourceRegistry=LinkedSourceRegistry(persistent:false)
      let grant=try store.linkedSourceRegistry.authorize(url),file=try LinkedArtworkRead.read(grant),linked=try self.linkedFixture(file)
      let reopened=try NativeArchive.decode(NativeArchive.encodeChunked(linked));XCTAssertTrue(reopened.layers.last!.smartObject!.data.isEmpty)
      store.session=EditorSession(document:reopened);try service.share(document)
      let revision=reopened.layers.last!.smartObject!.revision,monitor=LinkedSourceController(store:store);store.linkedSourceController=monitor;defer{monitor.stop()}
      await monitor.scan();XCTAssertEqual(store.document,reopened);XCTAssertEqual(store.activeLayer?.smartObject?.data,file.data);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertEqual(store.activeLayer?.smartObject?.revision,revision)
      let foreign=LinkedSourceRegistry(persistent:false);store.linkedSourceRegistry=foreign
      await monitor.scan();XCTAssertEqual(store.document,reopened);XCTAssertEqual(monitor.state(reopened.layers.last!.smartObject!).status,.missing)
      XCTAssertThrowsError(try foreign.resolve(file.reference))
    }
  }
}
