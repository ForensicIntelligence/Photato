import Foundation
import XCTest
@testable import PhotoCraftCore

final class RestrictedClipboardTests: XCTestCase {
  func samples(_ values: [UInt8] = [0, 1, 2, 1], transparent: Int? = nil) throws -> RestrictedModeRaster {
    .indexed(try IndexedRaster(width: 4, height: 1, palette: [.init(0, 0, 0), .init(0, 0, 0), .init(255, 255, 255)], indices: Data(values), transparentIndex: transparent))
  }
  func clip(_ raster: RestrictedModeRaster) throws -> ClipboardContent {
    try .pixels(raster.surface(), workingICC: raster.profile, restrictedSamples: raster)
  }
  func document(_ raster: RestrictedModeRaster) throws -> CraftDocument {
    try CraftDocument(width: raster.width, height: raster.height).replacingRestrictedMode(raster)
  }
  func testEnvelope2RetainsIdentityAndRejectsDowngradeAndMismatchedSamples() throws {
    let raster = try samples(), content = try clip(raster), bytes = try content.encoded()
    XCTAssertEqual(try ClipboardContent.decode(bytes), content)
    var fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
    XCTAssertEqual(fields["version"] as? Int, 2); fields["version"] = 1
    XCTAssertThrowsError(try ClipboardContent.decode(PropertyListSerialization.data(fromPropertyList: fields, format: .binary, options: 0)))
    var bad = content; bad.document.layers[0].content = .raster(try Surface(width: 4, height: 1, fill: Pixel(1, 0, 0)))
    XCTAssertThrowsError(try bad.validate()); XCTAssertThrowsError(try bad.encoded())
    bad = content; bad.document.layers[0].maskProperties = .init()
    XCTAssertThrowsError(try bad.validate(), "A pixel payload cannot hide layer effects or mask properties that flat paste would discard")
    let ordinary = try ClipboardContent.pixels(Surface(width: 1, height: 1, fill: .white)), old = try ordinary.encoded()
    let oldFields = try XCTUnwrap(PropertyListSerialization.propertyList(from: old, format: nil) as? [String: Any])
    XCTAssertEqual(oldFields["version"] as? Int, 1); XCTAssertEqual(try ClipboardContent.decode(old), ordinary)
  }
  func testOpaquePasteCopiesDuplicateIndexIdentityAndOneUndo() throws {
    let source = try samples([1, 1, 0, 1]), original = try document(samples([0, 0, 0, 0]))
    var session = EditorSession(document: original)
    try session.execute(.paste(clip(source), .inPlace, nil))
    XCTAssertEqual(session.document.restrictedMode, source); XCTAssertEqual(session.document.layers.count, 1)
    XCTAssertEqual(session.document.layers[0].id, original.layers[0].id)
    XCTAssertEqual(session.undoStack.count, 1); try session.undo(); XCTAssertTrue(session.document == original)
    try session.redo(); XCTAssertEqual(session.document.restrictedMode, source)
  }
  func testFractionalCoverageAndIntoOutsideDoNotCopyUnselectedIdentity() throws {
    let source = try clip(samples([1, 1, 1, 1]))
    for placement in [PastePlacement.into, .outside] {
      var original = try document(samples([0, 0, 0, 0]))
      original.setCoverageSelection(try SelectionMask(width: 4, height: 1, bytes: [255, 128, 0, 255]))
      var changed = original; try Command.paste(source, placement, nil).apply(to: &changed)
      guard case .indexed(let raster) = changed.restrictedMode else { return XCTFail() }
      XCTAssertEqual(raster.indices, Data(placement == .into ? [1, 0, 0, 1] : [0, 0, 1, 0]))
      XCTAssertNil(changed.selection); XCTAssertNil(changed.selectionMask)
    }
    var partial = source
    guard case .raster(var pixels) = partial.document.layers[0].content else { return XCTFail() }
    pixels.setPixel(x: 0, y: 0, Pixel(0, 0, 0, 0.5)); partial.document.layers[0].content = .raster(pixels)
    let created = try partial.newDocument(name: "Coverage")
    XCTAssertEqual(created.colorMode, .rgb); XCTAssertNil(created.restrictedMode)
    guard case .raster(let restored) = created.layers[0].content else { return XCTFail() }
    XCTAssertEqual(restored.pixel(x: 0, y: 0).a, Float(128) / 255)
  }
  func testBitmapPastePlacementAndNewDocumentRetainBits() throws {
    let source = RestrictedModeRaster.bitmap(try BitmapRaster(width: 2, height: 2, bits: Data([0x80, 0x40])))
    let content = try clip(source), created = try content.newDocument(name: "Bitmap clipboard")
    XCTAssertEqual(created.colorMode, .bitmap); XCTAssertEqual(created.restrictedMode, source)
    var target = try document(.bitmap(BitmapRaster(width: 4, height: 2, bits: Data([0, 0]))))
    try Command.paste(content, .centered, nil).apply(to: &target)
    guard case .bitmap(let bitmap) = target.restrictedMode else { return XCTFail() }
    XCTAssertEqual(bitmap.bits, Data([0x40, 0x20])); XCTAssertEqual(target.layers.count, 1)
  }
  func testCutClearsFlatPixelsWithTransparencyOrWhiteAndHonorsPixelProtection() throws {
    for raster in [try samples(), try samples(transparent: 2), .bitmap(try BitmapRaster(width: 4, height: 1, bits: Data([0xf0])))] {
      let original = try document(raster); var session = EditorSession(document: original)
      try session.execute(.cut([original.layers[0].id])); XCTAssertEqual(session.document.layers.count, 1)
      if case .indexed(let changed) = session.document.restrictedMode { XCTAssertEqual(changed.indices, Data([2, 2, 2, 2])) }
      if case .bitmap(let changed) = session.document.restrictedMode { XCTAssertEqual(changed.bits, Data([0])) }
      try session.undo(); XCTAssertTrue(session.document == original)
      var locked = original; locked.layers[0].protection = .image; var candidate = locked
      XCTAssertThrowsError(try Command.cut([locked.layers[0].id]).apply(to: &candidate)); XCTAssertTrue(candidate == locked)
      XCTAssertThrowsError(try Command.paste(clip(raster), .inPlace, nil).apply(to: &candidate)); XCTAssertTrue(candidate == locked)
    }
  }
  func testOpaqueCutUsesRequestedBackgroundAndFractionalSelection() throws {
    var original = try document(samples([2, 2, 2, 2]))
    original.setCoverageSelection(try SelectionMask(width: 4, height: 1, bytes: [255, 128, 0, 255]))
    var changed = original; try Command.cut([original.layers[0].id], background: .black).apply(to: &changed)
    guard case .indexed(let raster) = changed.restrictedMode else { return XCTFail() }
    XCTAssertEqual(raster.indices, Data([0, 0, 2, 0])); XCTAssertEqual(changed.selectionMask, original.selectionMask)
    var bitmap = try document(.bitmap(BitmapRaster(width: 4, height: 1, bits: Data([0]))))
    try Command.cut([bitmap.layers[0].id], background: .black).apply(to: &bitmap)
    guard case .bitmap(let bits) = bitmap.restrictedMode else { return XCTFail() }
    XCTAssertEqual(bits.bits, Data([0xf0]))
    var invalid = original
    XCTAssertThrowsError(try Command.cut([original.layers[0].id], background: .clear).apply(to: &invalid)); XCTAssertTrue(invalid == original)
  }
}
