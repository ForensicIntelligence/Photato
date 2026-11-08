import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class SmartObjectUnpackTests: XCTestCase {
  func source(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var source = try CraftDocument(width: 8, height: 6, depth: depth, name: "Owned source")
    source.layers[0].name = "Original pixels"
    source.layers[0].content = .raster(try Surface(width: 3, height: 2, depth: depth, fill: Pixel(0.25, 0.5, 0.75, 0.5)))
    source.layers[0].x = 2; source.layers[0].y = 1
    return source
  }
  func parent(_ source: CraftDocument, depth: PixelDepth? = nil) throws -> CraftDocument {
    var target = try CraftDocument(width: 8, height: 6, depth: depth ?? source.depth)
    let placed = try SmartObjectIO.placed(data: NativeArchive.encode(source), fileName: "Owned.photato", in: target, fit: false)
    target.layers = [placed]; target.activeLayerID = placed.id
    return target
  }
  func convert(_ document: CraftDocument, ids: Set<UUID>? = nil) throws -> CraftDocument {
    var result = document
    try SmartObjectUnpack.command(in: document, selected: ids ?? [document.layers[0].id]).apply(to: &result)
    return result
  }
  func testSingleLayerRestoresIntrinsicCoordinatesBitsAndOneUndoAcrossAllDepths() throws {
    for depth in PixelDepth.allCases {
      let source = try source(depth); var parent = try parent(source)
      parent.layers[0].x = 19; parent.layers[0].y = -8
      parent.layers[0].affine = .scale(2, 0.5)
      parent.layers[0].smartFilters = .init(); parent.layers[0].smartFilters?.enabled = false
      parent.selection = .init(x: 0, y: 0, width: 1, height: 1)
      let id = parent.layers[0].id
      var session = EditorSession(document: parent)
      try session.execute(SmartObjectUnpack.command(in: parent, selected: [id]))
      let result = session.document, layer = try XCTUnwrap(result.layers.first)
      XCTAssertEqual(result.layers.count, 1); XCTAssertEqual(layer.id, id)
      XCTAssertNil(layer.smartObject); XCTAssertNil(layer.smartFilters); XCTAssertNil(layer.affine)
      XCTAssertEqual(layer.x, 2); XCTAssertEqual(layer.y, 1)
      XCTAssertEqual(layer.content, source.layers[0].content)
      XCTAssertEqual(result.selection, parent.selection)
      XCTAssertEqual(session.undoStack.count, 1)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
      try session.undo(); XCTAssertEqual(session.document, parent)
      try session.redo(); XCTAssertEqual(session.document, result)
    }
  }
  func testEditableHierarchyTypeShapesMasksAndExactOwnCompositeSurvive() throws {
    for depth in PixelDepth.allCases {
      var source = try source(depth)
      var text = TextContent(text: "Editable", size: 4, color: Pixel(0.8, 0.2, 0.1))
      text.layoutWidth = 8; text.layoutHeight = 6
      var type = Layer(name: "Type", content: .text(text)); type.visible = false
      let shape = try ShapeContent(definition: .init(geometry: .init(width: 2, height: 2), fill: .init(color: Pixel(0, 1, 0))))
      var vector = Layer(name: "Shape", content: .shape(shape)); vector.x = 5
      let group = Layer(name: "Source folder", content: .group(.init(passThrough: false)))
      source.layers[0].parentID = group.id; type.parentID = group.id; vector.parentID = group.id
      source.layers[0].mask = try Surface(width: 3, height: 2, depth: depth, fill: .white)
      source.layers += [type, vector, group]
      let parent = try parent(source), result = try convert(parent)
      XCTAssertEqual(result.layers.count, 5); XCTAssertTrue(result.layers.last!.isGroup)
      XCTAssertEqual(result.layers.last!.id, parent.layers[0].id)
      XCTAssertEqual(result.layers.filter { $0.typeContent != nil }.first?.typeContent, text)
      XCTAssertEqual(result.layers.first(where: { $0.shape != nil })?.shape, shape)
      XCTAssertEqual(result.layers[0].mask, source.layers[0].mask)
      XCTAssertEqual(result.layers[0].parentID, result.layers[3].id)
      XCTAssertEqual(result.layers[3].parentID, result.layers[4].id)
      XCTAssertEqual(try Renderer.composite(result).rgbaData(depth: .f32), try Renderer.composite(source).rgbaData(depth: .f32))
      try result.validate()
    }
  }
  func testConflictingPatternsRemapFillShapeAndAllStyleDependenciesWithoutOverwriting() throws {
    var source = try source()
    let pattern = try RasterPattern(name: "Original pattern", surface: Surface(width: 2, height: 2, fill: Pixel(1, 0, 0)), id: "collision")
    source.patterns = [pattern]
    var effect = LayerEffect(.patternOverlay); effect.pattern = .init(patternID: pattern.id)
    source.layers[0].style = .init(effects: [effect])
    source.layers.append(Layer(name: "Pattern", content: .patternFill(.init(patternID: pattern.id))))
    var shape = ShapeContent(kind: .rectangle, width: 2, height: 2, color: .black)
    var paint = ShapePaint(); paint.kind = .pattern; paint.pattern = .init(patternID: pattern.id)
    shape.definition = .init(geometry: .init(width: 2, height: 2), fill: paint)
    shape.definition?.stroke.paint = paint
    shape.importedAppearance = .init(definition: shape.definition!, pixels: try Surface(width: 2, height: 2, fill: Pixel(1, 0, 0)))
    source.layers.append(Layer(name: "Pattern shape", content: .shape(shape)))
    var parent = try parent(source)
    let old = try RasterPattern(name: "Existing", surface: Surface(width: 2, height: 2, fill: Pixel(0, 0, 1)), id: pattern.id)
    parent.patterns = [old]
    let result = try convert(parent), replacement = try XCTUnwrap(result.patterns?.first { $0.id != old.id })
    XCTAssertEqual(result.pattern(old.id), old); XCTAssertEqual(replacement.surface, pattern.surface)
    XCTAssertEqual(result.layers[0].style?.presetPatternIDs, [replacement.id])
    if case .patternFill(let fill) = result.layers[1].content { XCTAssertEqual(fill.patternID, replacement.id) } else { XCTFail("Lost pattern fill") }
    let copied = try XCTUnwrap(result.layers[2].shape)
    XCTAssertEqual(copied.definition?.fill.pattern?.patternID, replacement.id)
    XCTAssertEqual(copied.definition?.stroke.paint.pattern?.patternID, replacement.id)
    XCTAssertEqual(copied.importedAppearance?.definition, copied.definition)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
  }
  func testNestedSharedSourcesAndPristineOrStaleCachesKeepTheirMeaning() throws {
    let child = try source()
    var source = try parent(child)
    var nested = source.layers[0]
    nested.importedSmartAppearance = try .init(layer: nested, pixels: Surface(width: 2, height: 2, fill: Pixel(1, 0, 0)))
    var stale = nested; stale.id = UUID(); stale.x += 1
    source.layers = [nested, stale]
    let parent = try parent(source), result = try convert(parent)
    XCTAssertEqual(result.layers[0].smartObject?.sourceID, result.layers[1].smartObject?.sourceID)
    XCTAssertNotEqual(result.layers[0].smartObject?.sourceID, nested.smartObject?.sourceID)
    XCTAssertEqual(result.layers[0].smartObject?.data, nested.smartObject?.data)
    XCTAssertNotNil(result.layers[0].pristineSmartAppearance)
    XCTAssertNil(result.layers[1].pristineSmartAppearance)
    XCTAssertEqual(result.layers[0].importedSmartAppearance?.pixels, nested.importedSmartAppearance?.pixels)
    try result.validate()
  }
  func testAllDepthTransfersUseExistingColorConversionAndKeepMaskCoverage() throws {
    for from in PixelDepth.allCases { for to in PixelDepth.allCases {
      var source = try source(from)
      source.layers[0].mask = try Surface(width: 3, height: 2, depth: from, fill: Pixel(0.25, 0.25, 0.25, 1))
      let parent = try parent(source, depth: to), result = try convert(parent)
      guard case .raster(let original) = source.layers[0].content, case .raster(let converted) = result.layers[0].content else { return XCTFail("Lost raster") }
      XCTAssertEqual(converted, try ColorManagement.converted(original, from: source, to: parent))
      XCTAssertEqual(result.layers[0].mask, try source.layers[0].mask?.converted(to: to))
    } }
  }
  func testSelectedSourceCompAndUnselectedInstancesRemainIndependent() throws {
    let helper = SmartObjectLayerCompIOTests(), source = try helper.source()
    var parent = try parent(source), first = parent.layers[0]
    first.smartObject?.layerComps?.selectedID = source.layerComps!.comps[0].id
    var other = first; other.id = UUID(); other.smartObject?.layerComps?.selectedID = nil
    parent.layers = [first, other]; parent.activeLayerID = first.id
    let result = try convert(parent)
    XCTAssertFalse(result.layers[1].visible)
    XCTAssertEqual(result.layers.last, other)
    XCTAssertEqual(result.activeLayerID, first.id)
  }
  func testLinkedOriginalUsesRetainedBytesWithoutOpeningItsPath() throws {
    var parent = try parent(source())
    let bytes = parent.layers[0].smartObject!.data
    parent.layers[0].smartObject = try parent.layers[0].smartObject!.linked(to: .init(reference: "file:///unavailable/never-open-this.photato", contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count)))
    XCTAssertNil(try convert(parent).layers[0].smartObject)
    parent.layers[0].smartObject?.data = Data()
    XCTAssertFalse(SmartObjectUnpack.available(in: parent, selected: [parent.layers[0].id]))
    XCTAssertThrowsError(try convert(parent))
  }
  func testCorruptLaterSourceAndLocksRejectWholeBatchAndStalePreparedCommit() throws {
    var parent = try parent(source()), broken = parent.layers[0]
    broken.id = UUID(); broken.smartObject?.sourceID = UUID(); broken.smartObject?.data = Data([1, 2, 3])
    parent.layers.append(broken)
    let before = parent
    XCTAssertThrowsError(try convert(parent, ids: Set(parent.layers.map(\.id))))
    XCTAssertEqual(parent, before)
    parent.layers.removeLast()
    let command = try SmartObjectUnpack.command(in: parent, selected: [parent.layers[0].id])
    var changed = parent; changed.name = "Changed during preparation"
    XCTAssertThrowsError(try command.apply(to: &changed)); XCTAssertNotNil(changed.layers[0].smartObject)
    parent.layers[0].locked = true
    XCTAssertFalse(SmartObjectUnpack.available(in: parent, selected: [parent.layers[0].id]))
    XCTAssertThrowsError(try convert(parent))
  }
  func testOuterAttachmentsRetainFolderIdentityAndMaskWorldPlacement() throws {
    var parent = try parent(source())
    parent.layers[0].opacity = 0.6; parent.layers[0].blendMode = .multiply
    parent.layers[0].style = .init(effects: [.init(.dropShadow)])
    parent.layers[0].x = 5; parent.layers[0].y = 3
    parent.layers[0].affine = .scale(2, 2)
    parent.layers[0].mask = try Surface(width: 2, height: 2, fill: .white)
    parent.layers[0].smartFilters = .init()
    let original = parent.layers[0], result = try convert(parent), folder = result.layers.last!
    XCTAssertTrue(folder.isGroup); XCTAssertEqual(folder.id, original.id)
    XCTAssertEqual(folder.opacity, original.opacity); XCTAssertEqual(folder.blendMode, original.blendMode)
    XCTAssertEqual(folder.style, original.style); XCTAssertEqual(folder.mask, original.mask)
    XCTAssertEqual(folder.maskCoordinateTransform, original.maskCoordinateTransform)
    XCTAssertNil(folder.smartFilters); XCTAssertNil(folder.affine); XCTAssertEqual(folder.x, 0)
  }
  func testMultipleTargetsKeepParentClippingUnselectedSourceAndOneUndo() throws {
    var parent = try parent(source()), first = parent.layers[0], second = parent.layers[0], other = parent.layers[0]
    let folder = Layer(name: "Parent folder", content: .group(.init()))
    second.id = UUID(); other.id = UUID(); second.clipped = true
    first.parentID = folder.id; second.parentID = folder.id; other.parentID = folder.id
    parent.layers = [first, second, other, folder]; parent.activeLayerID = second.id
    var session = EditorSession(document: parent)
    try session.execute(SmartObjectUnpack.command(in: parent, selected: [first.id, second.id]))
    let result = session.document
    XCTAssertEqual(result.layers.count, 4); XCTAssertEqual(result.activeLayerID, second.id)
    XCTAssertNil(result.layers[0].smartObject); XCTAssertNil(result.layers[1].smartObject)
    XCTAssertEqual(result.layers[2], other); XCTAssertEqual(result.layers[3], folder)
    XCTAssertEqual(result.layers[0].parentID, folder.id); XCTAssertTrue(result.layers[1].isClipped)
    XCTAssertEqual(session.undoStack.count, 1); try session.undo(); XCTAssertEqual(session.document, parent)
  }
  func testDifferentWorkingProfileAndInvalidTargetsRejectWithoutChanges() throws {
    let source = try WorkingProfileTests().p3()
    let parent = try parent(source)
    XCTAssertThrowsError(try convert(parent))
    XCTAssertThrowsError(try convert(parent, ids: []))
    XCTAssertThrowsError(try convert(parent, ids: [UUID()]))
    XCTAssertNotNil(parent.layers[0].smartObject)
  }
}
