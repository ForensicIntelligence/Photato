import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest
@testable import PhotoCraft

final class WorkflowGuideTests: XCTestCase {
  @MainActor func testRankedSuggestionsApplyTheSavedLimitBeforeTheyAreShown() throws {
    let suite = "photato.guide.settings.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = WorkflowGuidePreferences(defaults: defaults)
    let guide = WorkflowGuideModel(preferences: preferences)
    var state = WorkflowGuideSnapshot()
    state.documentID = UUID()
    state.layerID = UUID()
    state.isRaster = true
    state.canChangeOpacity = true
    state.canTransform = true
    guide.update(state)
    XCTAssertEqual(guide.suggestions, [WorkflowGuideContent.opacity, WorkflowGuideContent.duplicate,
      WorkflowGuideContent.addMask, WorkflowGuideContent.transform])
    preferences.setMaximumSuggestions(2)
    XCTAssertEqual(guide.suggestions, [WorkflowGuideContent.opacity, WorkflowGuideContent.duplicate])
    preferences.setMaximumSuggestions(0)
    XCTAssertEqual(guide.suggestions.count, 2)
    preferences.opensAtLaunch = true
    preferences.setShown(true)
    let reloaded = WorkflowGuidePreferences(defaults: defaults)
    XCTAssertEqual(reloaded.maximumSuggestions, 2)
    XCTAssertTrue(reloaded.opensAtLaunch)
    XCTAssertFalse(reloaded.isShown)
    preferences.setMaximumSuggestions(8)
    XCTAssertEqual(guide.suggestions.count, 7)
    XCTAssertEqual(guide.suggestions.last, WorkflowGuideContent.save)
  }

  @MainActor func testSuggestionsFollowLayerSelectionToolOptionsAndMaskState() throws {
    let document = try CraftDocument(width: 8, height: 6)
    let store = EditorStore(document: document)
    defer { store.renderTask?.cancel() }
    let model = WorkflowGuideModel()
    XCTAssertTrue(model.suggestions.isEmpty)
    let original = WorkflowGuideSnapshot.capture(store)
    model.update(original)
    XCTAssertEqual(model.context, .layer)
    XCTAssertLessThanOrEqual(model.suggestions.count, 4)
    XCTAssertTrue(model.suggestions.contains(WorkflowGuideContent.duplicate))
    store.tool = .marquee
    store.selectionAntiAlias.toggle()
    model.update(.capture(store))
    XCTAssertEqual(model.context, .selection)
    XCTAssertTrue(model.suggestions.contains(WorkflowGuideContent.select))
    XCTAssertFalse(model.suggestions.contains(WorkflowGuideContent.saveSelection))
    var selection = WorkflowGuideSnapshot.capture(store)
    selection.hasSelection = true
    model.update(selection)
    XCTAssertTrue(model.suggestions.contains(WorkflowGuideContent.saveSelection))
    selection.hasMask = true
    selection.editingMask = true
    model.update(selection)
    XCTAssertEqual(model.context, .mask)
    XCTAssertTrue(model.suggestions.contains(WorkflowGuideContent.paintMask))
    XCTAssertFalse(model.suggestions.contains(WorkflowGuideContent.addMask))
  }

  @MainActor func testWalkthroughChecksActualChangesAndPausesForDifferentDocument() throws {
    var state = WorkflowGuideSnapshot()
    state.documentID = UUID()
    state.layerID = UUID()
    state.layerName = "Owned layer"
    state.layerCount = 3
    let model = WorkflowGuideModel()
    model.update(state)
    model.start(WorkflowGuideContent.duplicate)
    XCTAssertEqual(model.walkthrough?.index, 0)
    XCTAssertTrue(model.stepObserved)
    model.next()
    model.next()
    XCTAssertFalse(model.stepObserved)
    var other = state
    other.documentID = UUID()
    other.layerCount += 2
    model.update(other)
    XCTAssertFalse(model.onLessonDocument)
    model.next()
    XCTAssertEqual(model.walkthrough?.index, 2)
    XCTAssertFalse(model.stepObserved)
    model.update(state)
    state.layerCount += 1
    model.update(state)
    XCTAssertTrue(model.stepObserved)
    model.next()
    XCTAssertEqual(model.walkthrough?.index, 3)
    model.back()
    XCTAssertEqual(model.walkthrough?.index, 2)
    model.end()
    XCTAssertNil(model.walkthrough)
  }

