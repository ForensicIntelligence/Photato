import AppKit
import Darwin
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LinkedPackageMergeTests:XCTestCase {
  @MainActor func initial()throws->(LinkedArtworkPackageTests.Fixture,PreparedLinkedPackage) {
    let f=try LinkedArtworkPackageTests().fixture()
    let output=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"existing"));try output.directory.commit();return(f,output)
  }
  func node(_ url:URL)throws->LinkedPackageNode{try XCTUnwrap(LinkedPackageNode.at(AT_FDCWD,url.path))}
  @MainActor func changed(_ original:LinkedArtworkPackageTests.Fixture)throws->LinkedArtworkPackageTests.Fixture {
    var f=original;let layer=f.document.layers[1],grant=try XCTUnwrap(f.grants[layer.smartObject!.sourceID])
    let data=try LinkedArtworkWorkflowTests().artwork(Pixel(0.15,0.85,0.25));try data.write(to:grant.url,options:.atomic)
    let read=try LinkedArtworkRead.read(grant)
    try LinkedSmartObjectIO.replacement(data,fileName:read.fileName,reference:read.reference,in:f.document,layerID:layer.id).apply(to:&f.document);return f
  }
  @MainActor func testMergePreservesUnrelatedInodesAttributesAndReusesIdenticalAssets()throws {
    let(f,old)=try initial();defer{try? FileManager.default.removeItem(at:f.folder)}
    let folder=old.folderURL,notes=folder.appendingPathComponent("Research/notes.txt"),shortcut=folder.appendingPathComponent("shortcut")
    try FileManager.default.createDirectory(at:notes.deletingLastPathComponent(),withIntermediateDirectories:true)
    let data=Data("Keep this research".utf8);try data.write(to:notes)
    try FileManager.default.setAttributes([.posixPermissions:0o640,.modificationDate:Date(timeIntervalSince1970:1_000_000)],ofItemAtPath:notes.path)
    try FileManager.default.createSymbolicLink(at:shortcut,withDestinationURL:notes)
    let beforeNotes=try node(notes),beforeLink=try node(shortcut),beforeRoot=try node(folder)
    let assets=try FileManager.default.contentsOfDirectory(at:folder.appendingPathComponent("Links"),includingPropertiesForKeys:nil)
    let beforeAssets=try Dictionary(uniqueKeysWithValues:assets.map{($0.lastPathComponent,try node($0))})
    let merged=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"existing",replaceExisting:true));try merged.directory.commit()
    XCTAssertTrue(merged.directory.updatedExisting);XCTAssertEqual(try node(notes),beforeNotes);XCTAssertEqual(try node(shortcut),beforeLink);XCTAssertTrue(try node(folder).sameFile(beforeRoot))
    for file in assets{XCTAssertEqual(try node(file),beforeAssets[file.lastPathComponent])}
    XCTAssertEqual(try Data(contentsOf:notes),data);XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.appendingPathComponent("Links").path).count,2)
    XCTAssertEqual(try Renderer.composite(DocumentIO.read(merged.documentURL)).rgbaData(depth:.u8),try Renderer.composite(f.document).rgbaData(depth:.u8))
  }
  @MainActor func testChangedSourceGetsNewNameAndOldSourcesAndUnknownInventoryStayIntact()throws {
    let(original,old)=try initial();defer{try? FileManager.default.removeItem(at:original.folder)}
    let oldSources=try Dictionary(uniqueKeysWithValues:old.sources.map{($0.name,try Data(contentsOf:old.folderURL.appendingPathComponent("Links/"+$0.name)))})
    let f=try changed(original)
    let output=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"existing",replaceExisting:true));try output.directory.commit()
    for(name,data)in oldSources{XCTAssertEqual(try Data(contentsOf:old.folderURL.appendingPathComponent("Links/"+name)),data)}
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:old.folderURL.appendingPathComponent("Links").path).count,3)
    let untouched=f.folder.appendingPathComponent("manual"),inventory=untouched.appendingPathComponent("package.json"),user=Data("A user inventory".utf8)
    try FileManager.default.createDirectory(at:untouched,withIntermediateDirectories:false);try user.write(to:inventory)
    let manual=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"manual",replaceExisting:true));try manual.directory.commit()
    XCTAssertEqual(try Data(contentsOf:inventory),user);XCTAssertEqual(manual.directory.manifestName,"package-2.json")
    XCTAssertTrue(FileManager.default.fileExists(atPath:manual.folderURL.appendingPathComponent(manual.directory.manifestName).path))
  }
  @MainActor func testDestinationChangesAndSymlinkDirectoriesNeverGetOverwritten()throws {
    let(f,old)=try initial();defer{try? FileManager.default.removeItem(at:f.folder)}
    let prepared=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"existing",replaceExisting:true))
    let user=Data("An intervening user edit".utf8);try user.write(to:old.documentURL,options:.atomic)
    XCTAssertThrowsError(try prepared.directory.commit());prepared.directory.discard();XCTAssertEqual(try Data(contentsOf:old.documentURL),user)
    let link=f.folder.appendingPathComponent("alias");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:old.folderURL)
    XCTAssertThrowsError(try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"alias",replaceExisting:true)))
    let other=f.folder.appendingPathComponent("links-alias");try FileManager.default.createDirectory(at:other,withIntermediateDirectories:false)
    try FileManager.default.createSymbolicLink(at:other.appendingPathComponent("Links"),withDestinationURL:old.folderURL.appendingPathComponent("Links"))
    XCTAssertThrowsError(try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"links-alias",replaceExisting:true)))
    XCTAssertEqual(try Data(contentsOf:old.documentURL),user)
  }
  @MainActor func testFailureAfterAssetsAndInventoryRollsBackBeforeDocumentCommit()throws {
    let(original,old)=try initial();defer{try? FileManager.default.removeItem(at:original.folder)}
    let document=try Data(contentsOf:old.documentURL),manifest=try Data(contentsOf:old.folderURL.appendingPathComponent("package.json"))
    let names=try FileManager.default.contentsOfDirectory(atPath:old.folderURL.appendingPathComponent("Links").path).sorted(),f=try changed(original),documentName=old.documentName
    let operations=LinkedPackageOperations(move:{a,b,c,d,flags in
      if d==documentName{errno=EIO;return -1};return LinkedPackageOperations.native.move(a,b,c,d,flags)
    })
    let prepared=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"existing",replaceExisting:true),operations:operations)
    XCTAssertThrowsError(try prepared.directory.commit());prepared.directory.discard()
    XCTAssertEqual(try Data(contentsOf:old.documentURL),document);XCTAssertEqual(try Data(contentsOf:old.folderURL.appendingPathComponent("package.json")),manifest)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:old.folderURL.appendingPathComponent("Links").path).sorted(),names)
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:f.folder.path).contains{$0.hasPrefix(".photato-package-")})
  }
  @MainActor func testConcurrentEditToPublishedAssetIsRetainedWithRecoveryData()throws {
    let(original,old)=try initial();defer{try? FileManager.default.removeItem(at:original.folder)}
    let before=try Data(contentsOf:old.documentURL),links=old.folderURL.appendingPathComponent("Links"),names=Set(try FileManager.default.contentsOfDirectory(atPath:links.path))
    let f=try changed(original),documentName=old.documentName,user=Data("Preserve this intervening edit".utf8)
    let operations=LinkedPackageOperations(move:{a,b,c,d,flags in
      if d==documentName {
        if let current=try? FileManager.default.contentsOfDirectory(atPath:links.path),let added=Set(current).subtracting(names).first{try? user.write(to:links.appendingPathComponent(added))}
        errno=EIO;return -1
      };return LinkedPackageOperations.native.move(a,b,c,d,flags)
    })
    let prepared=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"existing",replaceExisting:true),operations:operations)
    XCTAssertThrowsError(try prepared.directory.commit()){error in
      XCTAssertTrue(error is LinkedPackageRecoveryRequired);XCTAssertNotNil((error as? LinkedPackageRecoveryRequired)?.stagingName)
    };prepared.directory.discard()
    XCTAssertEqual(try Data(contentsOf:old.documentURL),before)
    let added=try XCTUnwrap(Set(FileManager.default.contentsOfDirectory(atPath:links.path)).subtracting(names).first)
    XCTAssertEqual(try Data(contentsOf:links.appendingPathComponent(added)),user)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:f.folder.path).contains{$0.hasPrefix(".photato-package-")})
  }
  @MainActor func testHTTPMergeIsExplicitPreservesHistoryAndReportsInventory()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,doc in
      let(f,old)=try self.initial();defer{try? FileManager.default.removeItem(at:f.folder)}
      let store=doc.store;store.onChange=nil;store.linkedSourceRegistry=f.registry;store.session=EditorSession(document:f.document)
      let source=f.folder.appendingPathComponent("source.photato");try NativeArchive.write(f.document,to:source);doc.fileURL=source;doc.fileType=CraftNSDocument.nativeType
      try service.share(doc);service.setDocumentSavesEnabled(true);service.setSaveDirectory(f.folder)
      for grant in f.grants.values{_ = try service.authorizeLinkedArtwork(grant.url,registry:f.registry)}
      var code=try await helper.edit(service,doc,"smartObject.linked.package",["name":"existing","format":"photato"]);XCTAssertEqual(code,409)
      code=try await helper.edit(service,doc,"smartObject.linked.package",["name":"existing","format":"photato","replace":"yes"]);XCTAssertEqual(code,400)
      let id=try XCTUnwrap(service.shares.first?.id)
      let(response,data)=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"smartObject.linked.package","revision":service.revision(store),"parameters":["name":"existing","format":"photato","replace":true]])
      XCTAssertEqual(response.statusCode,200);let result=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]);XCTAssertEqual(result["updatedExisting"]as?Bool,true);XCTAssertEqual(result["manifest"]as?String,"package.json")
      XCTAssertEqual(store.document,f.document);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertEqual(doc.fileURL,source)
      XCTAssertEqual(try Renderer.composite(DocumentIO.read(old.documentURL)).rgbaData(depth:.u8),try Renderer.composite(f.document).rgbaData(depth:.u8))
    }
  }
  @MainActor func testLinkedNativeSourceKeepsNativePackageAndRejectsPhotoshopFormats()throws {
    let f=try LinkedArtworkPackageTests().fixture();defer{try? FileManager.default.removeItem(at:f.folder)}
    let bytes=try NativeArchive.encodeChunked(CraftDocument(width:2,height:2)),file=f.folder.appendingPathComponent("Original.photato");try bytes.write(to:file)
    let grant=try f.registry.authorize(file),read=try LinkedArtworkRead.read(grant)
    var model=try CraftDocument(width:8,height:8);let layer=try LinkedSmartObjectIO.place(bytes,fileName:"Original.photato",reference:read.reference,in:model,fit:false);try Command.addLayer(layer).apply(to:&model)
    XCTAssertNotNil(DocumentIO.persistenceIssue(model,format:.psd));XCTAssertNotNil(DocumentIO.persistenceIssue(model,format:.psb))
    let prepared=try PreparedLinkedPackage.prepare(model,grants:[layer.smartObject!.sourceID:grant],parent:f.folder,options:.init(name:"native-source"));try prepared.directory.commit()
    XCTAssertEqual(try Data(contentsOf:prepared.folderURL.appendingPathComponent("Links/Original.photato")),bytes)
    XCTAssertThrowsError(try PreparedLinkedPackage.prepare(model,grants:[layer.smartObject!.sourceID:grant],parent:f.folder,options:.init(name:"invalid-psd",format:.psd)))
    XCTAssertFalse(FileManager.default.fileExists(atPath:f.folder.appendingPathComponent("invalid-psd").path))
  }
  @MainActor func testDocumentNameUsesFilesystemIdentityAndPreservesDistinctCaseEntries()throws {
    var f=try LinkedArtworkPackageTests().fixture();defer{try? FileManager.default.removeItem(at:f.folder)}
    f.document.name="Lower";let folder=f.folder.appendingPathComponent("case-test")
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
    let upper=folder.appendingPathComponent("LOWER.PHOTATO"),lower=folder.appendingPathComponent("Lower.photato"),user=Data("A separate case-sensitive file".utf8)
    try user.write(to:upper);let aliases=FileManager.default.fileExists(atPath:lower.path),upperBefore=try node(upper)
    let output=try PreparedLinkedPackage.prepare(f.document,grants:f.grants,parent:f.folder,options:.init(name:"case-test",replaceExisting:true));try output.directory.commit()
    XCTAssertEqual(output.documentName,aliases ? "LOWER.PHOTATO":"Lower.photato")
    if !aliases{XCTAssertEqual(try Data(contentsOf:upper),user);XCTAssertEqual(try node(upper),upperBefore)}
    XCTAssertNoThrow(try DocumentIO.read(output.documentURL))
    try f.registry.authorizePackage(folder,document:output.document,documentURL:output.documentURL)
    let aliasFolder=f.folder.appendingPathComponent("CASE-TEST")
    if FileManager.default.fileExists(atPath:aliasFolder.path) {
      let link=try XCTUnwrap(output.document.layers.compactMap(\.smartObject).first?.linkedSource)
      XCTAssertNoThrow(try f.registry.resolve(link,documentID:output.document.id,documentURL:aliasFolder.appendingPathComponent(output.documentName)))
    }
  }

}
