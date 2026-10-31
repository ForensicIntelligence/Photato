import XCTest
@testable import PhotoCraftCore

final class ChannelArithmeticTests: XCTestCase {
  func testHandComputedRGBMaskSelectionAndOutsideBitsAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:4,height:2,depth:depth)
      let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
      let original=try Surface(width:4,height:2,depth:depth,fill:Pixel(0.5,0.4,0.3),colorEncoding:encoding)
      d.layers[0].content = .raster(original);d.selection = .init(x:0,y:0,width:2,height:2)
      let source=ChannelArithmeticInput(samples:try Surface(width:4,height:2,depth:.f32,
        fill:Pixel(1,0.25,0)),components:3,mode:.rgb)
      let mask=try Surface(width:4,height:2,depth:.f32,fill:Pixel(0.5,0.5,0.5))
      var options=ChannelArithmeticOptions();options.opacity=0.5
      try ChannelArithmeticEngine.apply(source,mask:mask,options:options,target:.pixels(d.layers[0].id,[]),to:&d)
      guard case .raster(let result)=d.layers[0].content else{return XCTFail("Missing result")}
      let b=depth == .f32 ? original.linearPixel(x:0,y:0):original.pixel(x:0,y:0)
      let expected=Pixel(b.r,b.g+(b.g*0.25-b.g)*0.25,b.b+(0-b.b)*0.25).quantized(depth)
      XCTAssertEqual(depth == .f32 ? result.linearPixel(x:0,y:0):result.pixel(x:0,y:0),expected)
      for y in 0..<2 {for x in 2..<4 {
        let p=depth == .f32 ? result.linearPixel(x:x,y:y):result.pixel(x:x,y:y)
        let old=depth == .f32 ? original.linearPixel(x:x,y:y):original.pixel(x:x,y:y)
        XCTAssertTrue(p.hasSameBits(as:old))
      }}
    }
  }
  func testEmptyTargetExpansionPreserveTransparencyAndOffCanvasPixels() throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:5,height:3,depth:depth)
      var layer=Layer(name:"Small",content:.raster(try Surface(width:1,height:1,depth:depth)))
      layer.x=2;layer.y=1;d.layers=[layer];d.activeLayerID=layer.id
      let input=ChannelArithmeticInput(samples:try Surface(width:5,height:3,depth:.f32,fill:Pixel(0.75,0.5,0.25)),components:3,mode:.rgb)
      var options=ChannelArithmeticOptions();options.opacity=0.5
      var locked=d;options.preserveTransparency=true
      try ChannelArithmeticEngine.apply(input,options:options,target:.pixels(layer.id,[]),to:&locked)
      XCTAssertEqual(locked,d)
      options.preserveTransparency=false
      try ChannelArithmeticEngine.apply(input,options:options,target:.pixels(layer.id,[]),to:&d)
      guard case .raster(let result)=d.layers[0].content else{return XCTFail()}
      XCTAssertEqual(result.width,5);XCTAssertEqual(result.height,3)
      XCTAssertEqual(d.layers[0].x,0);XCTAssertEqual(d.layers[0].y,0)
      let expected=depth == .f32 ? SRGBTransfer.encoded(Pixel(0.75,0.5,0.25,0.5)) : Pixel(0.75,0.5,0.25,0.5).quantized(depth)
      XCTAssertEqual(result.pixel(x:4,y:2),expected)
    }
    var d=try CraftDocument(width:3,height:2)
    let original=try Surface(width:5,height:2,fill:Pixel(0.2,0.3,0.4))
    var layer=Layer(name:"Off canvas",content:.raster(original));layer.x = -2
    d.layers=[layer];d.activeLayerID=layer.id
    var options=ChannelArithmeticOptions();options.blending="normal"
    try ChannelArithmeticEngine.apply(.init(samples:Surface(width:3,height:2,depth:.f32,fill:.white)),options:options,target:.pixels(layer.id,[]),to:&d)
    guard case .raster(let result)=d.layers[0].content else{return XCTFail()}
    XCTAssertEqual(result.pixel(x:0,y:0),original.pixel(x:0,y:0))
    XCTAssertEqual(result.pixel(x:2,y:0),.white)
  }
  func testCalculationsOrderScaleOffsetCoverageAndInvalidAtomicity() throws {
    let first=try Surface(width:3,height:2,depth:.f32,fill:Pixel(0.75,0.75,0.75))
    let second=try Surface(width:3,height:2,depth:.f32,fill:Pixel(0.25,0.25,0.25))
    var options=ChannelArithmeticOptions();options.blending="subtract";options.scale=2;options.offset=127.5
    let output=try ChannelArithmeticEngine.calculate(first,second,options:options,depth:.f32)
    XCTAssertEqual(output.pixel(x:1,y:1).r,0.25)
    options.blending="add";options.opacity=0.5
    let mask=try Surface(width:3,height:2,depth:.f32,fill:Pixel(0.5,0.5,0.5))
    let added=try ChannelArithmeticEngine.calculate(first,second,mask:mask,options:options,depth:.f32)
    XCTAssertEqual(added.pixel(x:1,y:1).r,0.4375)
    var d=try CraftDocument(width:3,height:2);let before=d
    options.scale=3
    XCTAssertThrowsError(try ChannelArithmeticEngine.apply(.init(samples:first),options:options,target:.pixels(d.layers[0].id,[]),to:&d))
    XCTAssertEqual(d,before)
    options.scale=1;options.blending="hue"
    XCTAssertThrowsError(try options.validate())
    options.blending="normal"
    XCTAssertThrowsError(try ChannelArithmeticEngine.apply(.init(samples:first),mask:Surface(width:1,height:1),options:options,target:.pixels(d.layers[0].id,[]),to:&d))
    XCTAssertEqual(d,before)
  }
  func testAuxiliaryAndPixelMaskTargetsAndNoOpGeometry() throws {
    var d=try CraftDocument(width:4,height:3)
    let alpha=AlphaChannel(name:"A",pixels:try Surface(width:4,height:3,fill:.white))
    try Command.channel(.create(alpha)).apply(to:&d)
    d.selection = .init(x:0,y:0,width:2,height:3)
    var options=ChannelArithmeticOptions();options.blending="normal"
    let input=ChannelArithmeticInput(samples:try Surface(width:4,height:3,depth:.f32,fill:.black))
    try ChannelArithmeticEngine.apply(input,options:options,target:.alpha(alpha.id),to:&d)
    XCTAssertEqual(d.alphaChannels?.first?.pixels.pixel(x:0,y:0),.black)
    XCTAssertEqual(d.alphaChannels?.first?.pixels.pixel(x:3,y:0),.white)
    d.layers[0].mask=try Surface(width:1,height:1,fill:.white)
    var properties=MaskProperties();properties.outside=1;d.layers[0].maskProperties=properties
    let before=d;options.opacity=0
    try ChannelArithmeticEngine.apply(input,options:options,target:.layerMask(d.layers[0].id),to:&d)
    XCTAssertEqual(d,before)
    options.opacity=1
    try ChannelArithmeticEngine.apply(input,options:options,target:.layerMask(d.layers[0].id),to:&d)
    XCTAssertEqual(d.layers[0].mask?.pixel(x:0,y:0),.black)
    XCTAssertEqual(d.layers[0].mask?.pixel(x:3,y:0),.white)
  }
  func testMaximumImplicitCanvasAndNativeChannelPlaneBytes() throws {
    var d=try CraftDocument(width:300_000,height:300_000)
    d.layers[0].content = .raster(try Surface(width:1,height:1))
    let input=ChannelArithmeticInput(samples:try Surface(width:d.width,height:d.height,depth:.f32,fill:.white))
    try ChannelArithmeticEngine.apply(input,options:.init(),target:.pixels(d.layers[0].id,[]),to:&d)
    guard case .raster(let pixels)=d.layers[0].content else{return XCTFail()}
    XCTAssertLessThan(pixels.allocatedBytes,1_048_576);XCTAssertEqual(pixels.pixel(x:299_999,y:299_999),.white)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(d)),d)
    var cmyk=try CraftDocument(width:4,height:3,depth:.u16)
    var native=try NativeModeRaster(width:4,height:3,mode:.cmyk,depth:.u16)
    for i in 0..<12 {for c in 0..<5 {try native.set(c==4 ? 1:Float(c+1)/10,component:c,index:i)}}
    cmyk.modeDescriptor=try .init(mode:.cmyk,depth:.u16,profile:native.profile)
    cmyk.layers[0].nativeMode=native;cmyk.layers[0].content = .raster(try native.surface())
    var options=ChannelArithmeticOptions();options.blending="normal"
    try ChannelArithmeticEngine.apply(.init(samples:Surface(width:4,height:3,depth:.f32,fill:Pixel(0.75,0.75,0.75))),options:options,target:.pixels(cmyk.layers[0].id,[1]),to:&cmyk)
    let result=try XCTUnwrap(cmyk.layers[0].nativeMode)
    for c in [0,2,3,4] {XCTAssertEqual(result.planes[c],native.planes[c])}
    XCTAssertEqual(result.value(component:1,index:0),Float((0.25*65535).rounded())/65535)
  }
}