  @MainActor func testEditorClickRoutingAndNativeDuplicateUpdateTheGuide() throws {
    _ = NSApplication.shared
    let delegate = AppDelegate(workspaces: WorkspaceLibrary())
    var model = try CraftDocument(width: 24, height: 18)
    model.layers[0].name = "Training layer"
    let document = CraftNSDocument(model: model)
    let store = document.store
    let layer = try XCTUnwrap(model.activeLayerID)
    store.documentController = delegate.controller
    delegate.controller.documentWindows.activeDocument = document
    defer {
      delegate.workflowGuideWindow?.window?.close()
      delegate.controller.documentWindows.activeDocument = nil
      store.renderTask?.cancel()
    }
    delegate.toggleWorkflowGuide()
    let guide = try XCTUnwrap(delegate.workflowGuideWindow?.model)
    let marquee = try XCTUnwrap(WorkspaceCatalog.tools.first { $0.native == .marquee })
    store.chooseTool(marquee)
    XCTAssertEqual(guide.context, .selection)
    store.select(layer)
    XCTAssertEqual(guide.context, .layer)
    XCTAssertEqual(guide.caption, "Selected layer · Training layer")
    XCTAssertEqual(guide.suggestions.count, 4)
    guide.start(WorkflowGuideContent.duplicate)
    guide.next()
    guide.next()
    XCTAssertFalse(guide.stepObserved)
    store.perform(.duplicateLayer(layer))
    XCTAssertEqual(store.document.layers.count, 2)
    let deadline = Date().addingTimeInterval(1)
    while !guide.stepObserved && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    XCTAssertTrue(guide.stepObserved)
  }

