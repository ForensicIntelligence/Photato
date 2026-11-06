import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class TypographyPanelTests: XCTestCase {
  // Frozen catalog2, including reordered/grouped utilities and closed panels.
  let catalog2 = """
  {"catalogVersion":2,"groups":[
    {"id":"color","panels":["Patterns","Color","Gradients","Swatches"],"selected":"Gradients","collapsed":true,"preferredHeight":207},
    {"id":"properties","panels":["Properties","Libraries","Adjustments"],"selected":"Properties","collapsed":false,"columnID":"left","floatingFrame":{"x":-400,"y":200,"width":410,"height":350}},
    {"id":"layers","panels":["Layers","Channels","Paths"],"selected":"Paths","collapsed":false},
    {"id":"typography","panels":["Clone Source","History"],"selected":"History","collapsed":false,"columnID":"left"}
  ],"hidden":["Swatches","History"],"columns":[{"id":"left","side":"left","width":410,"collapsed":false,"iconWidth":140},{"id":"main","side":"right"}]}
  """
  func json<T:Encodable>(_ value:T)throws->[String:Any] { try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any] }
  func value(_ value:Any)throws->AutomationValue { try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:value)) }
  @MainActor func descendants<T:NSView>(_ view:NSView,_ type:T.Type)->[T] { (view as?T).map{[$0]} ?? view.subviews.flatMap{descendants($0,type)} }
  func model(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var document = try CraftDocument(width:180,height:100,depth:depth)
    document.layers[0].locked = false
    document.layers[0].content = .text(TextContent(text:"Alpha\nBeta",fontName:"HelveticaNeue",size:16,color:.black).promoted(dpi:72))
    return document
  }
  func testCatalogTwoMigrationPreservesEveryOldPlacementAndIsIdempotent() throws {
    let data = Data(catalog2.utf8), raw = try JSONSerialization.jsonObject(with:data)as! [String:Any]
    let old = try JSONDecoder().decode([PanelDockGroup].self,from:JSONSerialization.data(withJSONObject:raw["groups"]!))
    let dock = try JSONDecoder().decode(PanelDock.self,from:data)
    XCTAssertEqual(dock.catalogVersion,3);XCTAssertEqual(Array(dock.groups.prefix(4)),old)
    XCTAssertEqual(dock.orderedColumns.map(\.id),["left","main"])
    XCTAssertEqual(dock.hidden,[.swatches,.history,.character,.paragraph])
    let added = try XCTUnwrap(dock.groups.last)
    XCTAssertEqual(added.panels,[.character,.paragraph]);XCTAssertEqual(added.selected,.character)
    XCTAssertEqual(added.dockColumnID,"left");XCTAssertNotEqual(added.id,"typography")
    XCTAssertEqual(Set(dock.groups.flatMap(\.panels)),Set(WorkspacePanel.allCases))
    XCTAssertEqual(try JSONDecoder().decode(PanelDock.self,from:JSONEncoder().encode(dock)),dock)
  }
  func testCorruptOldAndCurrentCatalogsRejectWithoutHealingMissingPanels() throws {
    let raw = try JSONSerialization.jsonObject(with:Data(catalog2.utf8))as! [String:Any]
    for kind in 0..<6 {
      var invalid = raw;var groups = invalid["groups"]as! [[String:Any]]
      if kind == 0 { groups[0]["panels"] = ["Patterns","Color","Gradients"] }
      if kind == 1 { groups[0]["panels"] = ["Patterns","Color","Gradients","Color"] }
      if kind == 2 { invalid["hidden"] = ["Character"] }
      if kind == 3 { invalid["catalogVersion"] = 3 }
      if kind == 4 { invalid["catalogVersion"] = 4 }
      if kind == 5 { groups[1]["floatingFrame"] = ["x":0,"y":0,"width":274,"height":350] }
      invalid["groups"] = groups
      XCTAssertThrowsError(try JSONDecoder().decode(PanelDock.self,from:JSONSerialization.data(withJSONObject:invalid)),"Case \(kind)")
    }
  }
  @MainActor func testMigrationLoadSaveResetReopenRevisionAndWriteFailureAreAtomic() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try?FileManager.default.removeItem(at:directory)}
    let url = directory.appendingPathComponent("Workspaces.json")
    var raw = try json(WorkspaceState());var rows = raw["workspaces"]as! [[String:Any]];var layout = rows[0]["lastUsed"]as! [String:Any]
    layout["panelDock"] = try JSONSerialization.jsonObject(with:Data(catalog2.utf8));rows[0]["lastUsed"] = layout;raw["workspaces"] = rows
    let bytes = try JSONSerialization.data(withJSONObject:raw);try bytes.write(to:url)
    let library = WorkspaceLibrary(persistenceURL:url);XCTAssertNil(library.error);XCTAssertEqual(try Data(contentsOf:url),bytes)
    let before = library.layout, initial = library.panelRevision
    try library.setPanelVisible(.character,true);XCTAssertNotEqual(library.panelRevision,initial)
    XCTAssertEqual(library.layout.panelDock?.groups.prefix(4).map{$0},before.panelDock?.groups.prefix(4).map{$0})
    let revision = library.panelRevision;try library.setPanelVisible(.character,true);XCTAssertEqual(library.panelRevision,revision)
    try library.save(name:"Typography");let saved = library.layout
    try library.setPanelVisible(.paragraph,true);try library.reset();XCTAssertEqual(library.layout,saved)
    let reopened = WorkspaceLibrary(persistenceURL:url);XCTAssertNil(reopened.error);XCTAssertEqual(reopened.layout,saved)
    let failing = WorkspaceLibrary(persistenceURL:url,writer:{_,_ in throw CraftError.invalid("Owned simulated write failure")})
    let prior = failing.layout, priorRevision = failing.panelRevision, priorBytes = try Data(contentsOf:url)
    XCTAssertThrowsError(try failing.setPanelVisible(.paragraph,true));XCTAssertEqual(failing.layout,prior);XCTAssertEqual(failing.panelRevision,priorRevision);XCTAssertEqual(try Data(contentsOf:url),priorBytes)
    let command = try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"workspace.panels","revision":"fixture","parameters":["workspaceRevision":priorRevision.uuidString,"operation":"show","panel":"Paragraph"]]))
    XCTAssertThrowsError(try WorkspacePanelsAPI.apply(command,library:failing)){XCTAssertEqual(($0 as?AutomationFailure)?.status,422)}
    XCTAssertEqual(failing.layout,prior);XCTAssertEqual(failing.panelRevision,priorRevision)
  }
  @MainActor func testNativeMenuPathsRevealSamePanelsDuringTypeEditingAndRetainFactoryKeys() throws {
    try PhotoshopMenuTests().withMenus {app,menu in
      let document = CraftNSDocument(model:try model());let windows = app.controller.documentWindows
      windows.floatingPanels.presentsWindows = false
      app.controller.addDocument(document);document.makeWindowControllers();document.store.renderTask?.cancel()
      defer{document.store.finishType(cancel:true);document.close();windows.floatingPanels.dismissAll()}
      let store = document.store, before = try document.data(ofType:CraftNSDocument.nativeType)
      store.beginType(try XCTUnwrap(store.activeLayer));XCTAssertNotNil(store.typeEditingDraft)
      XCTAssertFalse(windows.canChangeDocument);XCTAssertTrue(windows.canUseTypographyPanels)
      for (path,panel)in [("Window > Character",WorkspacePanel.character),("Type > Panels > Character Panel",.character),("Window > Paragraph",.paragraph),("Type > Panels > Paragraph Panel",.paragraph)] {
        app.controller.workspaces.closePanels([panel]);app.controller.workspaces.layout.visibility.rail = false
        let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first{$0.identifier?.rawValue == path})
        XCTAssertEqual(item.keyEquivalent,"");XCTAssertTrue(app.validateMenuItem(item));XCTAssertEqual(item.state,.off)
        try XCTUnwrap(item.menu).performActionForItem(at:item.menu!.index(of:item))
        XCTAssertFalse(app.controller.workspaces.panelDock.hidden.contains(panel));XCTAssertTrue(app.controller.workspaces.layout.visibility.rail)
        XCTAssertTrue(app.validateMenuItem(item));XCTAssertEqual(item.state,.on)
        XCTAssertNotNil(store.typeEditingDraft);XCTAssertEqual(try document.data(ofType:CraftNSDocument.nativeType),before)
      }
      store.geometryBusy = true;XCTAssertFalse(windows.canUseTypographyPanels);store.geometryBusy = false
      XCTAssertTrue(store.finishType(cancel:true));XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testPanelDockFloatLockVisibilityAndDocumentSwitchRetainContent() throws {
    let controller = CraftDocumentController(workspaces:WorkspaceLibrary()), windows = controller.documentWindows
    windows.floatingPanels.presentsWindows = false
    let documents = [CraftNSDocument(model:try model()),CraftNSDocument(model:try model(.f32))]
    for document in documents {controller.addDocument(document);document.makeWindowControllers();document.store.renderTask?.cancel()}
    defer{for document in documents{document.close()};windows.floatingPanels.dismissAll()}
    let library = controller.workspaces, before = try documents.map{try $0.data(ofType:CraftNSDocument.nativeType)}
    for panel in [WorkspacePanel.character,.paragraph] {
      try library.setPanelVisible(panel,true)
      XCTAssertTrue(library.movePanels(.panel(panel),to:.newColumn(.left,before:nil)))
      XCTAssertTrue(library.floatPanels(.panel(panel),frame:.init(NSRect(x:120,y:180,width:322,height:450))))
    }
    windows.floatingPanels.synchronize();XCTAssertEqual(windows.floatingPanels.controllers.count,2)
    for document in documents {XCTAssertTrue(windows.activate(document));windows.floatingPanels.synchronize()}
    try library.setWorkspaceLocked(true)
    for panel in [WorkspacePanel.character,.paragraph] {
      XCTAssertFalse(library.movePanels(.panel(panel),to:.group("layers",before:nil)))
      try library.setPanelVisible(panel,false);try library.setPanelVisible(panel,true)
      XCTAssertFalse(library.panelDock.hidden.contains(panel))
    }
    XCTAssertEqual(try documents.map{try $0.data(ofType:CraftNSDocument.nativeType)},before)
    XCTAssertTrue(documents.allSatisfy{$0.store.session.undoStack.isEmpty})
  }
  @MainActor func testMixedFloatingStackKeepsTypeControlsAvailableDuringTyping() throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces:WorkspaceLibrary()), windows = controller.documentWindows
    windows.floatingPanels.presentsWindows = false
    let document = CraftNSDocument(model:try model())
    controller.addDocument(document);document.makeWindowControllers();document.store.renderTask?.cancel()
    defer{document.store.finishType(cancel:true);document.close();windows.floatingPanels.dismissAll()}
    let store = document.store, library = controller.workspaces
    try library.setPanelVisible(.character,true)
    XCTAssertTrue(library.floatPanels(.panel(.character),frame:.init(NSRect(x:80,y:100,width:322,height:600))))
    let group = try XCTUnwrap(library.panelDock.groups.first{$0.panels == [.character]})
    XCTAssertTrue(library.stackPanels(.group("layers"),hostID:group.floatingHostID,before:nil))
    let hostID = try XCTUnwrap(library.panelDock.groups.first{$0.panels.contains(.character)}).floatingHostID
    XCTAssertEqual(library.panelDock.floatingGroups(hostID).count,2)
    store.beginType(try XCTUnwrap(store.activeLayer));XCTAssertNotNil(store.typeEditingDraft)
    XCTAssertFalse(windows.canChangeDocument);XCTAssertTrue(windows.canUseTypographyPanels)
    windows.floatingPanels.synchronize()
    let panel = try XCTUnwrap(windows.floatingPanels.controllers[hostID]?.window)
    let content = try XCTUnwrap(panel.contentView)
    content.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.05));content.layoutSubtreeIfNeeded()
    let field = try XCTUnwrap(descendants(content,NSTextField.self).first{$0.placeholderString == "Size (pt)"})
    XCTAssertTrue(field.isEnabled,"A separate Layers row must not disable the Character controls")
    XCTAssertNotNil(store.typeEditingDraft);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testScopedControlsFitOffscreenAndPreserveSelectedRangeCancelAndUndo() async throws {
    let store = EditorStore(document:try model());store.renderTask?.cancel();defer{store.renderTask?.cancel()}
    let original = store.document
    store.beginType(try XCTUnwrap(store.activeLayer));let draft = try XCTUnwrap(store.typeEditingDraft)
    let editor = try CanvasTypeEditor(store:store,draft:draft);store.typeEditor = editor
    editor.setSelectedRange(NSRange(location:1,length:3))
    for panel in [WorkspacePanel.character,.paragraph] {
      for size in [NSSize(width:275,height:160),NSSize(width:322,height:450)] {
        let host = NSHostingView(rootView:WorkspaceView(store:store).dockContent(panel));host.sizingOptions = []
        let window = NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named:.darkAqua);window.contentView = host
        defer{window.contentView = nil;window.close()}
        host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(30));host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(host,NSScrollView.self).first)
        XCTAssertLessThanOrEqual(scroll.visibleRect.height,host.bounds.height + 0.001)
        let fields = descendants(host,NSTextField.self)
        let labels = fields.map{$0.accessibilityLabel() ?? $0.placeholderString ?? ""}
        if let base = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let diagnostics = fields.map{["label":$0.accessibilityLabel() ?? "", "placeholder":$0.placeholderString ?? "", "identifier":$0.identifier?.rawValue ?? "", "value":$0.stringValue]}
          try JSONSerialization.data(withJSONObject:diagnostics,options:.prettyPrinted).write(to:URL(fileURLWithPath:base).appendingPathComponent("437-" + panel.rawValue + "-" + String(Int(size.height)) + "-fields.json"))
        }
        XCTAssertEqual(labels.contains("Size (pt)"),panel == .character)
        XCTAssertEqual(editor.selectedRange(),NSRange(location:1,length:3));XCTAssertEqual(store.document,original)
        if panel == .paragraph,size.height == 450,let base = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
          host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:base).appendingPathComponent("437-paragraph-offscreen.png"))
        }
      }
    }
    store.formatType{s,_ in s.underline = true;s.tracking = 80}
    XCTAssertEqual(editor.selectedRange(),NSRange(location:1,length:3));XCTAssertEqual(store.document,original)
    store.formatType(paragraph:true){_,p in p.alignment = .right;p.spaceAfter = 4}
    if let base = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let storage = NSTextStorage(attributedString:try NativeTextLayout.attributed(draft.content,dpi:72))
      let manager = NSLayoutManager(), container = NSTextContainer(size:NSSize(width:32768,height:32768))
      manager.usesFontLeading = true;container.lineFragmentPadding = 0
      manager.addTextContainer(container);storage.addLayoutManager(manager);manager.ensureLayout(for:container)
      let used = manager.usedRect(for:container)
      let probe:[String:Any] = ["usedRect":[used.minX,used.minY,used.width,used.height],"legacyMetricWidth":max(1,Int(ceil(used.maxX))+2),"legacyMetricHeight":max(1,Int(ceil(used.maxY))+2),"selection":[editor.selectedRange().location,editor.selectedRange().length]]
      try JSONSerialization.data(withJSONObject:probe,options:.prettyPrinted).write(to:URL(fileURLWithPath:base).appendingPathComponent("437-point-right-layout.json"))
      try JSONEncoder().encode(draft.content).write(to:URL(fileURLWithPath:base).appendingPathComponent("437-point-right-type.json"))
    }
    XCTAssertTrue(store.finishType());XCTAssertNil(store.error);let edited = store.document
    XCTAssertEqual(store.session.undoStack.count,1)
    guard case .text(let text) = edited.layers[0].content else{return XCTFail("Editable type lost")}
    let attributed = try NativeTextLayout.attributed(text,dpi:72)
    XCTAssertFalse(NativeTextLayout.styles(attributed.attributes(at:0,effectiveRange:nil),dpi:72).0.underline)
    XCTAssertTrue(NativeTextLayout.styles(attributed.attributes(at:1,effectiveRange:nil),dpi:72).0.underline)
    XCTAssertFalse(NativeTextLayout.styles(attributed.attributes(at:4,effectiveRange:nil),dpi:72).0.underline)
    XCTAssertEqual(NativeTextLayout.styles(attributed.attributes(at:0,effectiveRange:nil),dpi:72).1.alignment,.right)
    XCTAssertEqual(NativeTextLayout.styles(attributed.attributes(at:6,effectiveRange:nil),dpi:72).1.alignment,.left)
    await store.undo();XCTAssertEqual(store.document,original);await store.redo();XCTAssertEqual(store.document,edited)
    store.beginType(try XCTUnwrap(store.activeLayer));store.typeEditingDraft?.content.text = "cancel";XCTAssertTrue(store.finishType(cancel:true));XCTAssertEqual(store.document,edited)
  }
  @MainActor func testNativeCharacterNumericControlChangesOnlyTheSelectedRange() throws {
    _ = NSApplication.shared
    let store = EditorStore(document:try model());store.renderTask?.cancel();defer{store.renderTask?.cancel()}
    let original = store.document
    store.beginType(try XCTUnwrap(store.activeLayer));let draft = try XCTUnwrap(store.typeEditingDraft)
    let editor = try CanvasTypeEditor(store:store,draft:draft);store.typeEditor = editor
    editor.setSelectedRange(NSRange(location:1,length:3))
    let host = NSHostingView(rootView:TypographyPanel(store:store,panel:.character));host.sizingOptions = []
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:322,height:450),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named:.darkAqua);window.contentView = host
    defer{store.finishType(cancel:true);window.contentView = nil;window.close()}
    host.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.03));host.layoutSubtreeIfNeeded()
    let field = try XCTUnwrap(descendants(host,NSTextField.self).first{$0.placeholderString == "Size (pt)"})
    XCTAssertTrue(window.makeFirstResponder(field))
    let input = try XCTUnwrap(field.currentEditor() as? NSTextView)
    input.selectAll(nil);input.insertText("24",replacementRange:NSRange(location:0,length:input.string.utf16.count))
    input.doCommand(by:#selector(NSResponder.insertNewline(_:)))
    _ = window.makeFirstResponder(host)
    RunLoop.main.run(until:Date().addingTimeInterval(0.03))
    XCTAssertNil(store.error)
    let attributed = try NativeTextLayout.attributed(draft.content,dpi:72)
    XCTAssertEqual(NativeTextLayout.styles(attributed.attributes(at:0,effectiveRange:nil),dpi:72).0.size,16)
    XCTAssertEqual(NativeTextLayout.styles(attributed.attributes(at:1,effectiveRange:nil),dpi:72).0.size,24)
    XCTAssertEqual(NativeTextLayout.styles(attributed.attributes(at:4,effectiveRange:nil),dpi:72).0.size,16)
    XCTAssertEqual(editor.selectedRange(),NSRange(location:1,length:3));XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPPresentationAndCompleteNativeLayoutHaveExactStateAndNoImageEffects() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document);let library = document.store.workspaceLibrary
      let before = try document.data(ofType:CraftNSDocument.nativeType), revision = service.revision(document.store)
      var parameters:[String:Any] = ["workspaceRevision":library.panelRevision.uuidString,"operation":"show","panel":"Character"]
      let denied = try await helper.edit(service,document,"workspace.panels",parameters);XCTAssertEqual(denied,403)
      service.setWorkspacePanelChangesEnabled(true)
      let shown = try await helper.edit(service,document,"workspace.panels",parameters);XCTAssertEqual(shown,200)
      XCTAssertFalse(library.panelDock.hidden.contains(.character))
      let native = WorkspaceLibrary();native.layout = library.layout
      try native.setPanelVisible(.paragraph,true);XCTAssertTrue(native.floatPanels(.panel(.paragraph),frame:.init(NSRect(x:-200,y:300,width:400,height:430))))
      let state = WorkspacePanelsAPI.state(native,allowed:true)
      parameters = ["workspaceRevision":library.panelRevision.uuidString,"operation":"layout","layout":state["layout"]!]
      let arranged = try await helper.edit(service,document,"workspace.panels",parameters);XCTAssertEqual(arranged,200)
      XCTAssertEqual(library.layout,native.layout)
      let noOpRevision = library.panelRevision
      parameters["workspaceRevision"] = noOpRevision.uuidString
      let noOp = try await helper.edit(service,document,"workspace.panels",parameters);XCTAssertEqual(noOp,200);XCTAssertEqual(library.panelRevision,noOpRevision)
      XCTAssertEqual(try document.data(ofType:CraftNSDocument.nativeType),before);XCTAssertEqual(service.revision(document.store),revision);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let exposed = WorkspacePanelsAPI.state(library,allowed:true)
      XCTAssertNoThrow(try BrushAPI.merge(self.value(exposed),schema:WorkspacePanelsAPI.stateSchema))
      let share = try XCTUnwrap(service.shares.first)
      XCTAssertNotNil(service.state(share,document:document)["workspacePanels"])
    }
  }
  @MainActor func testHTTPStrictStaleBusyLockTypingAndRevokedGuards() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      try service.share(document);service.setWorkspacePanelChangesEnabled(true)
      let store = document.store, library = store.workspaceLibrary
      @MainActor func params(_ operation:String = "show",_ panel:String = "Paragraph")->[String:Any] {["workspaceRevision":library.panelRevision.uuidString,"operation":operation,"panel":panel]}
      let before = library.layout, initial = library.panelRevision
      for patch in [["workspaceRevision":"bad"],["workspaceRevision":UUID().uuidString],["operation":"missing"],["panel":"missing"],["layout":[:]], ["unknown":true]]as [[String:Any]] {
        var request = params();request.merge(patch){_,new in new}
        let status = try await helper.edit(service,document,"workspace.panels",request)
        XCTAssertEqual(status,patch["workspaceRevision"]as?String == nil ? 400 : (patch["workspaceRevision"]as?String == "bad" ? 400:409))
        XCTAssertEqual(library.layout,before);XCTAssertEqual(library.panelRevision,initial)
      }
      store.geometryBusy = true;let busy = try await helper.edit(service,document,"workspace.panels",params());XCTAssertEqual(busy,409);store.geometryBusy = false
      try library.setWorkspaceLocked(true)
      let shown = try await helper.edit(service,document,"workspace.panels",params());XCTAssertEqual(shown,200)
      let locked = try await helper.edit(service,document,"workspace.panels",["workspaceRevision":library.panelRevision.uuidString,"operation":"layout","layout":WorkspacePanelsAPI.state(library,allowed:true)["layout"]!]);XCTAssertEqual(locked,409)
      try library.setWorkspaceLocked(false)
      store.beginType(at:.zero,end:.zero);XCTAssertNotNil(store.typeEditingDraft)
      let whileTyping = try await helper.edit(service,document,"workspace.panels",params("show","Character"));XCTAssertEqual(whileTyping,200);XCTAssertNotNil(store.typeEditingDraft)
      let other = try await helper.edit(service,document,"workspace.panels",params("show","Layers"));XCTAssertEqual(other,409)
      XCTAssertTrue(store.finishType(cancel:true))
      let old = params();try library.setPanelVisible(.character,false)
      let stale = try await helper.edit(service,document,"workspace.panels",old);XCTAssertEqual(stale,409)
      let id = try XCTUnwrap(service.shares.first?.id);service.revoke(id)
      let revoked = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"workspace.panels","revision":service.revision(store),"parameters":params()]);XCTAssertEqual(revoked.0.statusCode,404)
      service.stop();XCTAssertFalse(service.workspacePanelChangesEnabled);XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testExistingTextAPIAndPanelFormattingRetainExactDocumentsAtEveryDepth() async throws {
    let helper = AutomationTests()
    for depth in PixelDepth.allCases {
      try await helper.withService(pressedMouseButtons:{0}) {service,document in
        let source = try self.model(depth);document.store.session = EditorSession(document:source);document.store.renderTask?.cancel()
        let native = EditorStore(document:source);native.renderTask?.cancel();defer{native.renderTask?.cancel()}
        let layer = try XCTUnwrap(native.activeLayer)
        native.beginType(layer);let draft = try XCTUnwrap(native.typeEditingDraft);let editor = try CanvasTypeEditor(store:native,draft:draft);native.typeEditor = editor
        editor.setSelectedRange(NSRange(location:1,length:3));native.formatType{s,_ in s.underline = true;s.tracking = 75}
        native.formatType(paragraph:true){_,p in p.alignment = .center;p.spaceAfter = 6}
        XCTAssertTrue(native.finishType());let text = try XCTUnwrap(native.editableType)
        try service.share(document)
        let status = try await helper.edit(service,document,"text.set",["layerID":layer.id.uuidString,"text":text.apiType]);XCTAssertEqual(status,200)
        XCTAssertEqual(document.store.document,native.document)
        XCTAssertEqual(try document.data(ofType:CraftNSDocument.nativeType),try DocumentIO.encode(native.document,format:.native))
        XCTAssertEqual(document.store.session.undoStack.count,1)
        await document.store.undo();XCTAssertEqual(document.store.document,source)
      }
    }
  }
}
