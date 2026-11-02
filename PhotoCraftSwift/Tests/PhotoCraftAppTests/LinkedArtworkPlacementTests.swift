import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LinkedArtworkPlacementTests:XCTestCase {
  func parsed(_ fields:[String:Any],fit:Bool=true,explicit:Bool=false)throws->LinkedArtworkPlacementOptions {
    try LinkedArtworkPlacementAPI.options(JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:fields)),fit:fit,fitExplicit:explicit)
  }
  func pdf(_ name:String="owned-boxes")throws->Data {try Data(contentsOf:PDFPlacementWorkflowTests().fixture(name))}
  func png()throws->Data {try LinkedArtworkWorkflowTests().artwork()}
  @MainActor func setup(_ service:AutomationService,_ parent:CraftNSDocument,bytes:Data,name:String)throws->(URL,UUID,LinkedArtworkGrant) {
    let dir=try LinkedArtworkWorkflowTests().folder(),url=dir.appendingPathComponent(name);try bytes.write(to:url)
    parent.store.onChange=nil;parent.store.linkedSourceRegistry=LinkedSourceRegistry(persistent:false);try service.share(parent)
    let asset=try service.authorizeLinkedArtwork(url,registry:parent.store.linkedSourceRegistry)
    return(dir,asset,try XCTUnwrap(service.linkedArtworkAssets[asset]))
  }
  func parameters(_ asset:UUID,_ bytes:Data,_ placement:[String:Any]=[:])->[String:Any] {
    ["assetID":asset.uuidString,"fingerprint":LinkedSmartObjectSource.fingerprint(bytes),"placement":placement]
  }
  func testOptionsStrictValidationAndDiscovery()throws {
    let invalid:[[String:Any]]=[
      ["pdf":["page":1,"image":1]],["pdf":["crop":"invalid"]],["pdf":["resolution":0]],
      ["pdf":["page":2],"rawDevelopment":["exposure":0.5]],
      ["frameFit":"fit"],["frameID":UUID().uuidString,"transform":["a":1,"b":0,"c":0,"d":1,"tx":0,"ty":0]],
      ["layerID":UUID().uuidString],["pdf":["fit":false]],["pdf":["page":1.5]],["path":"/unauthorized"]]
    for value in invalid{XCTAssertThrowsError(try parsed(value),String(describing:value))}
    XCTAssertThrowsError(try parsed(["frameID":UUID().uuidString],explicit:true))
    let selected=try parsed(["pdf":["page":2,"crop":"trim","resolution":144,"antialias":false]],fit:false)
    XCTAssertEqual(selected.pdf?.page,2);XCTAssertEqual(selected.pdf?.resolution,144);XCTAssertFalse(selected.embedded.fit)
    XCTAssertFalse(try parsed(["frameID":NSNull()],fit:false).embedded.fit)
    let command=try XCTUnwrap(LinkedArtworkAPI.definitions.first{$0.name=="smartObject.linked.place"})
    let envelope=try XCTUnwrap(command.schema["properties"]as?[String:Any])
    let parameters=try XCTUnwrap(envelope["parameters"]as?[String:Any])
    XCTAssertNotNil((parameters["properties"]as?[String:Any])?["placement"])
    XCTAssertFalse((parameters["required"]as?[String] ?? []).contains("placement"))
    XCTAssertTrue(JSONSerialization.isValidJSONObject(LinkedArtworkAPI.capabilities));XCTAssertEqual(LinkedArtworkAPI.commands.count,7)
  }
  @MainActor func testHTTPPDFPageOptionsMatchNativeLinkedChooserAndHistory()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let bytes=try self.pdf(),(dir,asset,grant)=try self.setup(service,parent,bytes:bytes,name:"Pages.pdf");defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      let store=parent.store,original=store.document,url=dir.appendingPathComponent("Pages.pdf")
      store.pdfPlacementPresenter={model in Task{@MainActor in
        await model.loadTask?.value;model.settings.crop = .trim;model.settings.resolution=144;model.settings.antialias=false;model.selected=[2];model.run()
      }}
      store.placeEmbeddedSource(url,linkedGrant:grant);await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertNotNil(store.transformDraft);store.commitTransform();await store.geometryTask?.value
      XCTAssertNil(store.error);let native=store.document,expected=try Renderer.composite(native).rgbaData(depth:.u8)
      XCTAssertEqual(store.session.undoStack.count,1);await store.undo();XCTAssertEqual(store.document,original)
      let code=try await AutomationTests().edit(service,parent,"smartObject.linked.place",self.parameters(asset,bytes,["pdf":["page":2,"crop":"trim","resolution":144,"antialias":false]]))
      XCTAssertEqual(code,200);XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth:.u8),expected)
      let source=try XCTUnwrap(store.activeLayer?.smartObject);XCTAssertEqual(source.pdfSource,native.layers.last?.smartObject?.pdfSource);XCTAssertEqual(source.resolution,144);XCTAssertEqual(source.data,bytes);XCTAssertNotNil(source.linkedSource)
      XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(store.document)),store.document)
      let placed=store.document;await store.undo();XCTAssertEqual(store.document,original);await store.redo();XCTAssertEqual(store.document,placed);XCTAssertEqual(try Data(contentsOf:url),bytes)
    }
  }
  @MainActor func testHTTPPDFImageFrameMatchesNativeFramePlacement()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let bytes=try self.pdf("owned-images"),(dir,asset,grant)=try self.setup(service,parent,bytes:bytes,name:"Images.pdf");defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      let store=parent.store;store.session=EditorSession(document:try FrameWorkflowTests().frame());let original=store.document,id=try XCTUnwrap(original.layers.last?.id)
      PDFPlacementWorkflowTests().select(store,image:1)
      store.placeEmbeddedSource(dir.appendingPathComponent("Images.pdf"),frame:id,linkedGrant:grant);await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertNil(store.transformDraft);let expected=try Renderer.composite(store.document).rgbaData(depth:.u8)
      XCTAssertEqual(store.session.undoStack.count,1);await store.undo();XCTAssertEqual(store.document,original)
      let options:[String:Any]=["frameID":id.uuidString,"frameFit":"fill","pdf":["image":1]]
      let code=try await AutomationTests().edit(service,parent,"smartObject.linked.place",self.parameters(asset,bytes,options))
      XCTAssertEqual(code,200);XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth:.u8),expected);XCTAssertEqual(store.session.undoStack.count,1)
      let child=try XCTUnwrap(store.document.children(of:id).first);XCTAssertEqual(child.smartObject?.pdfSource?.image,1);XCTAssertNotNil(child.smartObject?.linkedSource);XCTAssertEqual(child.smartObject?.data,bytes)
    }
  }
  @MainActor func testHTTPRAWDevelopmentMatchesNativeChooserAndRetainsSensorBytes()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let bytes=try RawDevelopmentWorkflowTests().data(),(dir,asset,grant)=try self.setup(service,parent,bytes:bytes,name:"Sensor.dng");defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      let store=parent.store,original=store.document
      store.rawPlacementPresenter={workspace in Task{@MainActor in
        await workspace.prepare();var settings=workspace.model.sensorSettings!;settings.exposure=0.5
        workspace.model.changeSensor(settings);await workspace.model.task?.value;workspace.run()
      }}
      store.placeEmbeddedSource(dir.appendingPathComponent("Sensor.dng"),linkedGrant:grant);await store.geometryTask?.value
      XCTAssertNil(store.error);let settings=try XCTUnwrap(store.activeLayer?.smartObject?.rawDevelopment);store.commitTransform();await store.geometryTask?.value
      XCTAssertNil(store.error);let expected=try Renderer.composite(store.document).rgbaData(depth:.u8);await store.undo();XCTAssertEqual(store.document,original)
      let code=try await AutomationTests().edit(service,parent,"smartObject.linked.place",self.parameters(asset,bytes,["rawDevelopment":BrushAPI.json(settings)]))
      XCTAssertEqual(code,200);XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth:.u8),expected);XCTAssertEqual(store.activeLayer?.smartObject?.rawDevelopment,settings);XCTAssertEqual(store.activeLayer?.smartObject?.data,bytes);XCTAssertEqual(store.session.undoStack.count,1)
    }
  }
  @MainActor func testHTTPInitialTransformMatchesNativeAndWrongFormatOptionsAreAtomic()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let bytes=try self.png(),(dir,asset,grant)=try self.setup(service,parent,bytes:bytes,name:"Artwork.png");defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      let store=parent.store,original=store.document;store.placeEmbeddedSource(dir.appendingPathComponent("Artwork.png"),linkedGrant:grant);await store.geometryTask?.value
      var draft=try XCTUnwrap(store.transformDraft);draft.centerX+=2;draft.centerY+=3;store.updateTransform(draft);store.commitTransform();await store.geometryTask?.value
      XCTAssertNil(store.error);let expected=try Renderer.composite(store.document).rgbaData(depth:.u8);await store.undo();XCTAssertEqual(store.document,original)
      for invalid in [["pdf":["page":2]],["rawDevelopment":["exposure":0.5]]] {
        let code=try await AutomationTests().edit(service,parent,"smartObject.linked.place",self.parameters(asset,bytes,invalid));XCTAssertEqual(code,422);XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
      }
      let code=try await AutomationTests().edit(service,parent,"smartObject.linked.place",self.parameters(asset,bytes,["transform":["a":1,"b":0,"c":0,"d":1,"tx":2,"ty":3]]))
      XCTAssertEqual(code,200);XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth:.u8),expected);XCTAssertEqual(store.session.undoStack.count,1)
    }
  }
  @MainActor func testPendingPlacementCancellationRevocationAndStaleTargetCannotCommit()async throws {
    for mode in ["cancel","revoke","stale"] {
      try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
        let bytes=try self.png(),(dir,asset,_)=try self.setup(service,parent,bytes:bytes,name:"Artwork.png");defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
        service.linkedArtworkPlacementPreparation={file,original,options in
          try await Task.sleep(for:.milliseconds(200));return try LinkedArtworkPlacementAPI.prepare(file,in:original,options:options)
        }
        let store=parent.store,original=store.document,parameters=self.parameters(asset,bytes)
        let pending=Task{try await AutomationTests().edit(service,parent,"smartObject.linked.place",parameters)}
        for _ in 0..<100 where !store.geometryBusy{try await Task.sleep(for:.milliseconds(5))};XCTAssertTrue(store.geometryBusy)
        var expected=original
        if mode=="cancel"{store.geometryTask?.cancel()}
        else if mode=="revoke"{service.clearLinkedArtwork()}
        else{expected.name="Changed while preparing";store.session=EditorSession(document:expected)}
        let code=try await pending.value;XCTAssertEqual(code,409,mode);XCTAssertEqual(store.document,expected);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertFalse(store.geometryBusy)
      }
    }
  }
  @MainActor func testLinkedRAWRefreshPreservesDevelopmentForSharedInstancesAndUndo()async throws {
    for viaAPI in [false,true] {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      let bytes=try RawDevelopmentWorkflowTests().data(),(dir,asset,_)=try self.setup(service,parent,bytes:bytes,name:"Sensor.dng");defer{try? FileManager.default.removeItem(at:dir);parent.store.linkedSourceController?.stop()}
      let store=parent.store
      let placed=try await AutomationTests().edit(service,parent,"smartObject.linked.place",self.parameters(asset,bytes,["rawDevelopment":["exposure":0.5]]));XCTAssertEqual(placed,200)
      store.linkedSourceController?.stop()
      var shared=store.document;var copy=try XCTUnwrap(shared.layers.last);copy.id=UUID();shared.layers.append(copy)
      store.session=EditorSession(document:shared)
      let oldSource=try XCTUnwrap(shared.layers.last?.smartObject),expected=try Renderer.composite(shared).rgbaData(depth:.u8)
      XCTAssertEqual(oldSource.rawDevelopment?.exposure,0.5)
      let monitor=LinkedSourceController(store:store);store.linkedSourceController=monitor
      await monitor.scan()
      // A trailing TIFF payload changes original bytes without changing the owned Bayer samples.
      var changed=bytes;changed.append(Data("Owned refreshed metadata".utf8));XCTAssertTrue(RawSourceIO.recognizes(changed))
      try changed.write(to:dir.appendingPathComponent("Sensor.dng"),options:.atomic)
      if viaAPI {monitor.stop();let code=try await AutomationTests().edit(service,parent,"smartObject.linked.update");XCTAssertEqual(code,200)}
      else{await monitor.scan();XCTAssertNil(store.error)}
      let instances=store.document.layers.compactMap(\.smartObject).filter{$0.sourceID==oldSource.sourceID}
      XCTAssertEqual(instances.count,2);XCTAssertTrue(instances.allSatisfy{$0.rawDevelopment==oldSource.rawDevelopment && $0.data==changed})
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth:.u8),expected)
      XCTAssertEqual(store.session.undoStack.count,1);let updated=store.document
      await store.undo();XCTAssertEqual(store.document,shared);await store.redo();XCTAssertEqual(store.document,updated)
    }
    }
  }

}