  @MainActor func testNativeWindowMenuToggleAndMenuEvents() throws {
    _ = NSApplication.shared
    let previousMenu = NSApp.mainMenu
    let delegate = AppDelegate(workspaces: WorkspaceLibrary())
    let document = CraftNSDocument(model: try CraftDocument(width: 24, height: 18))
    delegate.controller.documentWindows.activeDocument = document
    document.store.setZoom(0.5)
    defer {
      NSApp.mainMenu = previousMenu
      delegate.workflowGuideWindow?.window?.close()
      delegate.workflowGuidePreferencesWindow?.close()
      delegate.controller.documentWindows.activeDocument = nil
      document.store.renderTask?.cancel()
    }
    delegate.installPhotoshopMenus()
    let appMenu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Photato")?.submenu)
    let settings = try XCTUnwrap(appMenu.item(withTitle: "Settings…")?.submenu)
    let guideSettings = try XCTUnwrap(settings.item(withTitle: "Workflow Guide…"))
    XCTAssertTrue(delegate.validateMenuItem(guideSettings))
    settings.performActionForItem(at: settings.index(of: guideSettings))
    XCTAssertEqual(delegate.workflowGuidePreferencesWindow?.window?.title, "Settings — Workflow Guide")
    XCTAssertTrue(delegate.workflowGuidePreferencesWindow?.window?.isVisible == true)
    let windowMenu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Window")?.submenu)
    let item = try XCTUnwrap(windowMenu.item(withTitle: "Workflow Guide"))
    XCTAssertNil(delegate.workflowGuideWindow)
    XCTAssertTrue(delegate.validateMenuItem(item))
    XCTAssertEqual(item.state, .off)
    windowMenu.performActionForItem(at: windowMenu.index(of: item))
    let guide = try XCTUnwrap(delegate.workflowGuideWindow)
    let panel = try XCTUnwrap(guide.window as? NSPanel)
    XCTAssertTrue(panel.isFloatingPanel)
    XCTAssertTrue(panel.isExcludedFromWindowsMenu)
    XCTAssertTrue(panel.worksWhenModal)
    XCTAssertEqual(panel.title, "Workflow Guide")
    XCTAssertTrue(delegate.controller.workflowGuide === guide.model)
    XCTAssertTrue(delegate.controller.workflowGuidePreferences.isShown)
    let viewMenu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "View")?.submenu)
    let action = try XCTUnwrap(viewMenu.item(withTitle: "100%"))
    viewMenu.performActionForItem(at: viewMenu.index(of: action))
    XCTAssertEqual(document.store.zoom, 1)
    XCTAssertEqual(guide.model.context, .navigation)
    XCTAssertEqual(guide.model.caption, "100%")
    panel.close()
    XCTAssertNil(delegate.controller.workflowGuide)
    XCTAssertFalse(delegate.controller.workflowGuidePreferences.isShown)
  }

  @MainActor func testGuideHighlightsTheVisibleLayerAndTheDuplicateSheetWithoutTakingFocus() async throws {
    _ = NSApplication.shared
    let delegate = AppDelegate(workspaces: WorkspaceLibrary())
    let document = CraftNSDocument(model: try CraftDocument(width: 80, height: 60))
    delegate.controller.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    delegate.controller.documentWindows.activeDocument = document
    let editor = try XCTUnwrap(document.windowForSheet)
    defer {
      if let sheet = editor.attachedSheet { editor.endSheet(sheet) }
      delegate.workflowGuideWindow?.close()
      document.close()
    }
    delegate.setWorkflowGuideVisible(true, takesFocus: false)
    let guide = try XCTUnwrap(delegate.workflowGuideWindow)
    let guidePanel = try XCTUnwrap(guide.window)
    let guideFrame = guidePanel.frame
    defer { guidePanel.setFrame(guideFrame, display: false) }
    editor.contentView?.layoutSubtreeIfNeeded()
    guide.model.start(WorkflowGuideContent.duplicate)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while guide.highlighter.overlay == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    let first = try XCTUnwrap(guide.highlighter.overlay)
    XCTAssertTrue(first.parent === editor)
    XCTAssertTrue(first.ignoresMouseEvents)
    XCTAssertFalse(first.isKeyWindow)
    XCTAssertEqual(guide.model.walkthrough?.index, 0)
    guidePanel.setFrameOrigin(NSPoint(x: first.frame.midX - guideFrame.width / 2,
      y: first.frame.midY - guideFrame.height / 2))
    XCTAssertTrue(guidePanel.frame.intersects(first.frame))
    guide.model.showMe()
    let replay = try XCTUnwrap(guide.highlighter.overlay)
    XCTAssertEqual(replay.frame, first.frame)
    XCTAssertFalse(replay === first)
    XCTAssertFalse(guidePanel.frame.intersects(replay.frame))
    XCTAssertEqual(guide.model.walkthrough?.index, 0)

    guide.model.next()
    document.store.beginDuplicate()
    let sheetDeadline = ContinuousClock.now.advanced(by: .seconds(3))
    while editor.attachedSheet == nil, ContinuousClock.now < sheetDeadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    _ = try XCTUnwrap(editor.attachedSheet)
    let layoutDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while guide.highlighter.visibleSheetHighlight == nil && guide.highlighter.overlay == nil,
      ContinuousClock.now < layoutDeadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    let request = try XCTUnwrap(guide.highlighter.sheetHighlight)
    XCTAssertEqual(request.control, .modalName)
    XCTAssertEqual(guide.highlighter.visibleSheetHighlight, request.id)
    XCTAssertNil(guide.highlighter.overlay)
    guide.model.showMe()
    XCTAssertNotEqual(guide.highlighter.sheetHighlight?.id, request.id)
    XCTAssertEqual(guide.model.walkthrough?.index, 1)
    guide.model.next()
    XCTAssertEqual(guide.highlighter.sheetHighlight?.control, .modalConfirm)
    guide.model.back()
    XCTAssertEqual(guide.highlighter.sheetHighlight?.control, .modalName)
    guide.model.end()
    XCTAssertNil(guide.highlighter.overlay)
    XCTAssertNil(guide.highlighter.sheetHighlight)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testSaveAndLoadSelectionHighlightTheirOwnSheetControls() async throws {
    _ = NSApplication.shared
    let delegate = AppDelegate(workspaces: WorkspaceLibrary())
    var source = try CraftDocument(width: 80, height: 60)
    source.selection = .init(x: 10, y: 10, width: 19, height: 16)
    let document = CraftNSDocument(model: source)
    delegate.controller.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    delegate.controller.documentWindows.activeDocument = document
    let editor = try XCTUnwrap(document.windowForSheet)
    defer {
      if let sheet = editor.attachedSheet { editor.endSheet(sheet) }
      delegate.workflowGuideWindow?.close()
      document.close()
    }
    delegate.setWorkflowGuideVisible(true, takesFocus: false)
    let guide = try XCTUnwrap(delegate.workflowGuideWindow)
    guide.model.note(.selection, "Selection")
    guide.model.start(WorkflowGuideContent.saveSelection)
    guide.model.next()
    XCTAssertEqual(guide.model.walkthrough?.index, 1)

    let store = document.store
    store.beginChannelDialog(.save)
    let save = try XCTUnwrap(store.channelDialog)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while guide.highlighter.visibleSheetHighlight == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    let name = try XCTUnwrap(guide.highlighter.sheetHighlight)
    XCTAssertEqual(name.surface, .savedSelection)
    XCTAssertEqual(name.control, .modalName)
    XCTAssertEqual(name.id, guide.highlighter.visibleSheetHighlight)
    guide.model.next()
    XCTAssertEqual(guide.highlighter.sheetHighlight?.control, .modalConfirm)
    save.name = "Training selection"
    store.commitChannelDialog(save)
    await save.task?.value
    XCTAssertEqual(store.document.alphaChannels?.first?.name, "Training selection")

    let dismissal = ContinuousClock.now.advanced(by: .seconds(3))
    while editor.attachedSheet != nil, ContinuousClock.now < dismissal {
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertNil(editor.attachedSheet)
    guide.model.next()
    XCTAssertEqual(guide.model.walkthrough?.index, 3)
    store.beginChannelDialog(.options)
    let unrelated = ContinuousClock.now.advanced(by: .seconds(3))
    while editor.attachedSheet == nil, ContinuousClock.now < unrelated {
      try await Task.sleep(for: .milliseconds(25))
    }
    _ = try XCTUnwrap(editor.attachedSheet)
    guide.model.showMe()
    XCTAssertNil(guide.highlighter.sheetHighlight)
    XCTAssertNil(guide.highlighter.overlay)
    store.cancelChannelDialog()

    let canceled = ContinuousClock.now.advanced(by: .seconds(3))
    while editor.attachedSheet != nil, ContinuousClock.now < canceled {
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertNil(editor.attachedSheet)
    store.beginChannelDialog(.load)
    let loading = ContinuousClock.now.advanced(by: .seconds(3))
    while guide.highlighter.visibleSheetHighlight == nil, ContinuousClock.now < loading {
      try await Task.sleep(for: .milliseconds(25))
    }
    let picker = try XCTUnwrap(guide.highlighter.sheetHighlight)
    XCTAssertEqual(picker.surface, .loadSelection)
    XCTAssertEqual(picker.control, .modalChannel)
    XCTAssertEqual(picker.id, guide.highlighter.visibleSheetHighlight)
    guide.model.showMe()
    XCTAssertNotEqual(guide.highlighter.sheetHighlight?.id, picker.id)
    XCTAssertEqual(guide.model.walkthrough?.index, 3)
    guide.model.next()
    XCTAssertEqual(guide.highlighter.sheetHighlight?.control, .modalConfirm)
    store.cancelChannelDialog()
  }

  @MainActor func testGuideOutlinesAParentMenuRowAndThenTheExactSubmenuCommand() throws {
    _ = NSApplication.shared
    let previousMenu = NSApp.mainMenu
    let delegate = AppDelegate(workspaces: WorkspaceLibrary())
    let document = CraftNSDocument(model: try CraftDocument(width: 24, height: 18))
    delegate.controller.documentWindows.activeDocument = document
    defer {
      delegate.workflowGuideWindow?.close()
      delegate.controller.documentWindows.activeDocument = nil
      document.store.renderTask?.cancel()
      NSApp.mainMenu = previousMenu
    }
    delegate.installPhotoshopMenus()
    delegate.setWorkflowGuideVisible(true, takesFocus: false)
    let guide = try XCTUnwrap(delegate.workflowGuideWindow)
    guide.model.showTool(.brush)
    guide.model.start(WorkflowGuideContent.brush)
    XCTAssertEqual(guide.model.walkthrough?.index, 0)

    let layerMenu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Layer")?.submenu)
    let newItem = try XCTUnwrap(layerMenu.item(withTitle: "New"))
    let newMenu = try XCTUnwrap(newItem.submenu)
    let layerItem = try XCTUnwrap(newMenu.item(withTitle: "Layer…"))
    for item in [newItem, layerItem] {
      let sample = try MenuTrackingSample(item: item, guide: guide)
      sample.open()
      let frame = try XCTUnwrap(sample.frame)
      let outline = try XCTUnwrap(sample.outline)
      XCTAssertTrue(outline.frame.contains(frame), "\(item.title) at \(frame) should be inside the cue at \(outline.frame)")
      XCTAssertGreaterThan(outline.level.rawValue, Int(CGWindowLevelForKey(.popUpMenuWindow)))
      XCTAssertTrue(outline.ignoresMouseEvents)
      XCTAssertFalse(outline.isKeyWindow)
      XCTAssertNil(guide.highlighter.overlay)
    }
    XCTAssertEqual(guide.model.walkthrough?.index, 0)
    XCTAssertNil(document.store.newLayerDraft)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testSaveGuideFindsItsNativeFormatControlAndIgnoresOtherSheets() async throws {
    _ = NSApplication.shared
    let delegate = AppDelegate(workspaces: WorkspaceLibrary())
    let document = CraftNSDocument(model: try CraftDocument(width: 80, height: 60))
    delegate.controller.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    delegate.controller.documentWindows.activeDocument = document
    let editor = try XCTUnwrap(document.windowForSheet)
    defer {
      if let sheet = editor.attachedSheet { editor.endSheet(sheet, returnCode: .cancel) }
      delegate.workflowGuideWindow?.close()
      document.close()
    }
    delegate.setWorkflowGuideVisible(true, takesFocus: false)
    let guide = try XCTUnwrap(delegate.workflowGuideWindow)
    guide.model.note(.export, "Save")
    guide.model.start(WorkflowGuideContent.save)
    guide.model.next()
    XCTAssertNotNil(guide.model.highlightHint)

    document.store.beginDuplicate()
    let duplicateDeadline = ContinuousClock.now.advanced(by: .seconds(3))
    while editor.attachedSheet == nil, ContinuousClock.now < duplicateDeadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    _ = try XCTUnwrap(editor.attachedSheet)
    guide.model.showMe()
    XCTAssertNil(guide.highlighter.overlay)
    XCTAssertNil(guide.highlighter.sheetHighlight)
    XCTAssertNil(guide.highlighter.nativeSheetOutline)

    document.store.duplicateLayerDraft = nil
    let dismissalDeadline = ContinuousClock.now.advanced(by: .seconds(3))
    while editor.attachedSheet != nil, ContinuousClock.now < dismissalDeadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertNil(editor.attachedSheet)

    let panel = NSSavePanel()
    XCTAssertTrue(document.prepareSavePanel(panel))
    panel.beginSheetModal(for: editor) { _ in }
    let panelDeadline = ContinuousClock.now.advanced(by: .seconds(3))
    while (editor.attachedSheet !== panel || !panel.isVisible), ContinuousClock.now < panelDeadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertTrue(editor.attachedSheet === panel)
    let cueDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while guide.highlighter.nativeSheetOutline == nil, ContinuousClock.now < cueDeadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    let cue = try XCTUnwrap(guide.highlighter.nativeSheetOutline)
    let popup = try XCTUnwrap(document.saveAccessory?.formats)
    XCTAssertTrue(cue.window === (try XCTUnwrap(popup.window)))
    XCTAssertTrue(cue.superview === popup)
    XCTAssertEqual(cue.frame, popup.bounds)
    XCTAssertFalse(cue.visibleRect.isEmpty)
    XCTAssertNil(cue.hitTest(CGPoint(x: cue.bounds.midX, y: cue.bounds.midY)))
    XCTAssertNil(guide.highlighter.overlay)
    XCTAssertNil(guide.model.highlightHint)
    XCTAssertEqual(guide.model.walkthrough?.index, 1)
    guide.model.showMe()
    XCTAssertFalse(guide.highlighter.nativeSheetOutline === cue)
    XCTAssertNil(cue.superview)
    panel.cancel(nil)
    XCTAssertFalse(document.isDocumentEdited)
  }
}

@MainActor private final class MenuTrackingSample {
  let item: NSMenuItem
  let menu: NSMenu
  let guide: WorkflowGuideWindow
  var frame: NSRect?
  var outline: NSPanel?

  init(item: NSMenuItem, guide: WorkflowGuideWindow) throws {
    self.item = item
    self.guide = guide
    menu = try XCTUnwrap(item.menu)
  }

  func open() {
    let timer = Timer(timeInterval: 0.2, repeats: false) { [self] _ in
      MainActor.assumeIsolated {
        frame = item.accessibilityFrame()
        outline = guide.highlighter.overlay
        menu.cancelTracking()
      }
    }
    RunLoop.main.add(timer, forMode: .eventTracking)
    _ = menu.popUp(positioning: nil, at: NSPoint(x: 500, y: 400), in: nil)
    timer.invalidate()
  }
}
