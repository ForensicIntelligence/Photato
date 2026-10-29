import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class SmartObjectTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 12, height: 10, depth: depth)
    var s = try Surface(width: 6, height: 4, depth: depth)
    for y in 0..<4 { for x in 0..<6 { s.setPixel(x: x, y: y, Pixel(Float(x)/5, Float(y)/3, 0.6)) } }
    d.layers[0].content = .raster(s); d.layers[0].x = 2; d.layers[0].y = 3
    return d
  }
  func converted(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    let d = try fixture(depth)
    var session = EditorSession(document: d)
    try session.execute(SmartObjectIO.convert(in: d, selected: [d.layers[0].id]))
    return session.document
  }
  func testConversionPixelsArchivesSourceEditingAndHistoryAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      let original = try fixture(depth)
      var session = EditorSession(document: original)
      try session.execute(SmartObjectIO.convert(in: original, selected: [original.layers[0].id]))
      let result = session.document, layer = result.layers[0]
      XCTAssertNotNil(layer.smartObject)
      XCTAssertEqual(try Renderer.composite(result).rgbaData(depth: depth), try Renderer.composite(original).rgbaData(depth: depth))
      let source = try SmartObjectIO.sourceDocument(XCTUnwrap(layer.smartObject))
      XCTAssertEqual(source.layers.count, 1); XCTAssertEqual(source.width, 6); XCTAssertEqual(source.height, 4)
      for bytes in [try NativeArchive.encode(result), try NativeArchive.encodeChunked(result)] {
        XCTAssertEqual(try NativeArchive.decode(bytes), result)
      }
      XCTAssertEqual(result.minimumArchiveVersion, 14)
      try session.undo(); XCTAssertEqual(session.document, original)
      try session.redo(); XCTAssertEqual(session.document, result)
    }
  }
  func testResizingRetainsOriginalSamplesAndRasterizationIsUndoable() throws {
    let d = try converted(), original = d.layers[0], id = original.id
    var session = EditorSession(document: d)
    try session.execute(.transform(id, .scale(0.1, 0.1), .bicubic))
    try session.execute(.transform(id, .scale(10, 10), .bicubic))
    XCTAssertEqual(session.document.layers[0].content, original.content)
    XCTAssertEqual(session.document.layers[0].smartObject, original.smartObject)
    XCTAssertEqual(try Renderer.composite(session.document).rgbaData(depth: .u8), try Renderer.composite(d).rgbaData(depth: .u8))
    XCTAssertThrowsError(try session.execute(.fill(id, .white)))
    let before = session.document
    try session.execute(.rasterize(id, Renderer.layerSurface(before.layers[0], in: before)))
    XCTAssertNil(session.document.layers[0].smartObject)
    try session.execute(.fill(id, .white))
    try session.undo(); try session.undo(); XCTAssertEqual(session.document, before)
  }
  func testSharedReplacementIndependentCopyMasksAndLockedAtomicity() throws {
    var d = try converted(); let id = d.layers[0].id
    d.layers[0].mask = try Surface(width: 6, height: 4, fill: .white)
    var session = EditorSession(document: d)
    try session.execute(.duplicateLayer(id)); let shared = session.document.activeLayerID!
    try session.execute(.independentSmartObjectCopy(id)); let independent = session.document.activeLayerID!
    let before = session.document, oldMask = before.layers[0].maskCoordinateTransform
    var replacement = try CraftDocument(width: 3, height: 8)
    replacement.layers[0].content = .raster(try Surface(width: 3, height: 8, fill: Pixel(1, 0, 0)))
    try session.execute(SmartObjectIO.replacement(in: before, layerID: id, source: replacement))
    for target in [id, shared] {
      let l = session.document.layers.first { $0.id == target }!
      XCTAssertEqual(l.smartObject?.width, 3)
      XCTAssertEqual(l.maskCoordinateTransform, oldMask)
      XCTAssertEqual(try l.coordinateTransform.bounds(width: 3, height: 8), try d.layers[0].coordinateTransform.bounds(width: 6, height: 4))
    }
    XCTAssertEqual(session.document.layers.first { $0.id == independent }?.smartObject?.width, 6)
    try session.undo(); XCTAssertEqual(session.document, before)
    try session.execute(.lock(shared, true)); let locked = session.document
    XCTAssertThrowsError(try session.execute(SmartObjectIO.replacement(in: locked, layerID: id, source: replacement)))
    XCTAssertEqual(session.document, locked)
  }
  func testPSDPSBSourceAndAffineRoundTripsAtAllDepths() throws {
    for depth in PixelDepth.allCases { for format in PSDFileFormat.allCases {
      var d = try converted(depth)
      try Command.transform(d.layers[0].id, .translation(1, 2) * .scale(1.5, 1.5), .bicubic).apply(to: &d)
      let bytes = try PSDCodec.writeRasterLayers(d, format: format)
      let read = try PSDCodec.read(bytes)
      XCTAssertNotNil(read.layers[0].smartObject)
      XCTAssertEqual(read.layers[0].coordinateTransform, d.layers[0].coordinateTransform)
      XCTAssertEqual(read.layers[0].smartObject?.width, 6)
      XCTAssertEqual(try Renderer.composite(read).rgbaData(depth: depth), try Renderer.composite(d).rgbaData(depth: depth))
      let nested = try SmartObjectIO.sourceDocument(XCTUnwrap(read.layers[0].smartObject))
      XCTAssertEqual(nested.layers.count, 1)
    } }
  }
  func testOriginalPNGBytesAndInvalidSourcesArePreservedOrRejected() throws {
    let original = try fixture(), data = try RasterIO.encoded(original)
    let layer = try SmartObjectIO.placed(data: data, fileName: "source.png", in: original)
    XCTAssertEqual(layer.smartObject?.data, data); XCTAssertEqual(layer.smartObject?.mediaType, "image/png")
    XCTAssertThrowsError(try SmartObjectIO.placed(data: Data([1,2,3]), fileName: "bad.png", in: original))
    XCTAssertThrowsError(try SmartObject(fileName: "../source.png", mediaType: "image/png", data: data, width: 1, height: 1))
    var d = try converted(); var duplicate = d.layers[0]; duplicate.id = UUID(); duplicate.smartObject?.data.append(0); d.layers.append(duplicate)
    XCTAssertThrowsError(try d.validate())
    var tag = try PSDSmartObjects.placedDescriptor(d.layers[0]); tag[0] = 0
    XCTAssertThrowsError(try PSDSmartObjects.descriptor(tag))
  }
  func testSourceBlobsSurviveScratchHistoryAndImageProtection() throws {
    let d = try converted()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let scratch = try HistoryScratchStore(parent: directory, limit: 16 * 1_024 * 1_024)
    let snapshot = try HistorySnapshot(d, store: scratch)
    XCTAssertEqual(try snapshot.restore(), d)
    var session = EditorSession(document: d)
    try session.execute(.protection([d.layers[0].id: .image]))
    let before = session.document
    XCTAssertThrowsError(try session.execute(SmartObjectIO.replacement(in: before, layerID: d.layers[0].id, source: fixture())))
    XCTAssertEqual(session.document, before)
    let bytes = try NativeArchive.encodeChunked(d)
    XCTAssertThrowsError(try NativeArchive.decode(bytes, rasterByteLimit: 1))
  }
  func testConvertRetainsOuterBlendOpacityAndMultiLayerEditability() throws {
    var d = try fixture(); d.layers[0].blendMode = .multiply; d.layers[0].opacity = 0.5
    let id = d.layers[0].id
    try Command.addLayer(Layer(name: "Base", content: .raster(try Surface(width: 12, height: 10, fill: Pixel(0.7,0.7,0.7))))).apply(to: &d)
    d.layers.swapAt(0,1)
    let before = try Renderer.composite(d)
    try SmartObjectIO.convert(in: d, selected: [id]).apply(to: &d)
    XCTAssertEqual(try Renderer.composite(d).rgbaData(depth: .u8), try before.rgbaData(depth: .u8))
    try SmartObjectIO.convert(in: d, selected: Set(d.layers.map(\.id))).apply(to: &d)
    XCTAssertEqual(try SmartObjectIO.sourceDocument(XCTUnwrap(d.layers[0].smartObject)).layers.count, 2)
  }
}
