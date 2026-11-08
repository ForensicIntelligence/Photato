import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LargeModePSBWorkflowTests: XCTestCase {
  @MainActor func testLargeNativeFileAndHTTPImportShareComponentsHistoryAndPermissions() async throws {
    let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/PSBLargeComponents/independent-large-gray8.psb")
    let bytes=try Data(contentsOf:url),prepared=try PreparedLocalDocument.read(url,format:.automatic)
    XCTAssertNil(DocumentIO.persistenceIssue(prepared.model,format:.psb))
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,_ in
      defer {
        for case let owned as CraftNSDocument in service.controller.documents {
          owned.store.renderTask?.cancel();owned.updateChangeCount(.changeCleared)
          service.controller.removeDocument(owned);owned.close()
        }
      }
      service.setDocumentTransfersEnabled(true)
      // Match the actual native Open boundary, including the captured opening
      // policy. Raw codec decoding alone intentionally does not apply it.
      let desktop=try ColorPolicyInput.opening(prepared.model,settings:service.controller.colorSettings.value)
      let reference=try XCTUnwrap(desktop.layers.first?.nativeMode)
      @MainActor func upload() async throws -> (HTTPURLResponse,Data) {
        var request=URLRequest(url:try XCTUnwrap(URL(string:try XCTUnwrap(service.endpoint)+"/v1/documents/import")))
        request.httpMethod="POST";request.timeoutInterval=120;request.httpBody=bytes
        request.setValue("Bearer "+(try XCTUnwrap(service.token)),forHTTPHeaderField:"Authorization")
        request.setValue("application/x-photoshop",forHTTPHeaderField:"Content-Type")
        let (body,response)=try await URLSession.shared.data(for:request)
        return (try XCTUnwrap(response as? HTTPURLResponse),body)
      }
      let imported=try await upload();XCTAssertEqual(imported.0.statusCode,201,String(decoding:imported.1,as:UTF8.self))
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:imported.1) as? [String:Any]),id=try XCTUnwrap(state["id"] as? String)
      let document=try XCTUnwrap(service.shares.first{$0.id.uuidString == id}?.document)
      let before=document.store.document,native=try XCTUnwrap(before.layers.first?.nativeMode)
      XCTAssertEqual(native,reference);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let layerID=try XCTUnwrap(before.activeLayerID)
      let fields:[String:Any]=["layerID":layerID.uuidString,"component":0,"offset":8_394_752,"values":[0.5]]
      let stale=try await helper.edit(service,document,"mode.channel.write",fields,revision:"stale")
      XCTAssertEqual(stale,409);XCTAssertEqual(document.store.document,before)
      let edited=try await helper.edit(service,document,"mode.channel.write",fields)
      XCTAssertEqual(edited,200);XCTAssertNotEqual(document.store.document,before)
      XCTAssertEqual(document.store.document.layers[0].nativeMode?.rawWord(component:0,index:8_394_752),128)
      let undo=try await helper.edit(service,document,"history.undo")
      XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,before)
      let capabilities=try await helper.request(service,path:"/v1/capabilities")
      XCTAssertEqual(capabilities.0.statusCode,200)
      XCTAssertTrue(String(decoding:capabilities.1,as:UTF8.self).contains("pagedNativeComponents"))
      service.setDocumentTransfersEnabled(false)
      let revoked=try await upload();XCTAssertEqual(revoked.0.statusCode,403)
    }
  }
}
