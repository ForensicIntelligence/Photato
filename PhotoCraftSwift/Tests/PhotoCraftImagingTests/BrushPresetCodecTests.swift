import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class BrushPresetCodecTests: XCTestCase {
  func testNativePresetsAndCaptureOptions() throws {
    let presets=BrushPresets.builtins()
    XCTAssertEqual(presets.count,12)
    XCTAssertEqual(try BrushPresetFile.decode(BrushPresetFile(presets:presets).encoded()).presets,presets)
    var current=Brush();current.size=77;current.opacity=0.4;current.color=Pixel(1,0,0);current.settings = .init();current.settings!.flow=0.3
    var preset=presets[1];preset.includeSize=false
    let selected=preset.applying(to:current)
    XCTAssertEqual(selected.size,77);XCTAssertEqual(selected.color,current.color);XCTAssertEqual(selected.opacity,0.4);XCTAssertEqual(selected.settings!.flow,0.3)
    preset.includeToolSettings=true;preset.brush.settings!.smoothing.amount=0.75
    XCTAssertEqual(preset.applying(to:current).settings!.smoothing.amount,0.75)
    var image=try Surface(width:2,height:2,fill:.white);image.setPixel(x:0,y:0,.black)
    XCTAssertEqual(try BrushPresets.define(from:image,bounds:.init(x:0,y:0,width:2,height:2)).bytes,Data([255,0,0,0]))
    XCTAssertThrowsError(try BrushPresets.define(from:Surface(width:2,height:2,fill:.white),bounds:.init(x:0,y:0,width:2,height:2)))
  }
  func testModernABRTipsDynamicsAndEmbeddedTexture() throws {
    var presets=BrushPresets.builtins()
    presets[0].includeToolSettings=true
    presets[0].brush.settings!.mode = .multiply
    presets[0].brush.settings!.flow=0.35
    let data=try ABRCodec.write(presets),decoded=try ABRCodec.read(data)
    XCTAssertEqual(decoded.version,6);XCTAssertEqual(decoded.presets.map(\.name),presets.map(\.name));XCTAssertEqual(decoded.warnings,[])
    for (before,after) in zip(presets,decoded.presets) {
      XCTAssertEqual(before.brush.size,after.brush.size)
      XCTAssertEqual(before.brush.settings!.tip,after.brush.settings!.tip)
      XCTAssertEqual(before.brush.settings!.shape,after.brush.settings!.shape)
      XCTAssertEqual(before.brush.settings!.scattering,after.brush.settings!.scattering)
      XCTAssertEqual(before.brush.settings!.dual,after.brush.settings!.dual)
      if before.brush.settings!.texture.enabled { XCTAssertNotNil(after.brush.settings!.texture.bitmap) }
    }
    XCTAssertEqual(decoded.presets[0].brush.settings!.flow,0.35,accuracy:0.000001)
    XCTAssertEqual(decoded.presets[0].brush.settings!.mode,.multiply)
  }
  func testIndependentLegacyComputedFixtureAndMalformedData() throws {
    // Literal ABR v1 computed brush: spacing25,diameter20,roundness50,angle45,hardness75.
    let data=Data([0,1,0,1,0,1,0,0,0,14,0,0,0,0,0,25,0,20,0,50,0,45,0,75])
    let result=try ABRCodec.read(data)
    XCTAssertEqual(result.presets[0].brush.size,20);XCTAssertEqual(result.presets[0].brush.hardness,0.75)
    XCTAssertEqual(result.presets[0].brush.settings!.roundness,0.5);XCTAssertEqual(result.presets[0].brush.settings!.angle,45)
    XCTAssertThrowsError(try ABRCodec.read(data+Data([1])))
    for size in 0..<data.count { XCTAssertThrowsError(try ABRCodec.read(data.prefix(size))) }
    var preset=BrushPresets.builtins()[0];preset.includeColor=true
    XCTAssertThrowsError(try ABRCodec.write([preset]))
    XCTAssertThrowsError(try BrushPresetFile(presets:[preset,preset]).encoded())
  }
}
