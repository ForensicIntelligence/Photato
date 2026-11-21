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

  func testMaximumPatternOverlayMatchesSmallControlAcrossPagedTiles() throws {
    let maximum = Surface.maxDimension
    let bigX = maximum - 34, bigY = maximum - 36
    let controlX = 14, controlY = 12
    let region = IntRect(x: bigX - 4, y: bigY - 4, width: 30, height: 30)
    let control = IntRect(x: controlX - 4, y: controlY - 4, width: 30, height: 30)
    var tile = try Surface(width: 4, height: 4, fill: .white)
    tile.setPixel(x: 0, y: 0, .black)
    let pattern = try RasterPattern(name: "Owned pattern", surface: tile)
    for depth in PixelDepth.allCases {
      var raster = try Surface(width: 24, height: 24, depth: depth, fill: .white,
        colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      raster.setPixel(x: 1, y: 1, Pixel(1, 1, 1, 128.0 / 255))
      var mask = try Surface(width: 24, height: 24, depth: depth, fill: .white)
      mask.setPixel(x: 2, y: 1, Pixel(0.4, 0.4, 0.4))
      for linkedOrigin in [false, true] {
        var overlay = LayerEffect(.patternOverlay)
        overlay.pattern = PatternFill(patternID: pattern.id)
        overlay.pattern?.placement.scale = 200
        overlay.opacity = 0.5
        var style = LayerStyle(effects: [overlay])
        if linkedOrigin { style.referenceOffset = PathPoint(0, 0) }

        func document(_ size: Int, x: Int, y: Int, background: Bool) throws -> CraftDocument {
          var doc = try CraftDocument(width: size, height: size, depth: depth)
          doc.patterns = [pattern]
          doc.layers[0].content = .raster(raster)
          doc.layers[0].x = x
          doc.layers[0].y = y
          if background { doc.layers[0].mask = mask }
          let id = doc.layers[0].id
          try Command.layerStyle([id], style).apply(to: &doc)
          if background { doc.layers.insert(Layer(name: "Backdrop", content: .fill(Pixel(0.2, 0.4, 0.7, 0.8))), at: 0) }
          return doc
        }

        let small = try document(64, x: controlX, y: controlY, background: true)
        let large = try document(maximum, x: bigX, y: bigY, background: true)
        let expected = try Renderer.composite(small).cropped(to: control).rgbaData(depth: depth)
        let regional = try Renderer.composite(large, region: region).cropped(to: region)
        XCTAssertEqual(try regional.rgbaData(depth: depth), expected, "\(depth) linked origin \(linkedOrigin)")
        let full = try Renderer.composite(large)
        XCTAssertEqual(try full.cropped(to: region).rgbaData(depth: depth), expected)
        XCTAssertEqual(full.pixel(x: 0, y: 0), full.pixel(x: maximum - 1, y: maximum - 1))
        XCTAssertLessThan(full.allocatedBytes, 4 * 1024 * 1024)

        if depth == .u8 && linkedOrigin {
          let standalone = try document(4096, x: controlX, y: controlY, background: false)
          let psb = try PSDCodec.writeRasterLayers(standalone, format: .psb, maximizeCompatibility: false)
          XCTAssertLessThan(psb.count, 1024 * 1024)
          let reopened = try PSDCodec.read(psb)
          XCTAssertEqual(reopened.width, standalone.width)
          XCTAssertEqual(reopened.height, standalone.height)
          XCTAssertEqual(reopened.layers[0].style?.effects[0].kind, .patternOverlay)
          let authored = try Renderer.composite(standalone, region: control).cropped(to: control)
          XCTAssertEqual(try Renderer.composite(reopened, region: control).cropped(to: control).rgbaData(depth: .u8),
            try authored.rgbaData(depth: .u8))
          let sample = (4 * control.width + 4) * 4
          XCTAssertEqual(Array(try authored.rgbaData(depth: .u8)[sample..<(sample + 4)]), [127, 127, 127, 255])
        }
      }
    }
  }

  func testOpaquePatternPreviewMatchesFullCompositeWithSparseEditsAndMasks() throws {
    let maximum = Surface.maxDimension, offset = 299_520
    var repeatPixels = try Surface(width: 4, height: 4, fill: .white)
    repeatPixels.setPixel(x: 0, y: 0, .black)
    repeatPixels.setPixel(x: 1, y: 2, Pixel(0.2, 0.6, 0.4))
    let pattern = try RasterPattern(name: "Owned repeating control", surface: repeatPixels)
    var overlay = LayerEffect(.patternOverlay)
    overlay.pattern = PatternFill(patternID: pattern.id)
    overlay.pattern?.placement.scale = 200
    overlay.opacity = 0.63
    var style = LayerStyle(effects: [overlay])
    style.referenceOffset = PathPoint(3, -2)
    style.fillOpacity = 0.89

    for depth in PixelDepth.allCases {
      func fixture(width: Int, height: Int, origin: Int) throws -> CraftDocument {
        var document = try CraftDocument(width: width, height: height, depth: depth)
        document.patterns = [pattern]
        var raster = try Surface(width: width, height: height, depth: depth, fill: Pixel(0.7, 0.5, 0.3),
          colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
        raster.setPixel(x: origin + 64, y: origin + 63, Pixel(0.2, 0.7, 0.9, 0.5))
        var mask = try Surface(width: width, height: height, depth: .u8, fill: .white)
        mask.setPixel(x: origin + 7, y: origin + 10, .black)
        document.layers[0].content = .raster(raster)
        document.layers[0].mask = mask
        try Command.layerStyle([document.layers[0].id], style).apply(to: &document)
        let foreground = try Surface(width: 7, height: 6, depth: depth, fill: Pixel(0.1, 0.3, 0.7, 0.6),
          colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
        var detail = Layer(name: "Local edit", content: .raster(foreground))
        detail.x = origin + 120
        detail.y = origin + 60
        document.layers.append(detail)
        return document
      }
      let large = try fixture(width: maximum, height: maximum, origin: offset)
      let small = try fixture(width: 192, height: 176, origin: 0)
      let repeating = try XCTUnwrap(PatternCanvasPreview(large))
      let reference = try Renderer.composite(small)
      let region = IntRect(x: 3, y: 2, width: 137, height: 107)
      let translated = IntRect(x: offset + region.x, y: offset + region.y, width: region.width, height: region.height)
      let units = try RasterPreviewRequest(region: translated, width: region.width, height: region.height)
      XCTAssertEqual(try repeating.imageSamples(units).rgbaData(depth: depth),
        try reference.cropped(to: region).rgbaData(depth: depth), "\(depth) unit view")
      XCTAssertEqual(try repeating.pixel(x: offset + 64, y: offset + 63), reference.pixel(x: 64, y: 63))
      XCTAssertEqual(try repeating.pixel(x: offset + 77, y: offset + 78), reference.pixel(x: 77, y: 78))

      let reduced = try RasterPreviewRequest(region: translated, width: 23, height: 19)
      let referenceRequest = try RasterPreviewRequest(region: region, width: 23, height: 19)
      XCTAssertEqual(try repeating.imageSamples(reduced).rgbaData(depth: .u8),
        try referenceRequest.reducing(reference).rgbaData(depth: .u8), "\(depth) reduced view")
      let channel = RGBChannelView(preview: .green)
      let original = try Renderer.composite(large, region: translated)
      let channelReference = try reduced.reducing(channel.applying(to: original))
      XCTAssertEqual(try repeating.imageSamples(reduced, channels: channel).rgbaData(depth: .u8),
        try channelReference.rgbaData(depth: .u8), "\(depth) isolated channel")
      var proof = ProofSettings()
      proof.enabled = true
      let proofReference = try referenceRequest.reducing(SoftProof.surface(small, composite: reference, settings: proof))
      XCTAssertEqual(try repeating.imageSamples(reduced, proof: proof).rgbaData(depth: .u8),
        try proofReference.rgbaData(depth: .u8), "\(depth) soft proof")
    }
  }

  func testOpaquePatternOverviewIntegratesWholeRepeatAtMaximumSize() throws {
    let size = Surface.maxDimension
    var document = try CraftDocument(width: size, height: size)
    document.layers[0].content = .raster(try Surface(width: size, height: size, fill: .white))
    var samples = try Surface(width: 4, height: 4, fill: .white)
    samples.setPixel(x: 0, y: 0, .black)
    let asset = try RasterPattern(name: "Area integration control", surface: samples)
    document.patterns = [asset]
    var overlay = LayerEffect(.patternOverlay)
    overlay.pattern = PatternFill(patternID: asset.id)
    overlay.pattern?.placement.scale = 200
    overlay.opacity = 0.5
    var style = LayerStyle(effects: [overlay])
    style.referenceOffset = PathPoint(0, 0)
    try Command.layerStyle([document.layers[0].id], style).apply(to: &document)
    let request = try RasterPreviewRequest.overview(width: size, height: size, maximumSide: 25)
    let repeating = try XCTUnwrap(PatternCanvasPreview(document))
    let result = try repeating.imageSamples(request)
    // Every 12,000-pixel footprint contains a whole number of repeats.
    // Black contributes one texel in sixteen at byte opacity 128/255.
    let sample: [UInt8] = [247, 247, 247, 255]
    XCTAssertEqual(try result.rgbaData(depth: .u8), Data(Array(repeating: sample, count: 25 * 25).joined()))
    let region = IntRect(x: size - 81, y: size - 100, width: 47, height: 83)
    let crop = try RasterPreviewRequest(region: region, width: region.width, height: region.height)
    for scale: Float in [75, 150, 300] {
      document.layers[0].style?.effects[0].pattern?.placement.scale = scale
      document.layers[0].style?.effects[0].pattern?.placement.phaseX = 0.25
      let samples = try XCTUnwrap(PatternCanvasPreview(document)).imageSamples(crop)
      XCTAssertEqual(try samples.rgbaData(depth: .u8),
        try Renderer.composite(document, region: region).cropped(to: region).rgbaData(depth: .u8), "\(scale)% repeat")
    }
    document.layers[0].style?.effects[0].pattern?.placement.angle = 30
    XCTAssertNil(try PatternCanvasPreview(document))
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
  func testPhotoshopPatternOverlaysStayEditableWithOriginalReferences() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/reference-patterns.psd")
    let document = try PSDCodec.read(fixture)
    let overlays = document.layers.filter { $0.style?.effects.first?.kind == .patternOverlay }
    XCTAssertEqual(overlays.count, 6)
    XCTAssertEqual(document.layers.count, 13)
    for layer in overlays {
      let style = try XCTUnwrap(layer.style), effect = try XCTUnwrap(style.effects.first)
      let pattern = try XCTUnwrap(effect.pattern)
      XCTAssertEqual(effect.opacity, 0.5)
      XCTAssertEqual(pattern.placement.scale, 200)
      XCTAssertTrue(pattern.linked)
      XCTAssertNotNil(document.pattern(pattern.patternID))
      let rawPoint = try PSDPatternFill.referencePoint(XCTUnwrap(layer.sourceTags?["fxrp"]))
      XCTAssertEqual(style.patternReference(in: layer), rawPoint)
    }
    let composite = try Renderer.composite(document)
    // Values sampled directly from the saved RGB planes of reference-patterns.psd.
    let reference: [(Int, Int, [UInt8])] = [
      (22, 142, [177, 177, 177]), (23, 143, [176, 176, 176]), (26, 148, [233, 233, 233]),
      (81, 142, [105, 105, 105]), (82, 143, [169, 169, 169]), (85, 148, [233, 233, 233]),
      (140, 142, [233, 233, 233]), (141, 143, [233, 233, 233]), (144, 148, [169, 169, 169]),
      (199, 142, [233, 233, 233]), (200, 143, [233, 233, 233]), (203, 148, [233, 233, 233]),
      (22, 201, [125, 105, 157]), (23, 202, [122, 105, 150]), (26, 207, [132, 125, 197]),
      (81, 201, [199, 197, 106]), (82, 202, [196, 193, 106]), (85, 207, [198, 195, 127]),
    ]
    for (x, y, rgb) in reference {
      let p = composite.pixel(x: x, y: y)
      XCTAssertEqual([p.r, p.g, p.b].map { UInt8((unit($0) * 255).rounded()) }, rgb, "At \(x),\(y)")
    }
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)
    let active = try XCTUnwrap(overlays.last)
    var style = try XCTUnwrap(active.style)
    style.effects[0].pattern?.placement.phaseX = 3.5
    style.effects[0].pattern?.placement.angle = 20
    var session = EditorSession(document: document)
    try session.execute(.layerStyle([active.id], style))
    for format in PSDFileFormat.allCases {
      let pristine = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
      XCTAssertEqual(try Renderer.composite(pristine), composite)
      for layer in overlays {
        let restored = try XCTUnwrap(pristine.layers.first { $0.name == layer.name })
        XCTAssertEqual(restored.sourceTags?["fxrp"], layer.sourceTags?["fxrp"])
        XCTAssertEqual(restored.sourceTags?["lfx2"], layer.sourceTags?["lfx2"])
        XCTAssertEqual(restored.style, layer.style)
      }
      let edited = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
      let editedLayer = try XCTUnwrap(edited.layers.first { $0.name == active.name })
      XCTAssertEqual(editedLayer.style, style)
      XCTAssertEqual(try Renderer.composite(edited), try Renderer.composite(session.document))
    }
    try session.undo()
    XCTAssertEqual(session.document, document)
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
