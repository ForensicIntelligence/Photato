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
