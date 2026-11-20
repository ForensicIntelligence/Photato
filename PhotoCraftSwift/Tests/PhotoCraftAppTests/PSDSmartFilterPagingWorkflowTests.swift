import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PSDSmartFilterPagingWorkflowTests:XCTestCase {
  @MainActor func testLargeEditableStackNativeAndHTTPPSBRoundTrip()async throws {
    print("Large Smart Filter HTTP: start",Date())
    var model=try CraftDocument(width:6000,height:1500)
    try SmartObjectIO.convert(in:model,selected:[model.layers[0].id]).apply(to:&model)
    try Command.applyFilter(model.layers[0].id,RasterFilter(.highPass)).apply(to:&model)
    // Photoshop does not accept ZIP for the merged preview. Use an editable
    // compatibility-off PSB so the fixture fits the bounded HTTP upload.
    let data = try PSDCodec.writeRasterLayers(model, compression: .zipPrediction, format: .psb, maximizeCompatibility: false)
    XCTAssertLessThan(data.count,DocumentIO.maximumUploadBytes)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("photato-large-filter-http-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let file=directory.appendingPathComponent("Owned.psb");try data.write(to:file)
    let native=try DocumentIO.read(file),rect=IntRect(x:2990,y:745,width:23,height:13)
    try checkEditableStack(native)
    let expected=try Renderer.composite(native,region:rect).cropped(to:rect).rgbaData(depth:.f32)
    print("Large Smart Filter HTTP: native ready",Date())
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,_ in
      service.setDocumentTransfersEnabled(true)
      var request=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/import")!)
      request.httpMethod="POST";request.httpBody=data;request.timeoutInterval=180
      request.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization");request.setValue("application/x-photoshop",forHTTPHeaderField:"Content-Type")
      let(body,response)=try await URLSession.shared.data(for:request)
      print("Large Smart Filter HTTP: import returned",Date())
      XCTAssertEqual((response as?HTTPURLResponse)?.statusCode,201,String(decoding:body.prefix(500),as:UTF8.self))
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:body)as?[String:Any]),id=try XCTUnwrap(state["id"]as?String)
      let document=try XCTUnwrap(service.shares.first{$0.id.uuidString==id}?.document)
      defer{document.store.renderTask?.cancel();service.controller.removeDocument(document)}
      let actual=document.store.document
      try checkEditableStack(actual)
      XCTAssertEqual(try Renderer.composite(actual,region:rect).cropped(to:rect).rgbaData(depth:.f32),expected)
      var download=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/\(id)/file.psb")!)
      download.timeoutInterval=180;download.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization")
      let(downloaded,downloadResponse)=try await URLSession.shared.data(for:download)
      print("Large Smart Filter HTTP: download returned",Date())
      XCTAssertEqual((downloadResponse as?HTTPURLResponse)?.statusCode,200)
      let reopened=try PSDCodec.readPaged(downloaded)
      try checkEditableStack(reopened)
      XCTAssertEqual(try Renderer.composite(reopened,region:rect).cropped(to:rect).rgbaData(depth:.f32),expected)
      print("Large Smart Filter HTTP: complete",Date())
    }
  }

  private func checkEditableStack(_ document: CraftDocument, file: StaticString = #filePath, line: UInt = #line) throws {
    let layer = try XCTUnwrap(document.layers.first, file: file, line: line)
    let object = try XCTUnwrap(layer.smartObject, file: file, line: line)
    XCTAssertEqual(object.width, 6000, file: file, line: line)
    XCTAssertEqual(object.height, 1500, file: file, line: line)
    guard case .raster(let source) = layer.content else {
      return XCTFail("The editable Smart Object needs a raster source.", file: file, line: line)
    }
    XCTAssertEqual(source.tileCount, 0, file: file, line: line)
    XCTAssertEqual(source.defaultPixel, .white, file: file, line: line)
    let stack = try XCTUnwrap(layer.smartFilters, file: file, line: line)
    XCTAssertEqual(stack.filters.first?.filter.kind, .highPass, file: file, line: line)
    let mask = try XCTUnwrap(stack.mask, file: file, line: line)
    XCTAssertEqual(mask.tileCount, 0, file: file, line: line)
    XCTAssertEqual(mask.defaultPixel, .white, file: file, line: line)
  }
}
