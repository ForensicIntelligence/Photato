import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class LayerStyleTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 24, height: 24, depth: depth)
    var s = try Surface(width: 24, height: 24, depth: depth, colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    for y in 8..<16 { for x in 8..<16 { s.setPixel(x:x,y:y,Pixel(0.4,0.6,0.8)) } }
    d.layers[0].content = .raster(s)
    var tile = try Surface(width: 2,height:2,fill:.white);tile.setPixel(x:0,y:0,.black);tile.setPixel(x:1,y:1,.black)
    d.patterns = [try RasterPattern(name:"Checker",surface:tile,id:"style-checker")]
    return d
  }
  func effect(_ kind: LayerEffect.Kind) -> LayerEffect {
    var effect=LayerEffect(kind)
    if kind == .gradientOverlay { effect.gradient=GradientFill(gradient:.blackToWhite) }
    if kind == .patternOverlay { effect.pattern=PatternFill(patternID:"style-checker") }
    return effect
  }
  func testAllTenEffectsAtAllDepthsRenderHistoryAndNativeArchives() throws {
    for depth in PixelDepth.allCases { for kind in LayerEffect.Kind.allCases {
      let original=try fixture(depth), baseline=try Renderer.composite(original)
      var session=EditorSession(document:original)
      try session.execute(.layerStyle([original.layers[0].id],LayerStyle(effects:[effect(kind)])))
      let changed=session.document
      XCTAssertNotEqual(try Renderer.composite(changed).rgbaData(depth:.u16),try baseline.rgbaData(depth:.u16),"\(kind) \(depth)")
      for bytes in [try NativeArchive.encode(changed),try NativeArchive.encodeChunked(changed)] {
        XCTAssertEqual(try NativeArchive.decode(bytes),changed)
      }
      try session.undo();XCTAssertEqual(session.document,original)
      try session.redo();XCTAssertEqual(session.document,changed)
    } }
  }
  func testSolidOverlayAndFillOpacityHaveKnownPixels() throws {
    var d=try fixture(),overlay=LayerEffect(.colorOverlay)
    overlay.color=Pixel(1,0,0);overlay.opacity=1
    var style=LayerStyle(effects:[overlay]);style.fillOpacity=0
    try Command.layerStyle([d.layers[0].id],style).apply(to:&d)
    let output=try Renderer.composite(d)
    XCTAssertEqual(output.pixel(x:10,y:10),Pixel(1,0,0))
    XCTAssertEqual(output.pixel(x:0,y:0).a,0)
    style.enabled=false;d.layers[0].style=style
    XCTAssertEqual(try Renderer.composite(d).pixel(x:10,y:10).a,0)
  }
  func testShadowPlacementAndOpacityArePredictable() throws {
    var d=try fixture(),shadow=LayerEffect(.dropShadow)
    shadow.size=0;shadow.distance=5;shadow.angle=180;shadow.useGlobalLight=false;shadow.opacity=1;shadow.blendMode = .normal
    d.layers[0].style=LayerStyle(effects:[shadow])
    XCTAssertEqual(try Renderer.composite(d).pixel(x:19,y:10),.black)
    XCTAssertEqual(try Renderer.composite(d).pixel(x:3,y:10).a,0)
    d.layers[0].opacity=0
    XCTAssertEqual(try Renderer.composite(d).pixel(x:19,y:10).a,0)
  }
  func testEditingPixelsAndIncrementalRenderingRefreshEffects() throws {
    var d=try fixture();d.layers[0].style=LayerStyle(effects:[effect(.stroke)])
    let before=try Renderer.render(d)
    try Command.move(d.layers[0].id,4,0).apply(to:&d)
    let after=try Renderer.render(d,reusing:before)
    XCTAssertEqual(try after.surface.rgbaData(depth:.u8),try Renderer.composite(d).rgbaData(depth:.u8))
    XCTAssertNotEqual(try before.surface.rgbaData(depth:.u8),try after.surface.rgbaData(depth:.u8))
  }
  func testPSDAndPSBRepresentedEffectsRemainEditable() throws {
    for kind in PSDLayerStyles.kinds.map(\.2) { for format in PSDFileFormat.allCases {
      var d=try fixture();d.layers[0].style=LayerStyle(effects:[effect(kind)])
      let read=try PSDCodec.read(PSDCodec.writeRasterLayers(d,format:format))
      XCTAssertEqual(read.layers[0].style?.effects.first?.kind,kind)
      XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.u8),try Renderer.composite(d).rgbaData(depth:.u8),"\(kind)")
    } }
    var d=try fixture();d.layers[0].style=LayerStyle(effects:[effect(.bevelEmboss)])
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
  }
  func testPhotoshopGradientOverlaysStayEditableWithOriginalRecords() throws {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PSDGradientOverlay")
    let cases: [(name: String, angle: Float, scale: Float, offsetX: Float, offsetY: Float, reversed: Bool)] = [
      ("shape--90-odd", -90, 1, 0, 0, false),
      ("shape--90-scale150-shift", -90, 1.5, 0.5, 0.25, true),
      ("shape-90-alpha-color", 90, 1, 0.25, -0.25, false),
    ]
    // Independent samples extracted from the stored Photoshop composite at x=60.
    let referenceRows: [[(y: Int, rgba: [UInt8])]] = [
      [(21, [0, 0, 0, 255]), (29, [120, 120, 120, 255]), (37, [240, 240, 240, 255])],
      [(48, [255, 255, 255, 255]), (56, [212, 212, 212, 255]), (72, [128, 128, 128, 255])],
      [(48, [123, 107, 52, 255]), (50, [107, 95, 57, 255]), (56, [66, 64, 64, 255]),
       (58, [54, 54, 64, 255])],
    ]
    let capture = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"].map { URL(fileURLWithPath: $0) }
    for (entry, rows) in zip(cases, referenceRows) {
      let input = try Data(contentsOf: folder.appendingPathComponent(entry.name + ".psd"))
      let document = try PSDCodec.read(input)
      let layer = try XCTUnwrap(document.layers.first)
      let style = try XCTUnwrap(layer.style)
      XCTAssertEqual(style.effects.map(\.kind), [.gradientOverlay])
      let fill = try XCTUnwrap(style.effects.first?.gradient)
      XCTAssertEqual(fill.placement.angle, entry.angle)
      XCTAssertEqual(fill.placement.scale, entry.scale)
      XCTAssertEqual(fill.placement.offsetX, entry.offsetX)
      XCTAssertEqual(fill.placement.offsetY, entry.offsetY)
      XCTAssertEqual(fill.placement.reverse, entry.reversed)
      XCTAssertTrue(fill.aligned)
      XCTAssertFalse(fill.dither)
      XCTAssertEqual(fill.gradient.opacity.map(\.opacity), entry.angle == 90 ? [0.2, 230.0 / 255] : [1, 1])
      let composite = try Renderer.composite(document)
      for row in rows {
        let pixel = composite.pixel(x: 60, y: row.y)
        XCTAssertEqual([pixel.r, pixel.g, pixel.b, pixel.a].map { UInt8((unit($0) * 255).rounded()) }, row.rgba,
          "\(entry.name) row \(row.y)")
      }
      var activeLegacy = try XCTUnwrap(layer.sourceTags?["lrFX"])
      let shadow = try XCTUnwrap(activeLegacy.range(of: Data("8BIMdsdw".utf8)))
      activeLegacy[shadow.upperBound + 4 + 38] = 1
      XCTAssertThrowsError(try PSDLayerStyles.validateInactiveLegacy(activeLegacy))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)
      for format in PSDFileFormat.allCases {
        let bytes = try PSDCodec.writeRasterLayers(document, compression: .raw, format: format)
        let read = try PSDCodec.read(bytes)
        XCTAssertEqual(read.layers.first?.style, style)
        XCTAssertEqual(read.layers.first?.sourceTags?["lfx2"], layer.sourceTags?["lfx2"])
        XCTAssertEqual(read.layers.first?.sourceTags?["lrFX"], layer.sourceTags?["lrFX"])
        XCTAssertEqual(try Renderer.composite(read).rgbaData(depth: .u8),
          try composite.rgbaData(depth: .u8))
        if let capture {
          try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
          try bytes.write(to: capture.appendingPathComponent(entry.name + (format == .psd ? ".psd" : ".psb")))
        }
        var edited = style
        edited.effects[0].gradient?.placement.angle = 45
        var session = EditorSession(document: document)
        try session.execute(.layerStyle([layer.id], edited))
        let update = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
        XCTAssertEqual(update.layers.first?.style?.effects.first?.gradient, edited.effects[0].gradient)
        XCTAssertNotEqual(update.layers.first?.sourceTags?["lfx2"], layer.sourceTags?["lfx2"])
        try session.undo()
        XCTAssertEqual(session.document, document)
      }
    }
  }
  func testStrictValidationLocksAndMergePreventSilentLoss() throws {
    for json in [#"{"bogus":1}"#, #"{"effects":[{"kind":"unknown"}]}"#, #"{"effects":[{"kind":"dropShadow","size":true}]}"#,
      #"{"effects":[{"kind":"gradientOverlay"}]}"#, #"{"effects":[{"kind":"stroke","size":251}]}"#] {
      XCTAssertThrowsError(try LayerStyle.decodeJSON(Data(json.utf8)))
    }
    var d=try fixture();d.layers[0].locked=true;let before=d
    XCTAssertThrowsError(try Command.layerStyle([d.layers[0].id],LayerStyle()).apply(to:&d));XCTAssertEqual(d,before)
    d.layers[0].locked=false;d.layers[0].style=LayerStyle(effects:[effect(.dropShadow)])
    let second=Layer(name:"Second",content:.raster(try Surface(width:24,height:24)))
    d.layers.append(second);d.activeLayerID=second.id
    XCTAssertThrowsError(try Command.mergeLayers(Set(d.layers.map(\.id)),.selected).apply(to:&d))
  }
  func testEffectsOnTextShapesGroupsAndMaskedContent() throws {
    var d = try fixture()
    for content: LayerContent in [.text(TextContent(text: "A", size: 16)), .shape(ShapeContent(kind: .ellipse, width: 12, height: 12, color: .white))] {
      d.layers[0].content = content; d.layers[0].style = nil
      let plain = try Renderer.composite(d)
      d.layers[0].style = LayerStyle(effects: [effect(.colorOverlay)])
      XCTAssertNotEqual(try Renderer.composite(d).rgbaData(depth: .u8), try plain.rgbaData(depth: .u8))
    }
    d = try fixture()
    let group = Layer(name: "Group", content: .group(GroupContent()))
    d.layers[0].parentID = group.id; d.layers.append(group)
    d.layers[1].style = LayerStyle(effects: [effect(.stroke)])
    XCTAssertGreaterThan(try Renderer.composite(d).pixel(x: 7, y: 10).a, 0)
    d.layers[1].mask = try Surface(width: 24, height: 24, fill: .black)
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 7, y: 10).a, 0)
  }
  func testMultiplePSDShadowsAndUnsupportedContourGuard() throws {
    var first=effect(.dropShadow),second=effect(.dropShadow);first.distance=3;second.distance=8
    let bytes=try PSDLayerStyles.write(LayerStyle(effects:[first,second]))
    XCTAssertEqual(try PSDLayerStyles.read(bytes).effects.count,2)
    var descriptor=try PSDDescriptor.read(Data(bytes.dropFirst(4)))
    descriptor.items.append(.init("ebbl",.object(PSDDescriptor("ebbl"))))
    XCTAssertThrowsError(try PSDLayerStyles.read(Data(repeating:0,count:4)+descriptor.encoded()))
  }
}
