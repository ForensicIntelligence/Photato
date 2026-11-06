import AppKit
import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class IndexedNativeWorkflowTests:XCTestCase {
  @MainActor func testNative63DownloadImportFileEquivalenceAndHistory()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      service.setDocumentTransfersEnabled(true);try service.share(document)
      let baseline=document.store.document,id=try XCTUnwrap(service.shares.first?.id.uuidString)
      var download=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/\(id)/file.photato")!)
      download.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization");download.setValue("63",forHTTPHeaderField:"X-Photato-Archive-Version")
      let(bytes,response)=try await URLSession.shared.data(for:download)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200,String(decoding:bytes.prefix(500),as:UTF8.self))
      XCTAssertEqual(try NativeArchive.decodePaged(bytes),baseline)
      let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
      let file=folder.appendingPathComponent("owned.photato");try bytes.write(to:file);XCTAssertEqual(try DocumentIO.readNative(file),baseline)
      var upload=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/import")!);upload.httpMethod="POST";upload.httpBody=bytes
      upload.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization");upload.setValue("application/vnd.photato.document",forHTTPHeaderField:"Content-Type")
      let(data,result)=try await URLSession.shared.data(for:upload);XCTAssertEqual((result as? HTTPURLResponse)?.statusCode,201,String(decoding:data.prefix(500),as:UTF8.self))
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]),newID=try XCTUnwrap(state["id"]as?String),shared=try XCTUnwrap(service.shares.first{$0.id.uuidString==newID}?.document)
      defer{shared.store.renderTask?.cancel();service.controller.removeDocument(shared)}
      XCTAssertEqual(shared.store.document,baseline)
      let parameters:[String:Any]=["points":[["x":3.5,"y":3.5]],"brush":["size":4,"color":["r":1,"g":0,"b":0,"a":1]]]
      let stale=try await helper.request(service,path:"/v1/documents/\(newID)/commands",body:["command":"paint.stroke","revision":"stale","parameters":parameters]);XCTAssertEqual(stale.0.statusCode,409)
      let edit=try await helper.request(service,path:"/v1/documents/\(newID)/commands",body:["command":"paint.stroke","revision":service.revision(shared.store),"parameters":parameters]);XCTAssertEqual(edit.0.statusCode,200);XCTAssertNotEqual(shared.store.document,baseline)
      let undo=try await helper.request(service,path:"/v1/documents/\(newID)/commands",body:["command":"history.undo","revision":service.revision(shared.store),"parameters":[:]]);XCTAssertEqual(undo.0.statusCode,200);XCTAssertEqual(shared.store.document,baseline)
      let capabilities=try XCTUnwrap(AutomationService.documentTransferCapabilities["nativeArchives"]as?[String:Any]);XCTAssertEqual(capabilities["hierarchicalIndexVersion"]as?Int,63);XCTAssertEqual(capabilities["readVersions"]as?[Int],Array(1...87))
      for version in 64...86 {
        download.setValue(String(version),forHTTPHeaderField:"X-Photato-Archive-Version")
        let(data,response)=try await URLSession.shared.data(for:download)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
        XCTAssertEqual(try NativeArchive.decodePaged(data),baseline)
      }
      download.setValue("87",forHTTPHeaderField:"X-Photato-Archive-Version");let(_,invalid)=try await URLSession.shared.data(for:download);XCTAssertEqual((invalid as? HTTPURLResponse)?.statusCode,400)
    }
  }
}
