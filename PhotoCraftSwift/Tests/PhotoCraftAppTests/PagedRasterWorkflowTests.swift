import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PagedRasterWorkflowTests:XCTestCase {
  func ownedPNG()throws->Data {
    let width=8000,height=5000
    var raw=Data(count:width*height*4)
    raw.withUnsafeMutableBytes{(p:UnsafeMutableRawBufferPointer)in for y in 0..<height {for x in 0..<width {
      let at=(y*width+x)*4;p[at]=UInt8((x*13+y*3)%256);p[at+1]=UInt8((x*7+y*11)%256);p[at+2]=UInt8((x*5+y*17)%256);p[at+3]=255
    }}}
    let image=try XCTUnwrap(CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:RasterIO.colorSpace(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:CGDataProvider(data:raw as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
    let bytes=NSMutableData();let destination=try XCTUnwrap(CGImageDestinationCreateWithData(bytes,UTType.png.identifier as CFString,1,nil));CGImageDestinationAddImage(destination,image,nil);XCTAssertTrue(CGImageDestinationFinalize(destination));return bytes as Data
  }
  @MainActor func testHTTPDenseImportStateSharedPaintingAndHistory()async throws {
    let data=try ownedPNG(),helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service, original in
      service.setDocumentTransfersEnabled(true)
      var request=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/import")!)
      request.httpMethod="POST";request.timeoutInterval=120;request.httpBody=data
      request.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization")
      request.setValue("image/png",forHTTPHeaderField:"Content-Type")
      request.setValue("Owned dense API40MP",forHTTPHeaderField:"X-Photato-Name")
      let(response,header)=try await URLSession.shared.data(for:request)
      XCTAssertEqual((header as? HTTPURLResponse)?.statusCode,201,String(decoding:response.prefix(500),as:UTF8.self))
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:response)as?[String:Any])
      let id=try XCTUnwrap(state["id"]as?String)
      let document=try XCTUnwrap(service.shares.first{$0.id.uuidString==id}?.document)
      defer{document.store.renderTask?.cancel();service.controller.removeDocument(document)}
      XCTAssertEqual(document.store.document.width*document.store.document.height,40_000_000)
      let storage=try XCTUnwrap(state["rasterStorage"]as?[String:Any])
      XCTAssertGreaterThanOrEqual((storage["referencedMappedSampleBytes"]as?Int) ?? 0,640_000_000)
      XCTAssertLessThan((storage["heapEstimateBytes"]as?Int) ?? Int.max,16*1024*1024)
      XCTAssertGreaterThan((storage["referencedMappedIndexBytes"]as?Int) ?? 0,0)
      XCTAssertEqual(Set(storage.keys),Set((RasterStorageAPI.stateSchema["required"]as? [String]) ?? []))
      let baseline=document.store.document
      guard case .raster(let p)=baseline.layers[0].content else{return XCTFail("Missing raster")}
      for(x,y)in[(0,0),(2048,64),(7999,4999)]{XCTAssertEqual(p.pixel(x:x,y:y),Pixel(Float((x*13+y*3)%256)/255,Float((x*7+y*11)%256)/255,Float((x*5+y*17)%256)/255))}
      let parameters:[String:Any]=["points":[["x":4000,"y":2500],["x":4010,"y":2500]],"brush":["size":8,"color":["r":1,"g":0,"b":0,"a":1]]]
      let stale=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"paint.stroke","revision":"stale","parameters":parameters]);XCTAssertEqual(stale.0.statusCode,409)
      let current=service.revision(document.store)
      let painted=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"paint.stroke","revision":current,"parameters":parameters]);XCTAssertEqual(painted.0.statusCode,200)
      XCTAssertNotEqual(document.store.document,baseline)
      let undo=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"history.undo","revision":service.revision(document.store),"parameters":[:]]);XCTAssertEqual(undo.0.statusCode,200);XCTAssertEqual(document.store.document,baseline)
      let capabilities=try XCTUnwrap(AutomationService.documentTransferCapabilities["pagedRasterInput"]as?[String:Any]);XCTAssertEqual(capabilities["maximumImageIOConversionPatchPixels"]as?Int,131072)
    }
  }
}

