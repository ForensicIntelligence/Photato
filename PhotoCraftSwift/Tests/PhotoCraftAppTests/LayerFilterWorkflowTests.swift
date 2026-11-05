import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LayerFilterWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 3, depth: depth)
    let pixels = try Surface(width: 4, height: 3, depth: depth, fill: Pixel(0.25, 0.5, 0.75))
    var group = Layer(name: "Closed group", content: .group(.init(expanded: false)))
    var child = Layer(name: "Nested pixels", content: .raster(pixels)); child.parentID = group.id
    var a = Layer(name: "Pixel A", content: .raster(pixels))
    var b = Layer(name: "Pixel B", content: .raster(pixels)); b.visible = false
    a.colorLabel = .red; b.colorLabel = .blue
    a.mask = try Surface(width: 4, height: 3, depth: depth, fill: .white)
    a.linkID = UUID(); b.linkID = a.linkID; b.linkDisabled = true
    a.style = LayerStyle(); a.style?.effects = [LayerEffect(.dropShadow)]
    b.blendMode = .multiply; b.protection = .position
    group.colorLabel = .red
    let adjustment = Layer(name: "Levels", content: .adjustment(.levels(.init())))
    let fill = Layer(name: "Color fill", content: .fill(.white))
    let gradient = Layer(name: "Gradient", content: .gradientFill(.init(dither: false)))
    let text = Layer(name: "Text", content: .text(.init(text: "Owned", size: 12)))
    let shape = Layer(name: "Shape", content: .shape(.init(kind: .rectangle, width: 2, height: 2, color: .black)))
    var smart = try CraftDocument(width: 4, height: 3, depth: depth)
    smart.layers[0].content = .raster(pixels)
    try SmartObjectIO.convert(in: smart, selected: [smart.layers[0].id]).apply(to: &smart)
    smart.layers[0].name = "Embedded"
    var boardContent = GroupContent(); boardContent.artboard = .init(width: 4, height: 3)
    let board = Layer(name: "Artboard", content: .group(boardContent))
    var boardChild = Layer(name: "Board pixels", content: .raster(pixels)); boardChild.parentID = board.id
    d.layers = [child, group, a, b, adjustment, fill, gradient, text, shape, smart.layers[0], boardChild, board]
    d.activeLayerID = a.id; try d.validate(); return d
  }
  @MainActor func retainingViewSelection(_ source: CraftDocument, _ store: EditorStore) -> CraftDocument {
    var expected = source; expected.activeLayerID = store.document.activeLayerID; return expected
  }
  @MainActor func stop(_ s: EditorStore) { s.renderTask?.cancel(); s.linkedSourceController?.stop() }
  @MainActor func names(_ s: EditorStore) -> [String] { s.layersInPanel().map(\.name) }
  @MainActor func select(_ s: EditorStore, names: Set<String>) {
    s.selectedLayerIDs = Set(s.document.layers.filter { names.contains($0.name) }.map(\.id))
  }

  @MainActor func testMultiKindUsesContentSemanticsAndIndependentNativeReferenceListsAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth), s = EditorStore(document: source)
      defer { stop(s) }
      let revision = s.revision
      XCTAssertFalse(names(s).contains("Nested pixels"))
      var filter = LayerPanelFilter(); filter.kinds = [.adjustment]
      try s.setLayerFilter(filter)
      XCTAssertEqual(names(s), ["Gradient", "Color fill", "Levels"])
      filter.kinds = [.pixel, .type]; try s.setLayerFilter(filter)
      XCTAssertEqual(names(s), ["Board pixels", "Text", "Pixel B", "Pixel A", "Nested pixels"])
      filter.kinds = [.smartObject]; try s.setLayerFilter(filter); XCTAssertEqual(names(s), ["Embedded"])
      filter.kinds = [.shape]; try s.setLayerFilter(filter); XCTAssertEqual(names(s), ["Shape"])
      filter.enabled = false; try s.setLayerFilter(filter)
      XCTAssertEqual(names(s), source.layers.reversed().filter { $0.name != "Nested pixels" }.map(\.name))
      XCTAssertEqual(s.document, retainingViewSelection(source, s)); XCTAssertEqual(s.revision, revision)
      XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }

  @MainActor func testNameEffectsModeColorMetadataAttributesPreserveSamplesHistoryAndClearExcludedSelection() throws {
    let source = try fixture(.f32), s = EditorStore(document: source)
    defer { stop(s) }
    let archive = try NativeArchive.encodeChunked(source)
    var changes = 0; s.onChange = { _ in changes += 1 }
    var filter = LayerPanelFilter(); filter.mode = .name; filter.name = "nEsTeD"
    try s.setLayerFilter(filter); XCTAssertEqual(names(s), ["Nested pixels"])
    filter.mode = .effect; filter.effect = .dropShadow
    try s.setLayerFilter(filter); XCTAssertEqual(names(s), ["Pixel A"])
    filter.mode = .mode; filter.blend = BlendMode.multiply.rawValue
    try s.setLayerFilter(filter); XCTAssertEqual(names(s), ["Pixel B"])
    filter.blend = "Pass Through"; try s.setLayerFilter(filter)
    XCTAssertEqual(names(s), ["Artboard", "Closed group"])
    filter.mode = .color; filter.color = .red; try s.setLayerFilter(filter)
    XCTAssertEqual(names(s), ["Pixel A", "Closed group"])
    let pairs: [(LayerFilterAttribute, LayerFilterAttribute, Set<String>)] = [
      (.visible, .notVisible, Set(source.layers.filter(\.visible).map(\.name))),
      (.linked, .notLinked, ["Pixel A", "Pixel B"]), (.clipped, .notClipped, []),
      (.locked, .notLocked, ["Pixel B"]), (.layerEffects, .noLayerEffects, ["Pixel A"]),
      (.layerMask, .noLayerMask, ["Pixel A"]), (.vectorMask, .noVectorMask, []),
    ]
    filter.mode = .attribute
    let all = Set(source.layers.map(\.name))
    for (positive, negative, expected) in pairs {
      filter.attribute = positive; try s.setLayerFilter(filter); XCTAssertEqual(Set(names(s)), expected)
      filter.attribute = negative; try s.setLayerFilter(filter); XCTAssertEqual(Set(names(s)), all.subtracting(expected))
    }
    XCTAssertEqual(changes, 0); XCTAssertEqual(s.document, retainingViewSelection(source, s))
    XCTAssertEqual(try NativeArchive.encodeChunked(s.document), try NativeArchive.encodeChunked(retainingViewSelection(source, s)))
    XCTAssertNotEqual(try NativeArchive.encodeChunked(s.document), archive); XCTAssertNil(s.document.activeLayerID)
    XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertTrue(s.session.redoStack.isEmpty)
  }

  @MainActor func testSelectedIsolationDynamicSelectionEnableSwitchAndFindFactoryMenus() throws {
    let source = try fixture(), s = EditorStore(document: source)
    defer { stop(s) }
    select(s, names: ["Pixel A", "Nested pixels"])
    s.toggleLayerIsolation(); XCTAssertTrue(s.layerFilterIsolated)
    XCTAssertEqual(names(s), ["Pixel A", "Nested pixels"])
    select(s, names: ["Pixel B"]); XCTAssertEqual(names(s), ["Pixel B"])
    s.editLayerFilter { $0.enabled = false }; XCTAssertFalse(s.layerFilterIsolated)
    XCTAssertTrue(names(s).contains("Pixel A")); XCTAssertFalse(names(s).contains("Nested pixels"))
    s.toggleLayerIsolation(); XCTAssertEqual(names(s), ["Pixel B"])
    s.toggleLayerIsolation(); XCTAssertEqual(s.layerPanelFilter.mode, .kind)
    XCTAssertTrue(s.layerPanelFilter.kinds.isEmpty)
    s.findLayers(); XCTAssertEqual(s.layerPanelFilter.mode, .name)
    XCTAssertEqual(s.layerFilterFocusRequest, 1); XCTAssertEqual(s.layersTab, .layers)
    XCTAssertEqual(s.document, retainingViewSelection(source, s)); XCTAssertTrue(s.session.undoStack.isEmpty)
    try PhotoshopMenuTests().withMenus { _, menu in
      let all = PhotoshopMenuTests().allItems(menu)
      let find = try XCTUnwrap(all.first { $0.identifier?.rawValue == "Select > Find Layers" })
      XCTAssertEqual(find.action, #selector(AppDelegate.findLayers))
      XCTAssertEqual(find.keyEquivalent, "f"); XCTAssertEqual(find.keyEquivalentModifierMask, [.option, .shift, .command])
      let isolate = try XCTUnwrap(all.first { $0.identifier?.rawValue == "Select > Isolate Layers" })
      XCTAssertEqual(isolate.action, #selector(AppDelegate.isolateLayers)); XCTAssertTrue(isolate.keyEquivalent.isEmpty)
    }
  }

  @MainActor func testArtboardDescendantsMissingTargetAndPerEditorDocumentLifecycle() throws {
    let source = try fixture(), first = EditorStore(document: source), second = EditorStore(document: source)
    defer { stop(first); stop(second) }
    var filter = LayerPanelFilter(); filter.mode = .artboard
    try first.setLayerFilter(filter); XCTAssertEqual(names(first), ["Artboard", "Board pixels"])
    filter.artboardID = try XCTUnwrap(source.layers.first { $0.name == "Artboard" }?.id.uuidString)
    filter.artboardID = filter.artboardID.lowercased()
    try first.setLayerFilter(filter); XCTAssertEqual(names(first), ["Artboard", "Board pixels"])
    XCTAssertEqual(first.layerPanelFilter.artboardID, filter.artboardID.uppercased())
    let unchanged = first.layerFilterRevision
    try first.setLayerFilter(filter); XCTAssertEqual(first.layerFilterRevision, unchanged)
    filter.artboardID = filter.artboardID.uppercased()
    XCTAssertEqual(second.layerPanelFilter, LayerPanelFilter())
    var withoutBoard = source; withoutBoard.layers.removeAll { $0.name == "Artboard" || $0.name == "Board pixels" }
    first.session = EditorSession(document: withoutBoard)
    XCTAssertEqual(first.layerPanelFilter, filter); XCTAssertEqual(names(first), [])
    XCTAssertEqual(first.layerFilterState["artboardTargetMissing"] as? Bool, true)
    first.session = EditorSession(document: try fixture())
    XCTAssertEqual(first.layerPanelFilter, LayerPanelFilter()); XCTAssertEqual(first.layerFilterFocusRequest, 0)
    XCTAssertEqual(second.document, source)
  }

  @MainActor func testSmartObjectClassificationUsesKnownStatusWithoutReadingSourcesOrInventingLibraryLinks() throws {
    var source = try fixture()
    let embedded = try XCTUnwrap(source.layers.first { $0.smartObject != nil })
    var local = embedded; local.id = UUID(); local.name = "Local"
    local.smartObject?.sourceID = UUID()
    let localBytes = UInt64(local.smartObject!.data.count)
    local.smartObject?.linkedSource = try .init(reference: "Never-read.psd", byteLength: localBytes)
    var remote = embedded; remote.id = UUID(); remote.name = "Remote"
    remote.smartObject?.sourceID = UUID()
    let remoteBytes = UInt64(remote.smartObject!.data.count)
    remote.smartObject?.linkedSource = try .init(reference: "https://example.test/never-read.psd", kind: .remote, byteLength: remoteBytes)
    source.layers += [local, remote]
    let s = EditorStore(document: source); defer { stop(s) }
    let controller = LinkedSourceController(store: s); s.linkedSourceController = controller
    var filter = LayerPanelFilter(); filter.mode = .smartObject
    try s.setLayerFilter(filter); XCTAssertEqual(names(s), ["Remote", "Local", "Embedded"])
    filter.smartKinds = [.embedded]; try s.setLayerFilter(filter); XCTAssertEqual(names(s), ["Embedded"])
    filter.smartKinds = [.local]; try s.setLayerFilter(filter); XCTAssertEqual(names(s), ["Local"])
    filter.smartKinds = [.missing]; try s.setLayerFilter(filter); XCTAssertEqual(names(s), [])
    controller.states[local.smartObject!.sourceID] = .init(status: .missing)
    XCTAssertEqual(names(s), ["Local"])
    let before = s.layerFilterRevisionToken
    controller.states[remote.smartObject!.sourceID] = .init(status: .modified)
    XCTAssertNotEqual(s.layerFilterRevisionToken, before)
    filter.smartKinds = [.missing, .modified]; try s.setLayerFilter(filter)
    XCTAssertEqual(names(s), ["Remote", "Local"])
    filter.smartKinds = [.library]; XCTAssertThrowsError(try s.setLayerFilter(filter))
    XCTAssertEqual(s.document, retainingViewSelection(source, s)); XCTAssertTrue(s.session.undoStack.isEmpty)
  }

  @MainActor func testFilteredShiftRangesSelectAllAndBackgroundBoundary() throws {
    var source = try fixture()
    var background = Layer(name: "Background", content: .raster(try Surface(width: 4, height: 3, fill: .white)))
    background.background = true; background.protection = .fullyLocked; source.layers.insert(background, at: 0)
    let s = EditorStore(document: source); defer { stop(s) }
    let a = try XCTUnwrap(source.layers.first { $0.name == "Nested pixels" }?.id)
    let b = try XCTUnwrap(source.layers.first { $0.name == "Board pixels" }?.id)
    var filter = LayerPanelFilter(); filter.mode = .name; filter.name = "pixels"
    try s.setLayerFilter(filter)
    s.select(a); s.select(b, modifiers: .shift)
    XCTAssertEqual(s.selectedLayerIDs, [a, b])
    s.selectAllLayers(); XCTAssertEqual(s.selectedLayerIDs, [a, b])
    filter.enabled = false; try s.setLayerFilter(filter); s.selectAllLayers()
    XCTAssertFalse(s.selectedLayerIDs.contains(background.id))
    XCTAssertEqual(s.selectedLayerIDs, Set(source.layers.filter { !$0.isBackground }.map(\.id)))
    XCTAssertEqual(s.document.activeLayerID, b); XCTAssertTrue(s.session.undoStack.isEmpty)
  }

  @MainActor func testBusyModalInvalidFiltersAndAll16ModifierCursors() throws {
    let source = try fixture(), s = EditorStore(document: source)
    defer { stop(s) }
    var filter = LayerPanelFilter(); filter.mode = .name; filter.name = "Pixel"
    for busy in [true, false] {
      s.geometryBusy = busy
      if busy { XCTAssertThrowsError(try s.setLayerFilter(filter)); XCTAssertEqual(s.layerPanelFilter, LayerPanelFilter()) }
      else { XCTAssertNoThrow(try s.setLayerFilter(filter)) }
    }
    s.beginLayerProtection(); XCTAssertThrowsError(try s.setLayerFilter(LayerPanelFilter())); s.layerProtectionDraft = nil
    filter.name = "bad\0name"; XCTAssertThrowsError(try s.setLayerFilter(filter))
    filter.name = "good"; filter.blend = "Unknown"; XCTAssertThrowsError(try s.setLayerFilter(filter))
    let canvas = CraftCanvas(store: s), flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for bits in 0..<16 {
      let modifiers = flags.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) != 0 ? $0.union($1.element) : $0 }
      canvas.updateCursorModifiers(modifiers); let before = canvas.toolCursor
      s.toggleLayerIsolation(); _ = s.layerFilterState
      canvas.updateCursorModifiers(modifiers); XCTAssertEqual(canvas.toolCursor, before)
    }
    XCTAssertEqual(s.document, retainingViewSelection(source, s)); XCTAssertTrue(s.session.undoStack.isEmpty)
  }

  @MainActor func testHostedNineModeControlsProduceOwnedLayoutEvidence() throws {
    _ = NSApplication.shared
    let stores = try LayerFilterMode.allCases.map { mode in
      let s = EditorStore(document: try fixture()); var filter = LayerPanelFilter(); filter.mode = mode
      try s.setLayerFilter(filter); s.renderTask?.cancel(); return s
    }
    defer { stores.forEach(stop) }
    let view = VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(stores.enumerated()), id: \.offset) { pair in
        VStack(alignment: .leading, spacing: 3) {
          Text(pair.element.layerPanelFilter.mode.title).font(.caption)
          LayerFilterControls(store: pair.element).frame(width: 310)
        }
      }
    }.padding(12).background(StudioTheme.panel).preferredColorScheme(.dark)
    let host = NSHostingView(rootView: view)
    host.frame = .init(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(host.fittingSize.width, 334); XCTAssertGreaterThan(host.fittingSize.height, 250)
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],
      let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: rep)
      let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
      try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("layer-filter-controls.png"))
    }
  }
}
