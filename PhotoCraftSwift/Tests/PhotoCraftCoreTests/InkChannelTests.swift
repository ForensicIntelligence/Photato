import Foundation
import XCTest
@testable import PhotoCraftCore

final class InkChannelTests: XCTestCase {
  func plane(_ depth: PixelDepth = .u8) throws -> InkPlane {
    let values: [UInt16] = depth == .u8 ? [0,64,128,255,1,100,200,254] : [0,1,257,65535,32768,1000,50000,65534]
    let bytes = depth == .u8 ? Data(values.map { UInt8($0) }) : Data(values.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
    return try .init(width: 4, height: 2, depth: depth, bytes: bytes)
  }
  func source(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    let samples = try plane(depth)
    let raster = try MultichannelRaster(plates: [
      .init(name: "Cyan", color: Pixel(0, 1, 1), samples: samples),
      .init(name: "Magenta", color: Pixel(1, 0, 1), samples: samples),
      .init(name: "Black", color: .black, solidity: 0.4, samples: samples)])
    return try CraftDocument(width: 4, height: 2, depth: depth).replacingInkMode(.multichannel(raster))
  }
  func duo() throws -> CraftDocument {
    let settings = DuotoneSettings(inks: [.init(name: "Black", color: .black), .init(name: "Red", color: Pixel(1, 0, 0))])
    return try CraftDocument(width: 4, height: 2).replacingInkMode(.duotone(.init(gray: plane(), settings: settings)))
  }
  func testRawWriteKeepsOtherPlanesAndNativeHistoryExact() throws {
    for depth in [PixelDepth.u8, .u16] {
      let original = try source(depth), before = try original.multichannelRaster(), target = InkChannelTarget.plate(before.plates[0].id)
      var session = EditorSession(document: original)
      try session.execute(.inkChannel(.write(target, 1, [0, 0.5])))
      let result = session.document, after = try result.multichannelRaster()
      XCTAssertEqual(after.plates[0].samples.value(at: 1), 0); XCTAssertEqual(after.plates[0].samples.value(at: 2), depth == .u8 ? 128.0/255 : 32768.0/65535)
      XCTAssertTrue(Array(after.plates.dropFirst()) == Array(before.plates.dropFirst()))
      XCTAssertEqual(after.plates[0].samples.bytes.suffix(depth == .u8 ? 5 : 10), before.plates[0].samples.bytes.suffix(depth == .u8 ? 5 : 10))
      let reopened = try NativeArchive.decode(NativeArchive.encodeChunked(result)); XCTAssertTrue(reopened == result)
      try session.undo(); XCTAssertTrue(session.document == original); try session.redo(); XCTAssertTrue(session.document == result)
    }
  }
  func testMultiTargetSelectedFillAndInvertUseNumericDensity() throws {
    for depth in [PixelDepth.u8, .u16] {
      var d = try source(depth)
      d.setCoverageSelection(try SelectionMask(width: 4, height: 2, bytes: [0,255,128,0,0,0,0,0]))
      let before = try d.multichannelRaster(), ids = [before.plates[0].id, before.plates[2].id]
      try Command.inkChannel(.edit(ids.map { .plate($0) }, .fill(0, 1))).apply(to: &d)
      let filled = try d.multichannelRaster()
      for index in [0,2] {
        XCTAssertEqual(filled.plates[index].samples.value(at: 1), 1)
        XCTAssertEqual(filled.plates[index].samples.value(at: 2), depth == .u8 ? 192.0/255 : 33024.0/65535)
        XCTAssertEqual(filled.plates[index].samples.bytes.suffix(depth == .u8 ? 5 : 10), before.plates[index].samples.bytes.suffix(depth == .u8 ? 5 : 10))
      }
      XCTAssertEqual(filled.plates[1], before.plates[1])
      d.setCoverageSelection(nil); try Command.inkChannel(.edit([.plate(ids[0])], .invert)).apply(to: &d)
      XCTAssertEqual(try d.inkChannel(.plate(ids[0])).value(at: 1), 0)
      XCTAssertEqual(try d.multichannelRaster().plates[1], before.plates[1])
    }
  }
  func testDuotoneEditingKeepsCurvesAndGrayCacheAndRespectsLock() throws {
    var d = try duo(); let original = d
    d.selection = .init(x: 1, y: 0, width: 1, height: 1)
    try Command.inkChannel(.edit([.duotone], .fill(0, 1))).apply(to: &d)
    guard case .duotone(let before) = original.inkMode, case .duotone(let after) = d.inkMode, case .raster(let cache) = d.layers[0].content else { return XCTFail() }
    XCTAssertEqual(try after.gray.bytes, Data([0,0,128,255,1,100,200,254])); XCTAssertEqual(after.settings, before.settings)
    XCTAssertTrue(cache == (try after.gray.surface()))
    d.layers[0].locked = true; let locked = d
    XCTAssertThrowsError(try Command.inkChannel(.write(.duotone, 0, [1])).apply(to: &d)); XCTAssertTrue(d == locked)
    XCTAssertThrowsError(try Command.inkChannel(.edit([.duotone], .invert)).apply(to: &d)); XCTAssertTrue(d == locked)
  }
  func testPlateMetadataOrderDuplicateAndDeleteAreAtomic() throws {
    let original = try source(.u16), before = try original.multichannelRaster(); var session = EditorSession(document: original)
    let id = before.plates[1].id, copyID = UUID()
    try session.execute(.inkChannel(.options(id, "Spot Magenta", Pixel(0.8, 0.2, 0.4), 0.75)))
    XCTAssertEqual(try session.document.inkChannel(.plate(id)), before.plates[1].samples)
    try session.execute(.inkChannel(.duplicate(id, copyID, nil)))
    XCTAssertEqual(try session.document.inkChannel(.plate(copyID)), before.plates[1].samples)
    try session.execute(.inkChannel(.move(copyID, 0))); XCTAssertEqual(try session.document.multichannelRaster().plates.first?.id, copyID)
    try session.execute(.inkChannel(.delete(id))); XCTAssertEqual(try session.document.multichannelRaster().plates.count, 3)
    for _ in 0..<4 { try session.undo() }; XCTAssertTrue(session.document == original)
    for bad: InkChannelCommand in [.duplicate(id, id, "Duplicate ID"), .move(id, -1), .delete(UUID()), .options(id, "", .black, 0), .options(id, "Bad", .black, 2)] {
      var value = original; XCTAssertThrowsError(try bad.apply(to: &value)); XCTAssertTrue(value == original)
    }
    var one = try original.replacingInkMode(.multichannel(.init(plates: [before.plates[0]]))); let saved = one
    XCTAssertThrowsError(try InkChannelCommand.delete(before.plates[0].id).apply(to: &one)); XCTAssertTrue(one == saved)
  }
  func testCreationRejectsGeometryChannelLimitAndAuxiliaryIdentityCollisions() throws {
    var d = try source(); let channel = try AlphaChannel(name: "Alpha", pixels: Surface(width: 4, height: 2))
    d.alphaChannels = [channel]; let original = d
    let bad = InkPlate(id: channel.id, name: "Conflict", color: .black, samples: try plane())
    XCTAssertThrowsError(try Command.inkChannel(.create(bad)).apply(to: &d)); XCTAssertTrue(d == original)
    let small = InkPlate(name: "Small", color: .black, samples: try .init(width: 1, height: 1))
    XCTAssertThrowsError(try Command.inkChannel(.create(small)).apply(to: &d)); XCTAssertTrue(d == original)
    let good = InkPlate(name: "Spot", color: Pixel(0.8, 0.2, 0.6), samples: try .init(width: 4, height: 2, value: 0))
    try Command.inkChannel(.create(good)).apply(to: &d); XCTAssertEqual(d.alphaChannels, original.alphaChannels)
    var plates = try d.multichannelRaster().plates
    while plates.count < 55 { plates.append(.init(name: "Ink \(plates.count)", color: .black, samples: try plane())) }
    d.inkMode = .multichannel(try .init(plates: plates)); try d.validate(); let full = d
    XCTAssertThrowsError(try Command.inkChannel(.create(.init(name: "Extra", color: .black, samples: plane()))).apply(to: &d)); XCTAssertTrue(d == full)
  }
  func testStrokeFiltersAndSelectionOperateOnViewGrayAndLeaveOtherPlates() throws {
    for depth in [PixelDepth.u8, .u16] {
      var d = try source(depth); let before = try d.multichannelRaster(), target = InkChannelTarget.plate(before.plates[0].id)
      var brush = Brush(); brush.color = .black; brush.size = 1; brush.hardness = 1; brush.opacity = 1
      try Command.inkChannel(.edit([target], .stroke([.init(x: 0.5, y: 0.5)], brush))).apply(to: &d)
      XCTAssertEqual(try d.inkChannel(target).value(at: 0), 1); XCTAssertTrue(Array(try d.multichannelRaster().plates.dropFirst()) == Array(before.plates.dropFirst()))
      try Command.inkChannel(.loadSelection(target, .replace, false)).apply(to: &d)
      XCTAssertEqual(try d.selectionMask?.bytes[0], 0); XCTAssertEqual(try d.selectionMask?.bytes[3], 0)
      let others = Array(try d.multichannelRaster().plates.dropFirst())
      try Command.inkChannel(.edit([target], .filter(.init(.average)))).apply(to: &d)
      XCTAssertTrue(Array(try d.multichannelRaster().plates.dropFirst()) == others)
      let saved = d
      XCTAssertThrowsError(try Command.inkChannel(.edit([target], .filter(.init(.lensBlur)))).apply(to: &d)); XCTAssertTrue(d == saved)
    }
  }
  func testInvalidTargetsAndSamplesNeverPartiallyEdit() throws {
    let original = try source(), target = try XCTUnwrap(original.inkChannelTargets.first)
    for bad: InkChannelCommand in [.edit([target, .plate(UUID())], .fill(0, 1)), .edit([target, target], .invert), .edit([], .invert), .write(target, 8, [0]), .write(target, -1, [0]), .write(target, 0, [.nan]), .edit([target], .fill(0, .infinity))] {
      var d = original; XCTAssertThrowsError(try bad.apply(to: &d)); XCTAssertTrue(d == original)
    }
    XCTAssertThrowsError(try plane(.u16).mapped { _, _, _ in .nan })
    let exact = try plane(.u16); XCTAssertEqual(try exact.mapped { _, _, value in value }.bytes, try exact.bytes)
  }
}
