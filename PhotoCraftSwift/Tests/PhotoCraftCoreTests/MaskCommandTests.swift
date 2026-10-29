import Foundation
import PhotoCraftCore
import XCTest

final class MaskCommandTests: XCTestCase {
  func raster(_ layer: Layer) throws -> Surface {
    guard case .raster(let pixels) = layer.content else {
      throw CraftError.invalid("Expected pixels")
    }
    return pixels
  }

  // Port of PhotoCraft's layer_menu_cmds mask_apply_from_transparency_hide_selection case.
  func testHideSelectionApplyAndFromTransparencyAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 4, height: 2, depth: depth)
      let id = doc.layers[0].id
      doc.layers[0].content = .raster(
        try Surface(width: 4, height: 2, depth: depth, fill: Pixel(0.2, 0.4, 0.6)))
      doc.selection = IntRect(x: 0, y: 0, width: 2, height: 2)
      var session = EditorSession(document: doc)
      try session.execute(.createMask(id, .hideSelection))
      XCTAssertNil(session.document.selection)
      XCTAssertEqual(try MaskSampler(layer: session.document.layers[0]).coverage(x: 0.5, y: 0.5), 0)
      XCTAssertEqual(try MaskSampler(layer: session.document.layers[0]).coverage(x: 3.5, y: 0.5), 1)
      try session.execute(.applyMask(id))
      let applied = session.document
      XCTAssertNil(applied.layers[0].mask)
      XCTAssertNil(applied.layers[0].maskProperties)
      let pixels = try raster(applied.layers[0])
      XCTAssertEqual(pixels.pixel(x: 0, y: 0).a, 0)
      XCTAssertEqual(pixels.pixel(x: 3, y: 0).a, 1)
      XCTAssertEqual(pixels.pixel(x: 0, y: 0).rgb, try raster(doc.layers[0]).pixel(x: 0, y: 0).rgb)
      XCTAssertEqual(session.undoStack.last?.label, "Apply Layer Mask")
      try session.execute(.createMask(id, .fromTransparency))
      let split = session.document.layers[0]
      XCTAssertEqual(try raster(split).pixel(x: 0, y: 0).a, 1)
      XCTAssertEqual(split.mask?.pixel(x: 0, y: 0).r, 0)
      XCTAssertEqual(split.mask?.pixel(x: 3, y: 0).r, 1)
      XCTAssertEqual(
        try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
      try session.undo()
      XCTAssertEqual(session.document, applied)
      try session.undo()
      XCTAssertNotNil(session.document.layers[0].mask)
      try session.undo()
      XCTAssertEqual(session.document, doc)
    }
  }

  func testSelectionMasksUseDocumentCoordinatesForTransformedLayersAndGroups() throws {
    for group in [false, true] {
      var doc = try CraftDocument(width: 4, height: 2, depth: .u16)
      var layer = Layer(name: "Target", content: group ? .group(GroupContent()) : .fill(.white))
      layer.x = 9
      layer.y = -2
      layer.affine = .rotation(30)
      doc.layers = [layer]
      doc.activeLayerID = layer.id
      doc.setCoverageSelection(
        try SelectionMask(width: 4, height: 2, bytes: [0, 64, 128, 255, 0, 0, 0, 0]))
      for kind in [LayerMaskCreation.revealSelection, .hideSelection] {
        var session = EditorSession(document: doc)
        try session.execute(.createMask(layer.id, kind))
        let mask = try MaskSampler(layer: session.document.layers[0])
        for x in 0..<4 {
          let value = Float([0, 64, 128, 255][x]) / 255
          XCTAssertEqual(
            mask.coverage(x: Double(x) + 0.5, y: 0.5),
            kind == .hideSelection ? 1 - value : value, accuracy: 0.00002)
        }
        XCTAssertEqual(mask.coverage(x: -100, y: 100), kind == .hideSelection ? 1 : 0)
        XCTAssertNil(session.document.selectionMask)
        XCTAssertEqual(session.document.layers[0].content, layer.content)
        XCTAssertEqual(session.document.layers[0].mask?.depth, .u16)
      }
    }
  }

  func testApplyUsesFeatherDensityInversionAndLeavesOtherLayerStateEditable() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 12, height: 10, depth: depth)
      var layer = Layer(
        name: "Offset",
        content: .raster(
          try Surface(width: 6, height: 6, depth: depth, fill: Pixel(0.8, 0.3, 0.1, 0.5))))
      layer.x = 3
      layer.y = 2
      layer.mask = try Surface(width: 1, height: 1, fill: .white)
      var properties = MaskProperties()
      properties.transform = .translation(2, 2)
      properties.feather = 1
      properties.density = 0.4
      properties.inverted = true
      properties.linked = false
      layer.maskProperties = properties
      layer.opacity = 0.6
      layer.blendMode = .multiply
      layer.vectorMask = VectorMask()
      layer.sourceTags = ["lyid": Data([0, 0, 0, 17])]
      doc.layers = [layer]
      doc.activeLayerID = layer.id
      // Apply affects the entire stored layer, regardless of the current selection.
      doc.selection = IntRect(x: 0, y: 0, width: 1, height: 1)
      var session = EditorSession(document: doc)
      try session.execute(.applyMask(layer.id))
      let result = session.document.layers[0]
      let old = try raster(layer).pixel(x: 2, y: 2)
      let expected = depth.quantize(old.a * (1 - 0.4 * 0.159241))
      XCTAssertEqual(try raster(result).pixel(x: 2, y: 2).a, expected, accuracy: 0.00001)
      XCTAssertEqual(try raster(result).pixel(x: 2, y: 2).rgb, old.rgb)
      XCTAssertEqual(result.vectorMask, layer.vectorMask)
      XCTAssertEqual(result.opacity, layer.opacity)
      XCTAssertEqual(result.blendMode, layer.blendMode)
      XCTAssertEqual(result.sourceTags, layer.sourceTags)
      XCTAssertEqual(session.document.selection, doc.selection)
      try session.undo()
      XCTAssertEqual(session.document, doc)
    }
  }

  func testFromTransparencyRetainsOffCanvasAndExtendedHiddenRGB() throws {
    var doc = try CraftDocument(width: 2, height: 2, depth: .f32)
    var pixels = try Surface(width: 4, height: 2, depth: .f32, fill: Pixel(-0.2, 2, 0.8, 0.75))
    pixels.setPixel(x: 0, y: 0, Pixel(4, -1, 0.2, 0))
    var layer = Layer(name: "Off canvas", content: .raster(pixels))
    layer.x = -1
    doc.layers = [layer]
    doc.activeLayerID = layer.id
    var session = EditorSession(document: doc)
    try session.execute(.createMask(layer.id, .fromTransparency))
    XCTAssertEqual(session.document.layers[0].x, -1)
    XCTAssertEqual(session.document.layers[0].mask?.width, 4)
    XCTAssertEqual(try raster(session.document.layers[0]).pixel(x: 0, y: 0), Pixel(4, -1, 0.2, 1))
    XCTAssertEqual(session.document.layers[0].mask?.pixel(x: 0, y: 0).r, 0)
    try session.execute(.applyMask(layer.id))
    let result = try raster(session.document.layers[0])
    for y in 0..<2 {
      for x in 0..<4 { XCTAssertEqual(result.pixel(x: x, y: y), pixels.pixel(x: x, y: y)) }
    }
  }

  func testApplyDisabledMaskAndDeleteAreDistinct() throws {
    var doc = try CraftDocument(width: 2, height: 2)
    let id = doc.layers[0].id
    try Command.createMask(id, .hideAll).apply(to: &doc)
    doc.layers[0].maskProperties?.enabled = false
    var applied = EditorSession(document: doc)
    try applied.execute(.applyMask(id))
    XCTAssertEqual(try raster(applied.document.layers[0]).pixel(x: 0, y: 0).a, 0)
    var deleted = EditorSession(document: doc)
    try deleted.execute(.deleteMask(id))
    XCTAssertEqual(deleted.document.layers[0].content, doc.layers[0].content)
    XCTAssertNil(deleted.document.layers[0].maskProperties)
    try deleted.undo()
    XCTAssertEqual(deleted.document, doc)
  }

  func testInvalidMaskOperationsAreTransactionalIncludingInheritedLocks() throws {
    var doc = try CraftDocument(width: 4, height: 4)
    let id = doc.layers[0].id
    for command in [
      Command.applyMask(id), .deleteMask(id), .createMask(id, .revealSelection),
      .createMask(id, .hideSelection),
    ] {
      var session = EditorSession(document: doc)
      XCTAssertThrowsError(try session.execute(command))
      XCTAssertEqual(session.document, doc)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
    try Command.createMask(id, .revealAll).apply(to: &doc)
    var existing = EditorSession(document: doc)
    XCTAssertThrowsError(try existing.execute(.createMask(id, .fromTransparency)))
    for content in [LayerContent.fill(.white), .group(GroupContent()), .adjustment(.invert)] {
      var candidate = doc
      candidate.layers[0].content = content
      var session = EditorSession(document: candidate)
      XCTAssertThrowsError(try session.execute(.applyMask(id)))
      XCTAssertEqual(session.document, candidate)
    }
    var parent = Layer(name: "Locked folder", content: .group(GroupContent()))
    parent.locked = true
    doc.layers[0].parentID = parent.id
    doc.layers.append(parent)
    for command in [Command.applyMask(id), .deleteMask(id)] {
      var session = EditorSession(document: doc)
      XCTAssertThrowsError(try session.execute(command))
      XCTAssertEqual(session.document, doc)
    }
  }
}
