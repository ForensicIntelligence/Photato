import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging
@testable import PhotoCraft

final class IndependentColorLookupWorkflowTests:XCTestCase {
  let names=["photoshop-rgb8-product2","photoshop-rgb8-product3","photoshop-rgb16-product2","photoshop-rgb16-product3","photoshop-rgb32-product2","photoshop-rgb32-product3","photoshop-rgb8-odd-product3"]
  func file(_ name:String,_ ext:String="psd")throws->Data {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/color-lookup-photoshop")
    return try Data(contentsOf:root.appendingPathComponent(name+"."+ext))
  }
  func source(_ name:String)throws->(CraftDocument,ColorLookupAdjustment) {
    var d=try PSDCodec.read(file(name))
    guard case .adjustment(.colorLookup(let value))=d.layers.removeLast().content else{throw CraftError.invalid("Missing independent lookup.")}
    d.activeLayerID=d.layers[0].id;return(d,value)
  }
  func merged(_ data:Data)throws->Data {
    var r=PSDReader(data:data);_=try r.bytes(12)
    let channels=try r.u16(),height=try r.u32(),width=try r.u32(),depth=try r.u16();_=try r.u16()
    for _ in 0..<3{_=try r.section()}
    return Data(try PSDChannelCodec.decode(r.bytes(r.remaining),width:width,height:height,depth:depth,channels:channels).prefix(width*height*3*(depth/8)))
  }
  func same(_ document:CraftDocument,_ name:String)throws {
    let encoded=try PSDCodec.writeRasterLayers(document,compression:.raw)
    XCTAssertEqual(try merged(encoded),try file(name,"merged"),name)
  }
  @MainActor func testNativeDialogAndEditablePropertiesMatchIndependentSamplesAndUndo()async throws {
    for name in names {
      let (original,value)=try source(name),s=EditorStore(document:original,actions:ActionLibrary(),brushes:BrushLibrary())
      defer{s.renderTask?.cancel()}
      s.beginColorLookup();XCTAssertEqual(s.colorLookupDraft?.adjustment.interpolation,.tetrahedral)
      s.colorLookupDraft?.adjustment=value;s.cancelColorLookup();await s.renderTask?.value
      XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
      s.beginColorLookup();s.colorLookupDraft?.adjustment=value;s.commitColorLookup();await s.geometryTask?.value
      XCTAssertNil(s.error);try same(s.document,name);XCTAssertEqual(s.session.undoStack.count,1)
      let destructive=s.document;_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,original)
      _=await s.requestHistory(redo:true).value;XCTAssertEqual(s.document,destructive)
      _=await s.requestHistory(redo:false).value
      s.addColorLookup();let id=try XCTUnwrap(s.activeLayer?.id)
      XCTAssertEqual(s.activeLayer?.content,.adjustment(.colorLookup(.photoshopDefault)))
      s.setColorLookup(id,value);await s.geometryTask?.value;XCTAssertNil(s.error);try same(s.document,name)
      XCTAssertEqual(s.activeLayer?.content,.adjustment(.colorLookup(value)))
      let encoded=try PSDCodec.writeRasterLayers(s.document,compression:.raw)
      XCTAssertEqual(try PSDCodec.read(encoded).layers.last?.content,s.activeLayer?.content)
      if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try encoded.write(to:URL(fileURLWithPath:folder).appendingPathComponent(name+"-fresh-native.psd"))
      }
      _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.activeLayer?.content,.adjustment(.colorLookup(.photoshopDefault)))
      _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,original)
    }
  }
  @MainActor func testExplicitHTTPCreateSetApplyAndTransfersMatchIndependentSamples()async throws {
    let helper=AutomationTests(),lookup=ColorLookupWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      try service.share(shared);service.setDocumentTransfersEnabled(true)
      for name in self.names {
        let (original,value)=try self.source(name),s=shared.store;s.renderTask?.cancel();s.session=EditorSession(document:original)
        let bytes=try XCTUnwrap(value.lut?.sourceData),filename=try XCTUnwrap(value.lut?.sourceFile)
        let upload=try await lookup.raw(service,path:"/v1/luts",data:bytes,name:filename)
        XCTAssertEqual(upload.0.statusCode,201)
        let data=try XCTUnwrap(JSONSerialization.jsonObject(with:upload.1)as?[String:Any]),lutID=try XCTUnwrap(data["lutID"]as?String)
        let parameters:[String:Any]=["kind":"colorLookup","lutID":lutID,"interpolation":"tetrahedral","dither":false]
        var status=try await helper.edit(service,shared,"adjustment.create",["adjustment":parameters]);XCTAssertEqual(status,200)
        try self.same(s.document,name);XCTAssertEqual(s.activeLayer?.content,.adjustment(.colorLookup(value)))
        let id=try XCTUnwrap(s.activeLayer?.id),share=try XCTUnwrap(service.shares.first?.id)
        let downloaded=try await helper.request(service,path:"/v1/documents/\(share)/layers/\(id)/lut")
        XCTAssertEqual(downloaded.0.statusCode,200);XCTAssertEqual(downloaded.1,bytes)
        let psd=try await helper.request(service,path:"/v1/documents/\(share)/file.psd")
        XCTAssertEqual(psd.0.statusCode,200);XCTAssertEqual(try self.merged(psd.1),try self.file(name,"merged"))
        let archive=try await helper.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":String(s.document.minimumArchiveVersion)])
        XCTAssertEqual(archive.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(archive.1),s.document)
        var changed=parameters;changed["dither"]=true
        status=try await helper.edit(service,shared,"adjustment.set",["layerID":id.uuidString,"adjustment":changed]);XCTAssertEqual(status,200)
        status=try await helper.edit(service,shared,"adjustment.set",["layerID":id.uuidString,"adjustment":parameters]);XCTAssertEqual(status,200);try self.same(s.document,name)
        for _ in 0..<3{_=try await helper.edit(service,shared,"history.undo")};XCTAssertEqual(s.document,original)
        status=try await helper.edit(service,shared,"adjustment.apply",["layerID":original.layers[0].id.uuidString,"adjustment":parameters]);XCTAssertEqual(status,200)
        try self.same(s.document,name);XCTAssertEqual(s.document.layers.count,1)
        _=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(s.document,original)
        _=try await lookup.raw(service,path:"/v1/luts/clear",data:Data())
      }
    }
  }
  @MainActor func testAdobeDescriptorAndBothJobRoutesMatchIndependentSamples()async throws {
    let transport=AutomationActionJobsTests.Transport(),jobs=AutomationActionJobsTests()
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport){service,shared in
      let untouched=shared.store.document
      for name in self.names {
        let (original,value)=try self.source(name),bytes=try XCTUnwrap(value.lut?.sourceData)
        let action:[String:Any]=["_obj":"colorLookup","lookupType":["_enum":"colorLookupType","_value":"3DLUT"],"LUTFormat":["_enum":"LUTFormatType","_value":"LUTFormatCUBE"],"dataOrder":["_enum":"colorLookupOrder","_value":"rgbOrder"],"tableOrder":["_enum":"colorLookupOrder","_value":"bgrOrder"],"LUT3DFileName":try XCTUnwrap(value.lut?.sourceFile),"LUT3DFileData":["_rawData":"base64","_data":bytes.base64EncodedString()],"dither":false]
        let json=String(decoding:try JSONSerialization.data(withJSONObject:[action]),as:UTF8.self)
        try self.same(PhotoshopActionProgram(actionJSON:json).applying(to:original).session.document,name)
        await transport.set(try PSDCodec.writeRasterLayers(original))
        let payload:[String:Any]=["image":["source":["url":"https://example.test/owned.psd"]],"options":["actions":[["source":["content":json,"contentType":"application/json"]]]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
        for route in ["/v2/execute-actions","/v1/action-jobs"] {
          service.setResourceJobsEnabled(false);service.setResourceJobsEnabled(true)
          let result=try await jobs.output(service,submit:route,payload:payload)
          XCTAssertEqual(try self.merged(result.2),try self.file(name,"merged"),name+route)
          XCTAssertEqual(try PSDCodec.read(result.2).layers.count,1)
        }
      }
      XCTAssertEqual(shared.store.document,untouched);XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
}
