import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class NativeTextTests: XCTestCase {
  func sample(_ string: String = "Hello world\nNative text") -> TextContent {
    var text = TextContent(text: string)
    var type = TextTypography(); type.defaultStyle.size = 24
    text.typography = type; return text
  }
  func testUnicodeRangesAndArchive16() throws {
    var text = sample("A😀B")
    text.typography?.runs = [.init(length: 2, style: .init()), .init(length: 2, style: .init())]
    XCTAssertThrowsError(try text.validate())
    text.typography?.runs = [.init(length: 1, style: .init()), .init(length: 2, style: .init()), .init(length: 1, style: .init())]
    try text.validate()
    var doc = try CraftDocument(width: 300, height: 120)
    doc.layers = [Layer(name: "Type", content: .text(text))]; doc.activeLayerID = doc.layers[0].id
    XCTAssertEqual(doc.minimumArchiveVersion, 16)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(doc)), doc)
    let chunks = try NativeArchive.encodeChunked(doc)
    XCTAssertEqual(try NativeArchive.decode(chunks), doc)
  }
  func testTextKitRichRoundTripAndAllDepthRendering() throws {
    var text = sample("Red and black")
    var red = TypeStyle(); red.size = 24; red.color = Pixel(1, 0, 0, 1); red.underline = true
    var black = red; black.color = .black; black.underline = false
    text.typography?.runs = [.init(length: 3, style: red), .init(length: 10, style: black)]
    let attributed = try NativeTextLayout.attributed(text, dpi: 144)
    let restored = try NativeTextLayout.content(attributed, template: text, dpi: 144)
    XCTAssertEqual(restored.typography?.runs, text.typography?.runs)
    for depth in [PixelDepth.u8, .u16, .f32] {
      var doc = try CraftDocument(width: 512, height: 160, depth: depth)
      doc.layers = [Layer(name: "Type", content: .text(text))]; doc.activeLayerID = doc.layers[0].id
      let rendered = try Renderer.layerSurface(doc.layers[0], in: doc)
      var redPixels = 0, blackPixels = 0
      for y in 0..<rendered.height { for x in 0..<rendered.width {
        let p = rendered.pixel(x: x, y: y)
        if p.a > 0.5 { if p.r > 0.7 { redPixels += 1 } else { blackPixels += 1 } }
      }}
      XCTAssertGreaterThan(redPixels, 20); XCTAssertGreaterThan(blackPixels, 20)
      XCTAssertEqual(rendered.depth, depth)
    }
  }
  func testPointDoesNotWrapAndParagraphReportsOverflow() throws {
    var text = sample("One two three four five six seven eight")
    let point = try NativeTextLayout.metrics(text, dpi: 72)
    text.typography?.kind = .paragraph; text.layoutWidth = 90; text.layoutHeight = 600
    let box = try NativeTextLayout.metrics(text, dpi: 72)
    XCTAssertGreaterThan(point.width, box.width); XCTAssertFalse(box.overset)
    text.layoutHeight = 10
    XCTAssertTrue(try NativeTextLayout.metrics(text, dpi: 72).overset)
  }
  func testPSDAndPSBPreserveEditableTypeAndTransform() throws {
    for kind in [TextTypography.Kind.point, .paragraph] {
      var text = sample("Hi 😀\nAgain")
      text.typography?.kind = kind
      if kind == .paragraph { text.layoutWidth = 180; text.layoutHeight = 100 }
      var doc = try CraftDocument(width: 300, height: 200)
      var layer = Layer(name: "Type", content: .text(text)); layer.affine = .translation(18, 27) * .scale(1.1, 0.9)
      doc.layers = [layer]; doc.activeLayerID = layer.id
      for format in [PSDFileFormat.psd, .psb] {
        let loaded = try PSDCodec.read(PSDCodec.writeRasterLayers(doc, format: format))
        guard case .text(let result) = loaded.layers[0].content else { return XCTFail("Text flattened") }
        XCTAssertEqual(result.text, text.text); XCTAssertEqual(result.typography?.kind, kind)
        XCTAssertEqual(loaded.layers[0].coordinateTransform.tx, layer.coordinateTransform.tx, accuracy: 0.00001)
        XCTAssertEqual(loaded.layers[0].coordinateTransform.ty, layer.coordinateTransform.ty, accuracy: 0.00001)
      }
    }
  }
  func testEngineDataEscapesAndMalformedInput() throws {
    let text = "A(\\)😀\nZ"
    let value = PSDTextValue.dictionary(["Text": .string(text)])
    XCTAssertEqual(try PSDTextValue.parse(value.encoded())["Text"]?.string, text)
    for bad in ["<< /A 1 /A 2 >>", "[1 2", "(unclosed", "<< /A nan >>"] {
      XCTAssertThrowsError(try PSDTextValue.parse(Data(bad.utf8)))
    }
  }
  func testCharacterScaleAndResolutionChangeActualLayout() throws {
    var text = sample("MMMMMM")
    let base = try NativeTextLayout.metrics(text, dpi: 72)
    let retina = try NativeTextLayout.metrics(text, dpi: 144)
    XCTAssertGreaterThan(retina.width, base.width * 18 / 10)
    text.typography?.defaultStyle.horizontalScale = 2
    let wide = try NativeTextLayout.metrics(text, dpi: 72)
    XCTAssertGreaterThan(wide.width, base.width * 18 / 10)
    let restored = try NativeTextLayout.content(NativeTextLayout.attributed(text, dpi: 72), template: text, dpi: 72)
    XCTAssertEqual(restored.typography?.defaultStyle.horizontalScale, 2)
    XCTAssertEqual(restored.typography?.defaultStyle.size, 24)
  }
  func testMissingFontAndResourceLimitsReject() throws {
    var text = sample()
    text.typography?.defaultStyle.font = "PhotatoMissingFont_162"
    XCTAssertThrowsError(try NativeTextLayout.metrics(text, dpi: 72))
    text = sample(); text.typography?.kind = .paragraph; text.layoutWidth = 32768; text.layoutHeight = 32768
    XCTAssertThrowsError(try NativeTextLayout.metrics(text, dpi: 72))
  }
}
