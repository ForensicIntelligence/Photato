import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class BatchNamingTests:XCTestCase {
  func naming(_ fields:[BatchFileNaming.Element] = [.init(kind:.documentName),.init(kind:.extensionLower)]) -> BatchFileNaming {
    var n=BatchFileNaming();n.elements=fields;n.date=ISO8601DateFormatter().date(from:"2026-11-05T00:30:00Z")!;n.timeZone="UTC";return n
  }
  func decode(_ raw:Any)throws->AutomationValue {try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:raw,options:[.fragmentsAllowed]))}
  func folder()throws->URL {try ActionBatchTests().folder()}
  func action()->RecordedAction {ActionBatchTests().action()}
  func testAllPublicFieldKindsAgainstLiteralNamesAndDateZoneBoundary()throws {
    let cases:[(BatchFileNaming.Kind,String)]=[
      (.documentName,"MiXeD"),(.documentLower,"mixed"),(.documentUpper,"MIXED"),
      (.extensionLower,".png"),(.extensionUpper,".PNG"),(.serial1,"1"),(.serial2,"01"),(.serial3,"001"),(.serial4,"0001"),
      (.letterLower,"a"),(.letterUpper,"A"),(.ddmm,"0511"),(.ddmmyy,"051126"),(.mmdd,"1105"),(.mmddyy,"110526"),(.yyddmm,"260511"),(.yymmdd,"261105"),(.yyyymmdd,"20261105")]
    XCTAssertEqual(cases.count,18)
    for (kind,expected)in cases {
      let n=naming([.init(kind:.documentName),.init(kind:.literal,text:"_"),.init(kind:kind)])
      XCTAssertEqual(try n.filename(source:"MiXeD",index:0,format:.png),"MiXeD_"+expected,kind.rawValue)
    }
    var n=naming([.init(kind:.yyyymmdd),.init(kind:.literal,text:"-"),.init(kind:.serial4),.init(kind:.extensionUpper)])
    n.timeZone="America/Vancouver";n.startingSerial=9999
    XCTAssertEqual(try n.plan(sources:["A","B"],format:.native),["20261104-9999.PHOTATO","20261104-10000.PHOTATO"])
    n=naming([.init(kind:.letterUpper)]);n.startingSerial=500
    XCTAssertEqual(try [0,25,26,51,255].map{try n.filename(source:"unused",index:$0,format:.png)},["A","Z","AA","AZ","IV"])
    n=naming([.init(kind:.serial1)]);n.startingSerial=BatchFileNaming.maximumSerial
    XCTAssertEqual(try n.filename(source:"unused",index:255,format:.png),"9007199254740990")
  }
  func testValidationCanonicalCollisionsDeviceNamesAndSerialization()throws {
    var n=naming();XCTAssertEqual(try n.filename(source:"cafe\u{301}",index:0,format:.jpeg),"café.jpeg")
    for names in [["Photo","photo"],["café","cafe\u{301}"]]{XCTAssertThrowsError(try n.plan(sources:names,format:.png))}
    n.macOS=false;n.windows=false;XCTAssertEqual(try n.plan(sources:["Photo","photo"],format:.png),["Photo.png","photo.png"])
    n=naming([.init(kind:.documentName)])
    for source in ["../outside","a/b","a\\b","a:b","NUL.txt","CON","LPT¹.png","COM³","name.","name ","bad?","a\n",String(repeating:"é",count:128)] {XCTAssertThrowsError(try n.filename(source:source,index:0,format:.png),source)}
    n.windows=false;XCTAssertEqual(try n.filename(source:"NUL.txt",index:0,format:.png),"NUL.txt")
    n=naming([.init(kind:.literal,text:"same")]);XCTAssertThrowsError(try n.validate())
    n=naming();n.elements += Array(repeating:.init(kind:.literal),count:5);XCTAssertThrowsError(try n.validate())
    n=naming();n.elements[0].text="ignored?";XCTAssertThrowsError(try n.validate())
    n=naming();n.startingSerial = -1;XCTAssertThrowsError(try n.validate())
    n=naming();n.timeZone="No/SuchZone";XCTAssertThrowsError(try n.validate())
    n=naming();n.date=Date(timeIntervalSince1970:.infinity);XCTAssertThrowsError(try n.validate())
    n=naming();XCTAssertThrowsError(try n.filename(source:"x",index:256,format:.png))
    let data=try JSONEncoder().encode(n),copy=try JSONDecoder().decode(BatchFileNaming.self,from:data)
    XCTAssertEqual(copy,n);XCTAssertNotEqual(copy.elements[0].id,n.elements[0].id)
    let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]);XCTAssertNil((raw["elements"] as? [[String:Any]])?.first?["id"])
  }
  func testStrictAPIParsingSchemasAndReproducibleNames()throws {
    let object=BatchNamingAPI.object(naming()),value=try decode(object)
    let n=try BatchNamingAPI.parse(value);XCTAssertEqual(try n.plan(sources:["One"],format:.png),["One.png"])
    for (key,bad)in [("startingSerial",NSNull()),("startingSerial",1.5),("windows",1),("macOS","true"),("unix",NSNull()),("date","yesterday"),("timeZone","Invalid/Zone"),("unknown",true)] as [(String,Any)] {
      var raw=object;raw[key]=bad;XCTAssertThrowsError(try BatchNamingAPI.parse(decode(raw)),key)
    }
    for fields:[[String:Any]] in [[[:]],[["kind":"unknown"]],[["kind":"documentName","text":"bad"]],[["kind":"documentName","id":"ignored"]],[["kind":"documentName","text":NSNull()]],[["kind":"literal","text":"same"]]] {
      var raw=object;raw["elements"]=fields;XCTAssertThrowsError(try BatchNamingAPI.parse(decode(raw)))
    }
    let schema=BatchNamingAPI.schema;XCTAssertEqual(schema["additionalProperties"] as? Bool,false)
    let props=try XCTUnwrap(schema["properties"] as? [String:Any]),elements=try XCTUnwrap(props["elements"] as? [String:Any]);XCTAssertEqual(elements["maxItems"] as? Int,6)
    XCTAssertNotNil(elements["contains"]);XCTAssertTrue(JSONSerialization.isValidJSONObject(BatchNamingAPI.capabilities));XCTAssertTrue(JSONSerialization.isValidJSONObject(BatchNamingAPI.stateSchema))
  }
  @MainActor func testNamedCopiesHaveSameMaterialAsLegacyAndPreserveInputBytes()async throws {
    let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
    let d=try CraftDocument(width:5,height:4,name:"Example"),input=root.appendingPathComponent("input.photato"),bytes=try NativeArchive.encodeChunked(d);try bytes.write(to:input)
    let source=ActionBatchSource(url:input)
    let named=try await ActionBatch.run(sources:[source],action:action(),destination:root,format:.png,naming:naming())
    let legacy=try await ActionBatch.run(sources:[source],action:action(),destination:root,format:.png)
    XCTAssertEqual(named[0].output,"input.png");XCTAssertEqual(legacy[0].output,"0001-input-processed.png")
    XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(try XCTUnwrap(named[0].output))),try Data(contentsOf:root.appendingPathComponent(try XCTUnwrap(legacy[0].output))))
    XCTAssertEqual(try Data(contentsOf:input),bytes)
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.hasPrefix(".photato-batch-")})
  }
  @MainActor func testPreflightCollisionsExistingAliasesSymlinksAndStopNumbering()async throws {
    let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
    let d=try CraftDocument(width:2,height:2,name:"Same"),source=ActionBatchSource(document:d)
    do{_ = try await ActionBatch.run(sources:[source,source],action:action(),destination:root,format:.png,naming:naming());XCTFail("Duplicate plan accepted")}catch{}
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),[])
    let sentinel=Data("owned sentinel".utf8),existing=root.appendingPathComponent("SAME.PNG");try sentinel.write(to:existing)
    let collision=try await ActionBatch.run(sources:[source],action:action(),destination:root,format:.png,naming:naming())
    XCTAssertNil(collision[0].output);XCTAssertNotNil(collision[0].error);XCTAssertEqual(try Data(contentsOf:existing),sentinel)
    try FileManager.default.removeItem(at:existing)
    let target=root.appendingPathComponent("sentinel");try sentinel.write(to:target)
    try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Same.png"),withDestinationURL:target)
    let link=try await ActionBatch.run(sources:[source],action:action(),destination:root,format:.png,naming:naming());XCTAssertNil(link[0].output);XCTAssertEqual(try Data(contentsOf:target),sentinel)
    let numbered=naming([.init(kind:.serial3),.init(kind:.extensionLower)])
    let sources=[ActionBatchSource(url:root.appendingPathComponent("missing.png")),source]
    let results=try await ActionBatch.run(sources:sources,action:action(),destination:root,format:.png,naming:numbered)
    XCTAssertNotNil(results[0].error);XCTAssertEqual(results[1].output,"002.png")
    var stopNaming=numbered;stopNaming.startingSerial=10
    let stopped=try await ActionBatch.run(sources:sources,action:action(),destination:root,format:.png,naming:stopNaming,stopOnError:true);XCTAssertTrue(stopped[1].cancelled)
    XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("011.png").path))
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.hasPrefix(".photato-batch-")})
  }
  @MainActor func testNamedCancellationAndRevocationRetainCompletedOutputs()async throws {
    let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
    let d=try CraftDocument(width:2,height:2),sources=(0..<3).map{_ in ActionBatchSource(document:d)},n=naming([.init(kind:.serial2),.init(kind:.extensionLower)])
    let task=Task{@MainActor in try await ActionBatch.run(sources:sources,action:action(),destination:root,format:.png,naming:n,progress:{if $0.count==1{withUnsafeCurrentTask{$0?.cancel()}}})}
    let cancelled=try await task.value;XCTAssertEqual(cancelled[0].output,"01.png");XCTAssertTrue(cancelled.dropFirst().allSatisfy(\.cancelled))
    var count=0,revokedNaming=n;revokedNaming.startingSerial=11
    let revoked=try await ActionBatch.run(sources:sources,action:action(),destination:root,format:.png,naming:revokedNaming,validatePublication:{count+=1;if count>=3{throw CraftError.invalid("Revoked")}})
    XCTAssertEqual(revoked[0].output,"11.png");XCTAssertTrue(revoked.dropFirst().allSatisfy(\.cancelled));XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("12.png").path))
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.hasPrefix(".photato-batch-")})
  }
  @MainActor func testNativeBindingsSnapshotAndBoundedOffscreenPanel()async throws {
    _=NSApplication.shared;let root=try folder();defer{try? FileManager.default.removeItem(at:root)}
    let library=ActionLibrary(),a=action();try library.save(a)
    let model=BatchWorkspace(controller:CraftDocumentController(),library:library)
    model.sources=[.init(document:try CraftDocument(width:2,height:2,name:"Native"))];model.destination=root;model.selected=a.id
    let controls=BatchNamingControls(model:model),id=model.naming.elements[0].id,binding=controls.kindBinding(id)
    controls.move(id,1);binding.wrappedValue = .documentUpper;XCTAssertEqual(model.naming.elements.last?.kind,.documentUpper)
    let text=controls.textBinding(id);model.naming.elements.removeAll{$0.id==id};binding.wrappedValue = .serial3;text.wrappedValue="stale"
    XCTAssertEqual(model.naming.elements.count,1);XCTAssertEqual(model.naming.elements[0].kind,.extensionLower)
    model.naming=naming([.init(kind:.documentName),.init(kind:.literal,text:"-"),.init(kind:.serial3),.init(kind:.extensionLower)])
    model.run();XCTAssertTrue(model.busy);model.naming.elements=[.init(kind:.documentUpper)];model.sources=[]
    await model.task?.value;XCTAssertFalse(model.busy);XCTAssertNil(model.error);XCTAssertEqual(model.results.first?.output,"Native-001.png")
    model.naming=naming([.init(kind:.documentName),.init(kind:.literal,text:"-"),.init(kind:.yyyymmdd),.init(kind:.literal,text:"-"),.init(kind:.serial3),.init(kind:.extensionLower)])
    let host=NSHostingView(rootView:BatchPanel(model:model));host.appearance=NSAppearance(named:.darkAqua);host.frame=NSRect(x:0,y:0,width:680,height:620);host.layoutSubtreeIfNeeded()
    XCTAssertEqual(host.bounds.size,NSSize(width:680,height:620));XCTAssertLessThanOrEqual(host.fittingSize.height,620)
    if let base=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);let png=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]));try png.write(to:URL(fileURLWithPath:base).appendingPathComponent("434-batch-six-fields-offscreen.png"))}
  }
  @MainActor func testHTTPMatchesNativeNamingAndRejectsInvalidOrStaleWithoutOutputs()async throws {
    let root=try folder(),nativeRoot=try folder();defer{try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:nativeRoot)}
    let library=ActionLibrary(),a=action();try library.save(a);let helper=AutomationTests()
    try await helper.withService(actions:library,pressedMouseButtons:{0}){service,document in
      try service.share(document);service.setDocumentSavesEnabled(true);service.setSaveDirectory(root)
      let id=try XCTUnwrap(service.shares.first?.id),d=document.store.document,n=naming([.init(kind:.yyyymmdd),.init(kind:.literal,text:"-"),.init(kind:.serial4),.init(kind:.extensionLower)])
      var parameters:[String:Any]=["actionID":a.id.uuidString,"sources":[["id":id.uuidString,"revision":service.revision(document.store)]],"format":"png","naming":BatchNamingAPI.object(n)]
      let native=try await ActionBatch.run(sources:[.init(document:d)],action:a,destination:nativeRoot,format:.png,naming:n);XCTAssertEqual(native[0].output,"20261105-0001.png")
      let response=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"actions.batch","revision":service.revision(document.store),"parameters":parameters])
      XCTAssertEqual(response.0.statusCode,200);let body=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any]);XCTAssertEqual(body["completed"] as? Int,1)
      XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("20261105-0001.png")),try Data(contentsOf:nativeRoot.appendingPathComponent("20261105-0001.png")))
      XCTAssertEqual(document.store.document,d);XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertNil(service.actionBatchNaming)
      XCTAssertTrue(service.actionBatchState["naming"] is NSNull);XCTAssertNotNil(service.actionBatchState["namingCapabilities"])
      service.actionBatchNaming=n;XCTAssertEqual((service.actionBatchState["naming"] as? [String:Any])?["startingSerial"] as? Int,1);service.actionBatchNaming=nil
      try FileManager.default.removeItem(at:root.appendingPathComponent("20261105-0001.png"))
      parameters["suffix"]="-bad";let conflicting=try await helper.edit(service,document,"actions.batch",parameters);XCTAssertEqual(conflicting,400);parameters.removeValue(forKey:"suffix")
      for raw:Any in [NSNull(),["elements":[["kind":"bogus"]]],["elements":[["kind":"literal","text":"same"]]],["elements":[["kind":"documentName"]],"windows":1]] {parameters["naming"]=raw;let invalid=try await helper.edit(service,document,"actions.batch",parameters);XCTAssertEqual(invalid,400)}
      parameters["naming"]=BatchNamingAPI.object(n);parameters["sources"]=[["id":id.uuidString,"revision":"stale"]];let stale=try await helper.edit(service,document,"actions.batch",parameters);XCTAssertEqual(stale,409)
      parameters["sources"]=[["id":id.uuidString,"revision":service.revision(document.store)]]
      let occupied=Task<[ActionBatchResult],Error>{[]};service.actionBatchTask=occupied
      let busy=try await helper.edit(service,document,"actions.batch",parameters);XCTAssertEqual(busy,409)
      service.actionBatchTask=nil;_ = try await occupied.value
      service.setDocumentSavesEnabled(false)
      let forbidden=try await helper.edit(service,document,"actions.batch",parameters);XCTAssertEqual(forbidden,403)
      XCTAssertNil(service.actionBatchTask);XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),[])
    }
  }
}
