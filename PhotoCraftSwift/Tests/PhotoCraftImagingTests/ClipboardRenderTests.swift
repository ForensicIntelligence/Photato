import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class ClipboardRenderTests: XCTestCase {
  func testSelectedPixelCopyTrimsTransparencyAndMultipliesCoverageLikeSource() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 8, height: 4, depth: depth)
      var pixels = try Surface(width: 4, height: 2, depth: depth)
      pixels.setPixel(x: 1, y: 0, Pixel(0.7, 0.2, 0.9, 0.8))
      pixels.setPixel(x: 2, y: 0, Pixel(0.1, 0.4, 0.8, 1))
      var layer = Layer(name: "Copy", content: .raster(pixels))
      layer.x = 2
      layer.y = 1
      doc.layers = [layer]
      doc.activeLayerID = layer.id
      var bytes = [UInt8](repeating: 0, count: 32)
      bytes[11] = 128
      bytes[12] = 255
      doc.setCoverageSelection(try SelectionMask(width: 8, height: 4, bytes: bytes))
      let clip = try ClipboardRenderer.copy(doc, layerIDs: [layer.id])
      XCTAssertEqual(clip.bounds, IntRect(x: 3, y: 1, width: 2, height: 1))
      XCTAssertEqual(clip.kind, .pixels)
      let surface = try ClipboardRenderer.preview(clip)
      let expected = pixels.pixel(x: 1, y: 0)
      XCTAssertEqual(surface.pixel(x: 0, y: 0).rgb, expected.rgb)
      XCTAssertEqual(surface.pixel(x: 0, y: 0).a, depth.quantize(expected.a * (Float(128) / 255)))
      XCTAssertEqual(surface.pixel(x: 1, y: 0), pixels.pixel(x: 2, y: 0))
    }
  }
  func testCopyMergedIncludesVisibleMasksOpacityAndBlendButIgnoresHiddenLayers() throws {
    var doc = try CraftDocument(width: 3, height: 2)
    var overlay = Layer(name: "Overlay", content: .fill(Pixel(1, 0, 0)))
    overlay.opacity = 0.5
    overlay.mask = try Surface(width: 3, height: 2, fill: Pixel(0.4, 0.4, 0.4))
    var hidden = Layer(name: "Hidden", content: .fill(.black))
    hidden.visible = false
    doc.layers += [overlay, hidden]
    let before = try Renderer.composite(doc).converted(to: doc.depth)
    let copy = try ClipboardRenderer.copy(doc, layerIDs: [], merged: true)
    XCTAssertEqual(try ClipboardRenderer.preview(copy), before)
    XCTAssertEqual(copy.kind, .pixels)
    doc.layers = []
    doc.activeLayerID = nil
    XCTAssertThrowsError(try ClipboardRenderer.copy(doc, layerIDs: [], merged: true))
  }
  func testLayerCopyKeepsWholeNestedSubtreeOffCanvasPixelsAndUnlinkedMasks() throws {
    var doc = try CraftDocument(width: 6, height: 4, depth: .f32)
    let group = Layer(name: "Group", content: .group(GroupContent()))
    var layer = Layer(
      name: "Child",
      content: .raster(
        try Surface(width: 10, height: 3, depth: .f32, fill: Pixel(-0.2, 1.3, 0.7, 0.6))))
    layer.x = -3
    layer.y = 1
    layer.parentID = group.id
    layer.mask = try Surface(width: 1, height: 2, depth: .f32, fill: .white)
    var properties = MaskProperties()
    properties.linked = false
    properties.transform = .translation(4, 0)
    layer.maskProperties = properties
    doc.layers += [layer, group]
    doc.activeLayerID = group.id
    let copy = try ClipboardRenderer.copy(doc, layerIDs: [group.id, layer.id])
    XCTAssertEqual(copy.kind, .layers)
    XCTAssertEqual(copy.document.layers, [layer, group])
    XCTAssertEqual(copy.bounds, IntRect(x: -3, y: 1, width: 10, height: 3))
    let pasted = try copy.newDocument(name: "Paste")
    XCTAssertEqual(pasted.layers[0].x, 0)
    XCTAssertEqual(pasted.layers[0].maskProperties, properties)
    XCTAssertEqual(try ClipboardContent.decode(copy.encoded()), copy)
  }
  func testNativeLayerCopyFreezesTextLayoutAndAffineSelectedPixelsUseDocumentCoordinates() throws {
    var doc = try CraftDocument(width: 12, height: 8, depth: .f32)
    var text = Layer(name: "Type", content: .text(TextContent(text: "Hello", size: 12)))
    text.affine = .translation(1.5, 1.5)
    doc.layers = [text]
    doc.activeLayerID = text.id
    let clip = try ClipboardRenderer.copy(doc, layerIDs: [text.id])
    guard case .text(let copied) = clip.document.layers[0].content else {
      return XCTFail("Type rasterized")
    }
    XCTAssertEqual(copied.layoutWidth, 12)
    XCTAssertEqual(copied.layoutHeight, 8)
    var raster = Layer(
      name: "Affine", content: .raster(try Surface(width: 2, height: 2, depth: .f32, fill: .white)))
    raster.affine = .translation(2, 1)
    doc.layers = [raster]
    doc.activeLayerID = raster.id
    doc.selection = IntRect(x: 0, y: 0, width: 12, height: 8)
    let pixels = try ClipboardRenderer.copy(doc, layerIDs: [raster.id])
    XCTAssertEqual(pixels.bounds, IntRect(x: 2, y: 1, width: 2, height: 2))
  }
  func testExternalTIFFAndPNGKeepOrientationAndAlphaWithExplicitPrecision() throws {
    var pixels = try Surface(width: 2, height: 3, depth: .f32)
    pixels.setPixel(x: 0, y: 0, Pixel(0.1, 0.4, 0.9, 0.5))
    pixels.setPixel(x: 1, y: 2, Pixel(0.9, 0.2, 0.1, 1))
    for depth in PixelDepth.allCases {
      let source = try pixels.converted(to: depth)
      let tiff = try ClipboardRenderer.readImage(ClipboardRenderer.imageData(source, type: .tiff))
      let output = try ClipboardRenderer.preview(tiff)
      XCTAssertEqual(output.depth, depth)
      for (x, y) in [(0, 0), (1, 2)] {
        let a = output.pixel(x: x, y: y)
        let b = source.pixel(x: x, y: y)
        let tolerance: Float = depth == .u8 ? 1 / 255 : depth == .u16 ? 1 / 65535 : 0.000001
        XCTAssertEqual(a.r, b.r, accuracy: tolerance)
        XCTAssertEqual(a.g, b.g, accuracy: tolerance)
        XCTAssertEqual(a.b, b.b, accuracy: tolerance)
        XCTAssertEqual(a.a, b.a, accuracy: tolerance)
      }
    }
    let png = try ClipboardRenderer.readImage(ClipboardRenderer.imageData(pixels, type: .png))
    XCTAssertEqual(png.document.depth, .u8)
    XCTAssertEqual(png.bounds.width, 2)
    XCTAssertEqual(png.bounds.height, 3)
    XCTAssertThrowsError(try ClipboardRenderer.readImage(Data("not an image".utf8)))
  }
}
