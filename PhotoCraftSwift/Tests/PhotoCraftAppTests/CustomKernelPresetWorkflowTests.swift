import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftCore
import PhotoCraftImaging

final class CustomKernelPresetWorkflowTests:XCTestCase {
  func owned()throws->Data {try Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:"owned-asymmetric",withExtension:"acf",subdirectory:"Fixtures/CustomKernelOwned")))}
  func filter()throws->RasterFilter {var f=RasterFilter(.customFilter);f.otherVideo=try CustomKernelPreset.decode(owned(),format:.acf);return f}
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try OtherVideoWorkflowTests().fixture(depth,smart:smart)}
  @MainActor func testNativeLoadLocalHistoryInvalidRecoveryAndCancel()async throws {
    let d=try fixture(),store=EditorStore(document:d,actions:ActionLibrary()),model=OtherVideoWorkspace()
    defer{model.close();store.cancelFilter();store.renderTask?.cancel()}
    store.beginFilter(.customFilter);await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));let initial=model.filter
    model.loadPreset(try owned());await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(model.filter,try filter());XCTAssertEqual(model.undoStates.count,1)
    model.undo();XCTAssertEqual(model.filter,initial);model.redo();XCTAssertEqual(model.filter,try filter())
    model.loadPreset(Data(repeating:0,count:54));XCTAssertNotNil(model.error);XCTAssertEqual(model.filter,try filter());XCTAssertEqual(store.document,d)
    model.loadPreset(try owned());await model.task?.value;XCTAssertTrue(model.ready)
    let json=try CustomKernelPreset.encode(try XCTUnwrap(model.filter.otherVideo),format:.json);model.loadPreset(json);await model.task?.value;XCTAssertTrue(model.ready)
    model.close();store.cancelFilter();model.loadPreset(try owned());XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testNativeFilePanelsExposeACFAndRetainJSONFormat()throws {
    let open=OtherVideoWorkspace.makePresetOpenPanel();XCTAssertFalse(open.allowsMultipleSelection);XCTAssertFalse(open.canChooseDirectories)
    XCTAssertEqual(Set(open.allowedContentTypes ?? []),Set([CustomKernelPresetSaveAccessory.acfType,.json]));XCTAssertEqual(CustomKernelPresetSaveAccessory.acfType.preferredFilenameExtension,"acf")
    let panel=NSSavePanel(),accessory=CustomKernelPresetSaveAccessory(panel:panel)
    XCTAssertFalse(accessory.picker.menu?.autoenablesItems ?? true)
    XCTAssertEqual(accessory.format,.acf);XCTAssertEqual(panel.nameFieldStringValue,"Custom Filter");XCTAssertFalse(panel.isExtensionHidden);XCTAssertTrue(panel.accessoryView === accessory.view)
    accessory.picker.selectItem(at:1);accessory.updateFormat();XCTAssertEqual(accessory.format,.json);XCTAssertEqual(panel.nameFieldStringValue,"Custom Filter");XCTAssertEqual(panel.allowedContentTypes,[.json])
    panel.nameFieldStringValue="Owned.kernel.json";accessory.picker.selectItem(at:0);accessory.updateFormat();XCTAssertEqual(panel.nameFieldStringValue,"Owned.kernel")
    let fractional=NSSavePanel(),restricted=CustomKernelPresetSaveAccessory(panel:fractional,canExportACF:false)
    XCTAssertEqual(restricted.format,.json);XCTAssertEqual(fractional.nameFieldStringValue,"Custom Filter");XCTAssertEqual(restricted.picker.item(at:0)?.isEnabled,false)
  }
  @MainActor func testNativeAtomicSaveFailureKeepsPreviewAndSnapshotAndJSONRecovers()async throws {
    let d=try fixture(),store=EditorStore(document:d,actions:ActionLibrary()),model=OtherVideoWorkspace()
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("Photato-owned-ACF-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer{model.close();store.cancelFilter();store.renderTask?.cancel();try? FileManager.default.removeItem(at:folder)}
    store.beginFilter(.customFilter);await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));model.loadPreset(try owned());await model.task?.value
    let snapshot=try XCTUnwrap(model.filter.otherVideo),acf=folder.appendingPathComponent("owned.acf")
    model.update{$0.otherVideo?.scale=2};await model.task?.value;XCTAssertTrue(model.ready)
    model.writePreset(snapshot,format:.acf,to:acf);XCTAssertEqual(try Data(contentsOf:acf),try owned());XCTAssertNil(model.presetError)
    var fractional=snapshot;fractional.scale=1.5
    model.writePreset(fractional,format:.acf,to:acf);XCTAssertNotNil(model.presetError);XCTAssertNil(model.error);XCTAssertTrue(model.ready);XCTAssertEqual(try Data(contentsOf:acf),try owned())
    let json=folder.appendingPathComponent("owned.json");model.writePreset(fractional,format:.json,to:json)
    XCTAssertNil(model.presetError);XCTAssertTrue(model.ready);XCTAssertEqual(try OtherVideoSettings.decodeCustomPreset(Data(contentsOf:json)),fractional)
    XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
    model.close();let closed=folder.appendingPathComponent("closed.acf");model.writePreset(snapshot,format:.acf,to:closed);XCTAssertFalse(FileManager.default.fileExists(atPath:closed.path))
  }
  func testDecodedPresetsPreserveSmartNative43Actions16AndHistoryAllDepths()throws {
    let f=try filter()
    for depth in PixelDepth.allCases {
      let original=try fixture(depth,smart:true),id=original.layers[0].id;var session=EditorSession(document:original)
      try session.execute(.applyFilter(id,f));let edited=session.document;XCTAssertEqual(edited.minimumArchiveVersion,43)
      XCTAssertEqual(edited.layers[0].content,original.layers[0].content)
      for bytes in [try NativeArchive.encode(edited),try NativeArchive.encodeChunked(edited)] {XCTAssertEqual(try NativeArchive.decode(bytes),edited)}
      let action=RecordedAction(name:"Owned ACF",steps:[.init(name:"Custom",operation:.filter(.active,f))]);let loaded=try ActionLibraryFile.decode(ActionLibraryFile(actions:[action]).encoded());XCTAssertEqual(loaded.version,16)
      var replay=original;try XCTUnwrap(loaded.actions[0].steps[0].operation.command(in:replay)).apply(to:&replay);XCTAssertEqual(try Renderer.composite(replay),try Renderer.composite(edited))
      try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,edited)
    }
  }
  func testCoordinatedPresetFileBoundsDirectoryAndReplacement()throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("Photato-owned-ACF-write-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:folder)}
    let file=folder.appendingPathComponent("owned.acf"),original=Data("owned previous file".utf8)
    try original.write(to:file)
    XCTAssertThrowsError(try CustomKernelPresetFile.write(Data(repeating:0,count:16_385),to:file));XCTAssertEqual(try Data(contentsOf:file),original)
    XCTAssertThrowsError(try CustomKernelPresetFile.write(owned(),to:folder));XCTAssertTrue(FileManager.default.fileExists(atPath:file.path));XCTAssertEqual(try Data(contentsOf:file),original)
    XCTAssertThrowsError(try CustomKernelPresetFile.write(owned(),to:URL(string:"https://example.invalid/owned.acf")!))
    try CustomKernelPresetFile.write(owned(),to:file);XCTAssertEqual(try Data(contentsOf:file),try owned())
  }
  @MainActor func testRealHTTPCodecAndNativeApplyAgreeEveryDepthWithoutConversionHistory()async throws {
    let h=AutomationTests(),bytes=try owned(),f=try filter()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document);let share=try XCTUnwrap(service.shares.first?.id)
      for depth in PixelDepth.allCases {
        let d=try self.fixture(depth),id=d.layers[0].id;document.store.session=EditorSession(document:d);let revision=service.revision(document.store)
        let response=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":CustomKernelPresetAPI.name,"revision":revision,"parameters":["operation":"decode","format":"acf","data":bytes.base64EncodedString()]])
        XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1,as:UTF8.self))
        let result=try XCTUnwrap(try JSONSerialization.jsonObject(with:response.1)as?[String:Any]),returned=try XCTUnwrap(result["filter"]as?[String:Any])
        XCTAssertEqual(result["data"]as?String,bytes.base64EncodedString());XCTAssertEqual(result["byteLength"]as?Int,54);XCTAssertEqual(result["revision"]as?String,revision)
        XCTAssertEqual(try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:returned)),f)
        let encoded=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":CustomKernelPresetAPI.name,"revision":revision,"parameters":["operation":"encode","format":"acf","settings":f.otherVideo!.apiParameters(kind:.customFilter)]])
        XCTAssertEqual(encoded.0.statusCode,200);let encodedJSON=try XCTUnwrap(try JSONSerialization.jsonObject(with:encoded.1)as?[String:Any]);XCTAssertEqual(encodedJSON["data"]as?String,bytes.base64EncodedString())
        XCTAssertEqual(document.store.document,d);XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertEqual(service.revision(document.store),revision)
        var expected=d;try Command.applyFilter(id,f).apply(to:&expected)
        let status=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":returned]);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
      }
    }
  }
  @MainActor func testHTTPStrictFieldsFractionsBusyStaleAndRevocation()async throws {
    let h=AutomationTests(),raw=try owned().base64EncodedString()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let d=try self.fixture();document.store.session=EditorSession(document:d);try service.share(document)
      let valid:[String:Any]=["operation":"decode","format":"acf","data":raw]
      for params in [[:],["operation":"decode","format":"acf","data":"%%%"],["operation":"decode","format":"png","data":raw],["operation":"decode","format":"json","data":raw],["operation":"decode","format":"acf","data":raw,"settings":[:]], ["operation":"encode","format":"acf","settings":["scale":1.5]],["operation":"encode","format":"acf","settings":["unknown":1]],["operation":"encode","format":"acf","settings":["kernel":[1]]],["operation":"decode","format":"acf","data":String(repeating:"A",count:CustomKernelPresetAPI.maximumBase64+4)]]as[[String:Any]] {
        let code=try await h.edit(service,document,CustomKernelPresetAPI.name,params);XCTAssertEqual(code,400);XCTAssertEqual(document.store.document,d)
      }
      let fraction=try await h.edit(service,document,CustomKernelPresetAPI.name,["operation":"encode","format":"json","settings":["scale":1.5,"offset":-0.25]]);XCTAssertEqual(fraction,200)
      let stale=try await h.edit(service,document,CustomKernelPresetAPI.name,valid,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.customFilter);let busy=try await h.edit(service,document,CustomKernelPresetAPI.name,valid);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name==CustomKernelPresetAPI.name});XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:definition.schema));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:CustomKernelPresetAPI.capabilities))
      XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,61);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let id=try XCTUnwrap(service.shares.first?.id);service.revoke(id)
      let revoked=try await h.request(service,path:"/v1/documents/\(id)/commands",body:["command":CustomKernelPresetAPI.name,"revision":service.revision(document.store),"parameters":valid]);XCTAssertEqual(revoked.0.statusCode,404)
    }
  }
}
