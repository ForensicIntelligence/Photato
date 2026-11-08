import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PcraftLinkedOriginalWorkflowTests:XCTestCase {
  func fixture(_ name:String="referenced-affine-cached-u8.pcraft")throws->Data {
    try Data(contentsOf:Bundle.module.url(forResource:"Fixtures",withExtension:nil)!.appendingPathComponent("PcraftLinkedOriginals").appendingPathComponent(name))
  }
  @MainActor func testNativeOpenEditContentsUndoSaveAsRetainsExactOriginalArchive()async throws {
    _ = NSApplication.shared;let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    let bytes=try fixture(),url=folder.appendingPathComponent("Embedded reference.pcraft");try bytes.write(to:url)
    let prepared=try PreparedLocalDocument.read(url,format:.pcraft),parent=prepared.makeDocument(url:url),controller=CraftDocumentController(workspaces:WorkspaceLibrary());controller.addDocument(parent)
    defer{for doc in controller.documents{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
    let original=parent.store.document,source=try XCTUnwrap(parent.store.activeLayer?.smartObject)
    XCTAssertNil(parent.fileURL);XCTAssertEqual(parent.importedSourceURL,url);XCTAssertTrue(parent.store.canEditSmartObjectContents)
    parent.store.editSmartObjectContents();await parent.store.geometryTask?.value;XCTAssertNil(parent.store.error)
    let child=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0.smartObjectEditLink?.parent === parent})
    XCTAssertEqual(child.smartObjectEditLink?.sourceID,source.sourceID)
    let id=try XCTUnwrap(child.store.document.layers.last?.id);child.store.perform(.fill(id,Pixel(1,0,0)));try await child.commitSmartObjectContents()
    XCTAssertNotEqual(parent.store.activeLayer?.smartObject?.data,source.data);XCTAssertNil(parent.store.activeLayer?.pristineSmartAppearance)
    XCTAssertEqual(parent.store.document.sourceMetadata,original.sourceMetadata)
    let edited=parent.store.document,target=folder.appendingPathComponent("Migrated.photato")
    try await DocumentSaveWorkflowTests().save(parent,to:target,format:.native);XCTAssertEqual(try DocumentIO.read(target),edited)
    await parent.store.undo();XCTAssertEqual(parent.store.document,original);XCTAssertEqual(try Data(contentsOf:url),bytes)
  }
  @MainActor func testHTTPUploadSourceDownloadRasterizeUndoAndNativePersistenceShareImporter()async throws {
    let helper=AutomationTests(),opening=AutomationOpeningTests(),bytes=try fixture("referenced-shared-u16.pcraft")
    try await helper.withService(pressedMouseButtons:{0}){service,parent in
      defer{for doc in service.controller.documents where doc !== parent{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
      let denied=try await opening.upload(service,bytes:bytes,type:PcraftImport.mediaType,format:"pcraft");XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let accepted=try await opening.upload(service,bytes:bytes,type:PcraftImport.mediaType,format:"pcraft");XCTAssertEqual(accepted.0.statusCode,201,String(decoding:accepted.1,as:UTF8.self))
      let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),original=document.store.document,layer=try XCTUnwrap(original.layers.first),source=try XCTUnwrap(layer.smartObject)
      await document.store.renderTask?.value
      XCTAssertEqual(original,try PcraftImport.read(bytes));XCTAssertEqual(original.layers.count,2)
      XCTAssertEqual(original.layers[0].smartObject?.sourceID,original.layers[1].smartObject?.sourceID)
      let download=try await helper.request(service,path:"/v1/documents/\(share.id)/smart-objects/\(layer.id)/source")
      XCTAssertEqual(download.0.statusCode,200);XCTAssertEqual(download.1,source.data)
      let native=try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"70"])
      XCTAssertEqual(native.0.statusCode,200);XCTAssertEqual(try NativeArchive.decodePaged(native.1),original)
      let old=try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"69"]);XCTAssertEqual(old.0.statusCode,422)
      let raster=try await helper.edit(service,document,"layer.rasterize",["layerID":layer.id.uuidString]);XCTAssertEqual(raster,200);XCTAssertNil(document.store.document.layers.first{$0.id==layer.id}?.smartObject)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
      let invalid=try await opening.upload(service,bytes:PcraftSmartWorkflowTests().fixture("linked-cached","u16"),type:PcraftImport.mediaType,format:"pcraft")
      XCTAssertEqual(invalid.0.statusCode,422);XCTAssertEqual(service.shares.count,1);XCTAssertEqual(document.store.document,original)
      let pcraft=try XCTUnwrap(AutomationService.documentOpeningCapabilities["pcraft"]as?[String:Any]),cap=try XCTUnwrap(pcraft["linkedEmbeddedOriginals"]as?[String:Any])
      XCTAssertEqual(cap["supported"]as?Bool,true);XCTAssertEqual(cap["blocks"]as?[String],["lnk2","lnk3","lnkD","lnkE"])
      XCTAssertEqual(pcraft["adobe"]as?String,"Photato-only input format; Adobe v2 input contract is unchanged.")
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:pcraft));XCTAssertEqual(AutomationCommand.definitions.count,267)
      XCTAssertEqual(try self.fixture("referenced-shared-u16.pcraft"),bytes)
    }
  }
  @MainActor func testSharedChildEditsUpdateEveryReferenceAndUndoRetainsSourceIdentity()async throws {
    _ = NSApplication.shared;let input=try fixture("referenced-shared-u16.pcraft"),model=try PcraftImport.read(input),parent=CraftNSDocument(model:model)
    let controller=CraftDocumentController(workspaces:WorkspaceLibrary());controller.addDocument(parent)
    defer{for doc in controller.documents{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
    let source=try XCTUnwrap(parent.store.activeLayer?.smartObject);parent.store.editSmartObjectContents();await parent.store.geometryTask?.value
    let child=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0.smartObjectEditLink?.parent === parent})
    let id=try XCTUnwrap(child.store.document.layers.last?.id);child.store.perform(.fill(id,Pixel(0,1,0)));try await child.commitSmartObjectContents()
    XCTAssertEqual(parent.store.document.layers[0].smartObject?.data,parent.store.document.layers[1].smartObject?.data)
    XCTAssertNotEqual(parent.store.document.layers[0].smartObject?.data,source.data)
    XCTAssertTrue(parent.store.document.layers.allSatisfy{$0.smartObject?.sourceID==source.sourceID && $0.pristineSmartAppearance==nil})
    await parent.store.undo();XCTAssertEqual(parent.store.document,model);XCTAssertEqual(try fixture("referenced-shared-u16.pcraft"),input)
  }
}
