import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SmartFilterTransferWorkflowTests: XCTestCase {
  @MainActor func testNativeGroupDragAndHTTPShareStackContentMaskAndOneHistoryStep() async throws {
    let h = AutomationTests()
    for part in SmartFilterTransferRequest.Part.allCases { for copying in [true, false] {
      try await h.withService(pressedMouseButtons:{0}) { service, file in
        let original = try SmartFilterDragTests().fixture(); file.store.session = .init(document:original); try service.share(file)
        let source = original.layers[0].id, target = original.layers[1].id
        let native = EditorStore(document:original, actions:ActionLibrary()); defer { native.renderTask?.cancel() }
        let provider = SmartFilterGroupDrag.provider(store:native, layerID:source, part:part)
        let accepted = await SmartFilterGroupDrag.receive(provider, store:native, layerID:target, copying:copying)
        XCTAssertTrue(accepted); await native.geometryTask?.value; XCTAssertNil(native.error)
        let code = try await h.edit(service,file,SmartFilterTransferAPI.name,["sourceLayerID":source.uuidString,"targetLayerID":target.uuidString,"part":part.rawValue,"copy":copying])
        XCTAssertEqual(code,200); XCTAssertEqual(file.store.session.undoStack.count,1)
        XCTAssertEqual(file.store.document.layers[1].smartFilters?.filters.map(\.filter), native.document.layers[1].smartFilters?.filters.map(\.filter))
        XCTAssertEqual(file.store.document.layers[1].smartFilters?.mask, native.document.layers[1].smartFilters?.mask)
        XCTAssertEqual(file.store.document.layers[0].smartFilters?.filters.count, native.document.layers[0].smartFilters?.filters.count)
        XCTAssertEqual(try Renderer.composite(file.store.document), try Renderer.composite(native.document))
        let undo = try await h.edit(service,file,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(file.store.document,original)
      }
    } }
  }
  @MainActor func testInvalidStaleBusyAndLockedHTTPRequestsLeaveSourceAndTargetUntouched() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) { service,file in
      let original = try SmartFilterDragTests().fixture(); file.store.session = .init(document:original); try service.share(file)
      let parameters:[String:Any] = ["sourceLayerID":original.layers[0].id.uuidString,"targetLayerID":original.layers[1].id.uuidString,"part":"stack","copy":false]
      let stale = try await h.edit(service,file,SmartFilterTransferAPI.name,parameters,revision:"stale"); XCTAssertEqual(stale,409)
      file.store.geometryBusy = true
      let busy = try await h.edit(service,file,SmartFilterTransferAPI.name,parameters); XCTAssertEqual(busy,409); file.store.geometryBusy = false
      for (key,value) in [("part","unknown"),("copy","true"),("sourceLayerID","invalid")] {
        var bad = parameters; bad[key] = value
        let code = try await h.edit(service,file,SmartFilterTransferAPI.name,bad); XCTAssertEqual(code,400)
      }
      XCTAssertEqual(file.store.document,original)
      var locked = original; locked.layers[0].locked = true; file.store.session = .init(document:locked)
      let code = try await h.edit(service,file,SmartFilterTransferAPI.name,parameters); XCTAssertEqual(code,422)
      XCTAssertEqual(file.store.document,locked); XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testSemanticRecordingNeeds58AndKeepsExistingFeatureMinima() async throws {
    let original = try SmartFilterDragTests().fixture(), store = EditorStore(document:try SmartFilterDragTests().fixture(), actions:ActionLibrary())
    defer { store.renderTask?.cancel() }
    var session = EditorSession(document:original); try session.startActionRecording(name:"Copy stack")
    try session.execute(SmartFilterTransferRequest(sourceLayerID:original.layers[0].id,targetLayerID:original.layers[1].id,part:.stack,copy:true).command(in:original))
    let action = try XCTUnwrap(session.actionRecording?.snapshot); session.stopActionRecording()
    var library = ActionLibraryFile(); library.actions = [action]
    XCTAssertEqual(library.requiredVersion,58)
    let data = try library.encoded(); XCTAssertEqual(try ActionLibraryFile.decode(data).version,58)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]); json["version"] = 57
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:json)))
    library.actions = [.init(name:"Old",steps:[.init(name:"Filters",operation:.filters(.active,original.layers[0].smartFilters))])]
    XCTAssertLessThan(library.requiredVersion,58)
    XCTAssertEqual(ActionLibraryFile.maximumVersion,60); XCTAssertEqual(AutomationCommand.definitions.count,267)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:SmartFilterTransferAPI.capabilities))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:SmartFilterStack.apiCapabilities))
  }
  @MainActor func testAllSixteenModifiersKeepDropProposalAndDispatchedCopyPolicyAligned() throws {
    let original = try SmartFilterDragTests().fixture(), store = EditorStore(document:try SmartFilterDragTests().fixture())
    defer { store.renderTask?.cancel() }; store.session = .init(document:original)
    for bits in 0..<16 {
      let flags:[NSEvent.ModifierFlags] = [.control,.command,.option,.shift]
      let modifiers = flags.enumerated().reduce(into:NSEvent.ModifierFlags()) { if bits & (1 << $1.offset) != 0 { $0.insert($1.element) } }
      let copying = SmartFilterDrag.operation(modifiers) == .copy
      XCTAssertEqual(copying,modifiers.contains(.option))
      _ = SmartFilterGroupDrag.provider(store:store,layerID:original.layers[0].id,part:.stack)
      XCTAssertTrue(SmartFilterGroupDrag.canReceive(store:store,layerID:original.layers[1].id,copying:copying))
    }
  }
  @MainActor func testForeignSupersededAndMalformedPrivatePayloadsCannotTransfer() async throws {
    let original = try SmartFilterDragTests().fixture(), store = EditorStore(document:try SmartFilterDragTests().fixture()), other = EditorStore(document:try SmartFilterDragTests().fixture())
    defer { store.renderTask?.cancel(); other.renderTask?.cancel() }; store.session = .init(document:original)
    let source = original.layers[0].id,target = original.layers[1].id
    var provider = SmartFilterGroupDrag.provider(store:store,layerID:source,part:.stack)
    _ = SmartFilterGroupDrag.provider(store:store,layerID:source,part:.mask)
    var accepted = await SmartFilterGroupDrag.receive(provider,store:store,layerID:target,copying:true); XCTAssertFalse(accepted)
    provider = SmartFilterGroupDrag.provider(store:store,layerID:source,part:.stack)
    accepted = await SmartFilterGroupDrag.receive(provider,store:other,layerID:other.document.layers[0].id,copying:true); XCTAssertFalse(accepted)
    let bad = NSItemProvider(); bad.registerDataRepresentation(forTypeIdentifier:SmartFilterGroupDrag.identifier,visibility:.ownProcess) { completion in completion(Data(repeating:65,count:200),nil); return nil }
    accepted = await SmartFilterGroupDrag.receive(bad,store:store,layerID:target,copying:true); XCTAssertFalse(accepted)
    XCTAssertEqual(store.document,original); XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testImportedEmptyStackMaskAndLockedSourceCopyMatchCoreAvailability() async throws {
    var original = try SmartFilterDragTests().fixture(); original.layers[0].smartFilters?.filters = []
    original.layers[0].locked = true
    let store = EditorStore(document:original); defer { store.renderTask?.cancel() }
    let source = original.layers[0].id, target = original.layers[1].id
    let provider = SmartFilterGroupDrag.provider(store:store,layerID:source,part:.mask)
    XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(SmartFilterGroupDrag.identifier))
    XCTAssertTrue(SmartFilterGroupDrag.canReceive(store:store,layerID:target,copying:true))
    XCTAssertFalse(SmartFilterGroupDrag.canReceive(store:store,layerID:target,copying:false))
    let accepted = await SmartFilterGroupDrag.receive(provider,store:store,layerID:target,copying:true)
    XCTAssertTrue(accepted); await store.geometryTask?.value; XCTAssertNil(store.error)
    XCTAssertEqual(store.document.layers[0],original.layers[0])
    XCTAssertEqual(store.document.layers[1].smartFilters?.mask,original.layers[0].smartFilters?.mask)
  }
  @MainActor func testSelectedFilterMaskWithOrdinaryMaskKeepsNativeAndAPIContextInSync() async throws {
    let h = AutomationTests()
    for copying in [true,false] {
      try await h.withService(pressedMouseButtons:{0}) { service,file in
        var original = try SmartFilterDragTests().fixture()
        original.layers[0].mask = try Surface(width:8,height:8,fill:.white)
        file.store.session = .init(document:original)
        let native = EditorStore(document:original); defer { native.renderTask?.cancel() }
        let source = original.layers[0].id,target = original.layers[1].id
        native.selectSmartFilterMask(source); file.store.selectSmartFilterMask(source)
        XCTAssertTrue(native.editingMask); XCTAssertTrue(native.smartFilterMaskEditing)
        try service.share(file)
        let provider = SmartFilterGroupDrag.provider(store:native,layerID:source,part:.mask)
        let accepted = await SmartFilterGroupDrag.receive(provider,store:native,layerID:target,copying:copying)
        XCTAssertTrue(accepted); await native.geometryTask?.value; XCTAssertNil(native.error)
        let code = try await h.edit(service,file,SmartFilterTransferAPI.name,["sourceLayerID":source.uuidString,"targetLayerID":target.uuidString,"part":"mask","copy":copying])
        XCTAssertEqual(code,200)
        XCTAssertEqual(file.store.document,native.document)
        XCTAssertEqual(file.store.maskEditingLayerID,native.maskEditingLayerID)
        XCTAssertEqual(file.store.smartFilterMaskEditing,native.smartFilterMaskEditing)
        XCTAssertEqual(file.store.smartFilterMaskEditing,copying)
        XCTAssertEqual(file.store.document.layers[0].mask,original.layers[0].mask)
        XCTAssertEqual(file.store.session.undoStack.count,1)
      }
    }
  }
  @MainActor func testCancelledAndRevokedPreparedTransfersNeverPublishEitherSide() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) { service,file in
      let original = try SmartFilterDragTests().fixture(); file.store.session = .init(document:original); try service.share(file)
      let share = try XCTUnwrap(service.shares.first?.id), revision = service.revision(file.store)
      let request = SmartFilterTransferRequest(sourceLayerID:original.layers[0].id,targetLayerID:original.layers[1].id,part:.stack,copy:false)
      let pending = Task {
        try await service.executePreparedOperation(document:file,shareID:share,revision:revision) { source in
          let command = try request.command(in:source); try await Task.sleep(for:.seconds(5)); return command
        }
      }
      for _ in 0..<200 where !file.store.geometryBusy { try await Task.sleep(for:.milliseconds(5)) }
      file.store.cancelActiveOperation()
      do { try await pending.value; XCTFail("Cancelled transfer committed") } catch {}
      XCTAssertEqual(file.store.document,original)
      do {
        try await service.executePreparedOperation(document:file,shareID:share,revision:revision,validateCommit:{service.revoke(share);throw AutomationFailure(status:409,message:"Revoked")}) { try request.command(in:$0) }
        XCTFail("Revoked transfer committed")
      } catch {}
      XCTAssertEqual(file.store.document,original); XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
}
