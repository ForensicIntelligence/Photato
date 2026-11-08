import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class RemoveCursorTests: XCTestCase {
  @MainActor func testAllSixteenModifiersMatchCapturedAddSubtractAndSpacePan() async throws {
    _ = NSApplication.shared
    var d = try CraftDocument(width:40,height:30); d.layers[0].locked = false
    let store = EditorStore(document:d), canvas = CraftCanvas(store:store)
    defer { store.cancelRemove(); store.renderTask?.cancel() }
    store.tool = .remove
    let modifiers: [NSEvent.ModifierFlags] = [.control,.command,.option,.shift]
    var rows = [[String:Any]]()
    for subtract in [false,true] {
      var settings = RemoveToolSettings(); settings.subtract = subtract; settings.removeAfterEachStroke = false
      try store.updateRemoveSettings(settings)
      for bits in 0..<16 {
        let flags = modifiers.enumerated().reduce(NSEvent.ModifierFlags()) {
          bits & (1 << $1.offset) == 0 ? $0:$0.union($1.element)
        }
        canvas.updateCursorModifiers(flags)
        let effectiveSubtract = subtract != flags.contains(.option)
        let expected = ToolCursor.symbol("eraser.fill",effectiveSubtract ? .subtract:.add)
        XCTAssertEqual(canvas.toolCursor,expected)
        XCTAssertEqual(EditorTool.remove.cursor(modifiers:flags,removeSubtract:subtract),expected)
        XCTAssertTrue(store.beginRemoveStroke(at:.init(x:20,y:15),alternate:flags.contains(.option)))
        XCTAssertEqual(store.removeStroke?.subtract,effectiveSubtract)
        canvas.updateCursorModifiers(flags.symmetricDifference([.option,.shift,.command,.control]))
        XCTAssertEqual(canvas.toolCursor,expected,"A modifier change must not relabel the captured stroke.")
        store.cancelRemoveGesture()
        canvas.spaceHeld = true; XCTAssertEqual(canvas.toolCursor,.openHand)
        canvas.spaceHeld = false
        rows.append(["settingSubtract":subtract,"bits":bits,"effectiveSubtract":effectiveSubtract,
          "cursor":String(describing:expected)])
      }
    }
    XCTAssertEqual(rows.count,32)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys])
        .write(to:URL(fileURLWithPath:path).appendingPathComponent("remove-modifier-matrix.json"))
    }
  }
  @MainActor func testJGroupIncludesRemoveAndUnavailableTargetsDoNotAdvertisePainting() throws {
    var d = try CraftDocument(width:40,height:30); d.layers[0].locked = false
    d.layers[0].mask = try Surface(width:40,height:30,fill:.white)
    let store = EditorStore(document:d), canvas = CraftCanvas(store:store)
    defer { store.cancelRemove(); store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("spotHealing"))
    XCTAssertTrue(store.chooseShortcut("j",cycle:true)); XCTAssertEqual(store.tool,.remove)
    XCTAssertEqual(store.selectedTool.id,"remove")
    XCTAssertTrue(store.chooseShortcut("j",cycle:true)); XCTAssertEqual(store.tool,.healingBrush)
    store.chooseTool(WorkspaceCatalog.tool("remove")); store.geometryBusy = true
    XCTAssertEqual(canvas.toolCursor,.unavailable)
    XCTAssertFalse(store.beginRemoveStroke(at:.init(x:20,y:15),alternate:false))
    store.geometryBusy = false; store.maskEditingLayerID = store.activeLayer?.id
    XCTAssertFalse(store.canUseRemove); XCTAssertEqual(canvas.toolCursor,.unavailable)
    store.maskEditingLayerID = nil
    store.removeSettings.mode = .generativeOn
    XCTAssertFalse(store.canUseRemove); XCTAssertEqual(canvas.toolCursor,.unavailable)
    store.removeSettings.mode = .generativeOff
    XCTAssertTrue(store.canUseRemove)
  }
  @MainActor func testNativeModePopupEnforcesAvailabilityAndUsesRealArtwork() throws {
    _ = NSApplication.shared
    let store = EditorStore(document:try CraftDocument(width:24,height:24))
    defer { store.cancelRemove(); store.renderTask?.cancel() }
    let source = store.document
    let binding = Binding(get:{ store.removeSettings.mode },set:{ value in
      var settings = store.removeSettings; settings.mode = value
      do { try store.updateRemoveSettings(settings) } catch { store.status = error.localizedDescription }
    })
    let coordinator = RemoveModeControl.Coordinator(binding)
    let popup = RemoveModeControl.makePopup(coordinator,enabled:true)
    XCTAssertFalse(try XCTUnwrap(popup.menu).autoenablesItems)
    XCTAssertEqual(popup.numberOfItems,3); XCTAssertEqual(popup.selectedTag(),0)
    XCTAssertTrue(try XCTUnwrap(popup.item(at:0)).isEnabled)
    XCTAssertTrue(try XCTUnwrap(popup.item(at:1)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(popup.item(at:2)).isEnabled)
    let action = try XCTUnwrap(popup.action)
    popup.selectItem(withTag:1); XCTAssertTrue(popup.sendAction(action,to:coordinator))
    XCTAssertEqual(store.removeSettings.mode,.generativeOff); XCTAssertEqual(popup.selectedTag(),1)
    popup.selectItem(withTag:2); XCTAssertTrue(popup.sendAction(action,to:coordinator))
    XCTAssertEqual(store.removeSettings.mode,.generativeOff); XCTAssertEqual(popup.selectedTag(),1)
    RemoveModeControl.synchronize(popup,selection:.generativeOff,enabled:false)
    popup.selectItem(withTag:0); coordinator.changed(popup)
    XCTAssertFalse(popup.isEnabled); XCTAssertEqual(store.removeSettings.mode,.generativeOff)
    XCTAssertEqual(popup.selectedTag(),1); XCTAssertFalse(try XCTUnwrap(popup.item(at:2)).isEnabled)
    XCTAssertEqual(store.document,source); XCTAssertTrue(store.session.undoStack.isEmpty)
    let settings = try XCTUnwrap(RemoveToolAPI.state(store)["settings"] as? [String:Any])
    XCTAssertEqual(settings["mode"] as? String,"generativeOff")
    XCTAssertEqual(RemoveToolAPI.capabilities["supportedModes"] as? [String],["auto","generativeOff"])
    let symbol = WorkspaceCatalog.tool("remove").symbol
    XCTAssertEqual(symbol,"eraser.fill")
    XCTAssertNotNil(NSImage(systemSymbolName:symbol,accessibilityDescription:"Remove"))
    XCTAssertEqual(EditorTool.remove.cursor(modifiers:[]),.symbol(symbol,.add))
    XCTAssertEqual(EditorTool.remove.cursor(modifiers:.option),.symbol(symbol,.subtract))
  }
}
