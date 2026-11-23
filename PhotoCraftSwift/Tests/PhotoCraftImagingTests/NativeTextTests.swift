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
  func testTypeBlockLengthKeepsFollowingProtectionAndRepairsLegacyFilesOnSave() throws {
    let typeSignature = Data("8BIMTySh".utf8)
    let protectionSignature = Data("8BIMlspf".utf8)
    for depth in PixelDepth.allCases {
      var source = try CraftDocument(width: 128, height: 72, depth: depth)
      var label = Layer(name: "Editable label", content: .text(TextContent(
        text: "Retouched Label", fontName: "Menlo-Regular", size: 15, color: .white)))
      label.protection = .position
      label.mask = try Surface(width: source.width, height: source.height, depth: depth, fill: .white)
      label.mask?.setPixel(x: 13, y: 8, Pixel(0.4, 0.4, 0.4))
      source.layers.append(label)
      source.activeLayerID = label.id
      for format in [PSDFileFormat.psd, .psb] {
        let data = try PSDCodec.writeRasterLayers(source, format: format)
        let start = try XCTUnwrap(data.range(of: typeSignature)).upperBound
        let length = data[start..<(start + 4)].reduce(0) { ($0 << 8) | Int($1) }
        let payload = start + 4, end = payload + length
        XCTAssertTrue(length.isMultiple(of: 2))
        XCTAssertEqual(data[end..<(end + protectionSignature.count)], protectionSignature)
        // The legacy writer placed the same zero outside the declared payload.
        // Verifying the shortened payload also ensures this fixture exercises padding.
        XCTAssertEqual(data[end - 1], 0)
        XCTAssertNoThrow(try PSDText.descriptor(data.subdata(in: payload..<(end - 1))))
        var legacy = data
        var header = PSDWriter(); header.n(length - 1, 4)
        legacy.replaceSubrange(start..<payload, with: header.data)
        let expected = try PSDCodec.read(data)
        let reopened = try PSDCodec.read(legacy)
        let restored = try XCTUnwrap(reopened.layers.last)
        XCTAssertEqual(restored.typeContent?.text, label.typeContent?.text)
        XCTAssertEqual(restored.mask, expected.layers.last?.mask)
        XCTAssertEqual(restored.protection, .position)
        let before = try Renderer.composite(expected).rgbaData(depth: depth)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: depth), before)
        let resaved = try PSDCodec.writeRasterLayers(reopened, format: format)
        let resavedStart = try XCTUnwrap(resaved.range(of: typeSignature)).upperBound
        let resavedLength = resaved[resavedStart..<(resavedStart + 4)].reduce(0) { ($0 << 8) | Int($1) }
        XCTAssertTrue(resavedLength.isMultiple(of: 2))
        XCTAssertEqual(try PSDCodec.read(resaved).layers.last?.protection, .position)
      }
    }
  }
  func testWholePixelAffineTypePreservesLinear32CompositeThroughPSDAndPSB() throws {
    var source = try CraftDocument(width: 128, height: 72, depth: .f32)
    source.layers[0].content = .raster(try Surface(width: source.width, height: source.height,
      depth: source.depth, fill: Pixel(0.25, 0.42, 0.56)))
    let content = TextContent(text: "Studio Test", fontName: "Menlo-Regular", size: 15, color: .white)
      .promoted(dpi: source.pixelsPerInch)
    var label = Layer(name: "Label", content: .text(content))
    label.x = 18; label.y = 15
    label.mask = try Surface(width: source.width, height: source.height, depth: source.depth, fill: .white)
    label.mask?.setPixel(x: 20, y: 6, Pixel(0.4, 0.4, 0.4))
    source.layers.append(label); source.activeLayerID = label.id
    let expected = try Renderer.composite(source).rgbaData(depth: .f32)
    var placed = source
    placed.layers[1].x = 7; placed.layers[1].y = 12
    placed.layers[1].affine = .translation(11, 3)
    XCTAssertEqual(try Renderer.composite(placed).rgbaData(depth: .f32), expected)
    for format in [PSDFileFormat.psd, .psb] {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(placed, format: format))
      XCTAssertEqual(reopened.layers.last?.coordinateTransform, label.coordinateTransform)
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .f32), expected)
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
