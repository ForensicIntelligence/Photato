import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PSDPagedWorkflowTests:XCTestCase {
  @MainActor func testCompressed40MPPSBUsesSharedPagedDesktopHTTPAndHistory() async throws {
    var model=try CraftDocument(width:8000,height:5000,depth:.u16)
    let surface=try Surface(width:8000,height:5000,depth:.u16,fill:Pixel(0.25,0.5,0.75,1))
    model.layers[0].content = .raster(surface)
    let bytes=try PSDCodec.writeRasterLayers(model,compression:.zipPrediction,format:.psb,compositeCompression:.zipPrediction)
    XCTAssertLessThan(bytes.count,DocumentIO.maximumUploadBytes)
    let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    let file=folder.appendingPathComponent("owned-compressed40mp.psb");try bytes.write(to:file)
    let desktop=try DocumentIO.read(file),upload=try DocumentIO.decodeUpload(bytes,native:false,name:"Owned40MP")
    guard case .raster(let p)=desktop.layers[0].content,case .raster(let q)=upload.layers[0].content else {return XCTFail("Raster")}
    XCTAssertEqual(p,q);XCTAssertGreaterThanOrEqual(upload.mappedRasterBytes,640_000_000)
    XCTAssertLessThan(upload.estimatedBytes,16*1024*1024)
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,_ in
      service.setDocumentTransfersEnabled(true)
      var request=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/import")!)
      request.httpMethod="POST";request.httpBody=bytes;request.timeoutInterval=120
      request.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization")
      request.setValue("application/x-photoshop",forHTTPHeaderField:"Content-Type")
      let(data,response)=try await URLSession.shared.data(for:request)
      XCTAssertEqual((response as?HTTPURLResponse)?.statusCode,201,String(decoding:data.prefix(500),as:UTF8.self))
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]),id=try XCTUnwrap(state["id"]as?String)
      let document=try XCTUnwrap(service.shares.first{$0.id.uuidString==id}?.document)
      defer{document.store.renderTask?.cancel();service.controller.removeDocument(document)}
      guard case .raster(let imported)=document.store.document.layers[0].content else {return XCTFail("Raster")}
      XCTAssertEqual(imported,p)
      let before=document.store.document
      let parameters:[String:Any]=["points":[["x":4000,"y":2500]],"brush":["size":8,"color":["r":1,"g":0,"b":0,"a":1]]]
      let stale=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"paint.stroke","revision":"stale","parameters":parameters]);XCTAssertEqual(stale.0.statusCode,409)
      let paint=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"paint.stroke","revision":service.revision(document.store),"parameters":parameters]);XCTAssertEqual(paint.0.statusCode,200)
      XCTAssertNotEqual(document.store.document,before)
      let undo=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"history.undo","revision":service.revision(document.store),"parameters":[:]]);XCTAssertEqual(undo.0.statusCode,200);XCTAssertEqual(document.store.document,before)
    }
  }
}
