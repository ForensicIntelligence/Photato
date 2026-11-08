import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class HueRangeColorWorkflowTests:XCTestCase {
  func value()->HueSaturationAdjustment {
    var value=HueSaturationAdjustment()
    value.ranges[0]=HueRange(bounds:[-8,22,52,82],displayColor:.init(hue:37,saturation:65,lightness:50));return value
  }
  func model()throws->CraftDocument {
    var d=try CraftDocument(width:8,height:8)
    var layer=Layer(name:"Hue/Saturation",content:.adjustment(.hueSaturation(.init())))
    layer.mask=try Surface(width:8,height:8,fill:.white);d.layers.append(layer);d.activeLayerID=layer.id;return d
  }
  func raw(_ object:Any)throws->AutomationValue {try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:object))}
  func testSettingsSchemaStatePartialEditsClearAndInvalidColors()throws {
    let value=value(),base=Adjustment.hueSaturation(value),settings=AdjustmentBrushAPI.settings(base)
    let decoded=try AdjustmentBrushAPI.decode(raw(settings),kind:.hueSaturation,base:.hueSaturation(.init()))
    XCTAssertEqual(decoded,base)
    XCTAssertEqual(try AdjustmentBrushAPI.decode(raw(["master":["hue":27]]),kind:.hueSaturation,base:base),.hueSaturation({var x=value;x.master.hue=27;return x}()))
    var ranges=(settings as! [String:Any])["ranges"] as! [[String:Any]];ranges[0]["displayColor"]=NSNull()
    let cleared=try AdjustmentBrushAPI.decode(raw(["ranges":ranges]),kind:.hueSaturation,base:base)
    guard case .hueSaturation(let result)=cleared else{return XCTFail()};XCTAssertNil(result.ranges[0].displayColor)
    for color:[String:Any] in [["hue":361,"saturation":65,"lightness":50],["hue":37,"saturation":true,"lightness":50],["hue":37,"saturation":65,"lightness":50,"extra":0]] {
      ranges[0]["displayColor"]=color;XCTAssertThrowsError(try AdjustmentBrushAPI.decode(raw(["ranges":ranges]),kind:.hueSaturation,base:base))
    }
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AdjustmentBrushAPI.capabilities))
  }
  @MainActor func testHTTPNativeEqualityUndoStaleAndInvalidRequests()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let original=try self.model(),id=try XCTUnwrap(original.activeLayerID),value=self.value()
      let s=document.store;s.session=EditorSession(document:original);try service.share(document)
      let native=EditorStore(document:original,actions:ActionLibrary());defer{native.renderTask?.cancel()}
      native.setHueSaturation(id,value)
      let settings=AdjustmentBrushAPI.settings(.hueSaturation(value))
      let parameters:[String:Any]=["operation":"replace","layerID":id.uuidString,"kind":"hueSaturation","settings":settings]
      var status=try await helper.edit(service,document,"adjustmentBrush.edit",parameters)
      XCTAssertEqual(status,200);XCTAssertEqual(s.document,native.document);XCTAssertEqual(s.session.undoStack.count,1)
      let edited=s.document
      status=try await helper.edit(service,document,"adjustmentBrush.edit",parameters,revision:"stale")
      XCTAssertEqual(status,409);XCTAssertEqual(s.document,edited)
      var bad=parameters;var ranges=(settings as! [String:Any])["ranges"] as! [[String:Any]]
      ranges[0]["displayColor"]=["hue":37,"saturation":101,"lightness":50];bad["settings"]=["ranges":ranges]
      status=try await helper.edit(service,document,"adjustmentBrush.edit",bad)
      XCTAssertEqual(status,400);XCTAssertEqual(s.document,edited);XCTAssertEqual(s.session.undoStack.count,1)
      await s.undo();XCTAssertEqual(s.document,original);await s.redo();XCTAssertEqual(s.document,edited)
    }
  }
  @MainActor func testNative92DownloadsRequirePermissionAndNegotiation()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      var model=try self.model();model.layers[1].content = .adjustment(.hueSaturation(self.value()))
      document.store.session=EditorSession(document:model);try service.share(document)
      let path="/v1/documents/\(try XCTUnwrap(service.shares.first).id)/file.photato"
      let denied=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"92"])
      XCTAssertEqual(denied.0.statusCode,403);service.setDocumentTransfersEnabled(true)
      for headers in [[:],["X-Photato-Archive-Version":"91"]] {
        let response=try await helper.request(service,path:path,headers:headers)
        XCTAssertEqual(response.0.statusCode,422);XCTAssertEqual(document.store.document,model)
      }
      let (response,data)=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"92"])
      XCTAssertEqual(response.statusCode,200);XCTAssertEqual(try NativeArchive.decode(data),model)
    }
  }
  func testActions60KeepDisplayColorsAndRejectAnOlderDeclaration()throws {
    let v=Adjustment.hueSaturation(value())
    for op in [ActionOperation.adjustment(.active,v),.replaceAdjustment(.active,v),.addContent("Hue",.adjustment(v))] {
      let action=RecordedAction(name:"Sampled Hue",steps:[.init(name:"Hue",operation:op)])
      let file=ActionLibraryFile(actions:[action]);XCTAssertEqual(file.requiredVersion,60)
      let bytes=try file.encoded();let decoded=try ActionLibraryFile.decode(bytes)
      XCTAssertEqual(decoded.version,60);XCTAssertEqual(try decoded.encoded(),bytes)
      var old=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];old["version"]=59
      XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:old)))
    }
    let plain=ActionLibraryFile(actions:[RecordedAction(name:"Legacy",steps:[.init(name:"Hue",operation:.replaceAdjustment(.active,.hueSaturation(.init())))])])
    XCTAssertEqual(plain.requiredVersion,3)
  }
}
