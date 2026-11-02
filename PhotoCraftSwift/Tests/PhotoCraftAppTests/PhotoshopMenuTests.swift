import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class PhotoshopMenuTests: XCTestCase {
  struct Expected: Decodable {
    let path: [String]
    let key: String
    let modifiers: [String]
  }
  struct FactoryDefaults: Decodable {
    struct Command: Decodable {
      struct Shortcut: Decodable {
        let key: String
        let modifiers: [String]
      }
      let path: [String]
      let primary: Shortcut
      let alternatives: [Shortcut]
    }
    let preset: String
    let mapped_commands: [Command]
  }
  @MainActor func withMenus(_ check: (AppDelegate, NSMenu) throws -> Void) throws {
    _ = NSApplication.shared
    let old = NSApp.mainMenu
    let windows = NSApp.windowsMenu
    let help = NSApp.helpMenu
    let services = NSApp.servicesMenu
    let servicesItem = services?.supermenu?.items.first { $0.submenu === services }
    defer {
      if let services, let servicesItem {
        services.supermenu?.items.first { $0.submenu === services }?.submenu = nil
        servicesItem.submenu = services
      }
      NSApp.mainMenu = old
      NSApp.windowsMenu = windows
      NSApp.helpMenu = help
      NSApp.servicesMenu = services
    }
    let app = AppDelegate()
    app.buildMenus()
    try check(app, XCTUnwrap(NSApp.mainMenu))
  }
  @MainActor func allItems(_ menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { item in [item] + (item.submenu.map(allItems) ?? []) }
  }
  @MainActor func testObservedMenuHierarchyOrderAndPrimaryShortcuts() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-menu-inventory", withExtension: "json", subdirectory: "Fixtures"))
    let expected = try JSONDecoder().decode([Expected].self, from: Data(contentsOf: url))
    try withMenus { _, menu in
      XCTAssertEqual(
        menu.items.map(\.title),
        [
          "Photato", "File", "Edit", "Image", "Layer", "Type", "Select", "Filter", "View",
          "Plugins", "Window", "Help",
        ])
      let items = allItems(menu).filter {
        !$0.isSeparatorItem && !$0.isHidden && $0.identifier != nil
      }
      // Keep every independently captured27.2 entry and shortcut intact.
      // Separate later adjustment commands and the Photato-only Relight extension.
      let additions = ["Light…","Clarity and dehaze…","Grain…"].map {"Layer > New Adjustment Layer > " + $0} + ["Filter > Photato","Filter > Photato > Relight…","Filter > Photato > Lighting Effects…"]
      XCTAssertEqual(items.count, 807)
      XCTAssertEqual(items.filter { !additions.contains($0.identifier!.rawValue) }.map { $0.identifier!.rawValue },
        expected.map { $0.path.joined(separator: " > ") })
      XCTAssertEqual(items.filter { additions.contains($0.identifier!.rawValue) }.map { $0.identifier!.rawValue }, additions)
      let report: [String: Any] = [
        "menus": menu.items.map(\.title), "entries": items.count,
        "default_preset": PhotoshopMenuCatalog.presetName,
        "alternative_shortcuts": allItems(menu).filter {
          $0.isHidden && $0.allowsKeyEquivalentWhenHidden
        }.count,
        "primary_shortcuts": items.filter { !$0.keyEquivalent.isEmpty }.count,
        "entries_with_actions": items.filter { $0.action != nil }.count,
        "bound_leaf_commands": items.filter { $0.submenu == nil && $0.action != nil }.count,
        "unavailable_leaf_commands": items.filter { $0.submenu == nil && $0.action == nil }.count,
        "rows": items.map { item -> [String: Any] in
          [
            "path": item.identifier!.rawValue, "title": item.title,
            "key": item.keyEquivalent, "modifiers": item.keyEquivalentModifierMask.rawValue,
            "action": item.action.map(NSStringFromSelector) ?? "", "submenu": item.submenu != nil,
          ]
        }, "full_photoshop_parity": false,
      ]
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: root.appendingPathComponent("artifacts/menu-parity-report.json"))
      let flags: [String: NSEvent.ModifierFlags] = [
        "command": .command, "option": .option, "shift": .shift, "control": .control,
      ]
      for (item, row) in zip(items.filter { !additions.contains($0.identifier!.rawValue) }, expected) {
        XCTAssertEqual(item.title, row.path.last, row.path.joined(separator: " > "))
        XCTAssertEqual(item.keyEquivalent, row.key, row.path.joined(separator: " > "))
        let modifiers = try row.modifiers.reduce(into: NSEvent.ModifierFlags()) { result, value in
          result.formUnion(try XCTUnwrap(flags[value]))
        }
        XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, row.path.joined(separator: " > "))
      }
    }
  }
  @MainActor func testFactoryDefaultsApplyWithoutOptInIncludingAlternateKeys() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-default-shortcuts", withExtension: "json", subdirectory: "Fixtures")
    )
    let defaults = try JSONDecoder().decode(FactoryDefaults.self, from: Data(contentsOf: url))
    XCTAssertEqual(PhotoshopMenuCatalog.presetName, defaults.preset)
    try withMenus { _, menu in
      let items = allItems(menu)
      let flags: [String: NSEvent.ModifierFlags] = [
        "command": .command, "option": .option, "shift": .shift, "control": .control,
      ]
      for command in defaults.mapped_commands {
        let path = command.path.joined(separator: " > ")
        let item = try XCTUnwrap(items.first { $0.identifier?.rawValue == path }, path)
        let aliases = item.menu!.items.filter { $0.isHidden && $0.title == item.title }
        XCTAssertEqual(aliases.count, command.alternatives.count, path)
        for (binding, expected) in zip([item] + aliases, [command.primary] + command.alternatives) {
          XCTAssertEqual(binding.keyEquivalent, expected.key, path)
          let modifiers = try expected.modifiers.reduce(into: NSEvent.ModifierFlags()) {
            $0.formUnion(try XCTUnwrap(flags[$1]))
          }
          XCTAssertEqual(binding.keyEquivalentModifierMask, modifiers, path)
          XCTAssertEqual(binding.action, item.action, path)
          XCTAssertTrue(binding.target === item.target, path)
          if binding !== item {
            XCTAssertTrue(binding.allowsKeyEquivalentWhenHidden, path)
            XCTAssertTrue(binding.identifier?.rawValue.hasPrefix("shortcut-alias:") == true)
          }
          if item.action == nil { XCTAssertFalse(binding.isEnabled, path) }
        }
      }
      XCTAssertEqual(defaults.mapped_commands.count, 102)
      XCTAssertEqual(items.filter { $0.isHidden && $0.allowsKeyEquivalentWhenHidden }.count, 8)
    }
  }

  @MainActor func testHiddenFactoryAlternateUsesNativeMenuDispatchAndValidation() throws {
    final class Receiver: NSObject, NSMenuItemValidation {
      var calls = 0
      var available = true
      @objc func record(_ sender: Any?) { calls += 1 }
      func validateMenuItem(_ item: NSMenuItem) -> Bool { available }
    }
    try withMenus { _, menu in
      let alias = try XCTUnwrap(
        allItems(menu).first {
          $0.isHidden && $0.title == "Zoom In"
        })
      let receiver = Receiver()
      alias.target = receiver
      alias.action = #selector(Receiver.record(_:))
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero,
          modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
          characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
      XCTAssertTrue(menu.performKeyEquivalent(with: event))
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      XCTAssertEqual(receiver.calls, 1)
      receiver.available = false
      _ = menu.performKeyEquivalent(with: event)
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      XCTAssertEqual(receiver.calls, 1, "Unavailable aliases must not execute")
    }
  }

  @MainActor func testCommandsReachCorrectExistingOperationsAndReservePhotoshopKeys() throws {
    try withMenus { _, menu in
      let byID = Dictionary(
        uniqueKeysWithValues: allItems(menu).compactMap { item in
          item.identifier.map { ($0.rawValue, item) }
        })
      func item(_ path: String) throws -> NSMenuItem { try XCTUnwrap(byID[path], path) }
      XCTAssertEqual(try item("File > Export > Export As…").action, #selector(AppDelegate.export))
      XCTAssertEqual(
        try item("File > Export > Export As…").keyEquivalentModifierMask,
        [.command, .option, .shift])
      XCTAssertEqual(try item("File > Export > Export As…").keyEquivalent, "w")
      XCTAssertEqual(try item("Layer > Merge Visible").action, #selector(AppDelegate.mergeVisible))
      XCTAssertEqual(try item("Layer > Merge Visible").keyEquivalent, "e")
      XCTAssertEqual(
        try item("Layer > Merge Visible").keyEquivalentModifierMask, [.command, .shift])
      XCTAssertEqual(
        try item("Select > Modify > Feather…").action, #selector(AppDelegate.featherSelection))
      XCTAssertEqual(
        try item("Select > Modify > Feather…").keyEquivalent,
        String(UnicodeScalar(NSEvent.SpecialKey.f6.rawValue)!))
      XCTAssertEqual(try item("Edit > Fill…").action, #selector(AppDelegate.fillDialog))
      XCTAssertEqual(
        try item("Filter > Blur > Gaussian Blur…").action, #selector(AppDelegate.rasterFilterDialog(_:))
      )
      XCTAssertEqual(
        try item("Layer > New > Layer Via Copy").action, #selector(AppDelegate.layerViaCopy))
      XCTAssertEqual(try item("Layer > New > Layer Via Copy").keyEquivalent, "j")
      XCTAssertTrue(try item("Layer > Duplicate Layer…").keyEquivalent.isEmpty)
      XCTAssertNil(
        try item("Image > Adjustments > Invert").action,
        "Pixel Invert must not create an adjustment layer")
      XCTAssertEqual(
        try item("Layer > New Adjustment Layer > Invert…").action, #selector(AppDelegate.invert))
      XCTAssertNil(try item("Edit > Generative Fill…").action)
      XCTAssertEqual(
        try item("Edit > Create with Apple Intelligence…").action, #selector(AppDelegate.ai))
      XCTAssertNil(byID["File > Export Image…"])
      XCTAssertNil(byID["Image > Flip Layer Horizontally"])
      XCTAssertNil(byID["Select > Feather…"])
    }
  }
  @MainActor func testUnavailableCommandsAndResponderRoutingAreHonest() throws {
    try withMenus { app, menu in
      let items = allItems(menu)
      for item in items where !item.isSeparatorItem && item.submenu == nil {
        if item.action == nil {
          XCTAssertFalse(item.isEnabled, item.title)
          XCTAssertNotNil(item.toolTip, item.title)
        } else if let target = item.target {
          XCTAssertTrue(target.responds(to: item.action!), item.title)
        }
      }
      for title in ["Cut", "Copy", "Paste"] {
        let item = try XCTUnwrap(menu.item(withTitle: "Edit")?.submenu?.item(withTitle: title))
        XCTAssertNil(item.target, "Text fields must retain native clipboard routing")
      }
      for selector in [
        #selector(AppDelegate.fillDialog), #selector(AppDelegate.rasterFilterDialog(_:)),
      ] {
        XCTAssertFalse(
          app.validateMenuItem(NSMenuItem(title: "", action: selector, keyEquivalent: "")))
      }
      XCTAssertTrue(
        NSApp.servicesMenu
          === menu.item(withTitle: "Photato")?.submenu?.item(withTitle: "Services")?.submenu)
      XCTAssertFalse(
        items.contains { $0.title.contains("Nano Banana") || $0.title.contains("Meaty, Beaty") })
      let keys = items.filter { !$0.keyEquivalent.isEmpty }
      let signatures = keys.map { "\($0.keyEquivalentModifierMask.rawValue):\($0.keyEquivalent)" }
      XCTAssertEqual(Set(signatures).count, signatures.count, "No competing menu key equivalents")
    }
  }
  @MainActor func testLayerViaCopyRejectsUnportedSelectionAndMultipleLayerCases() async throws {
    let store = EditorStore(document: try CraftDocument(width: 4, height: 4))
    store.renderTask?.cancel()
    XCTAssertTrue(store.canCopyWholeLayerViaMenu)
    let original = store.document
    store.copyWholeLayerViaMenu()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.layers.count, original.layers.count + 1)
    await store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, original)
    store.perform(.selection(IntRect(x: 0, y: 0, width: 2, height: 2)))
    store.renderTask?.cancel()
    let selected = store.document
    XCTAssertFalse(store.canCopyWholeLayerViaMenu)
    store.copyWholeLayerViaMenu()
    XCTAssertEqual(store.document, selected)
    store.perform(.selection(nil))
    store.addPixelLayer()
    store.renderTask?.cancel()
    store.selectedLayerIDs = Set(store.document.layers.map(\.id))
    XCTAssertFalse(store.canCopyWholeLayerViaMenu)
  }
  @MainActor func testMenuFillChoicePreservesForegroundSelectionAndUndo() async throws {
    let store = EditorStore(document: try CraftDocument(width: 4, height: 3))
    store.renderTask?.cancel()
    store.brush.color = .white
    store.perform(.selection(IntRect(x: 1, y: 1, width: 1, height: 1)))
    store.renderTask?.cancel()
    let before = store.document
    XCTAssertTrue(store.canUseMenuPixelEdit)
    let color = Pixel(0.2, 0.4, 0.6)
    store.fill(color: color)
    store.renderTask?.cancel()
    let layer = try XCTUnwrap(store.activeLayer)
    guard case .raster(let pixels) = layer.content else { return XCTFail("Missing raster") }
    XCTAssertEqual(pixels.pixel(x: 1, y: 1), color.quantized(store.document.depth))
    XCTAssertEqual(store.brush.color, .white)
    XCTAssertEqual(store.document.selection, before.selection)
    await store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, before)
    store.perform(.lock(layer.id, true))
    store.renderTask?.cancel()
    XCTAssertFalse(store.canUseMenuPixelEdit)
  }
  @MainActor func testMenuBlurRadiusAndInvalidInputDoNotSilentlyUseFive() async throws {
    var model = try CraftDocument(width: 5, height: 5)
    let id = try XCTUnwrap(model.activeLayerID)
    var source = try Surface(width: 5, height: 5)
    source.setPixel(x: 2, y: 2, .white)
    try Command.replaceContent(id, .raster(source)).apply(to: &model)
    let store = EditorStore(document: model)
    store.renderTask?.cancel()
    store.blur(radius: 1)
    await store.geometryTask?.value
    store.renderTask?.cancel()
    guard case .raster(let result) = store.activeLayer?.content else {
      return XCTFail("Missing raster")
    }
    var filter = RasterFilter(.gaussianBlur); filter.radius = 1
    var expected = model
    try Command.applyFilter(id, filter).apply(to: &expected)
    XCTAssertEqual(store.document, expected)
    filter.radius = 5
    try Command.applyFilter(id, filter).apply(to: &model)
    guard case .raster(let wider) = model.layers[0].content else { return XCTFail() }
    XCTAssertNotEqual(result, wider)
    model = expected
    model.layers[0].content = .raster(source)
    await store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, model)
    store.blur(radius: .nan)
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, model)
    XCTAssertNotNil(store.error)
  }
  @MainActor func testRebuiltServicesMenuRemainsAttachedAfterAppKitRunLoop() async throws {
    _ = NSApplication.shared
    try await Task.sleep(for: .milliseconds(20))
    for _ in 0..<3 {
      try withMenus { app, menu in
        let first = try XCTUnwrap(NSApp.servicesMenu)
        XCTAssertTrue(
          first === menu.item(withTitle: "Photato")?.submenu?.item(withTitle: "Services")?.submenu)
        app.buildMenus()
        let current = try XCTUnwrap(
          NSApp.mainMenu?.item(withTitle: "Photato")?.submenu?.item(withTitle: "Services")?.submenu)
        XCTAssertTrue(first === current, "Rebuilds retain the registered native Services menu")
        XCTAssertTrue(NSApp.servicesMenu === current)
      }
    }
  }

}
