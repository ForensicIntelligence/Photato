import Foundation
import PhotoCraftCore
import XCTest

final class ClipboardTests: XCTestCase {
  func pixels(_ layer: Layer) throws -> Surface {
    guard case .raster(let surface) = layer.content else {
      throw CraftError.invalid("Expected pixels")
    }
    return surface
  }
  func testNativeTransferPreservesDepthHiddenColorsCoordinatesAndRejectsDamagedArchives() throws {
    for depth in PixelDepth.allCases {
      var surface = try Surface(
        width: 3, height: 2, depth: depth, fill: Pixel(0.23, 0.57, 0.91, 0.37))
      surface.setPixel(x: 1, y: 0, Pixel(-0.5, 2, 0.7, 0))
      let clip = try ClipboardContent.pixels(surface, x: -7, y: 11, resolution: 300)
      let data = try clip.encoded()
      XCTAssertEqual(try ClipboardContent.decode(data), clip)
      for length in stride(from: 0, to: data.count, by: max(1, data.count / 25)) {
        XCTAssertThrowsError(try ClipboardContent.decode(data.prefix(length)))
      }
      var target = try CraftDocument(width: 16, height: 16, depth: depth)
      try Command.paste(clip, .inPlace, nil).apply(to: &target)
      XCTAssertEqual(target.layers.last?.x, -7)
      XCTAssertEqual(target.layers.last?.y, 11)
      XCTAssertEqual(try pixels(target.layers.last!), surface)
      let created = try clip.newDocument(name: "New from Clipboard")
      XCTAssertEqual(created.width, 3)
      XCTAssertEqual(created.height, 2)
      XCTAssertEqual(created.pixelsPerInch, 300)
      XCTAssertEqual(created.layers[0].x, 0)
      XCTAssertEqual(created.layers[0].y, 0)
      XCTAssertEqual(try pixels(created.layers[0]), surface)
    }
  }
  func testPasteIntoAndOutsideHaveIndependentDocumentMasksAndOneUndoStep() throws {
    let clip = try ClipboardContent.pixels(
      Surface(width: 4, height: 2, depth: .f32, fill: .white), x: 12, y: 8)
    for placement in [PastePlacement.into, .outside] {
      var doc = try CraftDocument(width: 8, height: 4, depth: .u16)
      var bytes = [UInt8](repeating: 0, count: 32)
      bytes[11] = 128
      bytes[12] = 255
      doc.setCoverageSelection(try SelectionMask(width: 8, height: 4, bytes: bytes))
      var session = EditorSession(document: doc)
      try session.execute(.paste(clip, placement, nil))
      let layer = session.document.layers.last!
      XCTAssertEqual(layer.x, 2)
      XCTAssertEqual(layer.y, 1)
      XCTAssertEqual(try pixels(layer).depth, .u16)
      XCTAssertEqual(layer.maskProperties?.linked, false)
      let sampler = try MaskSampler(layer: layer)
      for x in 0..<8 {
        let expected = Float(bytes[8 + x]) / 255
        XCTAssertEqual(
          sampler.coverage(x: Double(x) + 0.5, y: 1.5),
          placement == .into ? expected : 1 - expected, accuracy: 1 / 65535)
      }
      XCTAssertNil(session.document.selection)
      XCTAssertEqual(session.undoStack.count, 1)
      session.undo()
      XCTAssertEqual(session.document, doc)
      session.redo()
      XCTAssertEqual(session.document.layers.count, 2)
    }
  }
  func testCutFractionalSelectionPreservesHiddenRGBAndIsUndoableAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 4, height: 2, depth: depth)
      let surface = try Surface(width: 4, height: 2, depth: depth, fill: Pixel(0.7, 0.2, 0.9, 0.8))
      doc.layers[0].content = .raster(surface)
      doc.setCoverageSelection(
        try SelectionMask(
          width: 4, height: 2,
          bytes: [0, 128, 255, 0, 0, 0, 0, 0]))
      var session = EditorSession(document: doc)
      try session.execute(.cut([doc.layers[0].id]))
      let result = try pixels(session.document.layers[0])
      for x in 0..<4 {
        let original = surface.pixel(x: x, y: 0)
        XCTAssertEqual(result.pixel(x: x, y: 0).rgb, original.rgb)
        XCTAssertEqual(
          result.pixel(x: x, y: 0).a,
          depth.quantize(original.a * (1 - doc.selectionCoverage(x: x, y: 0))))
      }
      XCTAssertEqual(session.document.selection, doc.selection)
      session.undo()
      XCTAssertEqual(session.document, doc)
    }
  }
  func testPasteGroupRemapsIDsAndRetainsPropertiesMasksClippingAndDepthConversion() throws {
    var source = try CraftDocument(width: 20, height: 12, depth: .f32)
    let group = Layer(name: "Folder", content: .group(GroupContent()))
    var base = Layer(
      name: "Pixels",
      content: .raster(
        try Surface(width: 3, height: 2, depth: .f32, fill: Pixel(0.2, 0.7, 0.4, 0.6))))
    base.x = 4
    base.y = 3
    base.parentID = group.id
    base.opacity = 0.4
    base.mask = try Surface(width: 2, height: 2, depth: .f32, fill: Pixel(0.37, 0.37, 0.37))
    var mask = MaskProperties()
    mask.linked = false
    mask.transform = .translation(2, -1)
    base.maskProperties = mask
    var clipped = Layer(name: "Clip", content: .fill(.white))
    clipped.parentID = group.id
    clipped.clipped = true
    source.layers = [base, clipped, group]
    source.activeLayerID = group.id
    let clip = try ClipboardContent(
      kind: .layers, document: source,
      bounds: IntRect(x: 0, y: 0, width: 20, height: 12))
    var target = try CraftDocument(width: 40, height: 32, depth: .u16)
    try Command.paste(clip, .centered, nil).apply(to: &target)
    let copied = target.layers[1...]
    XCTAssertTrue(Set(copied.map(\.id)).isDisjoint(with: Set(source.layers.map(\.id))))
    XCTAssertEqual(copied.first?.parentID, copied.last?.id)
    XCTAssertEqual(copied.first?.x, 14)
    XCTAssertEqual(copied.first?.y, 13)
    XCTAssertEqual(copied.first?.maskProperties, mask)
    XCTAssertEqual(copied.first?.opacity, 0.4)
    XCTAssertEqual(copied.dropFirst().first?.isClipped, true)
    XCTAssertEqual(try pixels(copied.first!).depth, .u16)
    XCTAssertEqual(copied.first?.mask?.depth, .u16)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(target)), target)
  }
  func testCutAndPasteRejectLockedTargetsAndInvalidPlacementWithoutHistoryChanges() throws {
    var doc = try CraftDocument(width: 2, height: 2)
    let clip = try ClipboardContent.pixels(Surface(width: 1, height: 1, fill: .white))
    doc.layers[0].locked = true
    var session = EditorSession(document: doc)
    XCTAssertThrowsError(try session.execute(.cut([doc.layers[0].id])))
    XCTAssertThrowsError(try session.execute(.paste(clip, .into, nil)))
    XCTAssertThrowsError(try session.execute(.paste(clip, .centered, PathPoint(.infinity, 0))))
    XCTAssertEqual(session.document, doc)
    XCTAssertTrue(session.undoStack.isEmpty)
    var folder = Layer(name: "Locked", content: .group(GroupContent()))
    folder.locked = true
    doc.layers = [folder]
    doc.activeLayerID = folder.id
    session = EditorSession(document: doc)
    XCTAssertThrowsError(try session.execute(.paste(clip, .centered, nil)))
    XCTAssertEqual(session.document, doc)
  }
}
