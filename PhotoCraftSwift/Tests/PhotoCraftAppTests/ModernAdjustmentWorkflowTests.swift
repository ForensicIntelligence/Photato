import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ModernAdjustmentWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:13,height:9)
    var pixels=try Surface(width:13,height:9)
    for y in 0..<9 {for x in 0..<13 {pixels.setPixel(x:x,y:y,Pixel(Float(x+1)/15,Float(y+1)/11,Float(x+y+1)/24))}}
    d.layers[0].content = .raster(pixels)
    return d
  }
  func edited(_ kind:ModernAdjustment.Kind)->ModernAdjustment {
    var value=ModernAdjustment(kind)
    value.values[kind.keys[0]]=kind == .light ? 0.5:35
    if kind == .light {value.values["shadows"]=20;value.values["highlights"] = -10}
    return value
  }
  @MainActor func testNativeLivePropertiesHistoryMaskLockAndActions22()async throws {
    for kind in ModernAdjustment.Kind.allCases {
      var source=try fixture();source.selection = .init(x:3,y:2,width:5,height:4)
      let store=EditorStore(document:source)
      defer {store.renderTask?.cancel()}
      XCTAssertTrue(store.canAddModernAdjustment(kind))
      store.addModernAdjustment(kind)
      let id=try XCTUnwrap(store.document.activeLayerID),created=store.document
      XCTAssertEqual(store.activeLayer?.mask?.pixel(x:0,y:0),.black)
      store.setModernAdjustment(id,edited(kind));await store.renderTask?.value
      XCTAssertNil(store.error);XCTAssertNotNil(store.image)
      XCTAssertEqual(store.document.layers.first(where:{$0.id==source.layers[0].id})?.content,source.layers[0].content)
      let changed=store.document
      await store.undo();XCTAssertEqual(store.document,created)
      await store.redo();XCTAssertEqual(store.document,changed)
      var library=ActionLibraryFile()
      library.actions=[RecordedAction(name:"Modern",steps:[RecordedActionStep(name:kind.title,operation:.addContent(kind.title,.adjustment(.modern(edited(kind)))))] )]
      XCTAssertEqual(library.requiredVersion,22)
      let file=try ActionLibraryFile.decode(library.encoded());XCTAssertEqual(file.version,22)
      var replay=source;try file.actions[0].apply(to:&replay)
      XCTAssertTrue(replay.layers.contains{if case .adjustment(.modern(let value))=$0.content{return value.kind==kind};return false})
      store.perform(.lock(id,true));let locked=store.document
      store.setModernAdjustment(id,.init(kind));XCTAssertEqual(store.document,locked)
    }
  }
  @MainActor func testHTTPCreateSetStateNative65AndBusyStaleInvalidCases()async throws {
    let helper=AutomationTests()
    for kind in ModernAdjustment.Kind.allCases {
      try await helper.withService(pressedMouseButtons:{0}) {service,shared in
        let source=try self.fixture();shared.store.session=EditorSession(document:source)
        defer {shared.store.renderTask?.cancel()}
        try service.share(shared);service.setDocumentTransfersEnabled(true)
        let value=self.edited(kind),parameters:[String:Any]=["adjustment":value.apiObject]
        let created=try await helper.edit(service,shared,"adjustment.create",parameters);XCTAssertEqual(created,200)
        let id=try XCTUnwrap(shared.store.document.activeLayerID),before=shared.store.document
        XCTAssertEqual(before.minimumArchiveVersion,65)
        XCTAssertEqual(before.layers.first(where:{$0.id==source.layers[0].id})?.content,source.layers[0].content)
        let set:[String:Any]=["layerID":id.uuidString,"adjustment":ModernAdjustment(kind).apiObject]
        let stale=try await helper.edit(service,shared,"adjustment.set",set,revision:"stale");XCTAssertEqual(stale,409)
        shared.store.geometryBusy=true
        let busy=try await helper.edit(service,shared,"adjustment.set",set);XCTAssertEqual(busy,409)
        shared.store.geometryBusy=false
        let invalid=try await helper.edit(service,shared,"adjustment.set",["layerID":id.uuidString,"adjustment":["kind":kind.rawValue,"values":[kind.keys[0]:true]]]);XCTAssertEqual(invalid,400)
        XCTAssertEqual(shared.store.document,before)
        let shareID=try XCTUnwrap(service.shares.first?.id)
        let state=try await helper.request(service,path:"/v1/documents/\(shareID)")
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:state.1) as? [String:Any])
        let rows=try XCTUnwrap(json["layers"] as? [[String:Any]])
        let row=try XCTUnwrap(rows.first{($0["id"] as? String)==id.uuidString})
        XCTAssertEqual((row["modernAdjustment"] as? [String:Any])?["kind"] as? String,kind.rawValue)
        let denied=try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato");XCTAssertEqual(denied.0.statusCode,422)
        let archive=try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"65"])
        XCTAssertEqual(archive.0.statusCode,200)
        XCTAssertEqual(try NativeArchive.decodePaged(archive.1),before)
        let psd=try await helper.request(service,path:"/v1/documents/\(shareID)/file.psd");XCTAssertEqual(psd.0.statusCode,422)
        XCTAssertEqual(shared.store.document,before)
        let updated=try await helper.edit(service,shared,"adjustment.set",set);XCTAssertEqual(updated,200)
        let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,before)
        var expected=before
        try Command.applyAdjustment(source.layers[0].id,.modern(value)).apply(to:&expected)
        let applied=try await helper.edit(service,shared,"adjustment.apply",["layerID":source.layers[0].id.uuidString,"adjustment":value.apiObject])
        XCTAssertEqual(applied,200);XCTAssertEqual(shared.store.document,expected)
        let restored=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(restored,200);XCTAssertEqual(shared.store.document,before)
      }
    }
  }
  func testPublishedEditFieldsShareNativeModernTransfersWithoutInventedLayerTypes()throws {
    let input=try PSDCodec.writeRasterLayers(fixture())
    for kind in [ModernAdjustment.Kind.colorVibrance,.light,.clarityDehaze] {
      let value=edited(kind)
      let fields:[String:Any]=Dictionary(uniqueKeysWithValues:value.values.map{($0.key,$0.value as Any)})
      let edits:[String:Any]
      if kind == .colorVibrance {edits=["color":["vibrance":35]]}
      else {edits=[kind == .light ? "light":"effects":fields]}
      // The published Color object has no numeric temperature/tint fields.
      var nativeValue=value
      if kind == .colorVibrance {nativeValue.values["temperature"]=0;nativeValue.values["vibrance"]=35}
      let body:[String:Any]=["image":["source":["url":"https://example.test/owned.psd"]],"edits":edits,"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
      let request=try AdobeColorEditRequest(data:JSONSerialization.data(withJSONObject:body))
      var native=try AdobeActionAssets.decode(input)
      try Command.addLayer(nativeValue.layer(in:native)).apply(to:&native)
      let actual=try XCTUnwrap(request.execute(input:input).first).data
      XCTAssertEqual(actual,try DocumentIO.encode(native,format:.png),"Published \(kind) fields must use the shared native transfer.")
    }
  }
  @MainActor func testDocumentedMenusSchemaAndModeAvailabilityKeepLegacyEntries()throws {
    try PhotoshopMenuTests().withMenus {_,menu in
      let items=PhotoshopMenuTests().allItems(menu)
      for title in ["Color and vibrance…","Light…","Clarity and dehaze…","Grain…"] {
        let path="Layer > New Adjustment Layer > "+title
        XCTAssertNotNil(items.first{$0.identifier?.rawValue==path}?.action)
      }
    }
    let hdr=EditorStore(document:try CraftDocument(width:32,height:32,depth:.f32));defer{hdr.renderTask?.cancel()}
    XCTAssertFalse(hdr.canAddModernAdjustment(.light))
    XCTAssertTrue(hdr.canAddModernAdjustment(.colorVibrance))
    let cap=try XCTUnwrap(AutomationService.capabilities["modernAdjustments"] as? [String:Any])
    XCTAssertEqual(cap["nativeArchiveVersion"] as? Int,65)
    XCTAssertEqual((cap["defaults"] as? [[String:Any]])?.count,4)
    XCTAssertEqual((ModernAdjustment.apiSchema["oneOf"] as? [[String:Any]])?.count,4)
  }
}
