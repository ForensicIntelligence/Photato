import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor SourceWriteGate {
  var entered=false
  func mark(){entered=true}
}
final class LinkedSourceFileEditingTests:XCTestCase {
  func bytes(_ color:Pixel=Pixel(0.8,0.1,0.2))throws->Data {try LinkedArtworkWorkflowTests().artwork(color)}
  @MainActor func setup(_ service:AutomationService,_ parent:CraftNSDocument,data:Data?=nil,name:String="Source.png")async throws->(URL,UUID,UUID) {
    let dir=try LinkedArtworkWorkflowTests().folder(),url=dir.appendingPathComponent(name),data=try data ?? bytes();try data.write(to:url)
    let store=parent.store;store.onChange=nil;store.linkedSourceRegistry=LinkedSourceRegistry(persistent:false);try service.share(parent)
    let asset=try service.authorizeLinkedArtwork(url,registry:store.linkedSourceRegistry)
    let code=try await AutomationTests().edit(service,parent,"smartObject.linked.place",["assetID":asset.uuidString,"fingerprint":LinkedSmartObjectSource.fingerprint(data),"fit":false]);XCTAssertEqual(code,200)
    store.linkedSourceController?.stop();return(dir,asset,try XCTUnwrap(store.activeLayer?.id))
  }
  @MainActor func path(_ service:AutomationService,_ layerID:UUID)throws->String {
    "/v1/documents/\(try XCTUnwrap(service.shares.first?.id))/smart-objects/\(layerID)/linked-source"
  }
  @MainActor func upload(_ service:AutomationService,_ parent:CraftNSDocument,_ layerID:UUID,_ data:Data,
    hash:String?=nil,revision:String?=nil)->URLRequest {
    var request=URLRequest(url:URL(string:service.endpoint!+(try! path(service,layerID)))!);request.httpMethod="POST";request.httpBody=data;request.timeoutInterval=10
    request.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization");request.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
    request.setValue(revision ?? service.revision(parent.store),forHTTPHeaderField:"X-Photato-Revision")
    if let hash{request.setValue(LinkedSourceFileAPI.etag(hash),forHTTPHeaderField:"If-Match")};return request
  }
  @MainActor func send(_ request:URLRequest)async throws->(HTTPURLResponse,[String:Any]) {
    try decode(try await URLSession.shared.data(for:request))
  }
  @MainActor private func decode(_ value:(Data,URLResponse))throws->(HTTPURLResponse,[String:Any]) {
    let(data,response)=value
    return(try XCTUnwrap(response as?HTTPURLResponse),(try? JSONSerialization.jsonObject(with:data)as?[String:Any]) ?? [:])
  }
  @MainActor private func wait(_ gate:SourceWriteGate)async throws {
    for _ in 0..<200 {if await gate.entered{return};try await Task.sleep(for:.milliseconds(5))};XCTFail("Source worker did not reach the controlled phase.")
  }
  func testConditionalHeadersAndBoundedHTTPResponseMetadata()throws {
    let hash=String(repeating:"a",count:64);XCTAssertEqual(try LinkedSourceFileAPI.fingerprint(LinkedSourceFileAPI.etag(hash)),hash)
    for invalid in ["*","W/\"\(hash)\"",hash,"\""+String(repeating:"A",count:64)+"\""]{XCTAssertThrowsError(try LinkedSourceFileAPI.fingerprint(invalid))}
    XCTAssertThrowsError(try LinkedSourceFileAPI.fingerprint(nil))
    let path="/v1/documents/\(UUID())/smart-objects/\(UUID())/linked-source"
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:path),SmartObject.maximumSourceBytes)
    XCTAssertThrowsError(try AutomationRequest.parse(Data("POST \(path) HTTP/1.1\r\nContent-Length: \(SmartObject.maximumSourceBytes+1)\r\n\r\n".utf8)))
    let response=AutomationResponse(status:200,contentType:"application/octet-stream",body:Data([1]),headers:["ETag":LinkedSourceFileAPI.etag(hash),"Content-Length":"999","X-Injected":"bad\r\nInjected: yes"])
    let wire=String(decoding:response.wire,as:UTF8.self);XCTAssertTrue(wire.contains("ETag: \"\(hash)\""));XCTAssertTrue(wire.contains("Content-Length: 1\r\n"));XCTAssertFalse(wire.contains("999"));XCTAssertFalse(wire.contains("Injected: yes"));XCTAssertFalse(wire.contains("Access-Control-Allow-Origin"))
    XCTAssertTrue(JSONSerialization.isValidJSONObject(LinkedSourceFileAPI.capabilities))
  }
  @MainActor func testCurrentOriginalDownloadAndNativeWritePermissionLifecycle()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let(dir,asset,id)=try await self.setup(service,parent);defer{try? FileManager.default.removeItem(at:dir)}
      let path=try self.path(service,id),old=try self.bytes(),new=try self.bytes(Pixel(0.1,0.8,0.2)),original=parent.store.document
      let first=try await AutomationTests().request(service,path:path);XCTAssertEqual(first.0.statusCode,200);XCTAssertEqual(first.1,old);XCTAssertEqual(first.0.value(forHTTPHeaderField:"ETag"),LinkedSourceFileAPI.etag(LinkedSmartObjectSource.fingerprint(old)))
      try new.write(to:dir.appendingPathComponent("Source.png"),options:.atomic)
      let fresh=try await AutomationTests().request(service,path:path);XCTAssertEqual(fresh.1,new);XCTAssertEqual(parent.store.document,original)
      let legacy=try await AutomationTests().request(service,path:path.replacingOccurrences(of:"linked-source",with:"source"));XCTAssertEqual(legacy.1,old)
      XCTAssertFalse(service.linkedArtworkWritableAssets.contains(asset));service.setLinkedArtworkWritable(asset,enabled:true);XCTAssertTrue(service.linkedArtworkWritableAssets.contains(asset))
      let inventory=try await AutomationTests().request(service,path:"/v1/linked-artwork");let fields=try JSONSerialization.jsonObject(with:inventory.1)as![String:Any];let assets=fields["assets"]as![[String:Any]];XCTAssertEqual(assets.first?["canWrite"]as?Bool,true)
      service.clearLinkedArtwork();XCTAssertTrue(service.linkedArtworkWritableAssets.isEmpty)
      let denied=try await AutomationTests().request(service,path:path);XCTAssertEqual(denied.0.statusCode,403)
    }
  }
  @MainActor func testWriteUpdatesSharedInstancesInOneHistoryStepAndUndoKeepsOriginal()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let(dir,asset,id)=try await self.setup(service,parent);defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      let store=parent.store;var original=store.document;var copy=try XCTUnwrap(original.layers.last);copy.id=UUID();copy.smartObject?.sourceID=UUID();original.layers.append(copy);store.session=EditorSession(document:original)
      let monitor=LinkedSourceController(store:store);store.linkedSourceController=monitor;await monitor.scan()
      let old=try self.bytes(),new=try self.bytes(Pixel(0.2,0.7,0.4)),hash=LinkedSmartObjectSource.fingerprint(old)
      let denied=try await self.send(self.upload(service,parent,id,new,hash:hash));XCTAssertEqual(denied.0.statusCode,403);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.png")),old)
      service.setLinkedArtworkWritable(asset,enabled:true)
      let response=try await self.send(self.upload(service,parent,id,new,hash:hash));XCTAssertEqual(response.0.statusCode,200);XCTAssertEqual(response.1["fileWritten"]as?Bool,true);XCTAssertEqual(response.1["documentUpdated"]as?Bool,true)
      XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.png")),new);XCTAssertEqual(store.session.undoStack.count,1)
      XCTAssertTrue(store.document.layers.compactMap(\.smartObject).allSatisfy{$0.data==new});let updated=store.document
      await store.undo();XCTAssertEqual(store.document,original);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.png")),new)
      await store.linkedSourceController?.scan();XCTAssertEqual(store.document,original);await store.redo();XCTAssertEqual(store.document,updated)
      XCTAssertFalse(store.geometryBusy);XCTAssertTrue(service.linkedSourceWriteOperations.isEmpty);XCTAssertTrue(service.linkedSourceWriteLeases.isEmpty)
    }
  }
  @MainActor func testNoOpMissingPreconditionsInvalidFormatAndLockedInstancesWriteNothing()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let(dir,asset,id)=try await self.setup(service,parent);defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      service.setLinkedArtworkWritable(asset,enabled:true);let store=parent.store,old=try self.bytes(),hash=LinkedSmartObjectSource.fingerprint(old),original=store.document,history=store.session.undoStack.count
      let same=try await self.send(self.upload(service,parent,id,old,hash:hash));XCTAssertEqual(same.0.statusCode,200);XCTAssertEqual(same.1["fileWritten"]as?Bool,false);XCTAssertEqual(same.1["documentUpdated"]as?Bool,false);XCTAssertEqual(store.session.undoStack.count,history)
      let missing=try await self.send(self.upload(service,parent,id,old));XCTAssertEqual(missing.0.statusCode,428)
      let stale=try await self.send(self.upload(service,parent,id,old,hash:String(repeating:"0",count:64)));XCTAssertEqual(stale.0.statusCode,412)
      let bad=try await self.send(self.upload(service,parent,id,Data([1,2,3]),hash:hash));XCTAssertNotEqual(bad.0.statusCode,200)
      let pdf=try Data(contentsOf:PDFPlacementWorkflowTests().fixture())
      let changedFormat=try await self.send(self.upload(service,parent,id,pdf,hash:hash));XCTAssertEqual(changedFormat.0.statusCode,415)
      XCTAssertEqual(store.document,original);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.png")),old)
      var locked=original;locked.layers[locked.layers.count-1].locked=true;store.session=EditorSession(document:locked)
      let denied=try await self.send(self.upload(service,parent,id,try self.bytes(Pixel(0,0,1)),hash:hash));XCTAssertNotEqual(denied.0.statusCode,200);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.png")),old)
    }
  }
  @MainActor func testCancellationRevocationParentAndFileChangesBeforePublicationAreAtomic()async throws {
    for mode in ["cancel","revoke","parent","file"] {
      try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
        let(dir,asset,id)=try await self.setup(service,parent);defer{try? FileManager.default.removeItem(at:dir)}
        service.setLinkedArtworkWritable(asset,enabled:true);let gate=SourceWriteGate(),old=try self.bytes(),new=try self.bytes(Pixel(0,0,1)),original=parent.store.document
        service.linkedSourceWritePreparation={bytes,doc,grants,target,hash in
          let prepared=try PreparedLinkedSourceWrite.prepare(bytes,in:doc,grants:grants,target:target,expectedFingerprint:hash)
          await gate.mark();try await Task.sleep(for:.milliseconds(200));return prepared
        }
        let request=self.upload(service,parent,id,new,hash:LinkedSmartObjectSource.fingerprint(old)),pending=Task{try await URLSession.shared.data(for:request)};try await self.wait(gate)
        let simultaneous=try await self.send(self.upload(service,parent,id,new,hash:LinkedSmartObjectSource.fingerprint(old)));XCTAssertEqual(simultaneous.0.statusCode,429)
        var expected=original,fileExpected=old
        if mode=="cancel" {
          let share=try XCTUnwrap(service.shares.first?.id),operation=try XCTUnwrap(service.linkedSourceWriteOperations[share]?.id)
          let cancel=try await AutomationTests().request(service,path:try self.path(service,id)+"/cancel",body:["operationID":operation.uuidString]);XCTAssertEqual(cancel.0.statusCode,200)
        }else if mode=="revoke"{service.setLinkedArtworkWritable(asset,enabled:false)}
        else if mode=="parent"{expected.name="Changed while preparing";parent.store.session=EditorSession(document:expected)}
        else{fileExpected=try self.bytes(Pixel(0,1,0));try fileExpected.write(to:dir.appendingPathComponent("Source.png"),options:.atomic)}
        let response=try self.decode(try await pending.value);XCTAssertEqual(response.0.statusCode,mode=="file" ? 412:409,mode);XCTAssertNotEqual(response.1["fileWritten"]as?Bool,true)
        XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.png")),fileExpected);XCTAssertEqual(parent.store.document,expected);XCTAssertFalse(parent.store.geometryBusy);XCTAssertTrue(service.linkedSourceWriteOperations.isEmpty);XCTAssertTrue(service.linkedSourceWriteLeases.isEmpty)
      }
    }
  }
  @MainActor func testLateRevocationReportsSavedOriginalWithoutParentCommit()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let(dir,asset,id)=try await self.setup(service,parent);defer{try? FileManager.default.removeItem(at:dir)}
      service.setLinkedArtworkWritable(asset,enabled:true);let gate=SourceWriteGate(),old=try self.bytes(),new=try self.bytes(Pixel(0,0,1)),original=parent.store.document
      service.linkedSourceWriteAfterPublication={await gate.mark();try await Task.sleep(for:.milliseconds(200))}
      let request=self.upload(service,parent,id,new,hash:LinkedSmartObjectSource.fingerprint(old)),pending=Task{try await URLSession.shared.data(for:request)};try await self.wait(gate)
      XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.png")),new);service.setLinkedArtworkWritable(asset,enabled:false)
      let response=try self.decode(try await pending.value);XCTAssertEqual(response.0.statusCode,409);XCTAssertEqual(response.1["fileWritten"]as?Bool,true);XCTAssertEqual(response.1["documentUpdated"]as?Bool,false)
      XCTAssertEqual(parent.store.document,original);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.png")),new);XCTAssertFalse(parent.store.geometryBusy)
    }
  }
  @MainActor func testPDFSelectionsStayIndependentWhenOneApprovedOriginalIsSaved()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let old=try Data(contentsOf:PDFPlacementWorkflowTests().fixture()),(dir,asset,id)=try await self.setup(service,parent,data:old,name:"Source.pdf")
      defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      let second=try await AutomationTests().edit(service,parent,"smartObject.linked.place",["assetID":asset.uuidString,"fingerprint":LinkedSmartObjectSource.fingerprint(old),"placement":["pdf":["page":2,"crop":"trim","resolution":144]]]);XCTAssertEqual(second,200)
      parent.store.linkedSourceController?.stop();let store=parent.store,original=store.document;store.session=EditorSession(document:original)
      let selections=Dictionary(uniqueKeysWithValues:original.layers.compactMap{layer in layer.smartObject?.pdfSource.map{(layer.id,$0)}})
      XCTAssertEqual(selections.count,2);service.setLinkedArtworkWritable(asset,enabled:true)
      let invalid=try Data(contentsOf:PDFPlacementWorkflowTests().fixture("owned-images"))
      let rejected=try await self.send(self.upload(service,parent,id,invalid,hash:LinkedSmartObjectSource.fingerprint(old)))
      XCTAssertNotEqual(rejected.0.statusCode,200);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.pdf")),old);XCTAssertEqual(store.document,original)
      var changed=old;changed.append(Data("\n% Owned source edit\n".utf8))
      let saved=try await self.send(self.upload(service,parent,id,changed,hash:LinkedSmartObjectSource.fingerprint(old)));XCTAssertEqual(saved.0.statusCode,200)
      XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source.pdf")),changed)
      for layer in store.document.layers where selections[layer.id] != nil{XCTAssertEqual(layer.smartObject?.pdfSource,selections[layer.id]);XCTAssertEqual(layer.smartObject?.data,changed)}
    }
  }
  @MainActor func testNativePermissionPanelRendersPerFileSwitchAndStopRevokesIt()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let(dir,asset,_)=try await self.setup(service,parent);defer{try? FileManager.default.removeItem(at:dir)}
      let view=NSHostingView(rootView:LinkedSourcePermissionsView(service:service));view.appearance=NSAppearance(named:.aqua);view.frame=NSRect(x:0,y:0,width:800,height:280);view.layoutSubtreeIfNeeded()
      let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
      let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]));XCTAssertGreaterThan(data.count,100)
      if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{try data.write(to:URL(fileURLWithPath:folder).appendingPathComponent("linked-source-permissions.png"))}
      service.setLinkedArtworkWritable(asset,enabled:true);XCTAssertTrue(service.linkedArtworkWritableAssets.contains(asset));service.stop();XCTAssertTrue(service.linkedArtworkWritableAssets.isEmpty);XCTAssertTrue(service.linkedArtworkAssets.isEmpty)
    }
  }

  @MainActor func testOriginalFormatsAndRAWSettingsSurviveFilePublication()async throws {
    for format in [DocumentIO.Format.jpeg,.tiff,.native,.psd,.psb] {
      try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
        let source=try EmbeddedPlacementWorkflowTests().fixture();var changed=source
        changed.layers[0].content = .raster(try Surface(width:8,height:6,fill:Pixel(0,0,1)))
        let old=try DocumentIO.encode(source,format:format),new=try DocumentIO.encode(changed,format:format)
        let(dir,asset,id)=try await self.setup(service,parent,data:old,name:"Source."+format.rawValue);defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
        service.setLinkedArtworkWritable(asset,enabled:true)
        let response=try await self.send(self.upload(service,parent,id,new,hash:LinkedSmartObjectSource.fingerprint(old)))
        XCTAssertEqual(response.0.statusCode,200,format.rawValue);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Source."+format.rawValue)),new)
        XCTAssertEqual(parent.store.activeLayer?.smartObject?.data,new)
      }
    }
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let old=try RawDevelopmentWorkflowTests().data(),(dir,asset,id)=try await self.setup(service,parent,data:old,name:"Sensor.dng");defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      service.setLinkedArtworkWritable(asset,enabled:true);let source=try XCTUnwrap(parent.store.activeLayer?.smartObject),settings=try XCTUnwrap(source.rawDevelopment)
      var bytes=old;bytes.append(Data("Owned sensor edit".utf8))
      let response=try await self.send(self.upload(service,parent,id,bytes,hash:LinkedSmartObjectSource.fingerprint(old)));XCTAssertEqual(response.0.statusCode,200)
      XCTAssertEqual(parent.store.activeLayer?.smartObject?.rawDevelopment,settings);XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Sensor.dng")),bytes)
    }
  }
  @MainActor func testSourceSymlinkSubstitutionAndShareRevocationCannotWrite()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let(dir,asset,id)=try await self.setup(service,parent);defer{try? FileManager.default.removeItem(at:dir)}
      service.setLinkedArtworkWritable(asset,enabled:true);let old=try self.bytes(),new=try self.bytes(Pixel(0,0,1)),target=dir.appendingPathComponent("Other.png"),original=parent.store.document
      try old.write(to:target);try FileManager.default.removeItem(at:dir.appendingPathComponent("Source.png"));try FileManager.default.createSymbolicLink(at:dir.appendingPathComponent("Source.png"),withDestinationURL:target)
      let request=self.upload(service,parent,id,new,hash:LinkedSmartObjectSource.fingerprint(old)),response=try await self.send(request)
      XCTAssertNotEqual(response.0.statusCode,200);XCTAssertEqual(try Data(contentsOf:target),old);XCTAssertEqual(parent.store.document,original)
      let share=try XCTUnwrap(service.shares.first?.id);service.revoke(share)
      let revoked=try await self.send(request);XCTAssertEqual(revoked.0.statusCode,404);XCTAssertEqual(try Data(contentsOf:target),old)
    }
  }
  @MainActor func testMaximumLogicalNativeOriginalHasNoDenseCanvasAdmission()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      var source=try CraftDocument(width:300_000,height:300_000)
      source.layers[0].content = .raster(try Surface(width:300_000,height:300_000,fill:.white))
      let old=try NativeArchive.encodeChunked(source);source.layers[0].content = .raster(try Surface(width:300_000,height:300_000,fill:.black))
      let new=try NativeArchive.encodeChunked(source),(dir,asset,id)=try await self.setup(service,parent,data:old,name:"Huge.photato");defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      service.setLinkedArtworkWritable(asset,enabled:true)
      let response=try await self.send(self.upload(service,parent,id,new,hash:LinkedSmartObjectSource.fingerprint(old)));XCTAssertEqual(response.0.statusCode,200)
      XCTAssertEqual(parent.store.activeLayer?.smartObject?.width,300_000);XCTAssertEqual(parent.store.activeLayer?.smartObject?.height,300_000)
      XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("Huge.photato")),new)
    }
  }

}
