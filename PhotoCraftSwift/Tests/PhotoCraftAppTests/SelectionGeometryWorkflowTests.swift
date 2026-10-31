import AppKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class SelectionGeometryWorkflowTests:XCTestCase {
  @MainActor func testMaximumSelectionOperationsShareDesktopHistoryAndNative64()async throws {
    var original=try CraftDocument(width:300000,height:300000)
    try Command.selectShape(.ellipse(.init(x:100,y:100,width:80,height:80)),.replace,true,0).apply(to:&original)
    let shape:[String:Any]=["ellipse":["x":299900,"y":299900,"width":80,"height":80]]
    let operations:[(String,[String:Any],Command)]=[
      ("selection.shape",["shape":shape,"mode":"add","antiAlias":true,"feather":2],.selectShape(.ellipse(.init(x:299900,y:299900,width:80,height:80)),.add,true,2)),
      ("selection.inverse",[:],.invertSelection),("selection.feather",["radius":3],.featherSelection(3))]
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      try service.share(document)
      for(name,parameters,command)in operations {
        document.store.session=EditorSession(document:original)
        var desktop=EditorSession(document:original);try desktop.execute(command)
        let status1=try await helper.edit(service,document,name,parameters)
        XCTAssertEqual(status1,200,name)
        await document.store.renderTask?.value;XCTAssertNil(document.store.error)
        XCTAssertEqual(document.store.document,desktop.document);XCTAssertEqual(document.store.session.undoStack.count,1)
        let changed=document.store.document,data=try NativeArchive.encode(changed)
        XCTAssertEqual(try NativeArchive.decodePaged(data),changed)
        let status2=try await helper.edit(service,document,"history.undo")
        XCTAssertEqual(status2,200)
        await document.store.renderTask?.value;XCTAssertNil(document.store.error);XCTAssertEqual(document.store.document,original)
        let status3=try await helper.edit(service,document,"history.redo")
        XCTAssertEqual(status3,200)
        await document.store.renderTask?.value;XCTAssertNil(document.store.error);XCTAssertEqual(document.store.document,changed)
      }
      document.store.session=EditorSession(document:original)
      let status4=try await helper.edit(service,document,"selection.shape",["shape":shape],revision:"stale")
      XCTAssertEqual(status4,409)
      document.store.geometryBusy=true
      let status5=try await helper.edit(service,document,"selection.inverse")
      XCTAssertEqual(status5,409)
      document.store.geometryBusy=false
      let status6=try await helper.edit(service,document,"selection.feather",["radius":101])
      XCTAssertEqual(status6,400)
      let status7=try await helper.edit(service,document,"selection.shape",["shape":["ellipse":["x":0,"y":0,"width":0,"height":80]]])
      XCTAssertEqual(status7,400)
      XCTAssertEqual(document.store.document,original)
      XCTAssertEqual(SelectionGeometryAPI.capabilities["maximumPixels"]as?Int,90_000_000_000)
    }
  }
  func testBoundedContoursPreserveExactViewportEdgesAndMaximumRectangle()throws {
    let mask=try SelectionMask.make(.ellipse(.init(x:299900,y:299900,width:80,height:80)),width:300000,height:300000)
    let path=try SelectionOutline.path(mask,region:.init(x:299880,y:299880,width:120,height:120)).path
    let local=try SelectionMask.make(.ellipse(.init(x:20,y:20,width:80,height:80)),width:120,height:120)
    var transform=CGAffineTransform(translationX:299880,y:299880)
    let reference=try XCTUnwrap(SelectionOutline.path(local).path.copy(using:&transform))
    XCTAssertEqual(path,reference)
    let full=try SelectionMask.make(.rectangle(.init(x:0,y:0,width:300000,height:300000)),width:300000,height:300000)
    XCTAssertEqual(try SelectionOutline.path(full).path.boundingBoxOfPath,CGRect(x:0,y:0,width:300000,height:300000))
    let inside=try SelectionOutline.path(full,region:.init(x:100,y:100,width:120,height:120)).path
    XCTAssertTrue(inside.isEmpty)
  }
}
