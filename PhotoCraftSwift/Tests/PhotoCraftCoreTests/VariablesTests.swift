import Foundation
import XCTest
@testable import PhotoCraftCore

final class VariablesTests: XCTestCase {
  func template(depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 16, height: 12, depth: depth)
    d.layers = [Layer(name: "Photo", content: .raster(try Surface(width: 8, height: 8, depth: depth, fill: .white))),
                Layer(name: "Title", content: .text(.init(text: "Original"))),
                Layer(name: "Caption", content: .text(.init(text: "Original")))]
    d.layers[0].x = 3; d.layers[0].y = 2; d.activeLayerID = d.layers[0].id
    let definitions: [VariableDefinition] = [
      .init(name: "photo", layerID: d.layers[0].id, kind: .pixelReplacement),
      .init(name: "show", layerID: d.layers[0].id, kind: .visibility),
      .init(name: "title", layerID: d.layers[1].id, kind: .textReplacement),
      .init(name: "title", layerID: d.layers[2].id, kind: .textReplacement)]
    try Command.variables(.define(definitions)).apply(to: &d)
    return d
  }
  func testLinkedVariablesAtomicHistoryRenameAndNative61() throws {
    var session = EditorSession(document: try template())
    let image = VariableImage(name: "Red", pixels: try Surface(width: 4, height: 2, fill: Pixel(1, 0, 0)))
    try session.execute(.variables(.image(image)))
    let row = VariableDataSet(name: "Red greeting", values: ["title": .text("Hello 🥔"), "show": .visibility(false), "photo": .pixels(image.id)])
    try session.execute(.variables(.dataSets([row], append: false)))
    let original = session.document
    try session.execute(.variables(.apply(row.id)))
    let applied = session.document
    XCTAssertFalse(applied.layers[0].visible)
    for layer in applied.layers.suffix(2) {
      guard case .text(let t) = layer.content else { return XCTFail("Lost editable type") }
      XCTAssertEqual(t.text, "Hello 🥔")
    }
    XCTAssertEqual(applied.variables?.activeDataSetID, row.id)
    try session.undo(); XCTAssertEqual(session.document, original)
    try session.redo(); XCTAssertEqual(session.document, applied)
    try session.execute(.variables(.rename("title", "greeting")))
    XCTAssertEqual(session.document.variables?.definitions.filter { $0.name == "greeting" }.count, 2)
    XCTAssertEqual(session.document.variables?.dataSets[0].values["greeting"], .text("Hello 🥔"))
    XCTAssertNil(session.document.variables?.dataSets[0].values["title"])
    XCTAssertEqual(session.document.minimumArchiveVersion, 61)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
    let bytes = try NativeArchive.encodeChunked(session.document)
    XCTAssertEqual(bytes[8], 61); XCTAssertEqual(try NativeArchive.decode(bytes), session.document)
    var invalid = bytes; invalid[8] = 60
    XCTAssertThrowsError(try NativeArchive.decode(invalid))
  }
  func testEveryPlacementMethodAlignmentClipAndStableOriginalBox() throws {
    for depth in [PixelDepth.u8, .u16, .f32] {
      for method in VariablePixelMethod.allCases {
        for align in CanvasAnchor.allCases {
          for clip in [false, true] {
            var d = try template(depth: depth), defs = d.variables!.definitions
            defs[0].pixelOptions!.method = method; defs[0].pixelOptions!.alignment = align; defs[0].pixelOptions!.clipToBounds = clip
            try Command.variables(.define(defs)).apply(to: &d)
            let source = VariableImage(name: "Red", pixels: try Surface(width: 12, height: 4, depth: depth, fill: Pixel(1, 0, 0)))
            try Command.variables(.image(source)).apply(to: &d)
            let row = VariableDataSet(name: "Replacement", values: ["photo": .pixels(source.id)])
            try Command.variables(.dataSets([row], append: false)).apply(to: &d)
            let frame = d.variables!.definitions[0].pixelFrame!
            try Command.variables(.apply(row.id)).apply(to: &d)
            guard case .raster(let result) = d.layers[0].content else { return XCTFail("Lost pixels") }
            let expectedW: Int, expectedH: Int
            switch method {
            case .fit: expectedW = 8; expectedH = 3
            case .fill: expectedW = clip ? 8 : 24; expectedH = 8
            case .asIs: expectedW = clip ? 8 : 12; expectedH = 4
            case .conform: expectedW = 8; expectedH = 8
            }
            XCTAssertEqual(result.width, expectedW); XCTAssertEqual(result.height, expectedH)
            XCTAssertEqual(result.pixel(x: expectedW / 2, y: expectedH / 2), Pixel(1, 0, 0))
            XCTAssertEqual(d.variables!.definitions[0].pixelFrame, frame)
            let first = d.layers[0]
            try Command.variables(.apply(row.id)).apply(to: &d)
            XCTAssertEqual(d.layers[0], first, "Repeated \(method)/\(align)/\(clip) drifts")
          }
        }
      }
    }
  }
  func testDoNotReplaceMissingValuesAndLateLockedTargetAreAtomic() throws {
    var d = try template()
    let row = VariableDataSet(name: "Text only", values: ["title": .text("Changed"), "photo": .pixels(nil)])
    try Command.variables(.dataSets([row], append: false)).apply(to: &d)
    d.layers[2].locked = true; let before = d
    XCTAssertThrowsError(try Command.variables(.apply(row.id)).apply(to: &d)); XCTAssertEqual(d, before)
    d.layers[2].locked = false; let image = d.layers[0]
    try Command.variables(.apply(row.id)).apply(to: &d)
    XCTAssertEqual(d.layers[0], image)
  }
  func testDefinitionsValuesAssetsAndNamesRejectWithoutMutation() throws {
    var d = try template(); let before = d
    for name in ["", "9bad", "with space", "a/b", String(repeating: "x", count: 129)] {
      var defs = d.variables!.definitions; defs[0].name = name
      XCTAssertThrowsError(try Command.variables(.define(defs)).apply(to: &d)); XCTAssertEqual(d, before)
    }
    var defs = d.variables!.definitions; defs[0].name = "title"
    XCTAssertThrowsError(try Command.variables(.define(defs)).apply(to: &d))
    defs = d.variables!.definitions; defs.append(defs[0])
    XCTAssertThrowsError(try Command.variables(.define(defs)).apply(to: &d))
    for value in [VariableValue.visibility(true), .pixels(UUID())] {
      XCTAssertThrowsError(try Command.variables(.dataSets([.init(name: "Invalid", values: ["title": value])], append: false)).apply(to: &d))
    }
    XCTAssertThrowsError(try Command.variables(.dataSets([.init(name: "Missing", values: ["photo": .pixels(UUID())])], append: false)).apply(to: &d))
    XCTAssertEqual(d, before)
    XCTAssertTrue(VariableDefinition.validName("_Étiquette:1.2-test"))
  }
  func testLayerDeletionPrunesOnlyUnusedBindingsAndUndoRestoresThem() throws {
    var session = EditorSession(document: try template())
    try session.execute(.variables(.dataSets([.init(name: "Row", values: ["title": .text("Linked"), "show": .visibility(false)])], append: false)))
    let before = session.document, first = before.layers[1].id, second = before.layers[2].id
    try session.execute(.deleteLayer(first))
    XCTAssertEqual(session.document.variables?.definitions.filter { $0.name == "title" }.count, 1)
    XCTAssertNotNil(session.document.variables?.dataSets[0].values["title"])
    try session.execute(.deleteLayer(second))
    XCTAssertNil(session.document.variables?.dataSets[0].values["title"])
    XCTAssertNotNil(session.document.variables?.dataSets[0].values["show"])
    try session.undo(); try session.undo(); XCTAssertEqual(session.document, before)
  }
  func testTemplateFrameFollowsMovementAndCanvasResize() throws {
    var d = try template(); let id = d.layers[0].id
    try Command.move(id, 10, 11).apply(to: &d)
    XCTAssertEqual(d.variables!.definitions[0].pixelFrame!.transform.tx, 10)
    XCTAssertEqual(d.variables!.definitions[0].pixelFrame!.transform.ty, 11)
    let before = d.variables!.definitions[0].pixelFrame!
    try Command.imageSize(32, 24, 72, .nearest).apply(to: &d)
    XCTAssertEqual(d.variables!.definitions[0].pixelFrame!.transform, .scale(2, 2) * before.transform)
  }
  func testReplacementPreservesMaskDocumentCoordinatesAndTextStyle() throws {
    var d = try template()
    d.layers[0].mask = try Surface(width: 8, height: 8, fill: .white)
    let maskTransform = d.layers[0].maskCoordinateTransform
    var type = TextTypography(), style = TypeStyle(); style.size = 42
    type.runs = [.init(length: 8, style: style)]
    if case .text(var t) = d.layers[1].content { t.typography = type; d.layers[1].content = .text(t) }
    let asset = VariableImage(name: "Wide", pixels: try Surface(width: 8, height: 2, fill: .white))
    try Command.variables(.image(asset)).apply(to: &d)
    let row = VariableDataSet(name: "Styled", values: ["photo": .pixels(asset.id), "title": .text("Much longer 👩🏽‍🎨 text")])
    try Command.variables(.dataSets([row], append: false)).apply(to: &d)
    try Command.variables(.apply(row.id)).apply(to: &d)
    XCTAssertEqual(d.layers[0].maskCoordinateTransform, maskTransform)
    guard case .text(let text) = d.layers[1].content else { return XCTFail() }
    XCTAssertEqual(text.typography?.defaultStyle.size, 42); XCTAssertEqual(text.typography?.runs, [])
    try d.validate()
  }
}
