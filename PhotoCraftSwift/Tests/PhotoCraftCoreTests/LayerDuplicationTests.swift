import XCTest

@testable import PhotoCraftCore

final class LayerDuplicationTests: XCTestCase {
  func fixture(depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 8, height: 6, depth: depth)
    document.layers = try (0..<3).map { index in
      var layer = Layer(
        name: ["A", "B", "C"][index],
        content: .raster(
          try Surface(width: 3, height: 2, depth: depth, fill: Pixel(0.2, 0.4, 0.7, 0.8))))
      layer.x = index - 2
      layer.y = index + 1
      return layer
    }
    document.activeLayerID = document.layers[0].id
    return document
  }
  func testSelectedCopiesFollowEachOriginalAndHaveOneUndo() throws {
    let original = try fixture()
    let ids = original.layers.map(\.id)
    var session = EditorSession(document: original)
    try session.execute(.duplicateLayers([ids[0], ids[2]]))
    XCTAssertEqual(session.document.layers.map(\.name), ["A", "A copy", "B", "C", "C copy"])
    XCTAssertEqual(session.document.activeLayerID, session.document.layers[1].id)
    XCTAssertEqual(session.document.layers[1].content, original.layers[0].content)
    XCTAssertEqual(session.document.layers[4].x, original.layers[2].x)
    XCTAssertEqual(Set(session.document.layers.map(\.id)).count, 5)
    let result = session.document
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo()
    XCTAssertEqual(session.document, original)
    try session.redo()
    XCTAssertEqual(session.document, result)
  }
  func testNestedSelectionRemapsAllParentsPreservingEditableProperties() throws {
    var original = try fixture(depth: .u16)
    original.layers[0].mask = try Surface(
      width: 2, height: 3, depth: .u16, fill: Pixel(0.4, 0.4, 0.4))
    original.layers[0].maskProperties = MaskProperties()
    original.layers[0].vectorMask = VectorMask(path: VectorPathTests().rectangle())
    original.layers[0].affine = .translation(0.5, -0.25)
    original.layers[0].colorLabel = .violet
    original.layers[0].sourceTags?["shmd"] = Data([1, 2, 3])
    let child = original.layers[0].id
    try Command.groupLayers([child], "Inner").apply(to: &original)
    let inner = original.activeLayerID!
    try Command.groupLayers([inner], "Outer").apply(to: &original)
    let outer = original.activeLayerID!
    var result = original
    try Command.duplicateLayers([outer, inner, child], name: "Copy").apply(to: &result)
    let copy = result.activeLayerID!
    XCTAssertEqual(result.subtreeIDs(copy).count, 3)
    let copiedChild = try XCTUnwrap(result.layers.first { $0.id != child && $0.name == "A" })
    var normalized = copiedChild
    normalized.id = child
    normalized.parentID = inner
    XCTAssertEqual(normalized, original.layers.first { $0.id == child })
    XCTAssertEqual(result.ancestors(of: copiedChild.id).last?.id, copy)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
  }
  func testCrossDocumentTransferKeepsCoordinatesSelectionAndRemapsPatternConflict() throws {
    var source = try fixture()
    let pattern = try RasterPattern(
      name: "Tile", surface: Surface(width: 2, height: 2, fill: Pixel(0.2, 0.4, 0.6)),
      id: "collision")
    try source.installPattern(pattern)
    let fill = Layer(name: "Pattern", content: .patternFill(.init(patternID: pattern.id)))
    source.layers.append(fill)
    source.activeLayerID = fill.id
    var target = try CraftDocument(width: 4, height: 4)
    target.selection = .init(x: 1, y: 1, width: 2, height: 2)
    let existing = try RasterPattern(
      name: "Other", surface: Surface(width: 2, height: 2, fill: .white), id: "collision")
    try target.installPattern(existing)
    let before = target
    var session = EditorSession(document: target)
    try session.execute(.duplicateLayersFrom(source, [source.layers[0].id, fill.id]))
    target = session.document
    XCTAssertEqual(target.selection, before.selection)
    XCTAssertEqual(target.layers[1].x, -2)
    XCTAssertEqual(target.layers[1].y, 1)
    XCTAssertEqual(target.layers[1].name, "A")
    guard case .patternFill(let copied) = target.layers[2].content else {
      return XCTFail("No pattern copy")
    }
    XCTAssertNotEqual(copied.patternID, pattern.id)
    XCTAssertEqual(target.pattern(copied.patternID)?.surface, pattern.surface)
    XCTAssertEqual(target.pattern("collision"), existing)
    try session.undo()
    XCTAssertEqual(session.document, before)
  }
  func testNewDocumentUsesSourceCanvasProfileResolutionAndOnlyCopiedSubtrees() throws {
    var original = try fixture(depth: .u16)
    original.resolution = 300
    original.sourceICC = Data([1, 2, 3])
    original.selection = .init(x: 0, y: 0, width: 1, height: 1)
    original.paths = [NamedPath(path: VectorPathTests().rectangle())]
    let result = try LayerDuplication.newDocument(
      from: original, selected: [original.layers[2].id], layerName: "Output",
      documentName: "Separate")
    XCTAssertNotEqual(result.id, original.id)
    XCTAssertEqual(result.width, 8)
    XCTAssertEqual(result.height, 6)
    XCTAssertEqual(result.depth, .u16)
    XCTAssertEqual(result.resolution, 300)
    XCTAssertEqual(result.sourceICC, original.sourceICC)
    XCTAssertEqual(result.layers.count, 1)
    XCTAssertEqual(result.layers[0].name, "Output")
    XCTAssertEqual(result.layers[0].content, original.layers[2].content)
    XCTAssertEqual(result.layers[0].y, 3)
    XCTAssertNil(result.selection)
    XCTAssertNil(result.paths)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
  }
  func testRasterAndMaskDepthConversionAcrossNineCombinations() throws {
    for from in PixelDepth.allCases {
      var source = try fixture(depth: from)
      source.layers[0].mask = try Surface(
        width: 3, height: 2, depth: from, fill: Pixel(0.37, 0.37, 0.37))
      for to in PixelDepth.allCases {
        var target = try CraftDocument(width: 2, height: 2, depth: to)
        try Command.duplicateLayersFrom(source, [source.layers[0].id]).apply(to: &target)
        let copied = target.layers.last!
        guard case .raster(let raster) = copied.content,
          case .raster(let original) = source.layers[0].content
        else { return XCTFail("Raster lost") }
        XCTAssertEqual(raster.depth, to)
        XCTAssertEqual(copied.mask?.depth, to)
        XCTAssertEqual(raster.pixel(x: 0, y: 0), original.pixel(x: 0, y: 0).quantized(to))
        if from == to {
          XCTAssertEqual(copied.content, source.layers[0].content)
          XCTAssertEqual(copied.mask, source.layers[0].mask)
        }
      }
    }
  }
  func testFailureIsAtomicForNamesMissingIDsLocksProfilesAndCapacity() throws {
    let original = try fixture()
    for command: Command in [
      .duplicateLayers([]), .duplicateLayers([UUID()]),
      .duplicateLayers([original.layers[0].id], name: " "),
      .duplicateLayers(Set(original.layers.map(\.id)), name: "Shared"),
    ] {
      var target = original
      XCTAssertThrowsError(try command.apply(to: &target))
      XCTAssertEqual(target, original)
    }
    var locked = original
    try Command.groupLayers([locked.layers[0].id], "Locked").apply(to: &locked)
    let group = locked.activeLayerID!
    try Command.lock(group, true).apply(to: &locked)
    let before = locked
    XCTAssertThrowsError(try Command.duplicateLayer(original.layers[0].id).apply(to: &locked))
    XCTAssertEqual(locked, before)
    try Command.duplicateLayer(group).apply(to: &locked)
    XCTAssertTrue(locked.layers.first { $0.id == locked.activeLayerID }?.locked == true)
    var target = original
    target.workingICC = Data([1])
    let profile = target
    XCTAssertThrowsError(
      try Command.duplicateLayersFrom(original, [original.layers[0].id]).apply(to: &target))
    XCTAssertEqual(target, profile)
    target = original
    target.layers = (0..<LayerLimits.maximumLayers).map { Layer(name: "L\($0)", content: .fill(.white)) }
    target.activeLayerID = target.layers[0].id
    let full = target
    XCTAssertThrowsError(
      try Command.duplicateLayersFrom(original, [original.layers[0].id]).apply(to: &target))
    XCTAssertEqual(target, full)
  }
  func testTransferRejectsLockedAndExcessivelyNestedTargetsWithoutLeakingCopies() throws {
    var source = try fixture()
    try Command.newGroup(.init(name: "Source group"), children: [source.layers[0].id]).apply(
      to: &source)
    let selected = Set([source.activeLayerID!])
    var target = try fixture()
    for index in 0..<32 {
      try Command.newGroup(.init(name: "Level \(index)")).apply(to: &target)
    }
    let original = target
    XCTAssertThrowsError(try Command.duplicateLayersFrom(source, selected).apply(to: &target))
    XCTAssertEqual(target, original)
    try Command.lock(target.activeLayerID!, true).apply(to: &target)
    let locked = target
    XCTAssertThrowsError(
      try Command.duplicateLayersFrom(source, [source.layers[0].id]).apply(to: &target))
    XCTAssertEqual(target, locked)
  }

  func testTransferIntoGroupAndExternalClippingBasePolicy() throws {
    var source = try fixture()
    try Command.clipping(source.layers[1].id, true).apply(to: &source)
    let clipped = source.layers[1].id
    var target = try fixture()
    try Command.newGroup(.init(name: "Target")).apply(to: &target)
    let group = target.activeLayerID!
    try Command.duplicateLayersFrom(source, [clipped]).apply(to: &target)
    let copy = try XCTUnwrap(target.layers.first { $0.id == target.activeLayerID })
    XCTAssertEqual(copy.parentID, group)
    XCTAssertFalse(copy.isClipped)
    let new = try LayerDuplication.newDocument(
      from: source, selected: Set(source.layers.prefix(2).map(\.id)), documentName: "Chain")
    XCTAssertTrue(new.layers[1].isClipped)
    XCTAssertEqual(new.clippingBase(for: new.layers[1].id)?.id, new.layers[0].id)
  }
}
