import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LinkedArtworkPackageTests:XCTestCase {
  @MainActor struct Fixture {
    let folder:URL
    let registry:LinkedSourceRegistry
    var document:CraftDocument
    var grants:[UUID:LinkedArtworkGrant]
    var originals:[UUID:Data]
  }
  @MainActor func fixture()throws->Fixture {
    let folder=try LinkedArtworkWorkflowTests().folder(),registry=LinkedSourceRegistry(persistent:false)
    var document=try CraftDocument(width:16,height:12,name:"Package fixture"),grants:[UUID:LinkedArtworkGrant]=[:],originals:[UUID:Data]=[:]
    for (path,color)in [("a/shared.png",Pixel(0.8,0.2,0.1)),("b/SHARED.PNG",Pixel(0.2,0.5,0.8))] {
      let file=folder.appendingPathComponent(path);try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
      let bytes=try LinkedArtworkWorkflowTests().artwork(color);try bytes.write(to:file)
      let grant=try registry.authorize(file),read=try LinkedArtworkRead.read(grant)
      let layer=try LinkedSmartObjectIO.place(bytes,fileName:file.lastPathComponent,reference:read.reference,in:document,fit:false)
      grants[layer.smartObject!.sourceID]=grant;originals[layer.smartObject!.sourceID]=bytes;try Command.addLayer(layer).apply(to:&document)
    }
    var duplicate=document.layers.last!;duplicate.id=UUID();duplicate.name="Shared instance";try Command.addLayer(duplicate).apply(to:&document)
    return .init(folder:folder,registry:registry,document:document,grants:grants,originals:originals)
  }
  @MainActor func testNativePSDAndPSBPackagesRetainOriginalsRelativeReferencesAndSharedFiles()throws {
    let f=try fixture();defer{try? FileManager.default.removeItem(at:f.folder)}
    for format:DocumentIO.Format in [.native,.psd,.psb] {
      let prepared=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"package-"+format.rawValue,format:format))
      XCTAssertFalse(FileManager.default.fileExists(atPath:prepared.folderURL.path));try prepared.directory.commit()
      let files=try FileManager.default.contentsOfDirectory(at:prepared.folderURL.appendingPathComponent("Links"),includingPropertiesForKeys:nil)
      XCTAssertEqual(files.count,2);XCTAssertEqual(Set(files.map{$0.lastPathComponent.lowercased()}).count,2)
      for source in prepared.sources{XCTAssertEqual(try Data(contentsOf:prepared.folderURL.appendingPathComponent("Links/"+source.name)),f.originals[source.sourceID])}
      let decoded=try DocumentIO.read(prepared.documentURL)
      XCTAssertEqual(decoded.layers.filter{$0.smartObject != nil}.count,3)
      for source in decoded.layers.compactMap(\.smartObject){XCTAssertTrue(source.linkedSource!.reference.hasPrefix("Links/"));XCTAssertNil(source.linkedSource!.authorizationID);XCTAssertTrue(source.data.isEmpty)}
      try f.registry.authorizePackage(prepared.folderURL,document:prepared.document,documentURL:prepared.documentURL)
      for object in decoded.layers.compactMap(\.smartObject){XCTAssertNoThrow(try f.registry.resolve(object.linkedSource!,documentID:decoded.id,documentURL:prepared.documentURL))}
      if format == .native {XCTAssertEqual(try Renderer.composite(decoded).rgbaData(depth:.u8),try Renderer.composite(f.document).rgbaData(depth:.u8))}
      let manifest=try Data(contentsOf:prepared.folderURL.appendingPathComponent("package.json"));XCTAssertFalse(String(decoding:manifest,as:UTF8.self).contains(f.folder.path))
    }
  }
  @MainActor func testPackageFolderAuthorizationSurvivesMoveAndRejectsUnapprovedCopies()throws {
    let f=try fixture();defer{try? FileManager.default.removeItem(at:f.folder)}
    let prepared=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"portable"));try prepared.directory.commit()
    let linked=prepared.document.layers.compactMap(\.smartObject).first!.linkedSource!
    XCTAssertThrowsError(try f.registry.resolve(linked,documentID:prepared.document.id,documentURL:prepared.documentURL))
    try f.registry.authorizePackage(prepared.folderURL,document:prepared.document,documentURL:prepared.documentURL)
    let grant=try f.registry.resolve(linked,documentID:prepared.document.id,documentURL:prepared.documentURL)
    XCTAssertEqual(try LinkedArtworkRead.read(grant).reference.reference,linked.reference)
    let moved=f.folder.appendingPathComponent("moved");try FileManager.default.moveItem(at:prepared.folderURL,to:moved)
    let movedDoc=moved.appendingPathComponent(prepared.documentName)
    XCTAssertEqual(try LinkedArtworkRead.read(f.registry.resolve(linked,documentID:prepared.document.id,documentURL:movedDoc)).fingerprint,linked.contentHash)
    let copy=f.folder.appendingPathComponent("unapproved-copy");try FileManager.default.copyItem(at:moved,to:copy)
    XCTAssertThrowsError(try f.registry.resolve(linked,documentID:prepared.document.id,documentURL:copy.appendingPathComponent(prepared.documentName)))
    try f.registry.authorizePackage(copy,document:prepared.document,documentURL:copy.appendingPathComponent(prepared.documentName))
    XCTAssertNoThrow(try f.registry.resolve(linked,documentID:prepared.document.id,documentURL:copy.appendingPathComponent(prepared.documentName)))
  }
  @MainActor func testExistingDestinationSourceChangesAndDiscardPreserveFiles()throws {
    let f=try fixture();defer{try? FileManager.default.removeItem(at:f.folder)}
    let destination=f.folder.appendingPathComponent("existing");try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
    let user=destination.appendingPathComponent("keep.txt"),bytes=Data("user-owned content".utf8);try bytes.write(to:user)
    do{let prepared=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"existing"));XCTAssertThrowsError(try prepared.directory.commit())}
    XCTAssertEqual(try Data(contentsOf:user),bytes)
    do{let prepared=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"cancelled"));prepared.directory.discard()}
    XCTAssertFalse(FileManager.default.fileExists(atPath:f.folder.appendingPathComponent("cancelled").path))
    let source=f.grants.values.first!;try Data("modified original".utf8).write(to:source.url,options:.atomic)
    XCTAssertThrowsError(try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"changed")))
    XCTAssertFalse(FileManager.default.fileExists(atPath:f.folder.appendingPathComponent("changed").path))
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:f.folder.path).contains{$0.hasPrefix(".photato-package-")})
  }
  @MainActor func testMaximumLogicalNativeCanvasPackageHasNoDenseDocumentLimit()throws {
    var f=try fixture();defer{try? FileManager.default.removeItem(at:f.folder)}
    var maximum=try CraftDocument(width:300_000,height:300_000,name:"Maximum canvas")
    for layer in f.document.layers.dropFirst(){try Command.addLayer(layer).apply(to:&maximum)};f.document=maximum
    let output=try PreparedLinkedPackage.prepare(maximum,grants:f.grants,parent:f.folder,options:.init(name:"maximum"));try output.directory.commit()
    let reopened=try DocumentIO.read(output.documentURL);XCTAssertEqual(reopened.width,300_000);XCTAssertEqual(reopened.height,300_000);XCTAssertEqual(reopened.layers.count,4)
  }
  @MainActor func testNativeEmbedAllAndRevokedPackagePublicationKeepAtomicHistory()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){_,doc in
      let f=try self.fixture();defer{try? FileManager.default.removeItem(at:f.folder)}
      let store=doc.store;store.onChange=nil;store.linkedSourceRegistry=f.registry;store.session=EditorSession(document:f.document)
      let source=f.folder.appendingPathComponent("input.photato");try NativeArchive.write(f.document,to:source);doc.fileURL=source;doc.fileType=CraftNSDocument.nativeType
      XCTAssertTrue(store.canPackageLinkedArtwork)
      do{_ = try await store.publishLinkedPackage(parent:f.folder,options:.init(name:"revoked"),grants:f.grants,validatePublication:{throw AutomationFailure(status:409,message:"Revoked")});XCTFail("Revoked output published")}catch{}
      XCTAssertFalse(FileManager.default.fileExists(atPath:f.folder.appendingPathComponent("revoked").path));XCTAssertEqual(store.document,f.document);XCTAssertTrue(store.session.undoStack.isEmpty)
      store.embedAllLinkedArtwork();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertFalse(store.geometryBusy);XCTAssertEqual(store.session.undoStack.count,1)
      XCTAssertFalse(store.hasLinkedArtwork);await store.undo();XCTAssertEqual(store.document,f.document);store.linkedSourceController?.stop()
    }
  }
  @MainActor func testHTTPPackagePermissionsNativeEquivalenceAndEmbedAllContext()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,doc in
      var f=try self.fixture();defer{try? FileManager.default.removeItem(at:f.folder)}
      f.document.layers[f.document.layers.count-1].mask=try Surface(width:f.document.width,height:f.document.height,fill:.white)
      let store=doc.store;store.onChange=nil;store.linkedSourceRegistry=f.registry;store.session=EditorSession(document:f.document)
      let saved=f.folder.appendingPathComponent("input.photato");try NativeArchive.write(f.document,to:saved);doc.fileURL=saved;doc.fileType=CraftNSDocument.nativeType;try service.share(doc)
      var code=try await helper.edit(service,doc,"smartObject.linked.package",["name":"api","format":"photato"]);XCTAssertEqual(code,403)
      service.setDocumentSavesEnabled(true);service.setSaveDirectory(f.folder)
      code=try await helper.edit(service,doc,"smartObject.linked.package",["name":"api","format":"photato"]);XCTAssertEqual(code,403)
      for grant in f.grants.values{_ = try service.authorizeLinkedArtwork(grant.url,registry:f.registry)}
      let original=store.document,history=store.session.undoStack.count
      code=try await helper.edit(service,doc,"smartObject.linked.package",["name":"api","format":"photato"]);XCTAssertEqual(code,200)
      XCTAssertEqual(store.document,original);XCTAssertEqual(store.session.undoStack.count,history)
      let package=f.folder.appendingPathComponent("api"),names=try FileManager.default.contentsOfDirectory(atPath:package.path)
      let output=try XCTUnwrap(names.first{$0.hasSuffix(".photato")});let reopened=try DocumentIO.read(package.appendingPathComponent(output))
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth:.u8),try Renderer.composite(original).rgbaData(depth:.u8))
      code=try await helper.edit(service,doc,"smartObject.linked.package",["name":"api","format":"photato"]);XCTAssertEqual(code,409)
      for invalid:[String:Any] in [["name":"../escape","format":"photato"],["name":"x","format":"png"],["name":"x","format":"photato","path":f.folder.path]] {
        code=try await helper.edit(service,doc,"smartObject.linked.package",invalid);XCTAssertEqual(code,400)
      }
      code=try await helper.edit(service,doc,"smartObject.linked.package",["name":"stale","format":"photato"],revision:"old");XCTAssertEqual(code,409)
      store.maskEditingLayerID=store.activeLayer!.id;let target=store.maskEditingLayerID
      code=try await helper.edit(service,doc,"smartObject.linked.embedAll");XCTAssertEqual(code,200);XCTAssertEqual(store.maskEditingLayerID,target);XCTAssertFalse(store.hasLinkedArtwork)
      await store.undo();XCTAssertEqual(store.document,original);store.linkedSourceController?.stop()
    }
  }
}
