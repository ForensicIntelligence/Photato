import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class QuickMaskSelectionWorkflowTests:XCTestCase {
  func model(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:16,height:4,depth:depth)
    d.name="Selection source";d.selection = .init(x:2,y:0,width:8,height:4)
    let plane=try AlphaChannel.coverage(d.coverageSelection(),width:16,height:4,depth:depth)
    d.alphaChannels=[AlphaChannel(name:"Subject",pixels:plane)];return d
  }
  @MainActor func testQuickMaskPreferencesPersistAndCancelDoesNotChangeDefaultsOrPixels()throws {
    let suite="Photato366-"+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
    defer{defaults.removePersistentDomain(forName:suite)}
    let preferences=QuickMaskPreferences(defaults:defaults),original=try model(),store=EditorStore(document:original,quickMaskPreferences:preferences)
    defer{store.renderTask?.cancel()}
    XCTAssertEqual(store.quickMaskOptions,ChannelDisplayOptions())
    store.beginChannelDialog(.quickOptions);let cancel=try XCTUnwrap(store.channelDialog)
    cancel.options.opacity=0.37;cancel.options.indicates = .selectedAreas;store.cancelChannelDialog()
    XCTAssertEqual(store.document,original);XCTAssertEqual(preferences.value,ChannelDisplayOptions())
    store.beginChannelDialog(.quickOptions);let commit=try XCTUnwrap(store.channelDialog)
    commit.options.opacity=0.37;commit.options.indicates = .selectedAreas;store.commitChannelDialog(commit)
    XCTAssertEqual(QuickMaskPreferences(defaults:defaults).value,commit.options);XCTAssertEqual(store.document,original)
    store.toggleQuickMask();XCTAssertEqual(store.document.quickMask?.options,commit.options)
    let coverage=store.document.quickMask?.pixels;store.reverseQuickMaskIndication()
    XCTAssertEqual(store.document.quickMask?.options.indicates,.maskedAreas);XCTAssertEqual(store.document.quickMask?.pixels,coverage)
    XCTAssertEqual(store.document.layers,original.layers)
  }
  @MainActor func testNativeSaveAndLoadAcrossDocumentsHaveOneDestinationUndo()async throws {
    _ = NSApplication.shared
    let controller=CraftDocumentController(),source=CraftNSDocument(model:try model()),destination=CraftNSDocument(model:try model(.f32))
    source.store.documentController=controller;destination.store.documentController=controller
    controller.addDocument(source);controller.addDocument(destination)
    defer{source.store.cancelChannelDialog();destination.store.cancelChannelDialog();source.store.renderTask?.cancel();destination.store.renderTask?.cancel();controller.removeDocument(source);controller.removeDocument(destination)}
    let original=source.store.document,before=destination.store.document
    source.store.beginChannelDialog(.save);let save=try XCTUnwrap(source.store.channelDialog)
    save.documentID=before.id;save.channelID=nil;save.name="Saved cross-document"
    source.store.commitChannelDialog(save);await save.task?.value
    XCTAssertNil(save.error);XCTAssertEqual(source.store.document,original)
    XCTAssertEqual(destination.store.document.alphaChannels?.count,2);XCTAssertEqual(destination.store.session.undoStack.count,1)
    let saved=destination.store.document,channel=try XCTUnwrap(saved.alphaChannels?.last)
    await destination.store.undo();XCTAssertEqual(destination.store.document,before);await destination.store.redo();XCTAssertEqual(destination.store.document,saved)
    source.store.perform(.selection(nil));let deselected=source.store.document
    source.store.beginChannelDialog(.load);let load=try XCTUnwrap(source.store.channelDialog)
    load.documentID=saved.id;load.channelID=channel.id;source.store.commitChannelDialog(load);await load.task?.value
    XCTAssertNil(load.error);XCTAssertEqual(source.store.document.selection,original.selection)
    XCTAssertEqual(destination.store.document,saved);await source.store.undo();XCTAssertEqual(source.store.document,deselected)
  }
  @MainActor func testNativeSelectionDialogRejectsChangedSourcesAndCancellation()async throws {
    let original=try model(),store=EditorStore(document:original,quickMaskPreferences:QuickMaskPreferences())
    defer{store.cancelChannelDialog();store.renderTask?.cancel()}
    store.beginChannelDialog(.save);let stale=try XCTUnwrap(store.channelDialog)
    var changedModel=store.document;changedModel.name="Changed";store.session=EditorSession(document:changedModel);let changed=store.document
    store.commitChannelDialog(stale);await stale.task?.value;XCTAssertNotNil(stale.error);XCTAssertEqual(store.document,changed)
    store.cancelChannelDialog();store.beginChannelDialog(.save);let cancel=try XCTUnwrap(store.channelDialog)
    store.commitChannelDialog(cancel);store.cancelChannelDialog();await cancel.task?.value
    XCTAssertEqual(store.document,changed);XCTAssertFalse(store.geometryBusy)
    store.perform(.selection(nil));XCTAssertFalse(store.canSaveSelectionChannel)
    store.beginChannelDialog(.save);XCTAssertNil(store.channelDialog)
  }
  @MainActor func testAlphaShortcutsAndThumbnailModifiersUseNativeSelectionPath()throws {
    let original=try model();let store=EditorStore(document:original,quickMaskPreferences:QuickMaskPreferences())
    defer{store.renderTask?.cancel()}
    let channel=try XCTUnwrap(original.alphaChannels?.first)
    for bits in 0..<16 {
      store.session=EditorSession(document:original);store.alphaEditingID=nil
      let flags=NSEvent.ModifierFlags(rawValue:([NSEvent.ModifierFlags.command,.control,.option,.shift].enumerated().reduce(UInt(0)){$0 | ((bits & (1 << $1.offset)) != 0 ? $1.element.rawValue:0)}))
      let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:"6",charactersIgnoringModifiers:"6",isARepeat:false,keyCode:22))
      let handled=store.handleComponentShortcut(event)
      XCTAssertEqual(handled,flags == [.command] || flags == [.command,.option])
      if flags == [.command] {XCTAssertEqual(store.alphaEditingID,channel.id)}
      if flags == [.command,.option] {XCTAssertNil(store.alphaEditingID);XCTAssertEqual(store.document.selection,original.selection)}
    }
    for flags:NSEvent.ModifierFlags in [[.command],[.command,.shift],[.command,.option],[.command,.shift,.option]] {
      store.session=EditorSession(document:original);store.channelThumbnail(channel.id,modifiers:flags)
      XCTAssertEqual(store.document.layers,original.layers);XCTAssertEqual(store.document.alphaChannels,original.alphaChannels)
    }
  }
  @MainActor func testHTTPCrossDocumentSelectionsAndInvalidLeases()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,destination in
      destination.store.session=EditorSession(document:try self.model(.f32));try service.share(destination)
      let source=CraftNSDocument(model:try self.model());service.controller.addDocument(source);try service.share(source)
      defer{source.store.renderTask?.cancel();service.controller.removeDocument(source)}
      let share=try XCTUnwrap(service.shares.first{$0.document === source}),original=destination.store.document,sourceBefore=source.store.document
      let parameters:[String:Any]=["action":"saveSelection","sourceDocumentID":share.id.uuidString,"sourceRevision":service.revision(source.store),"name":"From source"]
      let saved=try await helper.edit(service,destination,"channel.edit",parameters);XCTAssertEqual(saved,200)
      let result=destination.store.document;XCTAssertEqual(result.alphaChannels?.count,2);XCTAssertEqual(source.store.document,sourceBefore)
      await destination.store.undo();XCTAssertEqual(destination.store.document,original)
      let id=try XCTUnwrap(sourceBefore.alphaChannels?.first?.id)
      let loaded=try await helper.edit(service,destination,"channel.edit",["action":"loadSelection","sourceDocumentID":share.id.uuidString,"sourceRevision":service.revision(source.store),"target":id.uuidString,"invert":true])
      XCTAssertEqual(loaded,200);XCTAssertEqual(source.store.document,sourceBefore)
      let before=destination.store.document
      for (fields,status) in [(["action":"loadSelection","target":id.uuidString,"sourceDocumentID":share.id.uuidString],400),(["action":"loadSelection","target":id.uuidString,"sourceDocumentID":share.id.uuidString,"sourceRevision":"stale"],409),(["action":"loadSelection","target":id.uuidString,"sourceDocumentID":UUID().uuidString,"sourceRevision":"unknown"],404)] {
        let response=try await helper.edit(service,destination,"channel.edit",fields);XCTAssertEqual(response,status);XCTAssertEqual(destination.store.document,before)
      }
      let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name=="channel.edit"});let root=try XCTUnwrap(definition.schema["properties"]as?[String:Any]);let parametersSchema=try XCTUnwrap(root["parameters"]as?[String:Any]);XCTAssertNotNil((parametersSchema["properties"]as?[String:Any])?["sourceDocumentID"])
    }
  }
  @MainActor func testHTTPSourceRevocationDuringPreparationLeavesDestinationUntouched()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,destination in
      destination.store.session=EditorSession(document:try self.model());try service.share(destination)
      let source=CraftNSDocument(model:try self.model());service.controller.addDocument(source);try service.share(source)
      defer{source.store.renderTask?.cancel();service.controller.removeDocument(source)}
      let share=try XCTUnwrap(service.shares.first{$0.document === source}),before=destination.store.document
      service.selectionChannelPrepare={command,target,defaults,source,settings in
        try await Task.sleep(for:.milliseconds(100));return try SelectionChannelPreparation.prepare(command,target:target,defaults:defaults,source:source,colorSettings:settings)
      }
      let task=Task {try await helper.edit(service,destination,"channel.edit",["action":"saveSelection","sourceDocumentID":share.id.uuidString,"sourceRevision":service.revision(source.store),"name":"Revoked"])}
      let deadline=Date().addingTimeInterval(5)
      while !destination.store.geometryBusy && Date()<deadline {await Task.yield()}
      guard destination.store.geometryBusy else {task.cancel();_ = try? await task.value;return XCTFail("Selection preparation did not start before its bounded deadline")}
      service.revoke(share.id);let response=try await task.value
      XCTAssertEqual(response,409);XCTAssertEqual(destination.store.document,before);XCTAssertTrue(destination.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPQuickMaskOptionsEntryContextAndNativeEquality()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.model();document.store.session=EditorSession(document:original);try service.share(document)
      let old=document.store.quickMaskOptions
      defer{document.store.quickMaskOptions=old}
      let options:[String:Any]=["action":"quickMaskOptions","overlayColor":[0,1,0],"opacity":0.37,"indicates":"selectedAreas"]
      let configured=try await helper.edit(service,document,"channel.edit",options);XCTAssertEqual(configured,200);XCTAssertEqual(document.store.document,original)
      try document.store.selectAlphaChannel(try XCTUnwrap(original.alphaChannels?.first?.id))
      let entered=try await helper.edit(service,document,"channel.edit",["action":"quickMask","enabled":true]);XCTAssertEqual(entered,200)
      XCTAssertEqual(document.store.editingChannel,.quickMask);XCTAssertEqual(document.store.document.quickMask?.options,document.store.quickMaskOptions)
      let active=document.store.document,plane=active.quickMask?.pixels
      let configuredActive=try await helper.edit(service,document,"channel.edit",["action":"quickMaskOptions","opacity":0.8]);XCTAssertEqual(configuredActive,200);XCTAssertEqual(document.store.document.quickMask?.pixels,plane)
      let exited=try await helper.edit(service,document,"channel.edit",["action":"quickMask","enabled":false]);XCTAssertEqual(exited,200)
      XCTAssertEqual(document.store.document.selection,original.selection);XCTAssertEqual(document.store.document.layers,original.layers)
      let before=document.store.document
      let bad=try await helper.edit(service,document,"channel.edit",["action":"quickMaskOptions","opacity":1.1]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,before)
      XCTAssertNotNil(service.state(try XCTUnwrap(service.shares.first),document:document)["quickMaskOptions"])
    }
  }
}