extension PagedRasterWorkflowTests {
  @MainActor func testHTTPDenseNativeUploadAndFileOpenKeepMappedStorage()async throws {
    let png=try ownedPNG(),model=try RasterIO.read(png,name:"Owned native40MP")
    let bytes=try NativeArchive.encodeChunked(model,minimumVersion:63),helper=AutomationTests()
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:folder)}
    if let directory=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let capture=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:capture,withIntermediateDirectories:true)
      try bytes.write(to:capture.appendingPathComponent("Owned dense native63 40MP.photato"))
    }
    let file=folder.appendingPathComponent("owned.photato");try bytes.write(to:file)
    let desktop=try DocumentIO.readNative(file)
    XCTAssertEqual(desktop,model);XCTAssertGreaterThanOrEqual(desktop.mappedRasterBytes,640_000_000);XCTAssertLessThan(desktop.estimatedBytes,16*1024*1024)
    try await helper.withService(pressedMouseButtons:{0}) {service,_ in
      service.setDocumentTransfersEnabled(true)
      var request=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/import")!)
      request.httpMethod="POST";request.timeoutInterval=120;request.httpBody=bytes
      request.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization");request.setValue("application/vnd.photato.document",forHTTPHeaderField:"Content-Type")
      let(data,response)=try await URLSession.shared.data(for:request)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,201,String(decoding:data.prefix(500),as:UTF8.self))
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]),id=try XCTUnwrap(state["id"]as?String)
      let shared=try XCTUnwrap(service.shares.first{$0.id.uuidString==id}?.document)
      defer{shared.store.renderTask?.cancel();service.controller.removeDocument(shared)}
      XCTAssertEqual(shared.store.document,desktop);XCTAssertGreaterThanOrEqual(shared.store.document.mappedRasterBytes,640_000_000)
      let storage=try XCTUnwrap(state["rasterStorage"]as?[String:Any]);XCTAssertLessThan((storage["heapEstimateBytes"]as?Int) ?? Int.max,16*1024*1024)
      XCTAssertEqual(storage["referencedMappedIndexBytes"]as?Int,shared.store.document.mappedRasterIndexBytes)
      XCTAssertGreaterThan(shared.store.document.mappedRasterIndexBytes,0)
      let runtime=try XCTUnwrap((try XCTUnwrap(RasterStorageAPI.capabilities["nativePagedInput"]as?[String:Any]))["runtimeTileIndex"]as?[String:Any])
      XCTAssertEqual(runtime["minimumTiles"]as?Int,Surface.pagedIndexMinimumTiles)
      XCTAssertEqual(runtime["recordBytes"]as?Int,16);XCTAssertEqual(runtime["copyOnWriteLevels"]as?Int,4)
      let reuse=try XCTUnwrap((try XCTUnwrap(RasterStorageAPI.capabilities["nativePagedInput"]as?[String:Any]))["tileOrdinalReuse"]as?[String:Any])
      XCTAssertEqual(reuse["persistentForDecode"]as?Bool,true);XCTAssertEqual(reuse["recordBytes"]as?Int,8)
      XCTAssertEqual(reuse["frontCacheEntries"]as?Int,256)
      let parameters:[String:Any]=["points":[["x":4000,"y":2500]],"brush":["size":8,"color":["r":1,"g":0,"b":0,"a":1]]]
      let stale=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"paint.stroke","revision":"stale","parameters":parameters]);XCTAssertEqual(stale.0.statusCode,409)
      let edit=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"paint.stroke","revision":service.revision(shared.store),"parameters":parameters]);XCTAssertEqual(edit.0.statusCode,200);XCTAssertNotEqual(shared.store.document,desktop)
      let undo=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"history.undo","revision":service.revision(shared.store),"parameters":[:]]);XCTAssertEqual(undo.0.statusCode,200);XCTAssertEqual(shared.store.document,desktop)
      let capability=try XCTUnwrap(RasterStorageAPI.capabilities["nativePagedInput"]as?[String:Any]);XCTAssertEqual(capability["nativeFileMaximumBytes"]as?Int,NativeArchive.maximumFileBytes)
    }
  }
  @MainActor func testRepeatedNative63OrdinalsMatchDesktopAndHTTPImport() async throws {
    let unique=269
    var model=try CraftDocument(width:unique*64,height:192,depth:.f32)
    var surface=try Surface(width:model.width,height:model.height,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<3 {for x in 0..<unique {surface.setLinearPixel(x:x*64,y:y*64,Pixel(Float(x+1)/269,0.5,-0.0,1))}}
    model.layers[0].content = .raster(surface)
    let bytes=try NativeArchive.encodeChunked(model,minimumVersion:63)
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
    let file=folder.appendingPathComponent("owned-aliases.photato");try bytes.write(to:file)
    let desktop=try DocumentIO.readNative(file);XCTAssertEqual(desktop,model)
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,_ in
      service.setDocumentTransfersEnabled(true)
      var request=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/import")!)
      request.httpMethod="POST";request.httpBody=bytes;request.timeoutInterval=120
      request.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization")
      request.setValue("application/vnd.photato.document",forHTTPHeaderField:"Content-Type")
      let (data,response)=try await URLSession.shared.data(for:request)
      XCTAssertEqual((response as?HTTPURLResponse)?.statusCode,201,String(decoding:data.prefix(500),as:UTF8.self))
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]),id=try XCTUnwrap(state["id"]as?String)
      let shared=try XCTUnwrap(service.shares.first{$0.id.uuidString==id}?.document)
      defer{shared.store.renderTask?.cancel();service.controller.removeDocument(shared)}
      XCTAssertEqual(shared.store.document,desktop)
      guard case .raster(let imported)=shared.store.document.layers[0].content else {return XCTFail("Missing raster")}
      for y in 0..<3 {for x in 0..<unique {XCTAssertTrue(imported.linearPixel(x:x*64,y:y*64).hasSameBits(as:surface.linearPixel(x:x*64,y:y*64)))}}
    }
  }

}
